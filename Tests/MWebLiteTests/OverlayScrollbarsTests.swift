import AppKit
import SwiftUI
import XCTest
import CaseReporting
import MWebCore
@testable import MWebLite

final class OverlayScrollbarsTests: CaseReportingTestCase {
    @MainActor
    func test_SCROLL_001_OverflowDoesNotReserveRowWidth() async throws {
        _ = NSApplication.shared
        let probe = ScrollbarRowProbe()
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 360, height: 400),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: ScrollbarTimelineFixture(count: 18, revision: 0, probe: probe))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(NSSize(width: 360, height: 400))
        defer {
            window.contentView = nil
            window.close()
        }

        await waitFor("The production timeline mounts its first native row") {
            host.layoutSubtreeIfNeeded()
            return probe.firstRow?.enclosingScrollView != nil
        }
        let scrollView = try XCTUnwrap(probe.firstRow?.enclosingScrollView)
        let firstRow = try XCTUnwrap(probe.firstRow)
        await waitFor("The initial list uses full-width native layout before any style injection") {
            host.layoutSubtreeIfNeeded()
            let rowInHost = firstRow.convert(firstRow.bounds, to: host)
            let scrollInHost = scrollView.convert(scrollView.bounds, to: host)
            return scrollView.scrollerStyle == .overlay && scrollView.hasVerticalScroller
                && abs(scrollView.frame.width - host.bounds.width) <= 0.5
                && abs(scrollView.contentView.frame.width - host.bounds.width) <= 0.5
                && abs(firstRow.bounds.width - (host.bounds.width - 20)) <= 0.5
                && abs(rowInHost.minX - (host.bounds.minX + 10)) <= 0.5
                && abs(rowInHost.maxX - (host.bounds.maxX - 10)) <= 0.5
                && abs(scrollInHost.minX - host.bounds.minX) <= 0.5
                && abs(scrollInHost.maxX - host.bounds.maxX) <= 0.5
        }
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        host.layoutSubtreeIfNeeded()
        let initialRow = firstRow.convert(firstRow.bounds, to: host)
        let initialScroll = scrollView.convert(scrollView.bounds, to: host)
        let baseline = "Initial system-preference layout: preferred=\(NSScroller.preferredScrollerStyle.rawValue), "
            + "host=\(host.bounds), scroll=\(initialScroll), clip=\(scrollView.contentView.frame), row=\(initialRow)"
        XCTAssertEqual(scrollView.frame.width, host.bounds.width, accuracy: 0.5, baseline)
        XCTAssertEqual(scrollView.contentView.frame.width, host.bounds.width, accuracy: 0.5, baseline)
        XCTAssertEqual(firstRow.bounds.width, host.bounds.width - 20, accuracy: 0.5, baseline)
        XCTAssertEqual(initialRow.minX, host.bounds.minX + 10, accuracy: 0.5, baseline)
        XCTAssertEqual(initialRow.maxX, host.bounds.maxX - 10, accuracy: 0.5, baseline)
        XCTAssertEqual(initialScroll.minX, host.bounds.minX, accuracy: 0.5, baseline)
        XCTAssertEqual(initialScroll.maxX, host.bounds.maxX, accuracy: 0.5, baseline)

        // Simulate the existing view receiving a legacy style without changing
        // the user's system preference. The production modifier must recover.
        scrollView.scrollerStyle = .legacy
        scrollView.needsLayout = true

        for (revision, sample) in [(18, CGFloat(360)), (18, 360), (1, 360), (18, 420), (1, 420), (18, 360)].enumerated() {
            window.setContentSize(NSSize(width: sample.1, height: 400))
            host.rootView = ScrollbarTimelineFixture(count: sample.0, revision: revision + 1, probe: probe)
            // A representable update and overlay style can precede AppKit's next
            // sizing pass. Wait for the native hierarchy's actual geometry, not
            // just the property changes that request it.
            await waitFor("Timeline revision \(revision + 1) completes native size negotiation") {
                host.layoutSubtreeIfNeeded()
                guard let row = probe.firstRow, let document = scrollView.documentView else { return false }
                let width = host.bounds.width
                let contentHeightMatches = sample.0 == 1
                    || document.frame.height > scrollView.contentView.bounds.height
                return probe.revision == revision + 1
                    && scrollView.scrollerStyle == .overlay
                    && scrollView.hasVerticalScroller
                    && abs(width - sample.1) <= 0.5
                    && abs(scrollView.frame.width - width) <= 0.5
                    && abs(scrollView.contentView.frame.width - width) <= 0.5
                    && abs(row.bounds.width - (width - 20)) <= 0.5
                    && abs(row.convert(row.bounds, to: host).minX - (host.bounds.minX + 10)) <= 0.5
                    && abs(row.convert(row.bounds, to: host).maxX - (host.bounds.maxX - 10)) <= 0.5
                    && contentHeightMatches
            }
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            host.layoutSubtreeIfNeeded()
            let row = try XCTUnwrap(probe.firstRow)
            let expectedWidth = host.bounds.width - 20
            let rowInHost = row.convert(row.bounds, to: host)
            let scrollInHost = scrollView.convert(scrollView.bounds, to: host)
            let diagnostic = "count=\(sample.0), style=\(scrollView.scrollerStyle.rawValue), "
                + "preferred=\(NSScroller.preferredScrollerStyle.rawValue), "
                + "scroll=\(scrollView.frame), clip=\(scrollView.contentView.frame), "
                + "document=\(String(describing: scrollView.documentView?.frame)), "
                + "insets=\(scrollView.contentInsets), row=\(row.frame), rowInHost=\(rowInHost)"

            XCTAssertTrue(row === firstRow, "Filtering keeps the first row mounted")
            XCTAssertTrue(row.enclosingScrollView === scrollView, "Filtering keeps the scroll container mounted")
            XCTAssertEqual(scrollView.frame.width, host.bounds.width, accuracy: 0.5, diagnostic)
            XCTAssertEqual(scrollView.contentView.frame.width, host.bounds.width, accuracy: 0.5, diagnostic)
            XCTAssertEqual(row.bounds.width, expectedWidth, accuracy: 0.5, diagnostic)
            XCTAssertEqual(rowInHost.minX, host.bounds.minX + 10, accuracy: 0.5, diagnostic)
            XCTAssertEqual(rowInHost.maxX, host.bounds.maxX - 10, accuracy: 0.5, diagnostic)
            XCTAssertEqual(scrollInHost.minX, host.bounds.minX, accuracy: 0.5, diagnostic)
            XCTAssertEqual(scrollInHost.maxX, host.bounds.maxX, accuracy: 0.5, diagnostic)
            XCTAssertEqual(scrollView.scrollerStyle, .overlay, diagnostic)
            XCTAssertTrue(scrollView.hasVerticalScroller, "SwiftUI updates retain the native overlay scroller")
            XCTAssertTrue(scrollView.autohidesScrollers, "Short content can hide its native overlay knob")
            if sample.0 > 1 {
                XCTAssertGreaterThan(try XCTUnwrap(scrollView.documentView).frame.height,
                                     scrollView.contentView.bounds.height, diagnostic)
            }
        }
    }

    @MainActor
    private func waitFor(_ description: String, condition: () -> Bool,
                         file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), description, file: file, line: line)
    }
}

@MainActor
private final class ScrollbarRowProbe {
    weak var firstRow: NSView?
    var revision = -1
}

private struct ScrollbarTimelineFixture: View {
    let count: Int
    let revision: Int
    let probe: ScrollbarRowProbe

    var body: some View {
        let articles = (0..<count).map {
            MWebArticle(id: "\($0)", title: "Article \($0)", excerpt: "Synthetic timeline row",
                        modifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
                        createdAt: nil, categoryIDs: [], isTrashed: false,
                        isPinned: false, sort: 0, isAvailable: true)
        }
        ArticleTimelineList(entries: ArticleTimelineGrouping.entries(articles: articles)) { entry in
            ScrollbarNativeRow(isFirst: entry.id == "0", revision: revision, probe: probe)
                .frame(maxWidth: .infinity)
                .frame(height: 80)
        }
    }
}

private struct ScrollbarNativeRow: NSViewRepresentable {
    let isFirst: Bool
    let revision: Int
    let probe: ScrollbarRowProbe

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard isFirst else { return }
        probe.firstRow = nsView
        probe.revision = revision
    }
}
