import AppKit
import SwiftUI
import XCTest
import CaseReporting
@testable import MWebLite

final class MarkdownEditorFocusTests: CaseReportingTestCase {
    func test_FOCUS_001_ResigningFocusCommitsCompositionToBinding() async {
        await MainActor.run {
            _ = NSApplication.shared
            var source = "Before "
            let editor = MarkdownEditor(
                text: Binding(get: { source }, set: { source = $0 }),
                documentID: "composition-fixture", onSave: {}
            )
            let coordinator = editor.makeCoordinator()
            let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
            textView.isRichText = false
            textView.allowsUndo = true
            textView.string = source
            textView.delegate = coordinator
            coordinator.textView = textView
            let window = NSWindow(
                contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: false
            )
            window.contentView = textView
            defer {
                coordinator.highlightWork?.cancel()
                textView.delegate = nil
                window.contentView = nil
            }
            XCTAssertTrue(window.makeFirstResponder(textView))
            textView.setSelectedRange(NSRange(location: 7, length: 0))
            textView.setMarkedText(
                "中文", selectedRange: NSRange(location: 2, length: 0),
                replacementRange: NSRange(location: NSNotFound, length: 0)
            )
            XCTAssertTrue(textView.hasMarkedText())
            XCTAssertEqual(source, "Before ")
            let selection = textView.selectedRange()

            XCTAssertTrue(window.makeFirstResponder(nil))

            XCTAssertFalse(textView.hasMarkedText())
            XCTAssertEqual(textView.string, "Before 中文")
            XCTAssertEqual(source, textView.string)
            XCTAssertEqual(textView.selectedRange(), selection)
            XCTAssertTrue(window.makeFirstResponder(textView))
            XCTAssertEqual(textView.selectedRange(), selection)
        }
    }

    @MainActor
    func test_FOCUS_002_FocusRoundTripPreservesSelectionAndUndo() async throws {
        _ = NSApplication.shared
        let store = LibraryStore()
        store.mode = .editor
        let original = "# Title\n原文"
        var source = original
        let focused = expectation(description: "The editor consumes the return-to-edit focus request")
        func editor() -> MarkdownEditor {
            MarkdownEditor(
                text: Binding(get: { source }, set: { source = $0 }),
                documentID: "undo-fixture", onSave: {}, focusRequest: store.editorFocusRequest,
                onFocusHandled: {
                    store.consumeEditorFocus($0)
                    focused.fulfill()
                }
            )
        }
        let coordinator = editor().makeCoordinator()
        let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        textView.isRichText = false
        textView.allowsUndo = true
        textView.string = source
        textView.delegate = coordinator
        coordinator.textView = textView
        let window = NSWindow(
            contentRect: textView.frame, styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = textView
        defer {
            coordinator.highlightWork?.cancel()
            textView.delegate = nil
            window.contentView = nil
        }
        XCTAssertTrue(window.makeFirstResponder(textView))
        let undoManager = try XCTUnwrap(textView.undoManager)
        undoManager.groupsByEvent = false
        undoManager.beginUndoGrouping()
        textView.insertText("追加", replacementRange: NSRange(location: (source as NSString).length, length: 0))
        undoManager.endUndoGrouping()
        XCTAssertEqual(source, original + "追加")
        let selection = (source as NSString).range(of: "原文")
        textView.setSelectedRange(selection)

        store.setMode(.preview)
        XCTAssertNil(store.editorFocusRequest)
        // A toolbar click can leave the window as responder. The production focus
        // request, rather than a manual makeFirstResponder(textView), must restore it.
        XCTAssertTrue(window.makeFirstResponder(nil))
        store.setMode(.editor)
        let request = try XCTUnwrap(store.editorFocusRequest)
        XCTAssertEqual(request.selection, .preserveSelection)
        coordinator.parent = editor()
        coordinator.scheduleFocus(request, documentID: coordinator.documentID)

        await fulfillment(of: [focused], timeout: 2)

        XCTAssertTrue(window.firstResponder === textView)
        XCTAssertEqual(textView.selectedRange(), selection)
        XCTAssertNil(store.editorFocusRequest)
        XCTAssertEqual(coordinator.lastFocusRequest, request.id)
        XCTAssertTrue(undoManager.canUndo)
        XCTAssertTrue(window.firstResponder?.tryToPerform(NSSelectorFromString("undo:"), with: nil) == true)
        XCTAssertEqual(source, original)

        let insertion = textView.selectedRange()
        let expected = (source as NSString).replacingCharacters(in: insertion, with: "x")
        let key = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "x",
            charactersIgnoringModifiers: "x", isARepeat: false, keyCode: 7
        ))
        undoManager.beginUndoGrouping()
        window.firstResponder?.keyDown(with: key)
        undoManager.endUndoGrouping()
        XCTAssertEqual(source, expected)

        // Returning to preview cancels an unconsumed request; it must not later
        // steal focus from the visible preview or reset the selected range.
        store.setMode(.preview)
        store.setMode(.editor)
        let cancelled = try XCTUnwrap(store.editorFocusRequest)
        coordinator.parent = editor()
        coordinator.scheduleFocus(cancelled, documentID: coordinator.documentID)
        store.setMode(.preview)
        coordinator.parent = editor()
        XCTAssertTrue(window.makeFirstResponder(nil))
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        XCTAssertFalse(window.firstResponder === textView)
        XCTAssertEqual(coordinator.lastFocusRequest, request.id)
    }

    func test_FOCUS_003_NewDocumentFocusSelectsUnicodeTitleOnly() async {
        await MainActor.run {
            _ = NSApplication.shared
            let textView = MarkdownTextView()
            textView.string = "# 新文章 😀\n\n正文"

            textView.selectTitleForEditing()

            XCTAssertEqual((textView.string as NSString).substring(with: textView.selectedRange()), "新文章 😀")
            textView.string = ""
            textView.selectTitleForEditing()
            XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
        }
    }
}
