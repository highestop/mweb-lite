import SwiftUI
import MWebCore

struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @StateObject private var articleListSelection = ArticleListSelectionController()
    private let accent = Color(red: 0.18, green: 0.48, blue: 0.40)
    private let headerHeight: CGFloat = 56

    var body: some View {
        Group {
            if store.rootURL == nil { welcome }
            else { workspace }
        }
        .tint(accent)
        .toolbar(.hidden, for: .windowToolbar)
        .alert("MWeb Lite", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "doc.text").font(.system(size: 46, weight: .light))
                .foregroundStyle(accent).padding(25)
                .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 25))
            Text("MWeb Lite").font(.system(size: 32, weight: .semibold, design: .rounded)).padding(.top, 24)
            Text("熟悉的文库，专注的写作空间。")
                .font(.system(size: 16)).foregroundStyle(.secondary).padding(.top, 10)
            Text("打开已有的 MWeb 文库，浏览分类、阅读和编辑 Markdown。")
                .foregroundStyle(.secondary).padding(.top, 22)
            Button { store.chooseLibrary() } label: {
                Label("选择文库目录", systemImage: "folder").fontWeight(.medium).padding(.horizontal, 18).padding(.vertical, 7)
            }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 28).disabled(store.isBusy)
            Text("目录中应包含 mainlib.db 和 docs 文件夹")
                .font(.caption).foregroundStyle(.tertiary).padding(.top, 14)
            if store.isBusy { ProgressView().controlSize(.small).padding(.top, 18) }
            Spacer()
            HStack(spacing: 30) {
                Label("直接使用原文库", systemImage: "externaldrive")
                Label("本地编辑与预览", systemImage: "doc.richtext")
                Label("保存前自动备份", systemImage: "clock.arrow.circlepath")
            }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 34)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var workspace: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // macOS keeps a three-column split's middle column visible. Group
            // both navigation panes into one sidebar so they collapse together.
            HSplitView {
                sidebar.frame(minWidth: 180, idealWidth: 215, maxWidth: 320)
                articleList.frame(minWidth: 220, idealWidth: 270, maxWidth: 400)
                    .ignoresSafeArea(.container, edges: .top)
            }
            .navigationSplitViewColumnWidth(min: 401, ideal: 486, max: 721)
        } detail: {
            // Reserve the window controls' top edge when navigation is hidden.
            detail.ignoresSafeArea(.container, edges: columnVisibility == .detailOnly ? [] : .top)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.libraryName).font(.headline).lineLimit(1)
                    Text("本地文库").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 17).padding(.vertical, 12)
                .background(WindowDragArea())
            List(selection: $store.selectedCategory) {
                rowLabel("所有文章", count: store.activeArticles.count).tag("all")
                rowLabel("未分类", count: store.activeArticles.filter { $0.categoryIDs.isEmpty }.count).tag("uncategorized")
                Section("分类") {
                    OutlineGroup(store.categoryTree, children: \.children) { node in
                        rowLabel(node.name, count: node.count).padding(.leading, 6).tag(node.id)
                    }
                }
            }.listStyle(.sidebar).disabled(store.isBusy)
        }
    }

    private func rowLabel(_ name: String, count: Int) -> some View {
        HStack { Text(name).lineLimit(1); Spacer(minLength: 5); Text("\(count)").font(.caption).foregroundStyle(.tertiary).monospacedDigit() }
    }

    private var articleList: some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("搜索标题与摘要", text: $store.search).textFieldStyle(.plain)
                    if !store.search.isEmpty {
                        Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                    }
                }
                .font(.system(size: 12)).padding(.horizontal, 8).frame(height: 32)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
            }.padding(.horizontal, 14).frame(height: headerHeight)
            Divider()
            if store.visibleArticles.isEmpty {
                ContentUnavailableView("没有文章", systemImage: "doc.text.magnifyingglass", description: Text(store.search.isEmpty ? "这个分类中还没有文章。" : "试试其他关键词。"))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(store.visibleArticles) { article in
                                articleRow(article).id(article.id)
                            }
                        }.padding(10)
                    }
                    .onChange(of: store.selectedArticleID) { _, selected in
                        if let selected { proxy.scrollTo(selected) }
                    }
                    .onChange(of: store.visibleArticles.map(\.id)) { _, _ in
                        // Creation publishes the selection before the refreshed
                        // index; scroll again once that row is actually present.
                        if let selected = store.selectedArticleID { proxy.scrollTo(selected) }
                    }
                    .background(ArticleListKeyboardSelection(controller: articleListSelection, onMove: selectRelativeArticle))
                }.disabled(store.isBusy)
            }
        }.background(Color(nsColor: .controlBackgroundColor))
    }

    private func articleRow(_ article: MWebArticle) -> some View {
        let selected = store.selectedArticleID == article.id
        return VStack(alignment: .leading, spacing: 7) {
            Text(article.id == store.document?.articleID ? store.currentTitle : article.title)
                .font(.system(size: 13, weight: .semibold)).lineLimit(2)
            if !article.excerpt.isEmpty {
                Text(article.excerpt).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
            }
            if let date = article.modifiedAt {
                Text(date, format: .dateTime.year().month().day()).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6).padding(.vertical, 12)
        .background(selected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : .clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .overlay(ArticleRowMouseSelection(controller: articleListSelection) { store.selectArticle(article.id) })
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            store.selectArticle(article.id)
            articleListSelection.focus()
        }
    }

    private func selectRelativeArticle(_ offset: Int) {
        let articles = store.visibleArticles
        guard !store.isBusy, !articles.isEmpty else { return }
        let current = articles.firstIndex { $0.id == store.selectedArticleID } ?? (offset > 0 ? -1 : articles.count)
        let target = min(max(current + offset, 0), articles.count - 1)
        store.selectArticle(articles[target].id)
    }

    private var detail: some View {
        VStack(spacing: 0) {
            documentToolbar
            Divider()
            if let document = store.document {
                ZStack {
                    // Keep the native editor mounted to preserve selection and undo across mode changes.
                    MarkdownEditor(text: Binding(get: { store.draft }, set: { if store.document?.articleID == document.articleID { store.edit($0) } }), documentID: document.articleID,
                        onSave: { store.saveNow() }, onInsertImages: { store.insertImages($0) }, onPasteImage: { store.pasteImage($0) },
                        focusRequest: store.editorFocusRequest, onFocusHandled: { store.consumeEditorFocus($0) })
                        .disabled(store.isBusy || store.mode != .editor)
                        .opacity(store.mode == .editor ? 1 : 0)
                        .allowsHitTesting(store.mode == .editor)
                        .accessibilityHidden(store.mode != .editor)
                    MarkdownPreview(markdown: store.draft, documentURL: document.fileURL, libraryRoot: store.rootURL,
                        onOpenArticle: { store.openArticleLink($0) })
                        .opacity(store.mode == .preview ? 1 : 0)
                        .allowsHitTesting(store.mode == .preview)
                        .accessibilityHidden(store.mode != .preview)
                }
            } else {
                ContentUnavailableView("选择一篇文章", systemImage: "doc.text", description: Text("从左侧的文章列表开始。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var documentToolbar: some View {
        HStack(spacing: 6) {
            ToolbarIconButton(
                title: columnVisibility == .detailOnly ? "展开侧边栏" : "收起侧边栏",
                symbol: "sidebar.left", help: "展开或收起分类和文章列表", accent: accent
            ) {
                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
            }
            .accessibilityIdentifier("toggle-navigation")
            ToolbarIconButton(title: "新建文章", symbol: "square.and.pencil", help: "新建文章 · ⌘N", accent: accent) {
                store.createArticle()
            }
            .accessibilityIdentifier("new-article")
            .disabled(store.isBusy)
            ToolbarIconButton(
                title: store.mode == .preview ? "切换到编辑" : "切换到预览",
                symbol: store.mode == .preview ? "pencil" : "eye",
                help: store.mode == .preview ? "切换到编辑 · ⌘R" : "切换到预览 · ⌘R", accent: accent
            ) {
                store.setMode(store.mode == .preview ? .editor : .preview)
            }
            .accessibilityIdentifier("toggle-editor-mode")
            .disabled(store.document == nil || store.isBusy)
            Spacer(minLength: 0)
            if store.isBusy { ProgressView().controlSize(.small) }
        }
        .padding(.horizontal, 14)
        .frame(height: headerHeight)
        .background(WindowDragArea())
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct ToolbarIconButton: View {
    let title: String
    let symbol: String
    let help: String
    let accent: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16)).frame(width: 32, height: 32)
        }
        .buttonStyle(ToolbarButtonStyle(accent: accent, isHovered: isHovered))
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .help(help)
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    let accent: Color
    let isHovered: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = isEnabled && configuration.isPressed
        let highlighted = isEnabled && (isHovered || pressed)
        return configuration.label
            .foregroundStyle(highlighted ? accent : .secondary)
            .background(accent.opacity(pressed ? 0.20 : highlighted ? 0.10 : 0),
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay {
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(accent.opacity(highlighted ? 0.18 : 0), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .scaleEffect(pressed && !reduceMotion ? 0.92 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: pressed)
    }
}
