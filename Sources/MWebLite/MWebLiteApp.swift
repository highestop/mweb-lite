import MWebCore
import AppKit
import SwiftUI

@main
struct MWebLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = LibraryStore()

    var body: some Scene {
        Window("MWeb Lite", id: "library") {
            LibraryView(store: store)
                .environment(\.locale, L10n.current.locale)
                .frame(minWidth: 940, minHeight: 600)
                .onAppear {
                    delegate.store = store
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    store.restore()
                }
                .background(WindowLifecycle(store: store))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(L10n.string("New Article")) { store.createArticle() }.keyboardShortcut("n")
                    .disabled(store.rootURL == nil || store.isBusy)
                Button(L10n.string("Open MWeb Library…")) { store.chooseLibrary() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button(L10n.string("Save")) { store.saveNow() }.keyboardShortcut("s").disabled(store.document == nil)
                Button(L10n.string("Reload from Disk…")) { store.reloadFromDisk() }.disabled(store.document == nil)
            }
            CommandGroup(after: .toolbar) {
                Button(store.mode == .preview ? L10n.string("Switch to Editing") : L10n.string("Switch to Preview")) {
                    store.setMode(store.mode == .preview ? .editor : .preview)
                }.keyboardShortcut("r")
                    .disabled(store.document == nil || store.isBusy)
            }
            CommandMenu("Markdown") {
                Button(L10n.string("Bold")) { MarkdownEditorAction.bold.perform() }.keyboardShortcut("b")
                Button(L10n.string("Italic")) { MarkdownEditorAction.italic.perform() }.keyboardShortcut("i")
                Button(L10n.string("Insert Link")) { MarkdownEditorAction.link.perform() }.keyboardShortcut("k")
                Button(L10n.string("Code Block")) { MarkdownEditorAction.codeBlock.perform() }
                Button(L10n.string("Task List")) { MarkdownEditorAction.taskList.perform() }
                Button(L10n.string("Table")) { MarkdownEditorAction.table.perform() }
                Divider()
                Button(L10n.string("Refresh Library")) { store.refresh() }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button(L10n.string("Show Library in Finder")) {
                    if let root = store.rootURL { NSWorkspace.shared.activateFileViewerSelecting([root]) }
                }.disabled(store.rootURL == nil)
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var store: LibraryStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        sender.keyWindow?.makeFirstResponder(nil)
        guard let store, store.hasPendingWrites else { return .terminateNow }
        Task { sender.reply(toApplicationShouldTerminate: await store.finishPendingWrites()) }
        return .terminateLater
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct WindowLifecycle: NSViewRepresentable {
    let store: LibraryStore
    func makeCoordinator() -> Coordinator { Coordinator(store: store) }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.delegate = context.coordinator }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
    @MainActor final class Coordinator: NSObject, NSWindowDelegate {
        let store: LibraryStore
        var closing = false
        init(store: LibraryStore) { self.store = store }
        func windowShouldClose(_ sender: NSWindow) -> Bool {
            sender.makeFirstResponder(nil)
            guard !closing, store.hasPendingWrites else { return true }
            Task {
                if await store.finishPendingWrites() { closing = true; sender.performClose(nil); closing = false }
            }
            return false
        }
    }
}

/// The document toolbar can move the window; article text remains selectable.
struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}
