import AppKit
import Darwin
import Foundation
import WebKit

// This integration test builds outside SwiftPM and only writes its temporary fixture.
extension Bundle {
    static var module: Bundle {
        fatalError("Packaged preview must load its bundled resources without SwiftPM build paths")
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { print("FAIL: \(message)"); fflush(stdout); exit(1) }
}

let fixture = URL(fileURLWithPath: ProcessInfo.processInfo.environment["MWEB_PREVIEW_FIXTURE"]!)
let library = fixture.appendingPathComponent("library")
let media = library.appendingPathComponent("docs/media")
try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
let pixel = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAQAAAAECAYAAACp8Z5+AAAAEklEQVR4nGPwb0r9j4wZSBcAAKGII1EMyG3IAAAAAElFTkSuQmCC")!
try pixel.write(to: media.appendingPathComponent("test.png"))
try pixel.write(to: fixture.appendingPathComponent("outside.png"))
try FileManager.default.createSymbolicLink(at: media.appendingPathComponent("outside.png"), withDestinationURL: fixture.appendingPathComponent("outside.png"))

let resourceHandler = PreviewResourceHandler()
resourceHandler.libraryRoot = library
expect(resourceHandler.localMediaURL(for: URL(string: "mweblite://library/docs/media/test.png")!) != nil, "library image should be readable")
expect(resourceHandler.localMediaURL(for: URL(string: "mweblite://library/docs/media/outside.png")!) == nil, "symlinks must not escape the library")
expect(resourceHandler.localMediaURL(for: URL(string: "mweblite://library/mainlib.db")!) == nil, "the database must not be served to WebKit")
expect(PreviewResourceHandler.confinedURL(path: "../outside.png", root: library) == nil, "parent traversal must be rejected")
expect(MarkdownPreview.Coordinator.articleID(from: URL(string: "mweblib://123456789")!) == "123456789", "MWeb article links")
expect(MarkdownPreview.Coordinator.articleID(from: URL(string: "mweblite://library/docs/123456789.md")!) == "123456789", "relative article links")
expect(MarkdownPreview.Coordinator.articleID(from: URL(string: "mweblib://invalid")!) == nil, "invalid article IDs must be rejected")

let sample = #"""
# Preview verification

[TOC]

## Formatting

**Bold** ~~Deleted~~

- [x] A task

| A | B |
| - | - |
| 1 | 2 |

A footnote[^a]. [Article](mweblib://123456789)

[^a]: Footnote content

![Image-w140](media/test.png)

Math ``x^2``, and $a+b$.

$$
x = \frac{1}{2}
$$

```swift
let value = 2
```

```mermaid
graph LR
A[Start] --> B[Done]
```

```echarts
option = {xAxis:{type:'category',data:['A','B']},yAxis:{},series:[{type:'bar',data:[1,2]}]};
```

<script>window.noteExecuted = true</script>
<img src="file:///etc/passwd" onerror="window.noteExecuted=true">
<a href="javascript:window.noteExecuted=true">bad</a>
<div style="background:url(file:///etc/passwd)">Styled</div>
"""#

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
                    state["math"] as? Int == 3 && state["chart"] as? Int == 1 && labels.contains("Start") && labels.contains("Done")))
                if !ready && attempts > 0 { self.check(webView, runtimeAvailable: runtimeAvailable, attempts: attempts - 1); return }
                expect(ready, "rendering timed out: \(json)")
                expect(state["title"] as? String == "Preview verification", "CommonMark headings")
                expect(state["table"] as? Int == 1 && state["task"] as? Int == 1, "GFM table and task list")
                expect(state["footnote"] as? Int == 1 && state["toc"] as? Int == 2, "footnotes and TOC")
                expect(state["imageWidth"] as? String == "140", "MWeb image width")
                expect(state["article"] as? String == "mweblib://123456789", "article link retention")
                expect(state["noteExecuted"] as? Bool == false, "note scripts must never execute")
                expect(state["fileURLs"] as? Int == 0 && state["javascriptURLs"] as? Int == 0 && state["inlineHandlers"] as? Int == 0, "unsafe attributes must be stripped")
                if !runtimeAvailable, resourceHandler.runtimeRoot != nil {
                    self.render(webView, runtimeAvailable: true)
                    return
                }
                print("PASS: WebKit preview, GFM/MWeb extensions, local media containment, HTML isolation\(runtimeAvailable ? ", MathJax, Mermaid, ECharts and Prism" : " (optional MWeb runtimes unavailable)")")
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
