import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit
#if canImport(MWebCore)
import MWebCore
#endif

/// The preview never grants WebKit file access. Local media is served through a
/// narrow URL scheme after resolving symlinks and checking the selected library.
struct MarkdownPreview: NSViewRepresentable {
    var markdown: String
    var documentURL: URL?
    var libraryRoot: URL?
    var isVisible = true
    var onOpenArticle: (String) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(context.coordinator.resources, forURLScheme: "mweblite")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.isHidden = !isVisible
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: URL(string: "mweblite://app/Preview.html")!))
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if view.isHidden == isVisible {
            view.isHidden = !isVisible
            view.window?.invalidateCursorRects(for: view)
        }
        let coordinator = context.coordinator
        coordinator.onOpenArticle = onOpenArticle
        coordinator.resources.libraryRoot = libraryRoot
        let base = PreviewResourceHandler.documentBase(documentURL: documentURL, libraryRoot: libraryRoot)
        let documentChanged = coordinator.documentURL != documentURL
        guard coordinator.markdown != markdown || documentChanged || coordinator.baseURL != base else { return }
        coordinator.markdown = markdown
        coordinator.documentURL = documentURL
        coordinator.baseURL = base
        coordinator.resetScroll = coordinator.resetScroll || documentChanged
        coordinator.render(in: view)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let resources = PreviewResourceHandler()
        var onOpenArticle: (String) -> Void = { _ in }
        var markdown: String?
        var documentURL: URL?
        var baseURL = "mweblite://library/docs/"
        var resetScroll = true
        var loaded = false

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            render(in: webView)
        }

        func render(in view: WKWebView) {
            guard loaded, let markdown else { return }
            view.callAsyncJavaScript(
                "window.renderMarkdown(markdown, baseURL, runtimeAvailable, resetScroll)",
                arguments: ["markdown": markdown, "baseURL": baseURL,
                            "runtimeAvailable": resources.runtimeRoot != nil, "resetScroll": resetScroll],
                in: nil, in: .page
            ) { _ in }
            resetScroll = false
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
            if url.scheme == "mweblite", url.host == "app", url.path == "/Preview.html" {
                decisionHandler(.allow)
                return
            }
            decisionHandler(.cancel)
            guard navigationAction.navigationType == .linkActivated else { return }
            if let id = Self.articleID(from: url) {
                onOpenArticle(id)
            } else if ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            } else if let localURL = resources.localMediaURL(for: url) {
                NSWorkspace.shared.open(localURL)
            }
        }

        static func articleID(from url: URL) -> String? {
            let candidate: String
            if ["mweblib", "mweb"].contains(url.scheme?.lowercased() ?? "") {
                candidate = url.host ?? url.lastPathComponent
            } else if url.scheme == "mweblite", url.host == "library", url.pathExtension.lowercased() == "md" {
                candidate = url.deletingPathExtension().lastPathComponent
            } else {
                return nil
            }
            guard !candidate.isEmpty, candidate.allSatisfy(\.isNumber) else { return nil }
            return candidate
        }
    }
}

