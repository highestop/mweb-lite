import AppKit
import Darwin
import Foundation
import WebKit

// This integration test builds outside SwiftPM and only writes its temporary runtime copy.
extension Bundle {
    static var module: Bundle {
        fatalError("Packaged preview must load its bundled resources without SwiftPM build paths")
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL: \(message)"); fflush(stdout); exit(1) }
}

func environmentDirectory(_ name: String) -> URL {
    guard let path = ProcessInfo.processInfo.environment[name], !path.isEmpty else {
        print("FAIL: Missing \(name); run scripts/test-preview.sh")
        exit(1)
    }
    return URL(fileURLWithPath: path, isDirectory: true)
}

let fixtures = environmentDirectory("MWEB_PREVIEW_FIXTURES")
let runtime = environmentDirectory("MWEB_PREVIEW_RUNTIME_ROOT")
let library = runtime.appendingPathComponent("library")
let docs = library.appendingPathComponent("docs")
let document = docs.appendingPathComponent("preview.md")
let media = docs.appendingPathComponent("media")
let files = FileManager.default
try files.createDirectory(at: docs, withIntermediateDirectories: true)
try files.copyItem(at: fixtures.appendingPathComponent("rendering.md"), to: document)
try files.copyItem(at: fixtures.appendingPathComponent("media"), to: media)
// The escape target and symlink belong only to this run, never to the checked-in fixtures.
let outsideImage = runtime.appendingPathComponent("outside.png")
try files.copyItem(at: media.appendingPathComponent("test.png"), to: outsideImage)
try files.createSymbolicLink(at: media.appendingPathComponent("outside.png"), withDestinationURL: outsideImage)

let resourceHandler = PreviewResourceHandler()
resourceHandler.libraryRoot = library
expect(resourceHandler.localMediaURL(for: URL(string: "mweblite://library/docs/media/test.png")!) != nil, "library image should be readable")
expect(resourceHandler.localMediaURL(for: URL(string: "mweblite://library/docs/media/outside.png")!) == nil, "symlinks must not escape the library")
expect(resourceHandler.localMediaURL(for: URL(string: "mweblite://library/mainlib.db")!) == nil, "the database must not be served to WebKit")
expect(PreviewResourceHandler.confinedURL(path: "../outside.png", root: library) == nil, "parent traversal must be rejected")
print("PASS PV-001: local media confinement")
expect(MarkdownPreview.Coordinator.articleID(from: URL(string: "mweblib://123456789")!) == "123456789", "MWeb article links")
expect(MarkdownPreview.Coordinator.articleID(from: URL(string: "mweblite://library/docs/123456789.md")!) == "123456789", "relative article links")
expect(MarkdownPreview.Coordinator.articleID(from: URL(string: "mweblib://invalid")!) == nil, "invalid article IDs must be rejected")
print("PASS PV-002: article URL parsing")

let sample = try String(contentsOf: document, encoding: .utf8)

let snapshotScript = #"""
JSON.stringify({title:document.querySelector('h1')?.textContent,
table:document.querySelectorAll('table').length,task:document.querySelectorAll('input[type=checkbox]').length,
footnote:document.querySelectorAll('.footnotes').length,toc:document.querySelectorAll('.table-of-contents a').length,
imageWidth:document.querySelector('img[width]')?.getAttribute('width'),imageLoaded:document.querySelector('img[width]')?.naturalWidth,
article:document.querySelector('a[href^="mweblib:"]')?.href,math:document.querySelectorAll('mjx-container').length,
mermaidLabels:Array.from(document.querySelectorAll('.diagram svg text')).map(x=>x.textContent),
chart:document.querySelectorAll('.chart canvas').length,highlight:document.querySelectorAll('.token').length,
noteExecuted:!!window.noteExecuted,fileURLs:document.querySelectorAll('[src^="file:"]').length,
javascriptURLs:document.querySelectorAll('[href^="javascript:"]').length,inlineHandlers:document.querySelectorAll('[onerror]').length,
errors:Array.from(document.querySelectorAll('.render-note')).map(x=>x.textContent)})
"""#

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let configuration = WKWebViewConfiguration()
configuration.websiteDataStore = .nonPersistent()
configuration.setURLSchemeHandler(resourceHandler, forURLScheme: "mweblite")
let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 900), configuration: configuration)
let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
window.contentView = view

final class Delegate: NSObject, WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        render(webView, runtimeAvailable: false)
    }

    func render(_ webView: WKWebView, runtimeAvailable: Bool) {
        webView.callAsyncJavaScript("window.renderMarkdown(markdown, 'mweblite://library/docs/', runtimeAvailable, true)",
                                   arguments: ["markdown": sample, "runtimeAvailable": runtimeAvailable], in: nil, in: .page) { result in
            if case .failure(let error) = result { print("FAIL: \(error)"); exit(1) }
            self.check(webView, runtimeAvailable: runtimeAvailable, attempts: 40)
        }
    }

    func check(_ webView: WKWebView, runtimeAvailable: Bool, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            webView.evaluateJavaScript(snapshotScript) { value, error in
                guard let json = value as? String, let data = json.data(using: .utf8),
                      let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    print("FAIL: JavaScript state unavailable: \(String(describing: error))"); exit(1)
                }
                let labels = state["mermaidLabels"] as? [String] ?? []
                let ready = (state["imageLoaded"] as? Int ?? 0) > 0 && (!runtimeAvailable || (
                    state["math"] as? Int == 3 && state["chart"] as? Int == 1 &&
                    (state["highlight"] as? Int ?? 0) > 0 && labels.contains("Start") && labels.contains("Done")))
                if !ready && attempts > 0 { self.check(webView, runtimeAvailable: runtimeAvailable, attempts: attempts - 1); return }
                expect(ready, "rendering timed out: \(json)")
                expect(state["title"] as? String == "Preview verification", "CommonMark headings")
                expect(state["table"] as? Int == 1 && state["task"] as? Int == 1, "GFM table and task list")
                expect(state["footnote"] as? Int == 1 && state["toc"] as? Int == 2, "footnotes and TOC")
                expect(state["imageWidth"] as? String == "140", "MWeb image width")
                expect(state["article"] as? String == "mweblib://123456789", "article link retention")
                expect(state["noteExecuted"] as? Bool == false, "note scripts must never execute")
                expect(state["fileURLs"] as? Int == 0 && state["javascriptURLs"] as? Int == 0 && state["inlineHandlers"] as? Int == 0, "unsafe attributes must be stripped")
                if !runtimeAvailable {
                    print("PASS PV-003: bundled CommonMark/GFM/MWeb rendering and local image loading")
                    print("PASS PV-004: unsafe HTML isolation")
                    if resourceHandler.runtimeRoot != nil {
                        self.render(webView, runtimeAvailable: true)
                        return
                    }
                    print("SKIP PV-005: optional MWeb runtimes are unavailable; install MWeb Pro and rerun")
                } else {
                    expect((state["highlight"] as? Int ?? 0) > 0, "Prism syntax highlighting")
                    print("PASS PV-005: MathJax, Mermaid, ECharts and Prism rendering")
                }
                print("PASS: preview integration checks finished; skipped cases are not verified")
                fflush(stdout)
                exit(0)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("FAIL: \(error)"); fflush(stdout); exit(1)
    }
}
let delegate = Delegate()
view.navigationDelegate = delegate
view.load(URLRequest(url: URL(string: "mweblite://app/Preview.html")!))
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { print("FAIL: WebKit timed out"); fflush(stdout); exit(1) }
app.run()
