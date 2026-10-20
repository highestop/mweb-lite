import AppKit
import SwiftUI

/// Selection comes from the store; expansion is retained by the workspace.
struct CategoryTreeView: View {
    let nodes: [CategoryNode]
    @Binding var selectedCategory: String
    let allCount: Int
    let uncategorizedCount: Int
    @Binding var expandedIDs: Set<String>
    @Environment(\.isEnabled) private var isEnabled
    @StateObject private var keyboard = CategoryTreeKeyboardController()

    private var categoryRows: [CategoryTreeEntry] {
        func flatten(_ nodes: [CategoryNode], depth: Int, parentID: String?) -> [CategoryTreeEntry] {
            nodes.flatMap { node in
                let entry = CategoryTreeEntry(id: node.id, name: node.name, count: node.count,
                                              depth: depth, parentID: parentID,
                                              hasChildren: !(node.children ?? []).isEmpty)
                return [entry] + (expandedIDs.contains(node.id)
                    ? flatten(node.children ?? [], depth: depth + 1, parentID: node.id) : [])
            }
        }
        return flatten(nodes, depth: 0, parentID: nil)
    }

    private var collectionRows: [CategoryTreeEntry] {
        [
            CategoryTreeEntry(id: "all", name: "所有文章", count: allCount),
            CategoryTreeEntry(id: "uncategorized", name: "未分类", count: uncategorizedCount)
        ]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(collectionRows) { row in categoryRow(row) }
                    Text("分类").font(.system(size: 11)).foregroundStyle(.secondary)
                        .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 4)
                    ForEach(categoryRows) { row in categoryRow(row) }
                }
                .padding(.horizontal, 10).padding(.bottom, 10)
            }
            .background(CategoryTreeKeyboardSelection(controller: keyboard, onCommand: navigate))
            .onChange(of: selectedCategory) { _, selected in proxy.scrollTo(selected) }
        }
    }

    private func categoryRow(_ entry: CategoryTreeEntry) -> some View {
        CategoryTreeRow(
            entry: entry, isSelected: selectedCategory == entry.id,
            isExpanded: expandedIDs.contains(entry.id),
            onSelect: {
                guard isEnabled else { return }
                selectedCategory = entry.id
                keyboard.focus()
            },
            onToggle: {
                toggle(entry)
                keyboard.focus()
            }
        ).id(entry.id)
    }

    private func toggle(_ entry: CategoryTreeEntry) {
        guard isEnabled, entry.hasChildren else { return }
        if expandedIDs.contains(entry.id) { expandedIDs.remove(entry.id) }
        else { expandedIDs.insert(entry.id) }
    }

    private func navigate(_ command: CategoryTreeCommand) {
        guard isEnabled else { return }
        let rows = collectionRows + categoryRows
        let index = rows.firstIndex { $0.id == selectedCategory }
        switch command {
        case .up, .down:
            let offset = command == .down ? 1 : -1
            let current = index ?? (offset > 0 ? -1 : rows.count)
            selectedCategory = rows[min(max(current + offset, 0), rows.count - 1)].id
        case .first:
            selectedCategory = rows[0].id
        case .last:
            selectedCategory = rows[rows.count - 1].id
        case .expand:
            guard let index else { return }
            let current = rows[index]
            if current.hasChildren, !expandedIDs.contains(current.id) {
                expandedIDs.insert(current.id)
            } else if current.hasChildren, rows.indices.contains(index + 1) {
                selectedCategory = rows[index + 1].id
            }
        case .collapse:
            guard let index else { return }
            let current = rows[index]
            if expandedIDs.contains(current.id) { expandedIDs.remove(current.id) }
            else if let parentID = current.parentID { selectedCategory = parentID }
        case .activate:
            if let index { toggle(rows[index]) }
        }
    }
}

private struct CategoryTreeEntry: Identifiable {
    let id: String
    let name: String
    let count: Int
    var depth = 0
    var parentID: String?
    var hasChildren = false
}

