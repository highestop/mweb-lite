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

    func test_FOCUS_002_FocusRoundTripPreservesSelectionAndUndo() async throws {
        try await MainActor.run {
            _ = NSApplication.shared
            var source = "原文"
            let editor = MarkdownEditor(
                text: Binding(get: { source }, set: { source = $0 }),
                documentID: "undo-fixture", onSave: {}
            )
            let coordinator = editor.makeCoordinator()
            let textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
            textView.isRichText = false
            textView.allowsUndo = true
            textView.string = source
            textView.delegate = coordinator
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
            textView.insertText("追加", replacementRange: NSRange(location: 2, length: 0))
            undoManager.endUndoGrouping()
            XCTAssertEqual(source, "原文追加")
            let selection = NSRange(location: 0, length: 2)
            textView.setSelectedRange(selection)

            XCTAssertTrue(window.makeFirstResponder(nil))
            XCTAssertTrue(window.makeFirstResponder(textView))

            XCTAssertEqual(textView.selectedRange(), selection)
            XCTAssertTrue(undoManager.canUndo)
            XCTAssertTrue(textView.tryToPerform(NSSelectorFromString("undo:"), with: nil))
            XCTAssertEqual(textView.string, "原文")
        }
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
