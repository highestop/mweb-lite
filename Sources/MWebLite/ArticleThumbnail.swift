import AppKit
import ImageIO
import SwiftUI

@MainActor
struct ArticleThumbnail: View {
    let reference: String
    let documentURL: URL
    let libraryRoot: URL?
    @StateObject private var state = ArticleThumbnailState()

    private var request: ArticleThumbnailRequest {
        ArticleThumbnailRequest(reference: reference, documentURL: documentURL, libraryRoot: libraryRoot)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.primary.opacity(0.045)
                if state.request == request, let image = state.image {
                    Image(decorative: image.cgImage, scale: 1)
                        .resizable()
                        .scaledToFill()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
        .task(id: request) {
            await state.load(request)
        }
    }
}

struct ArticleThumbnailRequest: Hashable, Sendable {
    let reference: String
    let documentURL: URL
    let libraryRoot: URL?
}

/// Only immutable, fully decoded pixels cross the worker/main-actor boundary.
final class ArticleThumbnailImage: @unchecked Sendable {
    let cgImage: CGImage
    init(_ cgImage: CGImage) { self.cgImage = cgImage }
}

@MainActor
final class ArticleThumbnailState: ObservableObject {
    @Published private(set) var image: ArticleThumbnailImage?
    private(set) var request: ArticleThumbnailRequest?
    private var generation = UUID()

    func load(_ request: ArticleThumbnailRequest,
              fetch: (ArticleThumbnailRequest) async throws -> ArticleThumbnailImage = {
                  try await ArticleThumbnailLoader.shared.load($0)
              }) async {
        let current = UUID()
        generation = current
        self.request = request
        image = nil
        do {
            let result = try await fetch(request)
            try Task.checkCancellation()
            guard generation == current else { return }
            image = result
        } catch {
            guard generation == current else { return }
            image = nil
        }
    }
}

actor ArticleThumbnailLoader {
    static let shared = ArticleThumbnailLoader()
    static let maximumPixelSize = 256
    static let maximumDataSize = 8 * 1024 * 1024
    private let cache = NSCache<NSString, ArticleThumbnailImage>()

    init() {
        cache.countLimit = 128
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    func load(_ request: ArticleThumbnailRequest) async throws -> ArticleThumbnailImage {
        try Task.checkCancellation()
        guard let url = Self.sourceURL(for: request) else { throw ThumbnailError.invalidSource }
        var key = url.absoluteString
        if url.isFileURL {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
            guard values.isRegularFile == true, let size = values.fileSize,
                  size <= Self.maximumDataSize else { throw ThumbnailError.invalidSource }
            key += "|\(size)|\(values.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }
        // Resolve confinement before every cache lookup, including after symlink changes.
        if let image = cache.object(forKey: key as NSString) { return image }
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            let data: Data
            if url.isFileURL {
                data = try Data(contentsOf: url, options: .mappedIfSafe)
            } else {
                data = try await Self.download(url)
            }
            try Task.checkCancellation()
            guard data.count <= Self.maximumDataSize else { throw ThumbnailError.tooLarge }
            return try autoreleasepool { try Self.decode(data) }
        }
        let image = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        cache.setObject(image, forKey: key as NSString,
                        cost: image.cgImage.bytesPerRow * image.cgImage.height)
        return image
    }

    static func sourceURL(for request: ArticleThumbnailRequest) -> URL? {
        let reference = request.reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !reference.isEmpty else { return nil }
        let base = URL(string: PreviewResourceHandler.documentBase(
            documentURL: request.documentURL, libraryRoot: request.libraryRoot
        ))
        guard let url = URL(string: reference, relativeTo: base)?.absoluteURL,
              let scheme = url.scheme?.lowercased() else { return nil }
        if ["https", "http"].contains(scheme) {
            return url.host?.isEmpty == false ? url : nil
        }
        guard scheme == "mweblite", url.host == "library", let root = request.libraryRoot else { return nil }
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let document = request.documentURL.standardizedFileURL.resolvingSymlinksInPath()
        guard document.path.hasPrefix(resolvedRoot.path + "/") else { return nil }
        return PreviewResourceHandler.confinedURL(path: url.path, root: root)
    }

    private static func download(_ url: URL) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        let session = URLSession(configuration: configuration, delegate: ThumbnailRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode),
              response.expectedContentLength <= Int64(maximumDataSize) else { throw ThumbnailError.invalidSource }
        var data = Data()
        if response.expectedContentLength > 0 {
            data.reserveCapacity(Int(response.expectedContentLength))
        }
        for try await byte in bytes {
            guard data.count < maximumDataSize else { throw ThumbnailError.tooLarge }
            data.append(byte)
            if data.count.isMultiple(of: 4096) { try Task.checkCancellation() }
        }
        return data
    }

    private static func decode(_ data: Data) throws -> ArticleThumbnailImage {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceShouldCacheImmediately: true
        ]
        // Decode only identified raster formats here. SVG must take the checked
        // path below even if a future ImageIO release gains an SVG decoder.
        let rasterTypes: Set<String> = [
            "public.png", "public.jpeg", "public.jpeg-2000", "public.tiff",
            "com.compuserve.gif", "org.webmproject.webp", "com.microsoft.bmp",
            "public.heic", "public.heif", "public.heics", "public.avif"
        ]
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let type = CGImageSourceGetType(source), rasterTypes.contains(type as String),
           let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
            return ArticleThumbnailImage(image)
        }
        // Native SVG support is checked against all three committed SVG fixtures.
        // Only self-contained static SVG reaches AppKit; it cannot load external files.
        guard ThumbnailSVGPolicy.accepts(data), let image = NSImage(data: data),
              image.size.width.isFinite, image.size.height.isFinite,
              image.size.width > 0, image.size.height > 0 else { throw ThumbnailError.unsupportedImage }
        let scale = CGFloat(maximumPixelSize) / max(image.size.width, image.size.height)
        let width = max(1, Int((image.size.width * scale).rounded()))
        let height = max(1, Int((image.size.height * scale).rounded()))
        guard let bitmap = CGContext(data: nil, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: width * 4,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ThumbnailError.unsupportedImage
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let context = NSGraphicsContext(cgContext: bitmap, flipped: false)
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        image.draw(in: NSRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)),
                   from: .zero, operation: .copy, fraction: 1)
        context.flushGraphics()
        guard let result = bitmap.makeImage() else { throw ThumbnailError.unsupportedImage }
        return ArticleThumbnailImage(result)
    }

    private enum ThumbnailError: Error { case invalidSource, tooLarge, unsupportedImage }
}

