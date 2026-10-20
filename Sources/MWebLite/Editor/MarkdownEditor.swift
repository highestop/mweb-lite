import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum MarkdownEditorAction: String, CaseIterable {
    case bold, italic, strikethrough, link, inlineCode, codeBlock
    case heading, quote, bulletList, orderedList, taskList, table

    @MainActor
    func perform() {
        NSApp.sendAction(NSSelectorFromString("markdown" + rawValue.prefix(1).uppercased() + rawValue.dropFirst() + ":"), to: nil, from: nil)
    }
}

struct EditorFocusRequest: Equatable {
    enum SelectionIntent: Equatable {
        case preserveSelection, selectTitle
    }

    let id = UUID()
    let selection: SelectionIntent
}

struct MarkdownEditor: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    let documentID: String
    var onSave: () -> Void
    var onInsertImages: (([URL]) -> [String])?
    var onPasteImage: ((Data) -> String?)?
    var focusRequest: EditorFocusRequest?
    var onFocusHandled: ((UUID) -> Void)?

    init(text: Binding<String>, documentID: String, onSave: @escaping () -> Void,
         onInsertImages: (([URL]) -> [String])? = nil, onPasteImage: ((Data) -> String?)? = nil,
         focusRequest: EditorFocusRequest? = nil, onFocusHandled: ((UUID) -> Void)? = nil) {
        _text = text
        self.documentID = documentID
        self.onSave = onSave
        self.onInsertImages = onInsertImages
        self.onPasteImage = onPasteImage
        self.focusRequest = focusRequest
        self.onFocusHandled = onFocusHandled
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = MarkdownTextView(frame: .zero)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isRichText = false
        textView.isEditable = isEnabled
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 6
        paragraph.paragraphSpacing = 3
        paragraph.tabStops = []
        paragraph.defaultTabInterval = 33.6
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: textView.font!, .foregroundColor: NSColor.textColor, .paragraphStyle: paragraph]
        textView.setAccessibilityLabel("Markdown 编辑器")
        textView.setAccessibilityHelp("编辑 Markdown 原文；Command B 加粗，Command I 斜体，Command K 插入链接。")
        textView.registerForDraggedTypes(textView.registeredDraggedTypes + [.fileURL, .png, .tiff])
        textView.string = text
        textView.delegate = context.coordinator
        textView.onSave = onSave
        textView.onInsertImages = onInsertImages
        textView.onPasteImage = onPasteImage
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.documentID = documentID
        textView.highlightMarkdown()
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownTextView else { return }
        context.coordinator.parent = self
        textView.isEditable = isEnabled
        textView.onSave = onSave
        textView.onInsertImages = onInsertImages
        textView.onPasteImage = onPasteImage
        let documentChanged = context.coordinator.documentID != documentID
        if documentChanged {
            context.coordinator.highlightWork?.cancel()
            textView.delegate = nil
            textView.unmarkText()
            context.coordinator.documentID = documentID
            textView.string = text
            textView.undoManager?.removeAllActions()
            textView.setSelectedRange(NSRange(location: 0, length: 0))
            textView.scrollRangeToVisible(NSRange(location: 0, length: 0))
            textView.highlightMarkdown()
            textView.delegate = context.coordinator
        } else if !textView.hasMarkedText(), textView.string != text {
            let oldSelection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            let location = min(oldSelection.location, length)
            textView.setSelectedRange(NSRange(location: location, length: min(oldSelection.length, length - location)))
            textView.highlightMarkdown()
        }
        if isEnabled, let focusRequest {
            context.coordinator.scheduleFocus(focusRequest, documentID: documentID)
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.highlightWork?.cancel()
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.hasMarkedText() {
            textView.unmarkText()
            coordinator.parent.text = textView.string
        }
        // The window's undo manager outlives this file's native editor.
        textView.undoManager?.removeAllActions()
        textView.delegate = nil
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        var documentID: String
        weak var textView: MarkdownTextView?
        var highlightWork: DispatchWorkItem?
        var lastFocusRequest: UUID?

        init(_ parent: MarkdownEditor) {
            self.parent = parent
            self.documentID = parent.documentID
        }

        func scheduleFocus(_ request: EditorFocusRequest, documentID expectedDocumentID: String) {
            guard lastFocusRequest != request.id else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, let textView = self.textView,
                      self.documentID == expectedDocumentID,
                      self.parent.focusRequest == request,
                      self.lastFocusRequest != request.id,
                      textView.isEditable,
                      let window = textView.window, window.makeFirstResponder(textView) else { return }
                self.lastFocusRequest = request.id
                if request.selection == .selectTitle { textView.selectTitleForEditing() }
                self.parent.onFocusHandled?(request.id)
            }
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownTextView, !textView.hasMarkedText() else { return }
            parent.text = textView.string
            highlightWork?.cancel()
            let work = DispatchWorkItem { [weak textView] in
                guard let textView, !textView.hasMarkedText() else { return }
                textView.highlightMarkdown()
            }
            highlightWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
        }
    }
}

