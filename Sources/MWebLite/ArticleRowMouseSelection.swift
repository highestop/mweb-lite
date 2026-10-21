import MWebCore
import AppKit
import SwiftUI

/// Holds keyboard focus outside lazy rows, without owning another selection value.
@MainActor
final class ArticleListSelectionController: ObservableObject {
    fileprivate weak var keyboardView: ArticleListKeyboardAnchor?

    func focus() {
        focus(in: keyboardView?.window)
    }

    fileprivate func focus(in window: NSWindow?) {
        guard let window, let keyboardView, keyboardView.window === window else { return }
        window.makeFirstResponder(keyboardView)
    }
}

/// A stable background on the ScrollView; input remains enabled/disabled with the list.
struct ArticleListKeyboardSelection: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let controller: ArticleListSelectionController
    let onMove: (Int) -> Void

    func makeNSView(context: Context) -> ArticleListKeyboardAnchor {
        let view = ArticleListKeyboardAnchor()
        view.configure(isEnabled: isEnabled, controller: controller, onMove: onMove)
        return view
    }

    func updateNSView(_ nsView: ArticleListKeyboardAnchor, context: Context) {
        nsView.configure(isEnabled: isEnabled, controller: controller, onMove: onMove)
    }

    static func dismantleNSView(_ nsView: ArticleListKeyboardAnchor, coordinator: ()) {
        nsView.invalidate()
    }
}

final class ArticleListKeyboardAnchor: NSView, NavigationKeyboardResponder {
    private weak var controller: ArticleListSelectionController?
    private var onMove: ((Int) -> Void)?
    private var selectionEnabled = false
    private var isDismantled = false

    // Retain list focus while loading temporarily disables selection.
    override var acceptsFirstResponder: Bool { !isDismantled }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    func configure(isEnabled: Bool, controller: ArticleListSelectionController, onMove: @escaping (Int) -> Void) {
        guard !isDismantled else { return }
        if self.controller?.keyboardView === self { self.controller?.keyboardView = nil }
        self.controller = controller
        controller.keyboardView = self
        selectionEnabled = isEnabled
        self.onMove = onMove
        focusRingType = .none
    }

    override func keyDown(with event: NSEvent) {
        guard !isDismantled, selectionEnabled else { return }
        // Hardware arrows include .function/.numericPad; preserve other key bindings.
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        guard modifiers.isEmpty, event.keyCode == 125 || event.keyCode == 126 else {
            super.keyDown(with: event)
            return
        }
        onMove?(event.keyCode == 125 ? 1 : -1)
        // Store selection ends editor focus synchronously. Restore list focus now,
        // never when asynchronous loading finishes and the user may be editing.
        if !isDismantled { controller?.focus(in: window) }
    }

    func invalidate() {
        isDismantled = true
        selectionEnabled = false
        onMove = nil
        if controller?.keyboardView === self { controller?.keyboardView = nil }
        controller = nil
    }
}

/// An input-only overlay for a row whose selection is drawn from LibraryStore.
/// Use inside a ScrollView, without a native List/Table selection.
struct ArticleRowMouseSelection: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let controller: ArticleListSelectionController
    let onSelect: () -> Void
    var onDelete: (() -> Void)?

    init(controller: ArticleListSelectionController, onDelete: (() -> Void)? = nil, _ onSelect: @escaping () -> Void) {
        self.controller = controller
        self.onSelect = onSelect
        self.onDelete = onDelete
    }

    func makeNSView(context: Context) -> ArticleRowSelectionAnchor {
        let view = ArticleRowSelectionAnchor()
        view.configure(isEnabled: isEnabled, controller: controller, onDelete: onDelete, onSelect: onSelect)
        return view
    }

    func updateNSView(_ nsView: ArticleRowSelectionAnchor, context: Context) {
        nsView.configure(isEnabled: isEnabled, controller: controller, onDelete: onDelete, onSelect: onSelect)
    }

    static func dismantleNSView(_ nsView: ArticleRowSelectionAnchor, coordinator: ()) {
        nsView.invalidate()
    }
}

final class ArticleRowSelectionAnchor: NSView {
    private weak var controller: ArticleListSelectionController?
    private var onSelect: (() -> Void)?
    private var onDelete: (() -> Void)?
    private var selectionEnabled = false
    private var isDismantled = false

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityElement() -> Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isDismantled, !isHidden else { return nil }
        return super.hitTest(point)
    }

    func configure(isEnabled: Bool, controller: ArticleListSelectionController, onDelete: (() -> Void)? = nil, onSelect: @escaping () -> Void) {
        guard !isDismantled else { return }
        selectionEnabled = isEnabled
        self.controller = controller
        self.onSelect = onSelect
        self.onDelete = onDelete
    }

    static func accepts(_ event: NSEvent) -> Bool {
        event.type == .leftMouseDown &&
            event.modifierFlags.intersection([.shift, .control, .option, .command, .function]).isEmpty
    }

    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control), let menu = menu(for: event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
            return
        }
        guard !isDismantled, selectionEnabled, Self.accepts(event) else { return }
        // No tracking loop or mouse-up action: the store changes during this down.
        onSelect?()
        if !isDismantled { controller?.focus(in: window) }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard !isDismantled, selectionEnabled, onDelete != nil else { return nil }
        let menu = NSMenu()
        let item = NSMenuItem(title: L10n.string("Delete Article…"), action: #selector(deleteArticle), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        menu.addItem(item)
        return menu
    }

    @objc private func deleteArticle() {
        guard !isDismantled, selectionEnabled else { return }
        onDelete?()
    }

    // Leave scrollWheel(with:) inherited so the surrounding scroll view receives it.
    func invalidate() {
        isDismantled = true
        selectionEnabled = false
        onSelect = nil
        onDelete = nil
        controller = nil
    }
}
