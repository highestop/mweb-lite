import AppKit
import XCTest
import CaseReporting
@testable import MWebLite

final class DrawerResizeViewTests: CaseReportingTestCase {
    @MainActor
    func test_DRAWER_003_NativeHandleOwnsCursorAndDragUntilDisabledOrRemoved() throws {
        // Given: a real native handle above a text view in a window. Events below
        // call its handlers directly; this does not simulate OS pointer routing.
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let textView = NSTextView(frame: root.bounds)
        let handle = DrawerResizeView(frame: NSRect(x: 196, y: 16, width: 8, height: 368))
        window.contentView = root
        root.addSubview(textView)
        root.addSubview(handle)
        let originalCursor = NSCursor.current
        defer {
            handle.invalidate()
            window.contentView = nil
            window.close()
            originalCursor.set()
        }
        var widths: [CGFloat] = []
        var highlights: [Bool] = []
        func configure(_ width: CGFloat, enabled: Bool = true) {
            handle.configure(width: width, isEnabled: enabled,
                             onResize: { widths.append($0) }, onHighlight: { highlights.append($0) })
        }
        func event(_ type: NSEvent.EventType, x: CGFloat = 200) throws -> NSEvent {
            let location = NSPoint(x: x, y: 100)
            if [.mouseEntered, .mouseExited, .cursorUpdate].contains(type) {
                return try XCTUnwrap(NSEvent.enterExitEvent(
                    with: type, location: location, modifierFlags: [], timestamp: 0,
                    windowNumber: window.windowNumber, context: nil,
                    eventNumber: 0, trackingNumber: 0, userData: nil
                ))
            }
            return try XCTUnwrap(NSEvent.mouseEvent(
                with: type, location: location, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil,
                eventNumber: 0, clickCount: 1, pressure: 1
            ))
        }
        configure(240)
        handle.updateTrackingAreas()
        XCTAssertTrue(handle.clipsToBounds, "Cursor tracking must stay within the narrow divider")
        XCTAssertEqual(handle.visibleRect, handle.bounds)
        for x in [CGFloat(196.5), 200, 203.5] {
            XCTAssertTrue(root.hitTest(NSPoint(x: x, y: 100)) === handle)
        }
        for x in [CGFloat(195), 205] {
            XCTAssertTrue(root.hitTest(NSPoint(x: x, y: 100)) === textView)
        }
        let tracking = try XCTUnwrap(handle.trackingAreas.first {
            $0.options.contains(.cursorUpdate)
        })
        XCTAssertTrue(tracking.options.contains([.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect]))
        XCTAssertFalse(tracking.options.contains(.activeAlways))
        XCTAssertFalse(handle.mouseDownCanMoveWindow)

        // When: another native view sets an I-beam between cursor updates.
        handle.mouseEntered(with: try event(.mouseEntered))
        XCTAssertEqual(highlights.last, true)
        for _ in 0..<2 {
            NSCursor.iBeam.set()
            handle.cursorUpdate(with: try event(.cursorUpdate))
            XCTAssertEqual(NSCursor.current, .resizeLeftRight)
        }
        NSCursor.pointingHand.set()
        handle.mouseExited(with: try event(.mouseExited, x: 205))
        XCTAssertEqual(NSCursor.current, .pointingHand,
                       "Exit must leave the destination cursor alone, without popping a stale cursor")
        XCTAssertEqual(highlights.last, false)

        // When: layout moves and reconfigures the handle during the same drag.
        handle.mouseDown(with: try event(.leftMouseDown))
        XCTAssertEqual(highlights.last, true)
        handle.setFrameOrigin(NSPoint(x: 236, y: 16))
        configure(280)
        handle.mouseDragged(with: try event(.leftMouseDragged, x: 230))
        handle.mouseExited(with: try event(.mouseExited, x: 230))
        XCTAssertEqual(highlights.last, true, "Dragging keeps the edge highlighted outside its bounds")
        handle.mouseDragged(with: try event(.leftMouseDragged, x: 185))
        XCTAssertEqual(widths, [270, 225],
                       "Use the initial width and window-coordinate delta, not the moved handle's coordinates")
        handle.mouseUp(with: try event(.leftMouseUp, x: 185))
        XCTAssertEqual(highlights.last, false)
        handle.mouseDragged(with: try event(.leftMouseDragged, x: 250))
        XCTAssertEqual(widths, [270, 225], "Mouse-up ends the drag")

        // Then: disabling mid-drag removes native input/cursor ownership.
        handle.mouseDown(with: try event(.leftMouseDown, x: 240))
        configure(280, enabled: false)
        XCTAssertEqual(highlights.last, false)
        XCTAssertTrue(handle.trackingAreas.isEmpty)
        XCTAssertTrue(root.hitTest(NSPoint(x: 240, y: 100)) === textView)
        NSCursor.pointingHand.set()
        handle.cursorUpdate(with: try event(.cursorUpdate, x: 240))
        handle.mouseEntered(with: try event(.mouseEntered, x: 240))
        handle.mouseDown(with: try event(.leftMouseDown, x: 240))
        handle.mouseDragged(with: try event(.leftMouseDragged, x: 300))
        handle.mouseUp(with: try event(.leftMouseUp, x: 300))
        XCTAssertEqual(NSCursor.current, .pointingHand)
        XCTAssertEqual(widths, [270, 225])
        XCTAssertEqual(highlights.last, false)

        // Re-enabling starts a new drag; invalidation releases it and callbacks.
        configure(500)
        XCTAssertFalse(handle.trackingAreas.isEmpty)
        XCTAssertTrue(root.hitTest(NSPoint(x: 240, y: 100)) === handle)
        handle.mouseDown(with: try event(.leftMouseDown, x: 240))
        handle.mouseDragged(with: try event(.leftMouseDragged, x: 245))
        XCTAssertEqual(widths, [270, 225, 505])
        handle.invalidate()
        XCTAssertEqual(highlights.last, false)
        XCTAssertTrue(handle.trackingAreas.isEmpty)
        XCTAssertTrue(root.hitTest(NSPoint(x: 240, y: 100)) === textView)
        let highlightCount = highlights.count
        NSCursor.iBeam.set()
        handle.cursorUpdate(with: try event(.cursorUpdate, x: 240))
        handle.mouseEntered(with: try event(.mouseEntered, x: 240))
        handle.mouseExited(with: try event(.mouseExited, x: 240))
        handle.mouseDown(with: try event(.leftMouseDown, x: 240))
        handle.mouseDragged(with: try event(.leftMouseDragged, x: 300))
        handle.mouseUp(with: try event(.leftMouseUp, x: 300))
        XCTAssertEqual(NSCursor.current, .iBeam)
        XCTAssertEqual(widths, [270, 225, 505])
        XCTAssertEqual(highlights.count, highlightCount)
    }
}
