import AppKit
import SwiftUI

/// ScrollViewReader mounts offscreen selections; this native anchor then reveals
/// the row below the headings that visually cover the top of its viewport.
struct ArticleRowRevealAnchor: NSViewRepresentable {
    let articleID: String
    let headerInset: CGFloat
    let coordinator: ArticleRowRevealCoordinator

    func makeNSView(context: Context) -> ArticleRowRevealView {
        ArticleRowRevealView()
    }

    func updateNSView(_ nsView: ArticleRowRevealView, context: Context) {
        nsView.configure(articleID: articleID, headerInset: headerInset, coordinator: coordinator)
    }

    static func dismantleNSView(_ nsView: ArticleRowRevealView, coordinator: ()) {
        nsView.invalidate()
    }
}

/// The request outlives individual lazy rows. Remounting a selected row must not
/// replay a request that was already completed before manual scrolling.
@MainActor
final class ArticleRowRevealCoordinator: ObservableObject {
    private var selectedArticleID: String?
    private var generation = 0
    private var pending = false
    private struct WeakAnchor { weak var view: ArticleRowRevealView? }
    private var anchors: [String: WeakAnchor] = [:]

    /// Mounted rows use only native scrolling. ScrollViewReader is a fallback
    /// for mounting an absent lazy row, never a competing scroll for a live row.
    func reveal(_ articleID: String?, mount: () -> Void) {
        selectedArticleID = articleID
        generation += 1
        pending = articleID != nil
        guard let articleID else { return }
        if let view = anchors[articleID]?.view, view.canReveal {
            view.scheduleIfNeeded()
        } else {
            mount()
        }
    }

    func register(_ view: ArticleRowRevealView, for articleID: String) {
        anchors[articleID] = WeakAnchor(view: view)
        view.scheduleIfNeeded()
    }

    func unregister(_ view: ArticleRowRevealView, for articleID: String) {
        if anchors[articleID]?.view === view { anchors.removeValue(forKey: articleID) }
    }

    func request(for articleID: String) -> Int? {
        pending && selectedArticleID == articleID ? generation : nil
    }

    func complete(_ request: Int, for articleID: String) -> Bool {
        guard self.request(for: articleID) == request else { return false }
        pending = false
        return true
    }
}

final class ArticleRowRevealView: NSView {
    private(set) var articleID = ""
    private(set) weak var coordinator: ArticleRowRevealCoordinator?
    private var headerInset: CGFloat = 0
    private var lifetime = 0
    private var scheduledRequest: Int?
    private var isDismantled = false

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    var canReveal: Bool {
        !isDismantled && window != nil && enclosingScrollView != nil && bounds.width > 0 && bounds.height > 0
    }

    func configure(articleID: String, headerInset: CGFloat,
                   coordinator: ArticleRowRevealCoordinator) {
        guard !isDismantled else { return }
        if self.articleID != articleID || self.coordinator !== coordinator {
            self.coordinator?.unregister(self, for: self.articleID)
            lifetime += 1
            scheduledRequest = nil
        }
        self.articleID = articleID
        self.coordinator = coordinator
        self.headerInset = headerInset
        coordinator.register(self, for: articleID)
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        scheduleIfNeeded()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        scheduleIfNeeded()
    }

    override func layout() {
        super.layout()
        scheduleIfNeeded()
    }

    func scheduleIfNeeded() {
        guard let request = coordinator?.request(for: articleID),
              scheduledRequest != request, !isDismantled,
              window != nil, enclosingScrollView != nil else { return }
        scheduledRequest = request
        let currentLifetime = lifetime
        // Wait until both SwiftUI's selection update and ScrollViewReader's
        // mounting/scrolling pass have left the current layout transaction.
        DispatchQueue.main.async { [weak self] in
            DispatchQueue.main.async { [weak self] in
                self?.reveal(request, lifetime: currentLifetime)
            }
        }
    }

    private func reveal(_ request: Int, lifetime: Int) {
        guard lifetime == self.lifetime, !isDismantled,
              let coordinator, coordinator.request(for: articleID) == request else { return }
        guard let scrollView = enclosingScrollView, let document = scrollView.documentView,
              window != nil else { scheduledRequest = nil; return }
        scrollView.layoutSubtreeIfNeeded()
        guard bounds.width > 0, bounds.height > 0 else { scheduledRequest = nil; return }
        var target = convert(bounds, to: document)
        if document.isFlipped {
            target.origin.y -= headerInset
        }
        target.size.height += headerInset
        // Complete the request before scrolling: that scroll can synchronously
        // lay out this view, and later manual scrolling must never retrigger it.
        guard coordinator.complete(request, for: articleID) else { return }
        scheduledRequest = nil
        _ = document.scrollToVisible(target)
    }

    func invalidate() {
        isDismantled = true
        lifetime += 1
        scheduledRequest = nil
        coordinator?.unregister(self, for: articleID)
        coordinator = nil
    }
}
