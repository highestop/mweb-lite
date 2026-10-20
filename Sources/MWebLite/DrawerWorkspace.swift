import AppKit
import SwiftUI

/// Marks the native keyboard responders owned by the two navigation panels.
protocol NavigationKeyboardResponder: AnyObject {}

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
        for (index, frame) in frames.enumerated() {
            // A native child can resolve a different width than the proposal.
            // Anchor the actual detail size to the fixed right edge.
            let x = index == 0 ? bounds.maxX : bounds.minX + frame.minX
            subviews[index].place(at: CGPoint(x: x, y: bounds.minY + frame.minY),
                                  anchor: index == 0 ? .topTrailing : .topLeading,
                                  proposal: ProposedViewSize(frame.size))
        }
    }
}

struct DrawerPanel: ViewModifier {
    let visible: Bool
    var highlighted = false

    func body(content: Content) -> some View {
        content
            .clipShape(UnevenRoundedRectangle(bottomTrailingRadius: 16, topTrailingRadius: 16,
                                             style: .continuous))
            .shadow(color: .black.opacity(visible ? (highlighted ? 0.12 : 0.06) : 0),
                    radius: highlighted ? 5 : 2, x: highlighted ? 2 : 1, y: 0)
            .disabled(!visible)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}

struct DrawerResizeHandle: View {
    let title: String
    let width: CGFloat
    let onResize: (CGFloat) -> Void
    let onHighlight: (Bool) -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        DrawerResizeRegion(width: width, isEnabled: isEnabled, onResize: onResize, onHighlight: onHighlight)
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

private struct DrawerResizeRegion: NSViewRepresentable {
    let width: CGFloat
    let isEnabled: Bool
    let onResize: (CGFloat) -> Void
    let onHighlight: (Bool) -> Void

    func makeNSView(context: Context) -> DrawerResizeView {
        let view = DrawerResizeView()
        view.configure(width: width, isEnabled: isEnabled, onResize: onResize, onHighlight: onHighlight)
        return view
    }

    func updateNSView(_ view: DrawerResizeView, context: Context) {
        view.configure(width: width, isEnabled: isEnabled, onResize: onResize, onHighlight: onHighlight)
    }

    static func dismantleNSView(_ view: DrawerResizeView, coordinator: ()) {
        view.invalidate()
    }
}

/// Owns the divider's native hit region and cursor updates, without a global
/// cursor stack that can restore another view's stale I-beam on exit.
final class DrawerResizeView: NSView {
    private var columnWidth: CGFloat = 0
    private var resizeEnabled = false
    private var initialDrag: (x: CGFloat, width: CGFloat)?
    private var hovering = false
    private var resizeTrackingArea: NSTrackingArea?
    private var onResize: ((CGFloat) -> Void)?
    private var onHighlight: ((Bool) -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func isAccessibilityElement() -> Bool { false }

    func configure(width: CGFloat, isEnabled: Bool,
                   onResize: @escaping (CGFloat) -> Void, onHighlight: @escaping (Bool) -> Void) {
        columnWidth = width
        self.onResize = onResize
        self.onHighlight = onHighlight
        guard resizeEnabled != isEnabled else { return }
        resizeEnabled = isEnabled
        if !isEnabled { endInteraction() }
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard resizeEnabled, !isHiddenOrHasHiddenAncestor else { return nil }
        return super.hitTest(point)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        if resizeEnabled, !isHiddenOrHasHiddenAncestor {
            addCursorRect(visibleRect, cursor: .resizeLeftRight)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let resizeTrackingArea { removeTrackingArea(resizeTrackingArea) }
        resizeTrackingArea = nil
        guard resizeEnabled else { return }
        let area = NSTrackingArea(rect: .zero,
                                  options: [.cursorUpdate, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        resizeTrackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        guard resizeEnabled, !isHiddenOrHasHiddenAncestor else { return }
        NSCursor.resizeLeftRight.set()
    }

    override func mouseEntered(with event: NSEvent) {
        guard resizeEnabled else { return }
        hovering = true
        onHighlight?(true)
    }

    override func mouseExited(with event: NSEvent) {
        hovering = false
        onHighlight?(initialDrag != nil)
        // AppKit chooses the destination view's cursor; do not pop or force one.
    }

    override func mouseDown(with event: NSEvent) {
        guard resizeEnabled, !isHiddenOrHasHiddenAncestor else { return }
        initialDrag = (event.locationInWindow.x, columnWidth)
        onHighlight?(true)
        NSCursor.resizeLeftRight.set()
    }

    override func mouseDragged(with event: NSEvent) {
        guard resizeEnabled, let initialDrag else { return }
        // The handle moves during resizing, so use stable window coordinates.
        onResize?(initialDrag.width + event.locationInWindow.x - initialDrag.x)
        NSCursor.resizeLeftRight.set()
    }

    override func mouseUp(with event: NSEvent) {
        guard initialDrag != nil else { return }
        initialDrag = nil
        hovering = resizeEnabled && visibleRect.contains(convert(event.locationInWindow, from: nil))
        onHighlight?(hovering)
        window?.invalidateCursorRects(for: self)
    }

    func invalidate() {
        resizeEnabled = false
        endInteraction()
        updateTrackingAreas()
        window?.invalidateCursorRects(for: self)
        onResize = nil
        onHighlight = nil
    }

    private func endInteraction() {
        initialDrag = nil
        hovering = false
        onHighlight?(false)
    }
}