final class PreviewResourceHandler: NSObject, WKURLSchemeHandler {
    var libraryRoot: URL?
    let runtimeRoot: URL?
    let localization: Localization
    // SwiftPM's generated lookup differs between native and Xcode build backends.
    // Prefer the packaged app location so downloaded builds do not depend on the CI checkout.
    private static let resourceBundle: Bundle = {
        if let resources = Bundle.main.resourceURL,
           let bundle = Bundle(url: resources.appendingPathComponent("MWebLite_MWebLite.bundle")) {
            return bundle
        }
        return .module
    }()
    private static let bundledFiles: Set<String> = [
        "Preview.html", "Preview.css", "Preview.js", "markdown-it.min.js",
        "markdown-it-footnote.min.js", "markdown-it-task-lists.min.js", "purify.min.js", "json5.min.js"
    ]
    private static let mediaExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "svg", "avif", "heic", "bmp", "tiff", "tif",
        "pdf", "mp4", "m4v", "mov", "webm", "mp3", "m4a", "aac", "wav", "ogg", "flac"
    ]

    override convenience init() { self.init(localization: L10n.current) }

    init(localization: Localization) {
        self.localization = localization
        let candidates = [
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.coderforart.MWeb3"),
            URL(fileURLWithPath: "/Applications/MWeb Pro.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/MWeb Pro.app")
        ]
        runtimeRoot = candidates.compactMap { $0?.appendingPathComponent("Contents/Resources/assets") }
            .first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("mathjax/tex-svg-full.js").path) }
        super.init()
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        // Only application-owned strings enter this script; JSON encoding prevents
        // quotes or line breaks in translations from becoming executable source.
        if let url = urlSchemeTask.request.url,
           url.scheme == "mweblite", url.host == "app", url.path == "/Localization.js" {
            let keys = ["Article preview", "Scroll article", "Scroll content horizontally", "Table of contents",
                        "Copy", "Copied!", "Press ⌘C to copy",
                        "Install MWeb to use its local diagram rendering resources.",
                        "The diagram could not be rendered. Its source is preserved. ECharts accepts data configurations only."]
            var strings = Dictionary(uniqueKeysWithValues: keys.map { ($0, localization.string($0)) })
            strings["language"] = localization.language
            do {
                let json = try JSONSerialization.data(withJSONObject: strings, options: [.sortedKeys])
                let data = Data("window.previewStrings = ".utf8) + json + Data(";".utf8)
                urlSchemeTask.didReceive(URLResponse(url: url, mimeType: "application/javascript",
                    expectedContentLength: data.count, textEncodingName: "utf-8"))
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch { urlSchemeTask.didFailWithError(error) }
            return
        }
        guard let url = urlSchemeTask.request.url, let resource = resourceURL(for: url),
              let data = try? Data(contentsOf: resource, options: .mappedIfSafe) else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        let mime: String
        switch resource.pathExtension.lowercased() {
        case "js": mime = "application/javascript"
        case "css": mime = "text/css"
        case "html": mime = "text/html"
        default: mime = UTType(filenameExtension: resource.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        }
        let response = URLResponse(url: url, mimeType: mime, expectedContentLength: data.count,
                                   textEncodingName: mime.hasPrefix("text/") || mime.contains("javascript") ? "utf-8" : nil)
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}

    private func resourceURL(for url: URL) -> URL? {
        guard url.scheme == "mweblite" else { return nil }
        switch url.host {
        case "app":
            let name = url.lastPathComponent
            guard url.path == "/" + name, Self.bundledFiles.contains(name) else { return nil }
            return Self.resourceBundle.url(forResource: name, withExtension: nil)
        case "library": return localMediaURL(for: url)
        case "runtime":
            guard let runtimeRoot, let directory = url.pathComponents.dropFirst().first,
                  ["mathjax", "mermaid", "prism", "echarts"].contains(directory),
                  ["js", "css", "woff", "woff2", "ttf"].contains(url.pathExtension.lowercased()) else { return nil }
            let relativePath = url.pathComponents.dropFirst(2).joined(separator: "/")
            return Self.confinedURL(path: relativePath, root: runtimeRoot.appendingPathComponent(directory))
        default: return nil
        }
    }

    func localMediaURL(for url: URL) -> URL? {
        guard url.scheme == "mweblite", url.host == "library", let libraryRoot,
              Self.mediaExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return Self.confinedURL(path: url.path, root: libraryRoot)
    }

    nonisolated static func confinedURL(path: String, root: URL) -> URL? {
        let resolvedRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let result = resolvedRoot.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
            .standardizedFileURL.resolvingSymlinksInPath()
        guard result.path.hasPrefix(resolvedRoot.path + "/") else { return nil }
        return result
    }

    static func documentBase(documentURL: URL?, libraryRoot: URL?) -> String {
        guard let documentURL, let libraryRoot else { return "mweblite://library/docs/" }
        let root = libraryRoot.standardizedFileURL.path + "/"
        let directory = documentURL.deletingLastPathComponent().standardizedFileURL.path + "/"
        guard directory.hasPrefix(root) else { return "mweblite://library/docs/" }
        var components = URLComponents()
        components.scheme = "mweblite"
        components.host = "library"
        components.path = "/" + directory.dropFirst(root.count)
        return components.url?.absoluteString ?? "mweblite://library/docs/"
    }
}
