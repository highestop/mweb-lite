import AppKit
import XCTest
import CaseReporting
@testable import MWebLite

final class ArticleRowMouseSelectionTests: CaseReportingTestCase {
    func test_ROW_001_AnchorAttachesToWholeRowAndUpdatesReusedAction() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let firstRow = NSTableRowView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
            let secondRow = NSTableRowView(frame: firstRow.frame)
            let container = NSView(frame: NSRect(x: 6, y: 0, width: 288, height: 80))
            let anchor = ArticleRowSelectionAnchor(frame: container.bounds)
            var selected = ""
            firstRow.addSubview(container)
            container.addSubview(anchor)
            anchor.configure(isEnabled: true) { selected = "first" }

            let recognizer = try XCTUnwrap(firstRow.gestureRecognizers.first as? ArticleRowMouseDownRecognizer)
            XCTAssertTrue(recognizer.view === firstRow)
            XCTAssertTrue(recognizer.delaysPrimaryMouseButtonEvents)
            XCTAssertNil(anchor.hitTest(NSPoint(x: 10, y: 10)))
            recognizer.onMouseDown?()
            XCTAssertEqual(selected, "first")

            container.removeFromSuperview()
            secondRow.addSubview(container)
            anchor.configure(isEnabled: true) { selected = "second" }

            XCTAssertFalse(firstRow.gestureRecognizers.contains { $0 === recognizer })
            XCTAssertTrue(recognizer.view === secondRow)
            XCTAssertEqual(secondRow.gestureRecognizers.filter { $0 === recognizer }.count, 1)
            recognizer.onMouseDown?()
            XCTAssertEqual(selected, "second")
            anchor.invalidate()
        }
    }

    func test_ROW_002_DisabledAndDismantledAnchorCannotSelect() async throws {
        try await MainActor.run {
            let row = NSTableRowView()
            let anchor = ArticleRowSelectionAnchor()
            var count = 0
            row.addSubview(anchor)
            anchor.configure(isEnabled: true) { count += 1 }
            let recognizer = try XCTUnwrap(row.gestureRecognizers.first as? ArticleRowMouseDownRecognizer)

            anchor.configure(isEnabled: false) { count += 1 }
            XCTAssertFalse(recognizer.isEnabled)
            recognizer.onMouseDown?()
            XCTAssertEqual(count, 0)

            anchor.invalidate()
            anchor.configure(isEnabled: true) { count += 1 }
            anchor.layout()
            XCTAssertNil(recognizer.view)
            XCTAssertNil(recognizer.onMouseDown)
            XCTAssertTrue(row.gestureRecognizers.isEmpty)
        }
    }

    func test_ROW_003_OnlyUnmodifiedPrimaryMouseDownIsAccepted() async throws {
        try await MainActor.run {
            func event(_ type: NSEvent.EventType, _ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
                try XCTUnwrap(NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: modifiers,
                                                timestamp: 0, windowNumber: 0, context: nil,
                                                eventNumber: 0, clickCount: 1, pressure: 1))
            }
            XCTAssertTrue(ArticleRowMouseDownRecognizer.accepts(try event(.leftMouseDown)))
            XCTAssertTrue(ArticleRowMouseDownRecognizer.accepts(try event(.leftMouseDown, .capsLock)))
            for modifier: NSEvent.ModifierFlags in [.shift, .control, .option, .command, .function] {
                XCTAssertFalse(ArticleRowMouseDownRecognizer.accepts(try event(.leftMouseDown, modifier)))
            }
            XCTAssertFalse(ArticleRowMouseDownRecognizer.accepts(try event(.rightMouseDown)))
            XCTAssertFalse(ArticleRowMouseDownRecognizer.accepts(try event(.leftMouseUp)))
        }
    }
}
