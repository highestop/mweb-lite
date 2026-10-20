import AppKit
import ImageIO
import XCTest
import CaseReporting
@testable import MWebLite

final class ArticleThumbnailTests: CaseReportingTestCase {
    @MainActor
    func test_THUMB_001_ConfinedImagesDecodeCacheAndIgnoreObsoleteLoads() async throws {
        // Given: only disposable copies of the committed image fixtures.
        _ = NSApplication.shared
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Library/docs")
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("MWebLite-Thumbnails-\(UUID())")
        let root = temporary.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        try FileManager.default.copyItem(at: source, to: root.appendingPathComponent("docs"))
        let document = root.appendingPathComponent("docs/10006.md")
        let loader = ArticleThumbnailLoader()
        func request(_ reference: String, library: URL? = nil) -> ArticleThumbnailRequest {
            ArticleThumbnailRequest(reference: reference, documentURL: document, libraryRoot: library ?? root)
        }
        let fixtures: [(name: String, ratio: Double)] = [
            ("mountain.svg", 1200.0 / 720), ("panorama.svg", 1600.0 / 480),
            ("portrait.svg", 720.0 / 1080), ("square.png", 1),
            ("detail.jpg", 960.0 / 640), ("transparent.png", 640.0 / 480)
        ]
        var images: [String: ArticleThumbnailImage] = [:]

        // When: the production loader reads PNG/JPEG and renders all three SVGs.
        for fixture in fixtures {
            let image = try await loader.load(request("media/10006/" + fixture.name))
            let pixels = image.cgImage
            XCTAssertGreaterThan(pixels.width, 0, fixture.name)
            XCTAssertGreaterThan(pixels.height, 0, fixture.name)
            XCTAssertLessThanOrEqual(max(pixels.width, pixels.height), ArticleThumbnailLoader.maximumPixelSize)
            XCTAssertEqual(Double(pixels.width) / Double(pixels.height), fixture.ratio,
                           accuracy: 0.03, fixture.name)
            let data = try XCTUnwrap(pixels.dataProvider?.data, fixture.name)
            XCTAssertTrue((data as Data).contains { $0 != 0 }, "Rendered pixels must not be empty: \(fixture.name)")
            images[fixture.name] = image
        }
        let first = try XCTUnwrap(images["mountain.svg"])
        let replacement = try XCTUnwrap(images["portrait.svg"])
        let firstRequest = request("media/10006/mountain.svg")
        let replacementRequest = request("media/10006/portrait.svg")
        let cached = try await loader.load(firstRequest)
        XCTAssertTrue(cached === first, "Repeated requests reuse the decoded thumbnail")

        // A one-pixel GIF has a red first frame and a blue second frame.
        let gif = Data([
            0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 1, 0, 1, 0, 0x80, 0, 0,
            0xff, 0, 0, 0, 0, 0xff,
            0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, 0x44, 1, 0,
            0x2c, 0, 0, 0, 0, 1, 0, 1, 0, 0, 2, 2, 0x4c, 1, 0, 0x3b
        ])
        let gifSource = try XCTUnwrap(CGImageSourceCreateWithData(gif as CFData, nil))
        XCTAssertEqual(CGImageSourceGetCount(gifSource), 2)
        try gif.write(to: root.appendingPathComponent("docs/media/10006/animated.gif"))
        let gifThumbnail = try await loader.load(request("media/10006/animated.gif"))
        let firstPixel = try XCTUnwrap(
            NSBitmapImageRep(cgImage: gifThumbnail.cgImage).colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB)
        )
        XCTAssertGreaterThan(firstPixel.redComponent, 0.9)
        XCTAssertLessThan(firstPixel.blueComponent, 0.1, "Animated images use their first frame")

