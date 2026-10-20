import AppKit
import SwiftUI
import XCTest
import CaseReporting
@testable import MWebCore
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
        // Production makeNSView initializes highlighting before editing. Match its
        // layout manager setup rather than switching text engines during the test.
        textView.highlightMarkdown()
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
        XCTAssertEqual(textView.string, original)

        let insertion = textView.selectedRange()
        let expected = (textView.string as NSString).replacingCharacters(in: insertion, with: "x")
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

    @MainActor
    func test_FOCUS_004_DocumentChangeStartsAtTop() async throws {
        _ = NSApplication.shared
        let root = try makeScrollingLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore()
        store.mode = .editor
        store.open(root, remember: false)
        await waitFor("The fixture opens Article A") {
            !store.isBusy && store.document?.articleID == "10001"
        }
        XCTAssertNil(store.errorMessage)
        let host = NSHostingView(rootView: LibraryView(store: store))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .resizable], backing: .buffered, defer: false
        )
        window.contentView = host
        defer { window.contentView = nil }
        await waitFor("The production view mounts Article A's native editor") {
            host.layoutSubtreeIfNeeded()
            return self.editor(in: host)?.string.hasPrefix("# Article A") == true
        }
        let savedMarker = "A-only undo marker"
        weak var priorEditor: MarkdownTextView?
        do {
            let articleA = try XCTUnwrap(editor(in: host))
            priorEditor = articleA
            let scrollA = try XCTUnwrap(articleA.enclosingScrollView)
            articleA.setSelectedRange(NSRange(location: (articleA.string as NSString).length, length: 0))
            let undoManager = try XCTUnwrap(articleA.undoManager)
            let groupsByEvent = undoManager.groupsByEvent
            undoManager.groupsByEvent = false
            undoManager.beginUndoGrouping()
            articleA.insertText(savedMarker, replacementRange: articleA.selectedRange())
            undoManager.endUndoGrouping()
            undoManager.groupsByEvent = groupsByEvent
            XCTAssertTrue(undoManager.canUndo, "Article A has a real native undo action before switching files")
            XCTAssertTrue(store.draft.hasSuffix(savedMarker))
            articleA.scrollRangeToVisible(articleA.selectedRange())
            XCTAssertGreaterThan(scrollA.contentView.bounds.minY, 0, "Article A starts scrolled down")
        }

        // Retain A only weakly so this test does not prevent its native teardown.
        store.selectArticle("10002")

        await waitFor("The production view mounts Article B's native editor") {
            host.layoutSubtreeIfNeeded()
            return !store.isBusy && store.document?.articleID == "10002"
                && self.editor(in: host)?.string.hasPrefix("# Article B") == true
        }
        XCTAssertNil(store.errorMessage)
        let articleB = try XCTUnwrap(editor(in: host))
        let scrollB = try XCTUnwrap(articleB.enclosingScrollView)
        XCTAssertFalse(priorEditor === articleB, "Each file owns its native editor and pending scroll work")
        XCTAssertEqual(articleB.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertEqual(scrollB.contentView.bounds.minY, 0, accuracy: 0.5)
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(scrollB.contentView.bounds.minY, 0, accuracy: 0.5)
        let undoB = try XCTUnwrap(articleB.undoManager)
        XCTAssertFalse(undoB.canUndo, "The new document must not inherit Article A's undo action")
        XCTAssertEqual(articleB.string, try String(contentsOf: root.appendingPathComponent("docs/10002.md")))
        XCTAssertTrue(try String(contentsOf: root.appendingPathComponent("docs/10001.md")).hasSuffix(savedMarker))

        // Switching only the view mode must keep this document's editor alive.
        let selection = (articleB.string as NSString).range(of: "Paragraph 145")
        XCTAssertNotEqual(selection.location, NSNotFound)
        articleB.setSelectedRange(selection)
        articleB.scrollRangeToVisible(selection)
        XCTAssertGreaterThan(scrollB.contentView.bounds.minY, 0)
        store.setMode(.preview)
        await waitFor("Preview disables the mounted editor") {
            host.layoutSubtreeIfNeeded()
            return !articleB.isEditable
        }
        XCTAssertTrue(editor(in: host) === articleB)
        store.setMode(.editor)
        await waitFor("Editing restores focus to the same mounted editor") {
            host.layoutSubtreeIfNeeded()
            return articleB.isEditable && store.editorFocusRequest == nil
        }
        XCTAssertTrue(editor(in: host) === articleB)
        XCTAssertEqual(articleB.selectedRange(), selection)
        XCTAssertGreaterThan(scrollB.contentView.bounds.minY, 0)
    }

    @MainActor
    private func editor(in view: NSView) -> MarkdownTextView? {
        if let editor = view as? MarkdownTextView { return editor }
        for child in view.subviews {
            if let editor = editor(in: child) { return editor }
        }
        return nil
    }

    @MainActor
    private func waitFor(_ description: String, condition: () -> Bool,
                         file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), description, file: file, line: line)
    }

    private func makeScrollingLibrary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MWebLite-EditorScroll-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
        let database = try SQLiteDatabase(url: root.appendingPathComponent("mainlib.db"), writable: true, create: true)
        try database.execute("CREATE TABLE article (id INTEGER PRIMARY KEY, uuid INTEGER UNIQUE, state INTEGER, dateAdd INTEGER, dateModif INTEGER)")
        try database.execute("CREATE TABLE cat (uuid INTEGER PRIMARY KEY, name TEXT, pid INTEGER)")
        try database.execute("CREATE TABLE cat_article (rid INTEGER, aid INTEGER)")
        try database.execute("INSERT INTO article VALUES (1, 10001, 1, 1700000100, 1700000100)")
        try database.execute("INSERT INTO article VALUES (2, 10002, 1, 1700000000, 1700000000)")
        for (id, title) in [("10001", "Article A"), ("10002", "Article B")] {
            let source = "# \(title)\n\n" + (1...150).map { "Paragraph \($0): 中文 and Markdown text.\n\n" }.joined()
            try Data(source.utf8).write(to: root.appendingPathComponent("docs/\(id).md"))
        }
        return root
    }
}