private final class ThumbnailRedirectPolicy: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let allowed = ["http", "https"].contains(request.url?.scheme?.lowercased() ?? "")
        completionHandler(allowed ? request : nil)
    }
}

/// A small static-SVG allowlist, rather than a browser or a general XML renderer.
private final class ThumbnailSVGPolicy: NSObject, XMLParserDelegate {
    private var valid = true
    private var sawRoot = false
    private static let elements: Set<String> = [
        "svg", "g", "defs", "path", "rect", "circle", "ellipse", "line", "polyline", "polygon",
        "text", "tspan", "title", "desc", "linearGradient", "radialGradient", "stop", "clipPath", "mask"
    ]

    static func accepts(_ data: Data) -> Bool {
        guard let source = String(data: data, encoding: .utf8),
              source.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              source.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { return false }
        let policy = ThumbnailSVGPolicy()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.shouldProcessNamespaces = true
        parser.delegate = policy
        return parser.parse() && policy.valid && policy.sawRoot
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if !sawRoot {
            valid = elementName == "svg"
            sawRoot = true
        }
        if !Self.elements.contains(elementName) || (namespaceURI != nil && namespaceURI != "http://www.w3.org/2000/svg") {
            valid = false
        }
        for (name, value) in attributeDict {
            let name = name.lowercased()
            if name.hasPrefix("on") || name == "style" || name.hasSuffix("href")
                || name == "xml:base" || value.contains("\\") {
                valid = false
            }
            if value.range(of: "url", options: .caseInsensitive) != nil,
               value.range(of: #"^url\(\s*#[A-Za-z0-9_-]+\s*\)$"#, options: .regularExpression) == nil {
                valid = false
            }
        }
        if !valid { parser.abortParsing() }
    }

    func parser(_ parser: XMLParser, foundProcessingInstructionWithTarget target: String, data: String?) {
        valid = false
        parser.abortParsing()
    }
}
