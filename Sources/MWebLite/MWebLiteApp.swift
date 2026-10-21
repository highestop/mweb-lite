import AppKit
import SwiftUI

@main
struct MWebLiteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var store = LibraryStore()

    var body: some Scene {
        Window("MWeb Lite", id: "library") {
            LibraryView(store: store)
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
                Button("新建文章") { store.createArticle() }.keyboardShortcut("n")
                    .disabled(store.rootURL == nil || store.isBusy)
                Button("打开 MWeb 文库…") { store.chooseLibrary() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("保存") { store.saveNow() }.keyboardShortcut("s").disabled(store.document == nil)
                Button("从磁盘重新载入…") { store.reloadFromDisk() }.disabled(store.document == nil)
            }
            CommandGroup(after: .toolbar) {
                Button(store.mode == .preview ? "切换到编辑" : "切换到预览") {
                    store.setMode(store.mode == .preview ? .editor : .preview)
                }.keyboardShortcut("r")
                    .disabled(store.document == nil || store.isBusy)
            }
            CommandMenu("Markdown") {
                Button("粗体") { MarkdownEditorAction.bold.perform() }.keyboardShortcut("b")
                Button("斜体") { MarkdownEditorAction.italic.perform() }.keyboardShortcut("i")
                Button("插入链接") { MarkdownEditorAction.link.perform() }.keyboardShortcut("k")
                Button("代码块") { MarkdownEditorAction.codeBlock.perform() }
                Button("任务列表") { MarkdownEditorAction.taskList.perform() }
                Button("表格") { MarkdownEditorAction.table.perform() }
                Divider()
                Button("刷新文库") { store.refresh() }.keyboardShortcut("r", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .help) {
                Button("在 Finder 中显示文库") {
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
