import SwiftUI
import MWebCore

struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var isComposeHovered = false
    private let accent = Color(red: 0.18, green: 0.48, blue: 0.40)

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
            sidebar.navigationSplitViewColumnWidth(min: 180, ideal: 215, max: 320)
        } content: {
            articleList.ignoresSafeArea(.container, edges: .top).navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 400)
        } detail: {
            detail.ignoresSafeArea(.container, edges: .top)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar(removing: .sidebarToggle)
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "books.vertical").foregroundStyle(accent).font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.libraryName).font(.headline).lineLimit(1)
                    Text("本地文库").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(.horizontal, 17).padding(.vertical, 12)
                .background(WindowDragArea())
            List(selection: $store.selectedCategory) {
                Label { rowLabel("所有文章", count: store.activeArticles.count) } icon: { Image(systemName: "tray.full") }.tag("all")
                Label { rowLabel("未分类", count: store.activeArticles.filter { $0.categoryIDs.isEmpty }.count) } icon: { Image(systemName: "doc") }.tag("uncategorized")
                Section("分类") {
                    OutlineGroup(store.categoryTree, children: \.children) { node in
                        Label { rowLabel(node.name, count: node.count) } icon: { Image(systemName: "folder") }.tag(node.id)
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
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                    TextField("搜索标题与摘要", text: $store.search).textFieldStyle(.plain)
                    if !store.search.isEmpty {
                        Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                    }
                }
                .font(.system(size: 12)).padding(8)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 7))
                Button { store.createArticle() } label: {
                    Image(systemName: "square.and.pencil").font(.system(size: 16)).frame(width: 32, height: 32)
                }
                .buttonStyle(ComposeButtonStyle(accent: accent, isHovered: isComposeHovered))
                .onHover { isComposeHovered = $0 }
                .accessibilityLabel("新建文章")
                .help("新建文章 · ⌘N")
                .disabled(store.isBusy)
            }.padding(.horizontal, 14).padding(.vertical, 12)
            Divider()
            if store.visibleArticles.isEmpty {
                ContentUnavailableView("没有文章", systemImage: "doc.text.magnifyingglass", description: Text(store.search.isEmpty ? "这个分类中还没有文章。" : "试试其他关键词。"))
            } else {
                List(selection: Binding<String?>(get: { store.document?.articleID }, set: { store.selectArticle($0) })) {
                    ForEach(store.visibleArticles) { article in
                        VStack(alignment: .leading, spacing: 7) {
                            Text(article.id == store.document?.articleID ? store.currentTitle : article.title)
                                .font(.system(size: 13, weight: .semibold)).lineLimit(2)
                            if !article.excerpt.isEmpty { Text(article.excerpt).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2) }
                            if let date = article.modifiedAt {
                                Text(date, format: .dateTime.year().month().day()).font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        }.padding(.vertical, 9).tag(article.id)
                    }
                }.listStyle(.inset).disabled(store.isBusy)
            }
        }.background(Color(nsColor: .controlBackgroundColor))
    }

    private var detail: some View {
        VStack(spacing: 0) {
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
        .overlay(alignment: .topTrailing) { if store.isBusy { ProgressView().controlSize(.small).padding(12) } }
    }
}

private struct ComposeButtonStyle: ButtonStyle {
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
