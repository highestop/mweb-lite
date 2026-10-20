import AppKit
import XCTest
import CaseReporting
@testable import MWebLite

final class ArticleRowMouseSelectionTests: CaseReportingTestCase {
    func test_ROW_001_AnchorAttachesToWholeRowAndUpdatesReusedAction() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 160),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let firstRow = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
            let secondRow = NSView(frame: NSRect(x: 0, y: 80, width: 300, height: 80))
            let controller = ArticleListSelectionController()
            let keyboard = ArticleListKeyboardAnchor()
            window.contentView?.addSubview(keyboard)
            let anchor = ArticleRowSelectionAnchor(frame: firstRow.bounds)
            var selected = ""
            var selections = 0
            var moves: [Int] = []
            window.contentView?.addSubview(firstRow)
            window.contentView?.addSubview(secondRow)
            firstRow.addSubview(anchor)
            anchor.configure(isEnabled: true, controller: controller, onSelect: {
                selected = "first"
                selections += 1
                window.makeFirstResponder(nil)
            })
            keyboard.configure(isEnabled: true, controller: controller, onMove: {
                moves.append($0)
                window.makeFirstResponder(nil)
            })

            XCTAssertTrue(firstRow.hitTest(NSPoint(x: 1, y: 1)) === anchor)
            XCTAssertTrue(firstRow.hitTest(NSPoint(x: 299, y: 79)) === anchor)
            anchor.mouseDown(with: try mouseEvent(.leftMouseDown))
            XCTAssertEqual(selected, "first") // Assert before sending any mouse-up.
            XCTAssertEqual(selections, 1)
            XCTAssertTrue(window.firstResponder === keyboard)
            XCTAssertTrue(anchor.gestureRecognizers.isEmpty)
            XCTAssertEqual(keyboard.focusRingType, .none)
            XCTAssertNil(keyboard.hitTest(.zero))
            keyboard.keyDown(with: try arrowEvent(125))
            keyboard.keyDown(with: try arrowEvent(126))
            XCTAssertEqual(moves, [1, -1])
            XCTAssertTrue(window.firstResponder === keyboard)

            anchor.removeFromSuperview()
            XCTAssertTrue(window.firstResponder === keyboard)
            keyboard.keyDown(with: try arrowEvent(125))
            XCTAssertEqual(moves, [1, -1, 1])
            secondRow.addSubview(anchor)
            anchor.configure(isEnabled: true, controller: controller, onSelect: {
                selected = "second"
                selections += 1
            })
            keyboard.configure(isEnabled: true, controller: controller, onMove: { moves.append($0 * 10) })

            XCTAssertTrue(firstRow.subviews.isEmpty)
            XCTAssertTrue(anchor.superview === secondRow)
            anchor.mouseDown(with: try mouseEvent(.leftMouseDown))
            XCTAssertEqual(selected, "second")
            anchor.mouseUp(with: try mouseEvent(.leftMouseUp))
            XCTAssertEqual(selections, 2)
            keyboard.keyDown(with: try arrowEvent(125))
            XCTAssertEqual(moves, [1, -1, 1, 10])
            anchor.invalidate()
        }
    }

    func test_ROW_002_DisabledAndDismantledAnchorCannotSelect() async throws {
        try await MainActor.run {
            let row = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
            let controller = ArticleListSelectionController()
            let keyboard = ArticleListKeyboardAnchor()
            let anchor = ArticleRowSelectionAnchor(frame: row.bounds)
            var count = 0
            row.addSubview(anchor)
            anchor.configure(isEnabled: true, controller: controller) { count += 1 }

            anchor.configure(isEnabled: false, controller: controller) { count += 1 }
            keyboard.configure(isEnabled: false, controller: controller) { _ in count += 1 }
            anchor.mouseDown(with: try mouseEvent(.leftMouseDown))
            keyboard.keyDown(with: try arrowEvent(125))
            XCTAssertEqual(count, 0)
            XCTAssertTrue(keyboard.acceptsFirstResponder)

            anchor.invalidate()
            keyboard.invalidate()
            anchor.configure(isEnabled: true, controller: controller) { count += 1 }
            keyboard.configure(isEnabled: true, controller: controller) { _ in count += 1 }
            anchor.mouseDown(with: try mouseEvent(.leftMouseDown))
            keyboard.keyDown(with: try arrowEvent(125))
            XCTAssertEqual(count, 0)
            XCTAssertFalse(keyboard.acceptsFirstResponder)
            XCTAssertNil(anchor.hitTest(NSPoint(x: 10, y: 10)))
        }
    }

    func test_ROW_003_OnlyUnmodifiedPrimaryMouseDownIsAccepted() async throws {
        try await MainActor.run {
            let controller = ArticleListSelectionController()
            let anchor = ArticleRowSelectionAnchor()
            var selections = 0
            anchor.configure(isEnabled: true, controller: controller) { selections += 1 }
            XCTAssertTrue(ArticleRowSelectionAnchor.accepts(try mouseEvent(.leftMouseDown)))
            XCTAssertTrue(ArticleRowSelectionAnchor.accepts(try mouseEvent(.leftMouseDown, .capsLock)))
            for modifier: NSEvent.ModifierFlags in [.shift, .control, .option, .command, .function] {
                let event = try mouseEvent(.leftMouseDown, modifier)
                XCTAssertFalse(ArticleRowSelectionAnchor.accepts(event))
                anchor.mouseDown(with: event)
            }
            XCTAssertFalse(ArticleRowSelectionAnchor.accepts(try mouseEvent(.rightMouseDown)))
            XCTAssertFalse(ArticleRowSelectionAnchor.accepts(try mouseEvent(.leftMouseUp)))
            XCTAssertEqual(selections, 0)
        }
    }

    private func mouseEvent(_ type: NSEvent.EventType, _ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: modifiers,
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        eventNumber: 0, clickCount: 1, pressure: 1))
    }

    private func arrowEvent(_ keyCode: UInt16) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero,
                                      modifierFlags: [.function, .numericPad],
                                      timestamp: 0, windowNumber: 0, context: nil,
                                      characters: keyCode == 125 ? "\u{f701}" : "\u{f700}",
                                      charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode))
    }
}
