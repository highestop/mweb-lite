import AppKit
import Foundation
import MWebCore
import SwiftUI

actor LibraryWorker {
    private var library: MWebLibrary?

    func open(_ url: URL) throws -> LibraryIndex {
        let candidate = try MWebLibrary(rootURL: url)
        let index = try candidate.loadIndex()
        library = candidate
        return index
    }

    func index() throws -> LibraryIndex {
        guard let library else { throw CocoaError(.fileNoSuchFile) }
        return try library.loadIndex()
    }

    func document(_ id: String) throws -> MWebDocument {
        guard let library else { throw CocoaError(.fileNoSuchFile) }
        return try library.loadDocument(articleID: id)
    }

    func save(_ document: MWebDocument, content: String) throws -> MWebDocument {
        guard let library else { throw CocoaError(.fileNoSuchFile) }
        return try library.saveDocument(document, content: content)
    }

    func create(categoryID: String?) throws -> MWebDocument {
        guard let library else { throw CocoaError(.fileNoSuchFile) }
        return try library.createDocument(categoryID: categoryID)
    }
}

enum EditorMode {
    case editor, preview
}

struct CategoryNode: Identifiable {
    let id: String
    let name: String
    let count: Int
    var children: [CategoryNode]?
}

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var rootURL: URL?
    @Published private(set) var categories: [MWebCategory] = []
    @Published private(set) var articles: [MWebArticle] = []
    @Published private(set) var document: MWebDocument?
    @Published var draft = ""
    @Published var selectedCategory = "all"
    @Published var search = ""
    @Published var mode: EditorMode = .preview
    @Published private(set) var isBusy = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published private(set) var saveBlocked = false
    @Published var lastSaved: Date?
    @Published private(set) var editorFocusRequest: EditorFocusRequest?
    @Published private var pendingArticleID: String?

    private let worker = LibraryWorker()
    private var debounceTask: Task<Void, Never>?
    private var saveTask: Task<Bool, Never>?
    private var creationTask: Task<Void, Never>?
    private var securityURL: URL?
    private var hasRestored = false
    private var isReloading = false

    var isDirty: Bool { document.map { $0.content != draft } ?? false }
    var selectedArticleID: String? { pendingArticleID ?? document?.articleID }
    var isSwitchingArticle: Bool { pendingArticleID != nil }
    var hasPendingWrites: Bool { isDirty || isSaving || creationTask != nil }
    var currentTitle: String { Self.title(draft, fallback: document?.title ?? "未命名文章") }
    var activeArticles: [MWebArticle] { articles.filter { !$0.isTrashed } }
    var visibleArticles: [MWebArticle] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedIDs = descendantIDs(of: selectedCategory)
        return activeArticles.filter { article in
            let inCategory = selectedCategory == "all" || (selectedCategory == "uncategorized" ? article.categoryIDs.isEmpty : !selectedIDs.isDisjoint(with: article.categoryIDs))
            return inCategory && (query.isEmpty || article.title.localizedCaseInsensitiveContains(query) || article.excerpt.localizedCaseInsensitiveContains(query))
        }
    }
    var categoryTree: [CategoryNode] {
        let ids = Set(categories.map(\.id))
        var visited = Set<String>()
        func build(_ category: MWebCategory) -> CategoryNode? {
            guard visited.insert(category.id).inserted else { return nil }
            let children = categories.filter { $0.parentID == category.id }.compactMap(build)
            let includedIDs = descendantIDs(of: category.id)
            return CategoryNode(id: category.id, name: category.name,
                count: activeArticles.filter { !includedIDs.isDisjoint(with: $0.categoryIDs) }.count,
                children: children.isEmpty ? nil : children)
        }
        var roots = categories.filter { $0.parentID == "0" || ($0.parentID ?? "").isEmpty || !ids.contains($0.parentID ?? "") }.compactMap(build)
        for category in categories where !visited.contains(category.id) { if let node = build(category) { roots.append(node) } }
        return roots
    }

    private func descendantIDs(of id: String) -> Set<String> {
        var result: Set<String> = [id]
        var pending = [id]
        while let parent = pending.popLast() {
            for category in categories where category.parentID == parent {
                if result.insert(category.id).inserted { pending.append(category.id) }
            }
        }
        return result
    }

    func restore() {
        guard !hasRestored else { return }
        hasRestored = true
        let arguments = ProcessInfo.processInfo.arguments
        if let offset = arguments.firstIndex(of: "--library"), arguments.indices.contains(offset + 1) {
            open(URL(fileURLWithPath: arguments[offset + 1]), remember: false)
            return
        }
        guard let data = UserDefaults.standard.data(forKey: "libraryBookmark") else { return }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale)
            open(url)
        } catch { errorMessage = "无法恢复上次的文库，请重新选择目录。\n\(error.localizedDescription)" }
    }

    func setMode(_ mode: EditorMode) {
        guard !isBusy, mode != self.mode else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        self.mode = mode
        editorFocusRequest = mode == .editor ? EditorFocusRequest(selection: .preserveSelection) : nil
    }

    func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.title = "选择 MWeb 文库"
        panel.message = "选择包含 mainlib.db 和 docs 文件夹的目录。"
        panel.prompt = "打开文库"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = rootURL
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }

    func open(_ url: URL, remember: Bool = true) {
        guard !isBusy else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        isBusy = true
        Task {
            defer { isBusy = false }
            guard await flush() else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            do {
                let index = try await worker.open(url)
                securityURL?.stopAccessingSecurityScopedResource()
                securityURL = scoped ? url : nil
                rootURL = url
                categories = index.categories
                articles = index.articles
                selectedCategory = "all"
                search = ""
                document = nil
                draft = ""
                editorFocusRequest = nil
                saveBlocked = false
                if remember {
                    let bookmark = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(bookmark, forKey: "libraryBookmark")
                }
                if let first = activeArticles.first { try await load(first.id) }
            } catch {
                if scoped && securityURL != url { url.stopAccessingSecurityScopedResource() }
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectArticle(_ id: String?) {
        guard let id, id != document?.articleID, !isBusy else { return }
        // Keep selection responsive while saving and loading on the worker.
        pendingArticleID = id
        NSApp.keyWindow?.makeFirstResponder(nil)
        isBusy = true
        Task {
            defer { isBusy = false; pendingArticleID = nil }
            guard await flush() else { return }
            do { try await load(id) } catch { errorMessage = error.localizedDescription }
        }
    }

    func createArticle() {
        guard rootURL != nil, !isBusy else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        let categoryID = ["all", "uncategorized"].contains(selectedCategory) ? nil : selectedCategory
        isBusy = true
        creationTask = Task {
            defer { isBusy = false; creationTask = nil }
            guard await flush() else { return }
            do {
                let created = try await worker.create(categoryID: categoryID)
                debounceTask?.cancel()
                document = created
                draft = created.content
                saveBlocked = false
                lastSaved = nil
                search = ""
                mode = .editor
                editorFocusRequest = EditorFocusRequest(selection: .selectTitle)
                let index = try await worker.index()
                articles = index.articles
                categories = index.categories
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func consumeEditorFocus(_ request: UUID) {
        if editorFocusRequest?.id == request { editorFocusRequest = nil }
    }

    func finishPendingWrites() async -> Bool {
        if let creationTask { await creationTask.value }
        return await flush()
    }

    func openArticleLink(_ id: String) {
        guard activeArticles.contains(where: { $0.id == id }) else {
            errorMessage = "文库中没有找到链接指向的文章。"
            return
        }
        selectedCategory = "all"
        search = ""
        selectArticle(id)
    }

    private func load(_ id: String) async throws {
        let next = try await worker.document(id)
        debounceTask?.cancel()
        editorFocusRequest = nil
        document = next
        draft = next.content
        saveBlocked = false
        lastSaved = nil
    }

    func edit(_ text: String) {
        draft = text
        debounceTask?.cancel()
        guard !saveBlocked else { return }
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 1_500_000_000) } catch { return }
            guard let self, !Task.isCancelled else { return }
            _ = await self.flush()
        }
    }

    @discardableResult
    func flush() async -> Bool {
        while let pending = saveTask {
            guard await pending.value else { return false }
        }
        guard !isReloading else { return false }
        guard isDirty, let original = document else { return true }
        guard !saveBlocked else { return false }
        let content = draft
        isSaving = true
        let task = Task { () -> Bool in
            defer { saveTask = nil; isSaving = false }
            do {
                let saved = try await worker.save(original, content: content)
                if document?.articleID == original.articleID {
                    document = saved
                    lastSaved = Date()
                }
                articles = articles.map { $0.updating(document: saved) }.sorted {
                    if $0.isPinned != $1.isPinned { return $0.isPinned }
                    if $0.modifiedAt != $1.modifiedAt { return ($0.modifiedAt ?? .distantPast) > ($1.modifiedAt ?? .distantPast) }
                    return $0.id.localizedStandardCompare($1.id) == .orderedDescending
                }
                return true
            } catch {
                saveBlocked = true
                errorMessage = "保存未完成，编辑内容仍保留在窗口中。\n\(error.localizedDescription)"
                return false
            }
        }
        saveTask = task
        let success = await task.value
        if success && isDirty { return await flush() }
        return success
    }

    func saveNow() {
        saveBlocked = false
        Task { _ = await flush() }
    }

    func refresh() {
        guard !isBusy, rootURL != nil else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        isBusy = true
        Task {
            defer { isBusy = false }
            guard await flush() else { return }
            do {
                let index = try await worker.index()
                articles = index.articles
                categories = index.categories
                if let id = document?.articleID {
                    if activeArticles.contains(where: { $0.id == id }) { try await load(id) }
                    else { document = nil; draft = "" }
                }
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func reloadFromDisk() {
        guard let id = document?.articleID, !isBusy else { return }
        let alert = NSAlert()
        alert.messageText = "重新载入磁盘上的文章？"
        alert.informativeText = "当前窗口中尚未保存的编辑会被替换。可先复制文本保留你的修改。"
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "重新载入")
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
        debounceTask?.cancel()
        isReloading = true
        isBusy = true
        Task {
            defer { isBusy = false; isReloading = false }
            if let saveTask { _ = await saveTask.value }
            do { try await load(id) } catch { errorMessage = error.localizedDescription }
        }
    }

    func insertImages(_ urls: [URL]) -> [String] {
        guard !isBusy else { return [] }
        return urls.compactMap { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let ext = url.pathExtension.lowercased()
                guard ["png", "jpg", "jpeg", "gif", "webp", "heic", "tif", "tiff", "bmp"].contains(ext) else { return nil }
                let data = try Data(contentsOf: url)
                return try storeImage(data, extension: ext)
            } catch { errorMessage = error.localizedDescription; return nil }
        }
    }

    func pasteImage(_ data: Data) -> String? {
        guard !isBusy else { return nil }
        do {
            guard let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) else { return nil }
            return try storeImage(png, extension: "png")
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    private func storeImage(_ data: Data, extension ext: String) throws -> String {
        guard let rootURL, let document, document.articleID.range(of: "^[a-zA-Z0-9_-]+$", options: .regularExpression) != nil else { throw CocoaError(.fileWriteInvalidFileName) }
        let canonicalRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        let docs = canonicalRoot.appendingPathComponent("docs").resolvingSymlinksInPath()
        guard docs.path.hasPrefix(canonicalRoot.path + "/") else { throw CocoaError(.fileWriteNoPermission) }
        let relative = "media/\(document.articleID)"
        let directory = docs.appendingPathComponent(relative).resolvingSymlinksInPath()
        guard directory.path.hasPrefix(docs.path + "/") else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = UUID().uuidString.lowercased() + "." + ext
        try data.write(to: directory.appendingPathComponent(name), options: .atomic)
        return "![](\(relative)/\(name))"
    }

    private static func title(_ content: String, fallback: String) -> String {
        let line = content.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let clean = line.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? fallback : String(clean.prefix(100))
    }
}
