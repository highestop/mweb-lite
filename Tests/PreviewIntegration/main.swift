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

let previewCaseIDs = ["PV-001", "PV-002", "PV-003", "PV-004", "PV-005", "PV-006"]

struct CaseResult: Encodable {
    let case_id: String
    let status: String
    let evidence: String
}

final class CaseResults {
    private let output: FileHandle
    private var failures: [String: [String]] = [:]
    private var completed: Set<String> = []
    private(set) var hasFailures = false
    private let summaries = [
        "PV-001": "Local media confinement assertions passed",
        "PV-002": "Article URL parsing assertions passed",
        "PV-003": "Bundled Markdown, MWeb extensions and local image assertions passed",
        "PV-004": "Script execution and unsafe HTML attribute assertions passed",
        "PV-005": "MathJax, Mermaid, ECharts and Prism assertions passed",
        "PV-006": "Document changes reset preview scrolling and same-document updates retain position"
    ]

    init(path: String) throws {
        output = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
    }

    func expect(_ caseID: String, _ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(previewCaseIDs.contains(caseID) && !completed.contains(caseID))
        if failures[caseID] == nil { failures[caseID] = [] }
        if !condition() {
            failures[caseID, default: []].append(message)
            hasFailures = true
        }
    }

    func complete(_ caseID: String) {
        guard let errors = failures[caseID], !completed.contains(caseID) else { return }
        let evidence = errors.isEmpty ? summaries[caseID]! : Array(Set(errors)).sorted().joined(separator: "; ")
        emit(caseID, status: errors.isEmpty ? "Passed" : "Failed", evidence: evidence)
    }

    func skip(_ caseID: String, reason: String) {
        precondition(failures[caseID] == nil && !completed.contains(caseID))
        emit(caseID, status: "Skipped", evidence: reason)
    }

    func completeObservedCases() {
        // A setup failure must not invent outcomes for assertions that never ran.
        for caseID in previewCaseIDs { complete(caseID) }
    }

    private func emit(_ caseID: String, status: String, evidence: String) {
        do {
            var data = try JSONEncoder().encode(CaseResult(case_id: caseID, status: status, evidence: evidence))
            data.append(0x0A)
            try output.write(contentsOf: data)
        } catch {
            print("FAIL: Could not write case results: \(error)")
            fflush(stdout)
            exit(1)
        }
        completed.insert(caseID)
        let label = status == "Passed" ? "PASS" : status == "Failed" ? "FAIL" : "SKIP"
        print("\(label) \(caseID): \(evidence)")
        fflush(stdout)
    }
}

func environmentValue(_ name: String) -> String {
    guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
        print("FAIL: Missing \(name); run scripts/test-preview.sh")
        fflush(stdout)
        exit(1)
    }
    return value
}

let results: CaseResults
do {
    results = try CaseResults(path: environmentValue("MWEB_CASE_RESULTS_PATH"))
} catch {
    print("FAIL: Could not open case results: \(error)")
    fflush(stdout)
    exit(1)
}

func abort(_ message: String, caseID: String? = nil) -> Never {
    if let caseID { results.expect(caseID, false, message) }
    results.completeObservedCases()
    print("FAIL: \(message)")
    fflush(stdout)
    exit(1)
}

let fixtures = URL(fileURLWithPath: environmentValue("MWEB_PREVIEW_FIXTURES"), isDirectory: true)
let runtime = URL(fileURLWithPath: environmentValue("MWEB_PREVIEW_RUNTIME_ROOT"), isDirectory: true)
let library = runtime.appendingPathComponent("library")
let docs = library.appendingPathComponent("docs")
let document = docs.appendingPathComponent("preview.md")
let media = docs.appendingPathComponent("media")
let files = FileManager.default
let sample: String
do {
    try files.createDirectory(at: docs, withIntermediateDirectories: true)
    try files.copyItem(at: fixtures.appendingPathComponent("rendering.md"), to: document)
    try files.copyItem(at: fixtures.appendingPathComponent("media"), to: media)
    // The escape target and symlink belong only to this run, never to the checked-in fixtures.
    let outsideImage = runtime.appendingPathComponent("outside.png")
    try files.copyItem(at: media.appendingPathComponent("test.png"), to: outsideImage)
    try files.createSymbolicLink(at: media.appendingPathComponent("outside.png"), withDestinationURL: outsideImage)
    sample = try String(contentsOf: document, encoding: .utf8)
} catch {
    abort("Preview fixture setup failed: \(error)")
}

