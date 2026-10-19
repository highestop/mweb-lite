import AppKit
import SwiftUI

/// Handles the whole native row, including the inset outside its SwiftUI content.
struct ArticleRowMouseSelection: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let onSelect: () -> Void

    init(_ onSelect: @escaping () -> Void) { self.onSelect = onSelect }

    func makeNSView(context: Context) -> ArticleRowSelectionAnchor {
        let view = ArticleRowSelectionAnchor()
        view.configure(isEnabled: isEnabled, onSelect: onSelect)
        return view
    }

    func updateNSView(_ nsView: ArticleRowSelectionAnchor, context: Context) {
        nsView.configure(isEnabled: isEnabled, onSelect: onSelect)
    }

    static func dismantleNSView(_ nsView: ArticleRowSelectionAnchor, coordinator: ()) {
        nsView.invalidate()
    }
}

final class ArticleRowSelectionAnchor: NSView {
    private let recognizer = ArticleRowMouseDownRecognizer(target: nil, action: nil)
    private var onSelect: (() -> Void)?
    private var isDismantled = false

    // This is a hierarchy anchor, not an extra mouse or accessibility target.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    func configure(isEnabled: Bool, onSelect: @escaping () -> Void) {
        guard !isDismantled else { return }
        self.onSelect = onSelect
        recognizer.isEnabled = isEnabled
        recognizer.onMouseDown = { [weak self] in
            guard let self, !self.isDismantled, self.recognizer.isEnabled else { return }
            self.onSelect?()
        }
        updateAttachment()
        // SwiftUI can update the anchor before inserting its hosting view into a row.
        DispatchQueue.main.async { [weak self] in self?.updateAttachment() }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        updateAttachment()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateAttachment()
    }

    override func layout() {
        super.layout()
        updateAttachment()
    }

    func invalidate() {
        isDismantled = true
        recognizer.isEnabled = false
        recognizer.onMouseDown = nil
        onSelect = nil
        recognizer.view?.removeGestureRecognizer(recognizer)
    }

    private func updateAttachment() {
        guard !isDismantled else { return }
        var ancestor = superview
        while let current = ancestor, !(current is NSTableRowView) { ancestor = current.superview }
        let row = ancestor as? NSTableRowView
        guard recognizer.view !== row else { return }
        recognizer.view?.removeGestureRecognizer(recognizer)
        row?.addGestureRecognizer(recognizer)
    }
}

final class ArticleRowMouseDownRecognizer: NSGestureRecognizer, NSGestureRecognizerDelegate {
    var onMouseDown: (() -> Void)?

    override init(target: Any?, action: Selector?) {
        super.init(target: target, action: action)
        delaysPrimaryMouseButtonEvents = true
        delegate = self
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        delaysPrimaryMouseButtonEvents = true
        delegate = self
    }

    static func accepts(_ event: NSEvent) -> Bool {
        event.type == .leftMouseDown &&
            event.modifierFlags.intersection([.shift, .control, .option, .command, .function]).isEmpty
    }

    func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer,
                           shouldAttemptToRecognizeWith event: NSEvent) -> Bool {
        isEnabled && Self.accepts(event)
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        guard state == .possible else { return }
        guard isEnabled, Self.accepts(event) else { state = .failed; return }
        // Recognize before calling the store so the native row never receives this down.
        // The store callback is synchronous; target/action dispatch would wait a run-loop turn.
        state = .recognized
        if state == .recognized { onMouseDown?() }
    }
}
