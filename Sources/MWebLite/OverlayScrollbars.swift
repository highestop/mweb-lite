import AppKit
import SwiftUI

extension View {
    /// Apply to the content of a ScrollView with `.scrollIndicators(.never)`.
    /// SwiftUI then reserves no legacy gutter; this probe restores native overlay
    /// scrollers while the rows use the containing viewport's actual width.
    func overlayScrollbars(viewportWidth: CGFloat) -> some View {
        frame(width: viewportWidth, alignment: .leading)
            .background(OverlayScrollbarConfiguration().allowsHitTesting(false))
    }
}

private struct OverlayScrollbarConfiguration: NSViewRepresentable {
    func makeNSView(context: Context) -> OverlayScrollbarView {
        OverlayScrollbarView()
    }

    func updateNSView(_ nsView: OverlayScrollbarView, context: Context) {
        nsView.scheduleConfiguration()
    }

    static func dismantleNSView(_ nsView: OverlayScrollbarView, coordinator: ()) {
        nsView.invalidate()
    }
}

private final class OverlayScrollbarView: NSView {
    private var isDismantled = false
    private var isConfigurationScheduled = false
    private weak var configuredScrollView: NSScrollView?
    private var visibilityObservation: NSKeyValueObservation?
    private var styleObservation: NSKeyValueObservation?

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
        scheduleConfiguration()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleConfiguration()
    }

    override func layout() {
        super.layout()
        scheduleConfiguration()
    }

    func scheduleConfiguration() {
        guard !isDismantled, !isConfigurationScheduled else { return }
        isConfigurationScheduled = true
        // Configure after SwiftUI's update, not while it measures its ancestor.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isConfigurationScheduled = false
            self.configureEnclosingScrollView()
        }
    }

    private func configureEnclosingScrollView() {
        guard !isDismantled else { return }
        guard let scrollView = enclosingScrollView else {
            visibilityObservation?.invalidate()
            visibilityObservation = nil
            styleObservation?.invalidate()
            styleObservation = nil
            configuredScrollView = nil
            return
        }
        if configuredScrollView !== scrollView {
            visibilityObservation?.invalidate()
            styleObservation?.invalidate()
            configuredScrollView = scrollView
            // SwiftUI can reapply its hidden-indicator policy without updating
            // this unchanged background. Restore only this native scroll view.
            visibilityObservation = scrollView.observe(\.hasVerticalScroller, options: [.new]) { [weak self] _, change in
                if change.newValue == false {
                    DispatchQueue.main.async { [weak self] in self?.scheduleConfiguration() }
                }
            }
            styleObservation = scrollView.observe(\.scrollerStyle, options: [.new]) { [weak self] _, change in
                if change.newValue != .overlay {
                    DispatchQueue.main.async { [weak self] in self?.scheduleConfiguration() }
                }
            }
        }
        if scrollView.scrollerStyle != .overlay {
            scrollView.scrollerStyle = .overlay
        }
        if !scrollView.hasVerticalScroller {
            scrollView.hasVerticalScroller = true
        }
        if !scrollView.autohidesScrollers {
            scrollView.autohidesScrollers = true
        }
        // AppKit owns the overlay knob's translucency, hover and fade animation.
    }

    @objc private func preferredScrollerStyleDidChange() {
        // AppKit also observes this notification and can restore its preferred
        // style. Apply our per-list policy after that notification is delivered.
        scheduleConfiguration()
    }

    func invalidate() {
        isDismantled = true
        visibilityObservation?.invalidate()
        visibilityObservation = nil
        styleObservation?.invalidate()
        styleObservation = nil
        configuredScrollView = nil
        NotificationCenter.default.removeObserver(self)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}