let resourceHandler = PreviewResourceHandler()
resourceHandler.libraryRoot = library
results.expect("PV-001", resourceHandler.localMediaURL(for: URL(string: "mweblite://library/docs/media/test.png")!) != nil, "Library image was not readable")
results.expect("PV-001", resourceHandler.localMediaURL(for: URL(string: "mweblite://library/docs/media/outside.png")!) == nil, "Symlink escaped the library")
results.expect("PV-001", resourceHandler.localMediaURL(for: URL(string: "mweblite://library/mainlib.db")!) == nil, "Database was exposed to WebKit")
results.expect("PV-001", PreviewResourceHandler.confinedURL(path: "../outside.png", root: library) == nil, "Parent traversal was accepted")
results.complete("PV-001")
results.expect("PV-002", MarkdownPreview.Coordinator.articleID(from: URL(string: "mweblib://123456789")!) == "123456789", "MWeb article link was not parsed")
results.expect("PV-002", MarkdownPreview.Coordinator.articleID(from: URL(string: "mweblite://library/docs/123456789.md")!) == "123456789", "Relative article link was not parsed")
results.expect("PV-002", MarkdownPreview.Coordinator.articleID(from: URL(string: "mweblib://invalid")!) == nil, "Invalid article ID was accepted")
results.complete("PV-002")

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
    private var activeRenderCaseID: String?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        render(webView, runtimeAvailable: false)
    }

    func render(_ webView: WKWebView, runtimeAvailable: Bool) {
        let caseID = runtimeAvailable ? "PV-005" : "PV-003"
        activeRenderCaseID = caseID
        webView.callAsyncJavaScript("window.renderMarkdown(markdown, 'mweblite://library/docs/', runtimeAvailable, true)",
                                   arguments: ["markdown": sample, "runtimeAvailable": runtimeAvailable], in: nil, in: .page) { result in
            if case .failure(let error) = result {
                abort("Markdown rendering failed: \(error.localizedDescription)", caseID: caseID)
            }
            self.check(webView, runtimeAvailable: runtimeAvailable, attempts: 40)
        }
    }

    func check(_ webView: WKWebView, runtimeAvailable: Bool, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            webView.evaluateJavaScript(snapshotScript) { value, error in
                guard let json = value as? String, let data = json.data(using: .utf8),
                      let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    abort("Rendered DOM was unavailable: \(error?.localizedDescription ?? "Invalid snapshot")", caseID: self.activeRenderCaseID)
                }
                let labels = state["mermaidLabels"] as? [String] ?? []
                let imageLoaded = (state["imageLoaded"] as? Int ?? 0) > 0
                let optionalReady = state["math"] as? Int == 3 && state["chart"] as? Int == 1 &&
                    (state["highlight"] as? Int ?? 0) > 0 && labels.contains("Start") && labels.contains("Done")
                let ready = imageLoaded && (!runtimeAvailable || optionalReady)
                if !ready && attempts > 0 {
                    self.check(webView, runtimeAvailable: runtimeAvailable, attempts: attempts - 1)
                    return
                }
                // Rendering and security have independent assertions. A missing image or
                // heading must not falsely turn the HTML isolation case into a failure.
                results.expect("PV-003", imageLoaded, "Local image did not load before the render timeout")
                results.expect("PV-003", state["title"] as? String == "Preview verification", "CommonMark heading did not match")
                results.expect("PV-003", state["table"] as? Int == 1 && state["task"] as? Int == 1, "GFM table or task list was missing")
                results.expect("PV-003", state["footnote"] as? Int == 1 && state["toc"] as? Int == 2, "Footnote or TOC did not match")
                results.expect("PV-003", state["imageWidth"] as? String == "140", "MWeb image width did not match")
                results.expect("PV-003", state["article"] as? String == "mweblib://123456789", "Article link was not retained")
                results.expect("PV-004", state["noteExecuted"] as? Bool == false, "Note script executed")
                results.expect("PV-004", state["fileURLs"] as? Int == 0 && state["javascriptURLs"] as? Int == 0 && state["inlineHandlers"] as? Int == 0, "Unsafe HTML attributes remained")
                if !runtimeAvailable, resourceHandler.runtimeRoot != nil {
                    self.render(webView, runtimeAvailable: true)
                    return
                }
                if runtimeAvailable {
                    results.expect("PV-005", state["math"] as? Int == 3, "MathJax did not render three expressions")
                    results.expect("PV-005", labels.contains("Start") && labels.contains("Done"), "Mermaid graph labels were missing")
                    results.expect("PV-005", state["chart"] as? Int == 1, "ECharts canvas was missing")
                    results.expect("PV-005", (state["highlight"] as? Int ?? 0) > 0, "Prism syntax highlighting was missing")
                }
                if !runtimeAvailable {
                    results.skip("PV-005", reason: "Optional MWeb runtimes are unavailable")
                }
                self.checkScrollReset(webView)
            }
        }
    }

    func checkScrollReset(_ webView: WKWebView) {
        activeRenderCaseID = "PV-006"
        // A visible window lets WebKit execute animation-frame layout callbacks.
        // Keep this component test behind the user's foreground app.
        window.orderBack(nil)
        let script = #"""
        const base = 'mweblite://library/docs/';
        const body = Array.from({length: 100}, (_, i) => `Paragraph ${i} with enough text to scroll.\n\n`).join('');
        const a = '# Scroll A\n\n[TOC]\n\n' + body + '\n## Bottom A\n\nEnd.';
        const b = '# Scroll B\n\n' + body;
        const nextFrame = () => Promise.race([
          new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))),
          new Promise((_, reject) => setTimeout(() => reject(new Error('Animation frame timeout')), 3000))
        ]);
        window.renderMarkdown(a, base, false, true);
        await nextFrame();
        window.scrollTo({top: 600, behavior: 'instant'});
        const oldY = window.scrollY;
        window.renderMarkdown(a + '\nAn edit.', base, false, false);
        await nextFrame();
        const preserved = oldY > 0 && Math.abs(window.scrollY - oldY) < 1;
        document.querySelector('a[href="#bottom-a"]').click();
        window.renderMarkdown(b, base, false, true);
        const immediate = window.scrollY === 0;
        await nextFrame();
        const settled = window.scrollY === 0 && document.querySelector('h1').textContent === 'Scroll B';
        window.scrollTo({top: 700, behavior: 'instant'});
        window.renderMarkdown(a, base, false, true);
        window.renderMarkdown(b, base, false, true);
        await nextFrame();
        return {preserved, immediate, settled, latest: window.scrollY === 0 &&
          document.querySelector('h1').textContent === 'Scroll B'};
        """#
        webView.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
            guard case .success(let value) = result, let state = value as? [String: Bool] else {
                abort("Preview scroll check failed: \(result)", caseID: "PV-006")
            }
            results.expect("PV-006", state["preserved"] == true, "Same-document rendering reset the reading position")
            results.expect("PV-006", state["immediate"] == true, "New document did not immediately start at the top")
            results.expect("PV-006", state["settled"] == true, "Old TOC scroll moved the replacement document after layout")
            results.expect("PV-006", state["latest"] == true, "Rapid article replacement did not settle at the latest article's top")
            results.completeObservedCases()
            print("\(results.hasFailures ? "FAIL" : "PASS"): preview integration checks finished; skipped cases are not verified")
            fflush(stdout)
            exit(results.hasFailures ? 1 : 0)
        }
    }

    func timedOut() {
        abort("WebKit timed out", caseID: activeRenderCaseID)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        abort("Preview navigation failed: \(error.localizedDescription)", caseID: activeRenderCaseID)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        abort("Preview navigation setup failed: \(error.localizedDescription)")
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        abort("WebKit content process terminated", caseID: activeRenderCaseID)
    }
}
let delegate = Delegate()
view.navigationDelegate = delegate
view.load(URLRequest(url: URL(string: "mweblite://app/Preview.html")!))
DispatchQueue.main.asyncAfter(deadline: .now() + 30) { delegate.timedOut() }
app.run()
