import AppKit
import SwiftUI

/// Panel backgrounds overlap at the rounded edges; their content does not.
struct DrawerGeometry {
    let categoryWidth: CGFloat
    let articleWidth: CGFloat
    let categoryFrame: CGRect
    let articleFrame: CGRect
    let detailFrame: CGRect
    let categoryDividerX: CGFloat
    let articleDividerX: CGFloat

    init(size: CGSize, progress: CGFloat, categoryWidth: CGFloat, articleWidth: CGFloat, overlap: CGFloat = 16) {
        let width = max(0, size.width)
        let height = max(0, size.height)
        let budget = max(0, width - 420)
        var category = min(max(categoryWidth, 180), 320)
        var article = min(max(articleWidth, 220), 400)
        article = max(220, article - max(0, category + article - budget))
        category = max(180, min(category, budget - article))
        if category + article > budget {
            let scale = budget / (category + article)
            category *= scale
            article *= scale
        }
        self.categoryWidth = category
        self.articleWidth = article
        let total = category + article
        let visibleWidth = total * min(max(progress, 0), 1)
        let slide = visibleWidth - total
        categoryFrame = CGRect(x: slide, y: 0, width: category, height: height)
        articleFrame = CGRect(x: slide + category - overlap, y: 0, width: article + overlap, height: height)
        detailFrame = CGRect(x: visibleWidth - overlap, y: 0, width: width - visibleWidth + overlap, height: height)
        categoryDividerX = slide + category
        articleDividerX = visibleWidth
    }
}

/// A single animation value drives translation and resizing on every frame.
/// All five subviews stay mounted, including the native editor and WebKit view.
struct DrawerWorkspaceLayout: Layout {
    var progress: CGFloat
    var categoryWidth: CGFloat
    var articleWidth: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 5 else { return }
        let geometry = DrawerGeometry(size: bounds.size, progress: progress,
                                      categoryWidth: categoryWidth, articleWidth: articleWidth)
        let frames = [
            geometry.detailFrame, geometry.articleFrame, geometry.categoryFrame,
            CGRect(x: geometry.categoryDividerX - 4, y: 16, width: 8, height: max(0, bounds.height - 32)),
            CGRect(x: geometry.articleDividerX - 4, y: 16, width: 8, height: max(0, bounds.height - 32))
        ]
        for (view, frame) in zip(subviews, frames) {
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
}

struct DrawerPanel: ViewModifier {
    let visible: Bool

    func body(content: Content) -> some View {
        content
            .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 16, topTrailingRadius: 16,
                                             style: .continuous))
            .shadow(color: .black.opacity(visible ? 0.10 : 0), radius: 4, x: 2, y: 0)
            .disabled(!visible)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}

struct DrawerResizeHandle: View {
    let title: String
    let width: CGFloat
    let onResize: (CGFloat) -> Void
    @State private var initialWidth: CGFloat?
    @State private var isHovered = false

    var body: some View {
        Color.clear
            .overlay {
                Rectangle().fill(Color.primary.opacity(isHovered || initialWidth != nil ? 0.18 : 0))
                    .frame(width: 1)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("drawer-workspace"))
                .onChanged { value in
                    if initialWidth == nil { initialWidth = width }
                    onResize((initialWidth ?? width) + value.translation.width)
                }
                .onEnded { _ in initialWidth = nil })
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(title)
            .accessibilityValue("\(Int(width))")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: onResize(width + 20)
                case .decrement: onResize(width - 20)
                @unknown default: break
                }
            }
            .help(title)
    }
}
