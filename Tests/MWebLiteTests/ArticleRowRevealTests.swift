import AppKit
import SwiftUI
import XCTest
import CaseReporting
import MWebCore
@testable import MWebLite

final class ArticleRowRevealTests: CaseReportingTestCase {
    @MainActor
    func test_SCROLL_002_SelectionClearsStickyHeadersWithoutMovingVisibleRows() async throws {
        _ = NSApplication.shared
        let state = RowRevealFixtureState()
        let probe = RowRevealProbe()
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 360, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: RowRevealFixture(state: state, probe: probe))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(NSSize(width: 360, height: 400))
        defer {
            window.contentView = nil
            window.close()
        }
        _ = try await settledRow("0", probe: probe, host: host)

        // Mount Previous Year, then put its card near the visible top, as when
        // the user scrolls to and clicks the year boundary in the real app.
        state.selectedID = "9"
        let previousYear = try await settledRow("9", probe: probe, host: host)
        let scrollView = try XCTUnwrap(previousYear.enclosingScrollView)
        let document = try XCTUnwrap(scrollView.documentView)
        let rowRect = previousYear.convert(previousYear.bounds, to: document)
        var viewport = scrollView.documentVisibleRect
        viewport.origin.y = document.isFlipped
            ? rowRect.minY - 90
            : rowRect.maxY + 90 - viewport.height
        _ = document.scrollRectToVisible(viewport)
        _ = try await settledRow("9", probe: probe, host: host)
        XCTAssertEqual(topClearance(of: previousYear, in: scrollView), 90, accuracy: 0.5)

        // The same two selection changes made by Up at this boundary.
        state.selectedID = "8"
        _ = try await settledRow("8", probe: probe, host: host)
        state.selectedID = "7"
        let september3 = try await settledRow("7", probe: probe, host: host)
        XCTAssertGreaterThanOrEqual(topClearance(of: september3, in: scrollView), 67.5,
                                    "The selected title must be below both sticky headers")
        let selectedRect = september3.convert(september3.bounds, to: document)
        let visible = scrollView.documentVisibleRect
        XCTAssertGreaterThanOrEqual(selectedRect.minY, visible.minY - 0.5)
        XCTAssertLessThanOrEqual(selectedRect.maxY, visible.maxY + 0.5,
                                 "The complete selected card must remain visible")

