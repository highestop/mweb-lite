import AppKit
import SwiftUI
import XCTest
import CaseReporting
@testable import MWebLite

final class DrawerWorkspaceLayoutTests: CaseReportingTestCase {
    @MainActor
    func test_DRAWER_002_NativeScrollViewKeepsItsRightEdgeAfterSizeNegotiation() async throws {
        // Given: the production layout hosts a real scroll view whose wrapper
        // chooses a pixel-rounded width instead of accepting the proposal exactly.
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 137, y: 93, width: 1280, height: 640),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let probe = DrawerNativeLayoutProbe(scale: window.backingScaleFactor)
        let samples: [(progress: CGFloat, category: CGFloat, article: CGFloat)] = [
            (0, 215, 340),
            (1, 215.25, 340.5),
            (1, 238.25, 340.5),
            (1, 238.25, 367.25),
            (0.875, 238.25, 367.25),
            (0.5, 238.25, 367.25),
            (0.125, 238.25, 367.25),
            (0, 238.25, 367.25),
            (0.625, 198.75, 391.25),
            (1, 198.75, 391.25),
            (1, 215.25, 340.5),
            (0, 215.25, 340.5)
        ]
        let host = NSHostingView(rootView: DrawerNativeLayoutFixture(
            progress: 0, category: 215, article: 340, revision: -1, probe: probe
        ))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(NSSize(width: 1280, height: 640))
        defer {
            window.contentView = nil
            window.close()
        }
        let accuracy = 0.51 / probe.scale
        var originalScrollView: NSScrollView?
        var scrollerRightInset: CGFloat?
        var observedDifferentPreferredWidth = false

        // When: resize each column and sample opening, closing, and reversal
        // progress without replacing the native detail view.
        for (revision, sample) in samples.enumerated() {
            host.rootView = DrawerNativeLayoutFixture(
                progress: sample.progress, category: sample.category,
                article: sample.article, revision: revision, probe: probe
            )
            let geometry = DrawerGeometry(
                size: host.bounds.size, progress: sample.progress,
                categoryWidth: sample.category, articleWidth: sample.article
            )
            let preferredWidth = probe.preferredWidth(for: geometry.detailFrame.width)
            let deadline = Date().addingTimeInterval(3)
            func layoutHasUpdated() -> Bool {
                host.layoutSubtreeIfNeeded()
                guard let scrollView = probe.scrollView else { return false }
                return probe.appliedRevision == revision
                    && abs(scrollView.frame.width - preferredWidth) <= accuracy
                    && abs(scrollView.frame.height - host.bounds.height) <= accuracy
            }
            while !layoutHasUpdated(), Date() < deadline {
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            XCTAssertTrue(layoutHasUpdated(), "Native layout did not settle for sample \(revision)")
            let scrollView = try XCTUnwrap(probe.scrollView)
            scrollView.tile()
            scrollView.layoutSubtreeIfNeeded()
            let scroller = try XCTUnwrap(scrollView.verticalScroller)
            let expectedRight = host.convert(host.bounds, to: nil).maxX
            let actualRight = scrollView.convert(scrollView.bounds, to: nil).maxX
            let scrollerRight = scroller.convert(scroller.bounds, to: nil).maxX
            let context = "Sample \(revision): progress \(sample.progress), columns "
                + "\(sample.category)/\(sample.article), proposed \(geometry.detailFrame.width), "
                + "native \(scrollView.frame.width)"

            // Then: both the native view and its scrollbar stay at the window's
            // right edge even when the chosen width differs from the proposal.
            XCTAssertEqual(actualRight, expectedRight, accuracy: accuracy, context)
            if let scrollerRightInset {
                XCTAssertEqual(scrollerRight, expectedRight - scrollerRightInset,
                               accuracy: accuracy, context)
            } else {
                scrollerRightInset = actualRight - scrollerRight
            }
            XCTAssertFalse(scroller.isHidden, context)
            if let originalScrollView {
                XCTAssertTrue(scrollView === originalScrollView, context)
            } else {
                originalScrollView = scrollView
            }
            if abs(scrollView.frame.width - geometry.detailFrame.width) > accuracy {
                observedDifferentPreferredWidth = true
            }
        }
        XCTAssertEqual(probe.creationCount, 1, "Column resizing must keep the native detail mounted")
        XCTAssertTrue(observedDifferentPreferredWidth,
                      "The regression must exercise an actual native size/proposal mismatch")
    }
}

@MainActor
private final class DrawerNativeLayoutProbe {
    let scale: CGFloat
    weak var scrollView: NSScrollView?
    var appliedRevision = -1
    var creationCount = 0

    init(scale: CGFloat) {
        self.scale = max(1, scale)
    }

    func preferredWidth(for proposed: CGFloat) -> CGFloat {
        // This deliberately coarse eight-pixel grid tests the Layout sizing
        // contract; it is not a claim about NSScrollView's default rounding.
        ceil(proposed * scale / 8) * 8 / scale
    }
}

private struct DrawerNativeLayoutFixture: View {
    let progress: CGFloat
    let category: CGFloat
    let article: CGFloat
    let revision: Int
    let probe: DrawerNativeLayoutProbe

    var body: some View {
        DrawerWorkspaceLayout(progress: progress, categoryWidth: category, articleWidth: article) {
            DrawerNativeScrollView(probe: probe, revision: revision)
            Color.clear
            Color.clear
            Color.clear
            Color.clear
        }
    }
}

private struct DrawerNativeScrollView: NSViewRepresentable {
    let probe: DrawerNativeLayoutProbe
    let revision: Int

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.scrollerStyle = .legacy
        scrollView.autohidesScrollers = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.documentView = NSView(frame: NSRect(x: 0, y: 0, width: 1600, height: 2400))
        probe.scrollView = scrollView
        probe.creationCount += 1
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        probe.appliedRevision = revision
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSScrollView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height,
              width.isFinite, height.isFinite else { return nil }
        return CGSize(width: probe.preferredWidth(for: width), height: height)
    }
}