        // Then: URL decoding retains spaces, and confinement precedes any read.
        let spaced = root.appendingPathComponent("docs/media/10006/space image.png")
        try FileManager.default.copyItem(at: root.appendingPathComponent("docs/media/10006/square.png"), to: spaced)
        let spacedRequest = request("media/10006/space%20image.png")
        XCTAssertEqual(ArticleThumbnailLoader.sourceURL(for: spacedRequest), spaced.resolvingSymlinksInPath())
        _ = try await loader.load(spacedRequest)
        let nestedDocument = root.appendingPathComponent("docs/nested/note.md")
        try FileManager.default.createDirectory(at: nestedDocument.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let parentRelative = ArticleThumbnailRequest(reference: "../media/10006/space%20image.png",
                                                     documentURL: nestedDocument, libraryRoot: root)
        XCTAssertEqual(ArticleThumbnailLoader.sourceURL(for: parentRelative), spaced.resolvingSymlinksInPath())
        _ = try await loader.load(parentRelative)
        for reference in ["/docs/media/10006/space%20image.png",
                          "mweblite://library/docs/media/10006/space%20image.png"] {
            XCTAssertEqual(ArticleThumbnailLoader.sourceURL(for: request(reference)), spaced.resolvingSymlinksInPath())
        }
        let outside = temporary.appendingPathComponent("outside.png")
        try FileManager.default.copyItem(at: spaced, to: outside)
        let link = root.appendingPathComponent("docs/media/10006/escape.png")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        for reference in ["../../outside.png", "%2e%2e/%2e%2e/outside.png",
                          "media/10006/escape.png", outside.absoluteString, "data:image/png;base64,AA=="] {
            let unsafe = request(reference)
            XCTAssertNil(ArticleThumbnailLoader.sourceURL(for: unsafe), reference)
            do {
                _ = try await loader.load(unsafe)
                XCTFail("Unsafe reference was loaded: \(reference)")
            } catch {}
        }
        XCTAssertNil(ArticleThumbnailLoader.sourceURL(for: ArticleThumbnailRequest(
            reference: "media/10006/square.png", documentURL: document, libraryRoot: nil
        )))
        XCTAssertEqual(ArticleThumbnailLoader.sourceURL(for: request("https://example.invalid/a%20b.png"))?.scheme, "https")
        XCTAssertEqual(ArticleThumbnailLoader.sourceURL(for: request("http://example.invalid/a.png"))?.scheme, "http")

        // SVG cannot follow an embedded file reference even when its own file is confined.
        let unsafeSVG = root.appendingPathComponent("docs/media/10006/external.svg")
        try Data("""
        <svg xmlns="http://www.w3.org/2000/svg" width="32" height="32">
        <image href="\(outside.absoluteString)" width="32" height="32"/>
        </svg>
        """.utf8).write(to: unsafeSVG)
        let invalid = root.appendingPathComponent("docs/media/10006/invalid.png")
        try Data("not an image".utf8).write(to: invalid)
        let oversized = root.appendingPathComponent("docs/media/10006/oversized.png")
        try Data(count: ArticleThumbnailLoader.maximumDataSize + 1).write(to: oversized)
        for name in ["external.svg", "invalid.png", "oversized.png", "missing.png"] {
            do {
                _ = try await loader.load(request("media/10006/" + name))
                XCTFail("Unsupported or invalid image was loaded: \(name)")
            } catch {}
        }

        // A cancelled cache hit still respects cancellation.
        let cancelled = Task { try await loader.load(firstRequest) }
        cancelled.cancel()
        do {
            _ = try await cancelled.value
            XCTFail("A cancelled request returned an image")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected cancellation, got \(error)")
        }

        // Controlled completion order checks row reuse without sleeps or real networking.
        let state = ArticleThumbnailState()
        let obsoleteGate = ThumbnailCompletionGate()
        let obsoleteStarted = expectation(description: "The first request starts loading")
        let obsolete = Task {
            await state.load(firstRequest) { _ in
                obsoleteStarted.fulfill()
                return await obsoleteGate.wait()
            }
        }
        await fulfillment(of: [obsoleteStarted], timeout: 2)
        await state.load(replacementRequest) { _ in replacement }
        await obsoleteGate.complete(with: first)
        await obsolete.value
        XCTAssertEqual(state.request, replacementRequest)
        XCTAssertTrue(state.image === replacement, "Late completion must not replace a reused row's image")

        let cancellationGate = ThumbnailCompletionGate()
        let cancellationStarted = expectation(description: "The cancellable request starts loading")
        let pending = Task {
            await state.load(firstRequest) { _ in
                cancellationStarted.fulfill()
                return await cancellationGate.wait()
            }
        }
        await fulfillment(of: [cancellationStarted], timeout: 2)
        XCTAssertNil(state.image, "Changing the request immediately clears the previous pixels")
        pending.cancel()
        await cancellationGate.complete(with: first)
        await pending.value
        XCTAssertNil(state.image, "Cancellation must not publish a completed image")
    }
}

private actor ThumbnailCompletionGate {
    private var completion: CheckedContinuation<ArticleThumbnailImage, Never>?
    private var result: ArticleThumbnailImage?

    func wait() async -> ArticleThumbnailImage {
        if let result { return result }
        return await withCheckedContinuation { continuation in
            completion = continuation
        }
    }

    func complete(with image: ArticleThumbnailImage) {
        result = image
        completion?.resume(returning: image)
        completion = nil
    }
}