final class MarkdownTextView: NSTextView {
    var onSave: (() -> Void)?
    var onInsertImages: (([URL]) -> [String])?
    var onPasteImage: ((Data) -> String?)?

    override func resignFirstResponder() -> Bool {
        let wasComposing = hasMarkedText()
        guard super.resignFirstResponder() else { return false }
        if wasComposing {
            // A mounted editor must publish its composition before the preview becomes visible.
            unmarkText()
            didChangeText()
        }
        return true
    }

    func selectTitleForEditing() {
        let source = string as NSString
        let firstLine = source.lineRange(for: NSRange(location: 0, length: 0))
        let line = source.substring(with: firstLine).trimmingCharacters(in: .newlines)
        let selection = line.hasPrefix("# ")
            ? NSRange(location: 2, length: (line as NSString).length - 2)
            : NSRange(location: 0, length: 0)
        setSelectedRange(selection)
        scrollRangeToVisible(selection)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option),
              !hasMarkedText() else { return super.performKeyEquivalent(with: event) }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "s" where !modifiers.contains(.shift): onSave?()
        case "b" where !modifiers.contains(.shift): markdownBold(nil)
        case "i" where !modifiers.contains(.shift): markdownItalic(nil)
        case "k" where !modifiers.contains(.shift): markdownLink(nil)
        case "x" where modifiers.contains(.shift): markdownStrikethrough(nil)
        case "f" where !modifiers.contains(.shift):
            let item = NSMenuItem()
            item.tag = NSTextFinder.Action.showFindInterface.rawValue
            performFindPanelAction(item)
        case "]": indentLines(outdent: false)
        case "[": indentLines(outdent: true)
        default: return super.performKeyEquivalent(with: event)
        }
        return true
    }

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText(), let edit = MarkdownEditing.newline(string, selection: selectedRange()) else {
            super.insertNewline(sender)
            return
        }
        apply(edit, actionName: "换行")
    }

    override func insertTab(_ sender: Any?) {
        guard !hasMarkedText() else { super.insertTab(sender); return }
        if selectedRange().length > 0 {
            indentLines(outdent: false)
        } else {
            insertText("    ", replacementRange: selectedRange())
        }
    }

    override func insertBacktab(_ sender: Any?) {
        guard !hasMarkedText() else { super.insertBacktab(sender); return }
        indentLines(outdent: true)
    }

    @objc func markdownBold(_ sender: Any?) { wrap(before: "**", after: "**", actionName: "加粗") }
    @objc func markdownItalic(_ sender: Any?) { wrap(before: "*", after: "*", actionName: "斜体") }
    @objc func markdownStrikethrough(_ sender: Any?) { wrap(before: "~~", after: "~~", actionName: "删除线") }
    @objc func markdownInlineCode(_ sender: Any?) { wrap(before: "`", after: "`", actionName: "行内代码") }
    @objc func markdownCodeBlock(_ sender: Any?) { wrap(before: "```\n", after: "\n```", actionName: "代码块") }
    @objc func markdownLink(_ sender: Any?) { apply(MarkdownEditing.link(string, selection: selectedRange()), actionName: "插入链接") }
    @objc func markdownHeading(_ sender: Any?) { prefixLines("# ", actionName: "标题") }
    @objc func markdownQuote(_ sender: Any?) { prefixLines("> ", actionName: "引用") }
    @objc func markdownBulletList(_ sender: Any?) { prefixLines("- ", actionName: "无序列表") }
    @objc func markdownOrderedList(_ sender: Any?) { prefixLines("1. ", actionName: "有序列表") }
    @objc func markdownTaskList(_ sender: Any?) { prefixLines("- [ ] ", actionName: "任务列表") }
    @objc func markdownTable(_ sender: Any?) {
        let value = "| 标题 | 标题 |\n| --- | --- |\n| 内容 | 内容 |\n"
        let range = selectedRange()
        apply(MarkdownEdit(range: range, replacement: value, selection: NSRange(location: range.location + 2, length: 2)), actionName: "插入表格")
    }

    override func paste(_ sender: Any?) {
        guard isEditable else { return }
        guard !hasMarkedText(), insertImages(from: .general) else { super.paste(sender); return }
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if canInsertImages(from: sender.draggingPasteboard) { return .copy }
        return super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        if canInsertImages(from: sender.draggingPasteboard) { return .copy }
        return super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isEditable else { return false }
        guard !hasMarkedText(), canInsertImages(from: sender.draggingPasteboard) else { return super.performDragOperation(sender) }
        let point = convert(sender.draggingLocation, from: nil)
        let location = characterIndexForInsertion(at: point)
        setSelectedRange(NSRange(location: min(location, (string as NSString).length), length: 0))
        window?.makeFirstResponder(self)
        return insertImages(from: sender.draggingPasteboard)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        highlightMarkdown()
    }

    private func wrap(before: String, after: String, actionName: String) {
        guard !hasMarkedText() else { return }
        apply(MarkdownEditing.wrap(string, selection: selectedRange(), before: before, after: after), actionName: actionName)
    }

    private func prefixLines(_ prefix: String, actionName: String) {
        guard !hasMarkedText() else { return }
        apply(MarkdownEditing.prefixLines(string, selection: selectedRange(), prefix: prefix), actionName: actionName)
    }

    private func indentLines(outdent: Bool) {
        apply(MarkdownEditing.indent(string, selection: selectedRange(), outdent: outdent), actionName: outdent ? "减少缩进" : "增加缩进")
    }

    private func apply(_ edit: MarkdownEdit, actionName: String) {
        guard isEditable, !hasMarkedText() else { return }
        breakUndoCoalescing()
        insertText(edit.replacement, replacementRange: edit.range)
        setSelectedRange(edit.selection)
        undoManager?.setActionName(actionName)
        scrollRangeToVisible(edit.selection)
        breakUndoCoalescing()
    }

    private func imageURLs(from pasteboard: NSPasteboard) -> [URL] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return urls.filter { url in
            guard url.isFileURL, let type = UTType(filenameExtension: url.pathExtension) else { return false }
            return type.conforms(to: .image)
        }
    }

    private func canInsertImages(from pasteboard: NSPasteboard) -> Bool {
        guard isEditable else { return false }
        return (onInsertImages != nil && !imageURLs(from: pasteboard).isEmpty) ||
        (onPasteImage != nil && pasteboard.availableType(from: [.png, .tiff]) != nil)
    }

    private func insertImages(from pasteboard: NSPasteboard) -> Bool {
        guard isEditable else { return false }
        let urls = imageURLs(from: pasteboard)
        let markdown: [String]
        if !urls.isEmpty, let onInsertImages {
            markdown = onInsertImages(urls)
        } else if let onPasteImage {
            let png = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff).flatMap {
                NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
            }
            guard let png else { return false }
            markdown = onPasteImage(png).map { [$0] } ?? []
        } else {
            return false
        }
        // The callback owns errors; a failed import must not paste a source path.
        guard !markdown.isEmpty else { return true }
        let range = selectedRange()
        let value = markdown.joined(separator: "\n")
        apply(MarkdownEdit(range: range, replacement: value, selection: NSRange(location: range.location + (value as NSString).length, length: 0)), actionName: "插入图片")
        return true
    }

    func highlightMarkdown() {
        guard !hasMarkedText(), let layoutManager else { return }
        let source = string as NSString
        let range = NSRange(location: 0, length: source.length)
        layoutManager.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
        layoutManager.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
        guard source.length > 0 else { return }
        // Temporary display attributes never modify the document or its undo stack.
        func color(_ pattern: String, _ color: NSColor, background: NSColor? = nil) {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { return }
            expression.enumerateMatches(in: string, range: range) { match, _, _ in
                guard let match else { return }
                layoutManager.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: match.range)
                if let background { layoutManager.addTemporaryAttribute(.backgroundColor, value: background, forCharacterRange: match.range) }
            }
        }
        color(#"^ {0,3}#{1,6}[ \t]+.*$"#, .systemBlue)
        color(#"^[ \t]*>.*$"#, .secondaryLabelColor)
        color(#"\*\*[^\n]+?\*\*|__[^\n]+?__"#, .systemPurple)
        color(#"(?<!\*)\*[^*\n]+\*(?!\*)|(?<!_)_[^_\n]+_(?!_)"#, .systemPurple)
        color(#"~~[^\n]+?~~"#, .secondaryLabelColor)
        color(#"!?\[[^\]\n]*\]\([^\n]*?\)|\[\^[^\]\n]+\]"#, .systemTeal)
        color(#"^[ \t]*(?:[-+*]|[0-9]+[.)])[ \t]+(?:\[[ xX]\])?"#, .systemOrange)
        color(#"`+[^`\n]+`+"#, .systemPink, background: NSColor.quaternaryLabelColor.withAlphaComponent(0.08))
        color(#"<!--[\s\S]*?-->"#, .tertiaryLabelColor)

        var fence: (character: Character, count: Int, start: Int)?
        var offset = 0
        for line in string.components(separatedBy: "\n") {
            let count = (line as NSString).length
            let indentation = line.prefix(while: { $0 == " " }).count
            let content = line.dropFirst(indentation)
            if indentation <= 3, let first = content.first, first == "`" || first == "~" {
                let markers = content.prefix(while: { $0 == first }).count
                if markers >= 3 {
                    if let open = fence {
                        if first == open.character, markers >= open.count, content.dropFirst(markers).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            let block = NSRange(location: open.start, length: offset + count - open.start)
                            layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.systemPink, forCharacterRange: block)
                            layoutManager.addTemporaryAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.06), forCharacterRange: block)
                            fence = nil
                        }
                    } else if first != "`" || !content.dropFirst(markers).contains("`") {
                        fence = (first, markers, offset)
                    }
                }
            }
            offset += count + 1
        }
        if let open = fence {
            layoutManager.addTemporaryAttribute(.foregroundColor, value: NSColor.systemPink, forCharacterRange: NSRange(location: open.start, length: source.length - open.start))
        }
    }
}
