import AppKit
import SwiftUI
import XCTest
import CaseReporting
@testable import MWebCore
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
        _ = document.scrollToVisible(viewport)
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
        _ = document.scrollToVisible(movedViewport)
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
        _ = document.scrollToVisible(remountViewport)
        let beforeRemount = scrollView.contentView.bounds.origin
        let remounted = ArticleRowRevealView(frame: visibleRow.bounds)
        visibleRow.addSubview(remounted)
        remounted.configure(articleID: "8", headerInset: 68, coordinator: coordinator)
        _ = try await settledRow("8", probe: probe, host: host)
        XCTAssertEqual(scrollView.contentView.bounds.origin.y, beforeRemount.y, accuracy: 0.5,
                       "Remounting the same selected row must not replay its completed reveal")
        remounted.invalidate()
        remounted.removeFromSuperview()

        try await verifyLibrarySelection()
    }

    /// Exercise the real store's pending selection, asynchronous document load,
    /// and resulting view updates, rather than only a synchronous fixture binding.
    @MainActor
    private func verifyLibrarySelection() async throws {
        let root = try makeDateLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore()
        store.mode = .editor
        store.open(root, remember: false)
        try await waitFor { !store.isBusy && store.rootURL != nil }
        XCTAssertNil(store.errorMessage)
        store.selectedCategory = "107"
        XCTAssertEqual(store.visibleArticles.count, 18)

        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 1100, height: 500),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: LibraryView(store: store))
        host.sizingOptions = []
        window.contentView = host
        window.setContentSize(NSSize(width: 1100, height: 500))
        defer {
            window.contentView = nil
            window.close()
        }
        host.layoutSubtreeIfNeeded()
        store.selectArticle("12006")
        try await waitFor {
            host.layoutSubtreeIfNeeded()
            return !store.isBusy && store.document?.articleID == "12006"
        }
        let previousYear = try await settledRow(host: host) {
            self.anchor(for: "12006", in: host)
        }
        let scrollView = try XCTUnwrap(previousYear.enclosingScrollView)
        let document = try XCTUnwrap(scrollView.documentView)
        let rowRect = previousYear.convert(previousYear.bounds, to: document)
        var viewport = scrollView.documentVisibleRect
        viewport.origin.y = document.isFlipped
            ? rowRect.minY - 90
            : rowRect.maxY + 90 - viewport.height
        _ = document.scrollToVisible(viewport)
        _ = try await settledRow(host: host) { self.anchor(for: "12006", in: host) }
        XCTAssertEqual(topClearance(of: previousYear, in: scrollView), 90, accuracy: 0.5)

        let keyboard = try XCTUnwrap(keyboardAnchor(in: host))
        let up = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [.function, .numericPad],
            timestamp: 0, windowNumber: window.windowNumber, context: nil,
            characters: "\u{f700}", charactersIgnoringModifiers: "\u{f700}",
            isARepeat: false, keyCode: 126
        ))
        for id in ["12010", "12009"] {
            keyboard.keyDown(with: up)
            try await waitFor {
                host.layoutSubtreeIfNeeded()
                return !store.isBusy && store.document?.articleID == id
            }
            let selected = try await settledRow(host: host) { self.anchor(for: id, in: host) }
            XCTAssertGreaterThanOrEqual(topClearance(of: selected, in: scrollView), 67.5,
                                       "The real loaded selection must clear both sticky headers")
            let rect = selected.convert(selected.bounds, to: document)
            XCTAssertGreaterThanOrEqual(rect.minY, scrollView.documentVisibleRect.minY - 0.5)
            XCTAssertLessThanOrEqual(rect.maxY, scrollView.documentVisibleRect.maxY + 0.5)
        }
        XCTAssertNil(store.errorMessage)
    }

    private func makeDateLibrary() throws -> URL {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MWebLite-RowReveal-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: fixtures.appendingPathComponent("Library"), to: root)
        let dates = fixtures.appendingPathComponent("DateGroups")
        let database = try SQLiteDatabase(url: root.appendingPathComponent("mainlib.db"), writable: true, create: true)
        for sqlURL in [
            root.appendingPathComponent("schema.sql"), root.appendingPathComponent("seed.sql"),
            dates.appendingPathComponent("seed.sql")
        ] {
            let sql = try String(contentsOf: sqlURL, encoding: .utf8)
            for statement in sql.split(separator: ";") where !statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                try database.execute(String(statement))
            }
        }
        for file in try FileManager.default.contentsOfDirectory(
            at: dates.appendingPathComponent("docs"), includingPropertiesForKeys: nil
        ) {
            try FileManager.default.copyItem(at: file, to: root.appendingPathComponent("docs/\(file.lastPathComponent)"))
        }
        return root
    }

    @MainActor
    private func waitFor(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        guard condition() else {
            throw NSError(domain: "RowRevealTest", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "The real store did not complete selection"])
        }
    }

    @MainActor
    private func anchor(for id: String, in view: NSView) -> ArticleRowRevealView? {
        if let anchor = view as? ArticleRowRevealView, anchor.articleID == id { return anchor }
        for child in view.subviews {
            if let anchor = anchor(for: id, in: child) { return anchor }
        }
        return nil
    }

    @MainActor
    private func keyboardAnchor(in view: NSView) -> ArticleListKeyboardAnchor? {
        if let anchor = view as? ArticleListKeyboardAnchor { return anchor }
        for child in view.subviews {
            if let anchor = keyboardAnchor(in: child) { return anchor }
        }
        return nil
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
        try await settledRow(host: host) { probe.rows[id]?.view }
    }

    @MainActor
    private func settledRow(host: NSView, row: () -> NSView?) async throws -> NSView {
        let deadline = Date().addingTimeInterval(3)
        var previous: [CGRect]?
        var stableSamples = 0
        while Date() < deadline {
            host.layoutSubtreeIfNeeded()
            if let row = row(), row.window != nil,
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
                      userInfo: [NSLocalizedDescriptionKey: "The selected row did not reach stable native geometry"])
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
                               modifiedAt: date, createdAt: date, categoryIDs: [],
                               isTrashed: false, isPinned: false, sort: 0, isAvailable: true)
        }
        return ArticleTimelineGrouping.entries(articles: articles, calendar: calendar)
    }

    var body: some View {
        ArticleTimelineList(entries: entries, selectedArticleID: state.selectedID) { entry in
            RowRevealNativeRow(id: entry.id, revision: state.revision, probe: probe)
                .frame(maxWidth: .infinity)
                .frame(height: 80)
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
