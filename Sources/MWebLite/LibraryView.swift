import SwiftUI
import MWebCore

struct LibraryView: View {
    @ObservedObject var store: LibraryStore
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private let accent = Color(red: 0.18, green: 0.48, blue: 0.40)

    var body: some View {
        Group {
            if store.rootURL == nil { welcome }
            else { workspace }
        }
        .tint(accent)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { store.chooseLibrary() } label: { Label("打开文库", systemImage: "folder.badge.gearshape") }
                    .help("选择 MWeb 文库 · ⌘O").disabled(store.isBusy)
            }
            if store.rootURL != nil {
                ToolbarItem(placement: .automatic) {
                    Button { store.refresh() } label: { Label("刷新文库", systemImage: "arrow.clockwise") }
                        .help("读取磁盘上的最新内容 · ⇧⌘R").disabled(store.isBusy)
                }
                ToolbarItem(placement: .principal) {
                    Text(store.document == nil ? store.libraryName : store.currentTitle)
                        .font(.system(size: 13, weight: .medium)).lineLimit(1)
                }
                ToolbarItem(placement: .primaryAction) {
                    Picker("显示方式", selection: Binding(get: { store.mode }, set: { store.setMode($0) })) {
                        ForEach(EditorMode.allCases) { mode in Image(systemName: mode.symbol).tag(mode).help(mode.rawValue) }
                    }.pickerStyle(.segmented).frame(width: 128).help("编辑 / 分栏 / 预览")
                }
            }
        }
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
                Label("本地编辑与预览", systemImage: "rectangle.split.2x1")
                Label("保存前自动备份", systemImage: "clock.arrow.circlepath")
            }.font(.caption).foregroundStyle(.secondary).padding(.bottom, 34)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var workspace: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar.navigationSplitViewColumnWidth(min: 180, ideal: 215, max: 320)
        } content: {
            articleList.navigationSplitViewColumnWidth(min: 220, ideal: 270, max: 400)
        } detail: {
            detail
        }.navigationSplitViewStyle(.balanced)
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
            }.padding(.horizontal, 17).padding(.top, 19).padding(.bottom, 15)
            List(selection: $store.selectedCategory) {
                Label { rowLabel("所有文章", count: store.activeArticles.count) } icon: { Image(systemName: "tray.full") }.tag("all")
                Label { rowLabel("未分类", count: store.activeArticles.filter { $0.categoryIDs.isEmpty }.count) } icon: { Image(systemName: "doc") }.tag("uncategorized")
                Section("分类") {
                    OutlineGroup(store.categoryTree, children: \.children) { node in
                        Label { rowLabel(node.name, count: node.count) } icon: { Image(systemName: "folder") }.tag(node.id)
                    }
                }
            }.listStyle(.sidebar)
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 5, height: 5)
                Text("直接连接 MWeb 文库").font(.caption2).foregroundStyle(.secondary)
                Spacer()
            }.padding(16)
        }
    }

    private func rowLabel(_ name: String, count: Int) -> some View {
        HStack { Text(name).lineLimit(1); Spacer(minLength: 5); Text("\(count)").font(.caption).foregroundStyle(.tertiary).monospacedDigit() }
    }

    private var articleList: some View {
        VStack(spacing: 0) {
            HStack {
                Text(store.categoryTitle).font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(store.visibleArticles.count)").font(.caption).foregroundStyle(.secondary)
            }.padding(.horizontal, 18).padding(.top, 20).padding(.bottom, 13)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("搜索标题与摘要", text: $store.search).textFieldStyle(.plain)
                if !store.search.isEmpty {
                    Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
                }
            }.font(.system(size: 12)).padding(8).background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 7)).padding(.horizontal, 14).padding(.bottom, 14)
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
                HStack(spacing: 8) {
                    Text("MARKDOWN").font(.system(size: 9, weight: .semibold, design: .monospaced)).tracking(1.5).foregroundStyle(.tertiary)
                    Spacer()
                    if store.saveBlocked {
                        Button("重新载入磁盘版本…") { store.reloadFromDisk() }.font(.caption).buttonStyle(.plain).foregroundStyle(.orange)
                    }
                    Text(store.mode.rawValue).font(.caption).foregroundStyle(.secondary)
                }.padding(.horizontal, 22).frame(height: 40)
                Divider()
                HSplitView {
                    if store.mode != .preview {
                        MarkdownEditor(text: Binding(get: { store.draft }, set: { if store.document?.articleID == document.articleID { store.edit($0) } }), documentID: document.articleID,
                            onSave: { store.saveNow() }, onInsertImages: { store.insertImages($0) }, onPasteImage: { store.pasteImage($0) })
                            .frame(minWidth: 240).disabled(store.isBusy)
                    }
                    if store.mode != .editor {
                        MarkdownPreview(markdown: store.draft, documentURL: document.fileURL, libraryRoot: store.rootURL,
                            onOpenArticle: { store.openArticleLink($0) }).frame(minWidth: 240)
                    }
                }
                Divider()
                statusBar
            } else {
                ContentUnavailableView("选择一篇文章", systemImage: "doc.text", description: Text("从左侧的文章列表开始。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .topTrailing) { if store.isBusy { ProgressView().controlSize(.small).padding(12) } }
    }

    private var statusBar: some View {
        HStack(spacing: 6) {
            Image(systemName: store.saveBlocked ? "exclamationmark.circle" : store.isSaving ? "arrow.triangle.2.circlepath" : store.isDirty ? "circle.fill" : "checkmark.circle")
                .font(.system(size: store.isDirty && !store.isSaving && !store.saveBlocked ? 5 : 10))
                .foregroundStyle(store.saveBlocked ? Color.orange : accent)
            Text(store.saveBlocked ? "保存暂停，修改保留在窗口中" : store.isSaving ? "正在保存…" : store.isDirty ? "等待保存" : "已保存到本地")
            Spacer()
            Text("\(store.draft.count) 字符").monospacedDigit()
            Text("·")
            Text("UTF-8")
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 18).frame(height: 30)
    }
}
