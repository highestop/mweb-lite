import AppKit
import SwiftUI

extension View {
    /// Apply to a ScrollView's content so its native scrollers float over the
    /// existing viewport without reserving space beside the rows.
    func overlayScrollbars() -> some View {
        background(OverlayScrollbarConfiguration().allowsHitTesting(false))
    }
}

private struct OverlayScrollbarConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> OverlayScrollbarView {
        OverlayScrollbarView()
    }

    func updateNSView(_ nsView: OverlayScrollbarView, context: Context) {
        nsView.configureEnclosingScrollView()
    }

    static func dismantleNSView(_ nsView: OverlayScrollbarView, coordinator: ()) {
        nsView.invalidate()
    }
}

private final class OverlayScrollbarView: NSView {
    private var isDismantled = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        NotificationCenter.default.addObserver(
            self, selector: #selector(preferredScrollerStyleDidChange),
            name: NSScroller.preferredScrollerStyleDidChangeNotification, object: nil
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureEnclosingScrollView()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureEnclosingScrollView()
    }

    override func layout() {
        super.layout()
        configureEnclosingScrollView()
    }

    func configureEnclosingScrollView() {
        guard !isDismantled, let scrollView = enclosingScrollView else { return }
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
        if !scrollView.autohidesScrollers {
            scrollView.autohidesScrollers = true
        }
        // AppKit owns the overlay knob's translucency, hover and fade animation.
    }

    @objc private func preferredScrollerStyleDidChange() {
        // AppKit also observes this notification and can restore its preferred
        // style. Apply our per-list policy after that notification is delivered.
        DispatchQueue.main.async { [weak self] in
            self?.configureEnclosingScrollView()
        }
    }

    func invalidate() {
        isDismantled = true
        NotificationCenter.default.removeObserver(self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