private struct CategoryTreeRow: View {
    let entry: CategoryTreeEntry
    let isSelected: Bool
    let isExpanded: Bool
    let onSelect: () -> Void
    let onToggle: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            if entry.hasChildren {
                Button(action: onToggle) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .frame(width: 18, height: 28, alignment: .center)
                }
                .buttonStyle(CategoryTreeButtonStyle())
                .focusEffectDisabled()
                .accessibilityLabel("\(isExpanded ? "收起" : "展开") \(entry.name)")
                .accessibilityValue(isExpanded ? "已展开" : "已收起")
            } else {
                Color.clear.frame(width: 18, height: 28).accessibilityHidden(true)
            }
            Button(action: onSelect) {
                HStack(spacing: 5) {
                    Text(entry.name).font(.system(size: 13)).lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(entry.count)").font(.system(size: 11))
                        .foregroundStyle(.secondary).monospacedDigit()
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(CategoryTreeButtonStyle())
            .focusEffectDisabled()
            .accessibilityLabel(entry.name)
            .accessibilityValue("\(entry.count) 篇文章")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
        .padding(.leading, CGFloat(entry.depth) * 14 + 4)
        .background(
            isSelected ? Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
                : Color.primary.opacity(isEnabled && isHovered ? 0.04 : 0),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .onHover { isHovered = $0 }
    }
}

private struct CategoryTreeButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.primary)
            .background(Color.primary.opacity(isEnabled && configuration.isPressed ? 0.08 : 0),
                        in: RoundedRectangle(cornerRadius: 4))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

private enum CategoryTreeCommand: Equatable {
    case up, down, expand, collapse, first, last, activate
}

@MainActor
private final class CategoryTreeKeyboardController: ObservableObject {
    weak var view: CategoryTreeKeyboardView?

    func focus() {
        guard let view else { return }
        view.window?.makeFirstResponder(view)
    }
}

private struct CategoryTreeKeyboardSelection: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let controller: CategoryTreeKeyboardController
    let onCommand: (CategoryTreeCommand) -> Void

    func makeNSView(context: Context) -> CategoryTreeKeyboardView {
        let view = CategoryTreeKeyboardView()
        view.configure(isEnabled: isEnabled, controller: controller, onCommand: onCommand)
        return view
    }

    func updateNSView(_ nsView: CategoryTreeKeyboardView, context: Context) {
        nsView.configure(isEnabled: isEnabled, controller: controller, onCommand: onCommand)
    }

    static func dismantleNSView(_ nsView: CategoryTreeKeyboardView, coordinator: ()) {
        nsView.invalidate()
    }
}

private final class CategoryTreeKeyboardView: NSView {
    private weak var controller: CategoryTreeKeyboardController?
    private var onCommand: ((CategoryTreeCommand) -> Void)?
    private var selectionEnabled = false
    private var isDismantled = false

    override var acceptsFirstResponder: Bool { !isDismantled }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    func configure(isEnabled: Bool, controller: CategoryTreeKeyboardController,
                   onCommand: @escaping (CategoryTreeCommand) -> Void) {
        guard !isDismantled else { return }
        if self.controller?.view === self { self.controller?.view = nil }
        self.controller = controller
        controller.view = self
        selectionEnabled = isEnabled
        self.onCommand = onCommand
        focusRingType = .none
    }

    override func keyDown(with event: NSEvent) {
        guard selectionEnabled, !isDismantled else { return }
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        let command: CategoryTreeCommand?
        switch event.keyCode {
        case 125: command = .down
        case 126: command = .up
        case 124: command = .expand
        case 123: command = .collapse
        case 115: command = .first
        case 119: command = .last
        case 36, 49, 76: command = .activate
        default: command = nil
        }
        guard modifiers.isEmpty, let command else { super.keyDown(with: event); return }
        onCommand?(command)
        if !isDismantled { controller?.focus() }
    }

    func invalidate() {
        isDismantled = true
        selectionEnabled = false
        onCommand = nil
        if controller?.view === self { controller?.view = nil }
        controller = nil
    }
}