        // A fully visible adjacent card needs no scroll adjustment.
        let beforeClick = scrollView.contentView.bounds.origin
        state.selectedID = "8"
        let visibleRow = try await settledRow("8", probe: probe, host: host)
        XCTAssertGreaterThanOrEqual(topClearance(of: visibleRow, in: scrollView), 67.5)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, beforeClick.x, accuracy: 0.5)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, beforeClick.y, accuracy: 0.5,
                       "Selecting a fully visible row must not recenter the list")

        // Later manual scrolling and unrelated updates must not replay a reveal.
        var movedViewport = scrollView.documentVisibleRect
        movedViewport.origin.y += document.isFlipped ? 20 : -20
        _ = document.scrollRectToVisible(movedViewport)
        let afterManualScroll = scrollView.contentView.bounds.origin
        state.revision += 1
        _ = try await settledRow("8", probe: probe, host: host)
        XCTAssertEqual(scrollView.contentView.bounds.origin.x, afterManualScroll.x, accuracy: 0.5)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, afterManualScroll.y, accuracy: 0.5,
                       "An unchanged selection must not pull manual scrolling back")

        // A newly mounted native anchor must also respect the completed request.
        // Put the selected row partly under the headers to make a replay observable.
        let coordinator = try XCTUnwrap(revealCoordinator(in: document))
        let visibleRowRect = visibleRow.convert(visibleRow.bounds, to: document)
        var remountViewport = scrollView.documentVisibleRect
        remountViewport.origin.y = document.isFlipped
            ? visibleRowRect.minY - 24
            : visibleRowRect.maxY + 24 - remountViewport.height
        _ = document.scrollRectToVisible(remountViewport)
        let beforeRemount = scrollView.contentView.bounds.origin
        let remounted = ArticleRowRevealView(frame: visibleRow.bounds)
        visibleRow.addSubview(remounted)
        remounted.configure(articleID: "8", selectedArticleID: "8", headerInset: 68, coordinator: coordinator)
        _ = try await settledRow("8", probe: probe, host: host)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, beforeRemount.y, accuracy: 0.5,
                       "Remounting the same selected row must not replay its completed reveal")
        remounted.invalidate()
        remounted.removeFromSuperview()
    }

    @MainActor
    private func topClearance(of row: NSView, in scrollView: NSScrollView) -> CGFloat {
        guard let document = scrollView.documentView else { return -.infinity }
        let rect = row.convert(row.bounds, to: document)
        let visible = scrollView.documentVisibleRect
        return document.isFlipped ? rect.minY - visible.minY : visible.maxY - rect.maxY
    }

    @MainActor
    private func revealCoordinator(in view: NSView) -> ArticleRowRevealCoordinator? {
        if let anchor = view as? ArticleRowRevealView, let coordinator = anchor.coordinator { return coordinator }
        for child in view.subviews {
            if let coordinator = revealCoordinator(in: child) { return coordinator }
        }
        return nil
    }

    @MainActor
    private func settledRow(
        _ id: String, probe: RowRevealProbe, host: NSView
    ) async throws -> NSView {
        let deadline = Date().addingTimeInterval(3)
        var previous: [CGRect]?
        var stableSamples = 0
        while Date() < deadline {
            host.layoutSubtreeIfNeeded()
            if let row = probe.rows[id]?.view, row.window != nil,
               let scrollView = row.enclosingScrollView, let document = scrollView.documentView,
               row.bounds.width > 0, row.bounds.height > 0 {
                scrollView.layoutSubtreeIfNeeded()
                let snapshot = [
                    scrollView.frame, document.frame, scrollView.documentVisibleRect,
                    row.convert(row.bounds, to: document)
                ]
                stableSamples = snapshot == previous ? stableSamples + 1 : 0
                previous = snapshot
                if stableSamples >= 3 { return row }
            } else {
                stableSamples = 0
                previous = nil
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        throw NSError(domain: "RowRevealTest", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Row \(id) did not reach stable native geometry"])
    }
}

@MainActor
private final class RowRevealFixtureState: ObservableObject {
    @Published var selectedID: String?
    @Published var revision = 0
}

@MainActor
private final class RowRevealProbe {
    struct WeakRow {
        weak var view: NSView?
    }
    var rows: [String: WeakRow] = [:]
}

private struct RowRevealFixture: View {
    @ObservedObject var state: RowRevealFixtureState
    let probe: RowRevealProbe

    private var entries: [ArticleTimelineGrouping.Entry] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let articles = (0..<18).map { index in
            let year = index < 9 ? 2026 : 2025
            let month = index < 4 || index >= 9 ? 10 : 9
            let date = calendar.date(from: DateComponents(year: year, month: month, day: 20))!
            return MWebArticle(id: "\(index)", title: "Article \(index)", excerpt: "",
                               modifiedAt: date, createdAt: nil, categoryIDs: [],
                               isTrashed: false, isPinned: false, sort: 0, isAvailable: true)
        }
        return ArticleTimelineGrouping.entries(articles: articles, calendar: calendar)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ArticleTimelineList(entries: entries, selectedArticleID: state.selectedID) { entry in
                RowRevealNativeRow(id: entry.id, revision: state.revision, probe: probe)
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
            }
            .onChange(of: state.selectedID) { _, selected in
                if let selected { proxy.scrollTo(selected) }
            }
        }
    }
}

private struct RowRevealNativeRow: NSViewRepresentable {
    let id: String
    let revision: Int
    let probe: RowRevealProbe

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        probe.rows[id] = RowRevealProbe.WeakRow(view: nsView)
    }
}
