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
        .defaultSize(width: 1380, height: 850)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("打开 MWeb 文库…") { store.chooseLibrary() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .saveItem) {
                Button("保存") { store.saveNow() }.keyboardShortcut("s").disabled(store.document == nil)
                Button("从磁盘重新载入…") { store.reloadFromDisk() }.disabled(store.document == nil)
            }
            CommandMenu("Markdown") {
                Button("编辑 / 预览") { store.setMode(store.mode == .preview ? .editor : .preview) }.keyboardShortcut("r")
                Button("边编辑边预览") { store.setMode(.split) }.keyboardShortcut("4")
                Divider()
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
        guard let store, store.isDirty || store.isSaving else { return .terminateNow }
        Task { sender.reply(toApplicationShouldTerminate: await store.flush()) }
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
            guard !closing, store.isDirty || store.isSaving else { return true }
            Task {
                if await store.flush() { closing = true; sender.performClose(nil); closing = false }
            }
            return false
        }
    }
}
