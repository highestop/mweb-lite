import SwiftUI
import MWebCore

struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationVisible = true
    @State private var categoryWidth: CGFloat = 243
    @State private var articleWidth: CGFloat = 360
    @State private var categoryEdgeHighlighted = false
    @State private var articleEdgeHighlighted = false
    @State private var expandedCategoryIDs: Set<String> = []
    @StateObject private var articleListSelection = ArticleListSelectionController()
    private let headerHeight: CGFloat = 56

    var body: some View {
        Group {
            if store.rootURL == nil { welcome }
            else { workspace }
        }
        .tint(.gray)
        .onChange(of: store.rootURL) { _, _ in
            expandedCategoryIDs.removeAll()
            categoryEdgeHighlighted = false
            articleEdgeHighlighted = false
        }
        .toolbar(.hidden, for: .windowToolbar)
        .alert("MWeb Lite", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("好", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "doc.text").font(.system(size: 46, weight: .light))
                .foregroundStyle(.secondary).padding(25)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 25))
            Text("MWeb Lite").font(.system(size: 32, weight: .semibold, design: .rounded)).padding(.top, 24)
            Text("熟悉的文库，专注的写作空间。")
                .font(.system(size: 16)).foregroundStyle(.secondary).padding(.top, 10)
            Text("打开已有的 MWeb 文库，浏览分类、阅读和编辑 Markdown。")
                .foregroundStyle(.secondary).padding(.top, 22)
            Button { store.chooseLibrary() } label: {
                Label("选择文库目录", systemImage: "folder").fontWeight(.medium).padding(.horizontal, 18).padding(.vertical, 7)
            }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .controlSize(.large).padding(.top, 28).disabled(store.isBusy)
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
        GeometryReader { proxy in
            let geometry = DrawerGeometry(size: proxy.size, progress: navigationVisible ? 1 : 0,
                                          categoryWidth: categoryWidth, articleWidth: articleWidth)
            DrawerWorkspaceLayout(progress: navigationVisible ? 1 : 0,
                                  categoryWidth: categoryWidth, articleWidth: articleWidth) {
                detail
                    .padding(.leading, 16)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .zIndex(0)
                articleList(width: geometry.articleWidth)
                    .padding(.leading, 16)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .modifier(DrawerPanel(visible: navigationVisible, highlighted: articleEdgeHighlighted))
                    .zIndex(1)
                sidebar
                    .padding(.top, max(28, proxy.safeAreaInsets.top))
                    .background(Color(nsColor: .windowBackgroundColor))
                    .modifier(DrawerPanel(visible: navigationVisible, highlighted: categoryEdgeHighlighted))
                    .zIndex(2)
                DrawerResizeHandle(title: "调整分类栏宽度", width: geometry.categoryWidth) {
                    categoryWidth = min(max($0, 180), min(320, max(180, proxy.size.width - 420 - geometry.articleWidth)))
                } onHighlight: {
                    categoryEdgeHighlighted = $0
                }
                .disabled(!navigationVisible)
                .allowsHitTesting(navigationVisible)
                .accessibilityHidden(!navigationVisible)
                .zIndex(3)
                DrawerResizeHandle(title: "调整文章栏宽度", width: geometry.articleWidth) {
                    articleWidth = min(max($0, 220), min(400, max(220, proxy.size.width - 420 - geometry.categoryWidth)))
                } onHighlight: {
                    articleEdgeHighlighted = $0
                }
                .disabled(!navigationVisible)
                .allowsHitTesting(navigationVisible)
                .accessibilityHidden(!navigationVisible)
                .zIndex(3)
            }
            .clipped()
        }
        .ignoresSafeArea(.container, edges: .top)
    }

    private var sidebar: some View {
        CategoryTreeView(
            nodes: store.categoryTree, selectedCategory: $store.selectedCategory,
            allCount: store.activeArticles.count,
            uncategorizedCount: store.activeArticles.filter { $0.categoryIDs.isEmpty }.count,
            expandedIDs: $expandedCategoryIDs
        )
        .id(store.rootURL)
        .disabled(store.isBusy)
        .padding(.top, 10)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func articleList(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("搜索标题与摘要", text: $store.search).textFieldStyle(.plain)
                    if !store.search.isEmpty {
                        Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                    }
                }
                .font(.system(size: 12)).padding(.horizontal, 12).frame(height: 32)
                .background(.quaternary.opacity(0.55), in: Capsule())
            }.padding(.horizontal, 14).frame(height: headerHeight)
            Divider()
            if store.visibleArticles.isEmpty {
                ContentUnavailableView("没有文章", systemImage: "doc.text.magnifyingglass", description: Text(store.search.isEmpty ? "这个分类中还没有文章。" : "试试其他关键词。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ArticleTimelineList(entries: ArticleTimelineGrouping.entries(articles: store.visibleArticles)) { entry in
                        articleRow(entry.article, width: width - 20, showsDate: entry.showsDate)
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
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func articleRow(_ article: MWebArticle, width: CGFloat, showsDate: Bool) -> some View {
        let selected = store.selectedArticleID == article.id
        return ArticleTimelineContent(
            article: article,
            title: article.id == store.document?.articleID ? store.currentTitle : article.title,
            libraryRoot: store.rootURL,
            width: width - 20,
            showsDate: showsDate
        )
        .padding(10)
        .background(selected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor) : .clear,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    // Keep the native editor across mode changes, but start each file
                    // with a fresh view so delayed native scrolling cannot leak across files.
                    MarkdownEditor(text: Binding(get: { store.draft }, set: { if store.document?.articleID == document.articleID { store.edit($0) } }), documentID: document.articleID, isVisible: store.mode == .editor,
                        onSave: { store.saveNow() }, onInsertImages: { store.insertImages($0) }, onPasteImage: { store.pasteImage($0) },
                        focusRequest: store.editorFocusRequest, onFocusHandled: { store.consumeEditorFocus($0) })
                        .id(document.fileURL)
                        .disabled(store.isBusy || store.mode != .editor)
                        .opacity(store.mode == .editor ? 1 : 0)
                        .allowsHitTesting(store.mode == .editor)
                        .accessibilityHidden(store.mode != .editor)
                    MarkdownPreview(markdown: store.draft, documentURL: document.fileURL, libraryRoot: store.rootURL, isVisible: store.mode == .preview,
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
                title: navigationVisible ? "收起侧边栏" : "展开侧边栏",
                symbol: "sidebar.left", help: "展开或收起分类和文章列表"
            ) {
                categoryEdgeHighlighted = false
                articleEdgeHighlighted = false
                // End navigation input before it goes offscreen; leave an active
                // editor's selection, composition, and undo history in place.
                let responder = NSApp.keyWindow?.firstResponder
                if navigationVisible,
                   responder is NavigationKeyboardResponder || (responder as? NSTextView)?.isFieldEditor == true {
                    NSApp.keyWindow?.makeFirstResponder(nil)
                }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.22)) {
                    navigationVisible.toggle()
                }
            }
            .accessibilityIdentifier("toggle-navigation")
            ToolbarIconButton(title: "新建文章", symbol: "plus", help: "新建文章 · ⌘N") {
                store.createArticle()
            }
            .accessibilityIdentifier("new-article")
            .disabled(store.isBusy)
            Spacer(minLength: 0)
            if store.isBusy && !store.isSwitchingArticle { ProgressView().controlSize(.small) }
            modeButtons
        }
        .padding(.leading, navigationVisible ? 14 : 88)
        .padding(.trailing, 14)
        .frame(height: headerHeight)
        .background(WindowDragArea())
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var modeButtons: some View {
        HStack(spacing: 2) {
            EditorModeButton(title: "预览", symbol: "eye", isSelected: store.mode == .preview) {
                store.setMode(.preview)
            }
            .accessibilityIdentifier("show-preview-mode")
            EditorModeButton(title: "编辑", symbol: "pencil", isSelected: store.mode == .editor) {
                store.setMode(.editor)
            }
            .accessibilityIdentifier("show-editor-mode")
        }
        .padding(3)
        .background(Color.primary.opacity(0.025), in: Capsule())
        // Custom buttons can block input without changing their loading appearance.
        .disabled(store.document == nil || store.isBusy)
        .opacity(store.document == nil ? 0.45 : 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("文章视图")
    }
}

private struct EditorModeButton: View {
    let title: String
    let symbol: String
    let isSelected: Bool
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 32, height: 32, alignment: .center)
        }
        .buttonStyle(ToolbarButtonStyle(isHovered: isHovered, isSelected: isSelected))
        .onHover { isHovered = $0 }
        .help("\(title) · ⌘R 切换视图")
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct ToolbarIconButton: View {
    let title: String
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14))
                .frame(width: 32, height: 32, alignment: .center)
        }
        .buttonStyle(ToolbarButtonStyle(isHovered: isHovered))
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .help(help)
    }
}

private struct ToolbarButtonStyle: ButtonStyle {
    let isHovered: Bool
    var isSelected = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = isEnabled && configuration.isPressed
        let highlighted = isEnabled && (isHovered || pressed)
        // Loading briefly disables actions without fading the toolbar.
        return configuration.label
            .foregroundStyle(isSelected || highlighted ? Color.primary : Color.secondary)
            .background(Color.primary.opacity(pressed ? 0.12 : isSelected ? 0.08 : highlighted ? 0.06 : 0),
                        in: Circle())
            .contentShape(Circle())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: pressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
    }
}
