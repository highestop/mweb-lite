import SwiftUI
import MWebCore

struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigationVisible = true
    @State private var categoryWidth: CGFloat = 180
    @State private var articleWidth: CGFloat = 400
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
            Button(L10n.string("OK"), role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }

    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "doc.text").font(.system(size: 46, weight: .light))
                .foregroundStyle(.secondary).padding(25)
                .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 25))
            Text("MWeb Lite").font(.system(size: 32, weight: .semibold, design: .rounded)).padding(.top, 24)
            Text(L10n.string("Your library. A space to focus."))
                .font(.system(size: 16)).foregroundStyle(.secondary).padding(.top, 10)
            Text(L10n.string("Open an existing MWeb library to browse categories, read, and edit Markdown."))
                .foregroundStyle(.secondary).padding(.top, 22)
            Button { store.chooseLibrary() } label: {
                Label(L10n.string("Choose Library Folder"), systemImage: "folder").fontWeight(.medium).padding(.horizontal, 18).padding(.vertical, 7)
            }.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                .controlSize(.large).padding(.top, 28).disabled(store.isBusy)
            Text(L10n.string("The folder should contain mainlib.db and the docs folder."))
                .font(.caption).foregroundStyle(.tertiary).padding(.top, 14)
            if store.isBusy { ProgressView().controlSize(.small).padding(.top, 18) }
            Spacer()
            HStack(spacing: 30) {
                Label(L10n.string("Use your existing library"), systemImage: "externaldrive")
                Label(L10n.string("Edit and preview locally"), systemImage: "doc.richtext")
                Label(L10n.string("Back up before saving"), systemImage: "clock.arrow.circlepath")
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
                DrawerResizeHandle(title: L10n.string("Resize categories"), width: geometry.categoryWidth) {
                    categoryWidth = min(max($0, 180), min(280, max(180, proxy.size.width - 420 - geometry.articleWidth)))
                } onHighlight: {
                    categoryEdgeHighlighted = $0
                }
                .disabled(!navigationVisible)
                .allowsHitTesting(navigationVisible)
                .accessibilityHidden(!navigationVisible)
                .zIndex(3)
                DrawerResizeHandle(title: L10n.string("Resize article list"), width: geometry.articleWidth) {
                    articleWidth = min(max($0, 320), min(400, max(320, proxy.size.width - 420 - geometry.categoryWidth)))
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
            expandedIDs: $expandedCategoryIDs,
            onCreate: promptCreateCategory,
            onRename: promptRenameCategory,
            onDelete: confirmDeleteCategory
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
                    TextField(L10n.string("Search titles and summaries"), text: $store.search).textFieldStyle(.plain)
                    if !store.search.isEmpty {
                        Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                            .buttonStyle(.plain).accessibilityLabel(L10n.string("Clear search"))
                    }
                }
                .font(.system(size: 12)).padding(.horizontal, 12).frame(height: 32)
                .background(.quaternary.opacity(0.55), in: Capsule())
            }.padding(.horizontal, 14).frame(height: headerHeight)
            Divider()
            if store.visibleArticles.isEmpty {
                ContentUnavailableView(L10n.string("No Articles"), systemImage: "doc.text.magnifyingglass", description: Text(store.search.isEmpty ? L10n.string("This category has no articles yet.") : L10n.string("Try different search terms.")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ArticleTimelineList(entries: ArticleTimelineGrouping.entries(articles: store.visibleArticles),
                                    selectedArticleID: store.selectedArticleID) { entry in
                    articleRow(entry.article, width: width - 20, showsDate: entry.showsDate)
                }
                .background(ArticleListKeyboardSelection(controller: articleListSelection, onMove: selectRelativeArticle))
                .disabled(store.isBusy)
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
        .overlay(ArticleRowMouseSelection(controller: articleListSelection, onDelete: {
            confirmTrashArticle(article)
        }) { store.selectArticle(article.id) })
        .accessibilityAction(named: Text(L10n.string("Delete Article"))) { confirmTrashArticle(article) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction {
            store.selectArticle(article.id)
            articleListSelection.focus()
        }
    }

    private func promptCreateCategory(parentID: String?) {
        guard !store.isBusy else { return }
        if let name = categoryNamePrompt(title: parentID == nil ? L10n.string("New Category") : L10n.string("New Subcategory"), name: "") {
            if let parentID { expandedCategoryIDs.insert(parentID) }
            store.createCategory(name: name, parentID: parentID)
        }
    }

    private func promptRenameCategory(_ id: String) {
        guard !store.isBusy, let category = store.categories.first(where: { $0.id == id }) else { return }
        if let name = categoryNamePrompt(title: L10n.string("Rename Category"), name: category.name) {
            store.renameCategory(id: id, name: name)
        }
    }

    private func categoryNamePrompt(title: String, name: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: L10n.string("OK"))
        alert.addButton(withTitle: L10n.string("Cancel"))
        let field = NSTextField(string: name)
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        field.placeholderString = L10n.string("Category name")
        field.setAccessibilityLabel(L10n.string("Category name"))
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue
    }

    private func confirmDeleteCategory(_ id: String) {
        guard !store.isBusy, let category = store.categories.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = L10n.format("Delete Category “%@”?", category.name)
        alert.informativeText = L10n.string("This category and all its subcategories will be deleted. Articles and attachments will be kept; only their links to these categories will be removed.")
        alert.addButton(withTitle: L10n.string("Cancel"))
        alert.addButton(withTitle: L10n.string("Delete Category"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        store.deleteCategory(id: id)
    }

    private func confirmTrashArticle(_ article: MWebArticle) {
        guard !store.isBusy else { return }
        let alert = NSAlert()
        alert.messageText = L10n.format("Delete Article “%@”?", article.title)
        alert.informativeText = L10n.string("The article will move to MWeb’s trash. Its text and attachments will be kept, and you can restore it in MWeb.")
        alert.addButton(withTitle: L10n.string("Cancel"))
        alert.addButton(withTitle: L10n.string("Move to Trash"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        store.trashArticle(article.id)
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
                ContentUnavailableView(L10n.string("Select an Article"), systemImage: "doc.text", description: Text(L10n.string("Choose an article from the list.")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var documentToolbar: some View {
        HStack(spacing: 6) {
            ToolbarIconButton(
                title: navigationVisible ? L10n.string("Hide Sidebar") : L10n.string("Show Sidebar"),
                symbol: "sidebar.left", help: L10n.string("Show or hide the categories and article list")
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
            ToolbarIconButton(title: L10n.string("New Article"), symbol: "plus", help: L10n.string("New article · ⌘N")) {
                store.createArticle()
            }
            .accessibilityIdentifier("new-article")
            .disabled(store.isBusy)
            Spacer(minLength: 0)
            if store.isBusy && !store.isSwitchingArticle { ProgressView().controlSize(.small) }
            DocumentSaveStatusIndicator(status: store.saveStatus)
            editorModeButton
        }
        .padding(.leading, navigationVisible ? 14 : 88)
        .padding(.trailing, 14)
        .frame(height: headerHeight)
        .background(WindowDragArea())
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var editorModeButton: some View {
        ToolbarIconButton(
            title: store.mode == .editor ? L10n.string("Preview") : L10n.string("Edit"),
            symbol: store.mode == .editor ? "eye" : "square.and.pencil",
            help: store.mode == .editor ? L10n.string("Switch to preview · ⌘R") : L10n.string("Switch to editing · ⌘R"),
            isSelected: store.mode == .editor,
            symbolWeight: .medium,
            symbolVerticalOffset: store.mode == .editor ? 0 : -1
        ) {
            store.setMode(store.mode == .editor ? .preview : .editor)
        }
        .accessibilityIdentifier("toggle-editor-mode")
        .accessibilityValue(store.mode == .editor ? L10n.string("Edit") : L10n.string("Preview"))
        // Custom buttons can block input without changing their loading appearance.
        .disabled(store.document == nil || store.isBusy)
        .opacity(store.document == nil ? 0.45 : 1)
    }
}

private struct ToolbarIconButton: View {
    let title: String
    let symbol: String
    let help: String
    var isSelected = false
    var symbolWeight: Font.Weight = .regular
    var symbolVerticalOffset: CGFloat = 0
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .symbolRenderingMode(.monochrome)
                .font(.system(size: 14, weight: symbolWeight))
                .offset(y: symbolVerticalOffset)
                .frame(width: 32, height: 32, alignment: .center)
        }
        .buttonStyle(ToolbarButtonStyle(isHovered: isHovered, isSelected: isSelected))
        .onHover { isHovered = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(help)
    }
}

struct ToolbarButtonStyle: ButtonStyle {
    let isHovered: Bool
    var isSelected = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = isEnabled && configuration.isPressed
        let highlighted = isEnabled && (isHovered || pressed)
        // Loading briefly disables actions without fading the toolbar.
        return configuration.label
            .foregroundStyle(highlighted ? Color.primary : Color.secondary)
            .background(Color.primary.opacity(pressed ? 0.12 : isSelected ? 0.08 : highlighted ? 0.06 : 0),
                        in: Circle())
            .contentShape(Circle())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: pressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isSelected)
    }
}
