import CSQLite
import Foundation
import XCTest
import CaseReporting
@testable import MWebCore

final class MarkdownImageReferencesTests: CaseReportingTestCase {
    func test_MEDIA_001_ImageReferencesFollowMarkdownOrderAndIgnoreCode() {
        let markdown = #"""
        # Images

        ```markdown
        ![not rendered](media/fenced.png)
        <img src="media/fenced-html.png">
        ```
        ~~~
        ![not rendered either](media/tilde.png)
        ~~~
        `![inline code](media/inline.png)` and `` `![more code](media/two-backticks.png)` ``
        <!-- ![comment](media/comment.png)
        <img src="media/comment-html.png"> -->
        \![escaped image](media/escaped.png)

        ![嵌套 [说明] -w320](media/山(1).png "A title with )")
        ![reference -w240][ Picture   One ]
        <img alt="HTML picture src='media/not-the-source.png'" src='media/html.png?x=1&amp;y=2' width="200">
        ![space](<media/space name.png>)
        ![fifth](media/fifth.png)

        [picture one]: media/reference.png "Title ![not an image](media/title.png)"
        """#
        XCTAssertEqual(MarkdownImageReferences.firstImages(in: markdown), [
            "media/山(1).png", "media/reference.png",
            "media/html.png?x=1&y=2", "media/space name.png"
        ])
        XCTAssertEqual(MarkdownImageReferences.firstImages(in: markdown, limit: 2), [
            "media/山(1).png", "media/reference.png"
        ])
        XCTAssertEqual(MarkdownImageReferences.firstImages(in: markdown, limit: 99).count, 4)
        XCTAssertTrue(MarkdownImageReferences.firstImages(in: markdown, limit: 0).isEmpty)

        let references = #"""
        ![repeated][] ![REPEATED] ![escaped](media/a\(b\).png) <IMG SRC=media/unquoted.png>
        [repeated]: media/repeated.png
        [repeated]: media/ignored-duplicate-definition.png
        """#
        XCTAssertEqual(MarkdownImageReferences.firstImages(in: references), [
            "media/repeated.png", "media/repeated.png", "media/a(b).png", "media/unquoted.png"
        ])
        XCTAssertEqual(MarkdownImageReferences.firstImages(in: "![remote](https://example.invalid/a.png)"),
                       ["https://example.invalid/a.png"], "Extraction must not perform network or path resolution")
        let nestedCodeAndComments = """
        <!--
        ```
        ![inside a comment](media/comment-fence.png)
        -->
        ![visible](media/visible.png)
        > ~~~
        > ![inside quoted code](media/quoted-code.png)
        > ~~~
        `<!--` ![also visible](media/visible-two.png)
        """
        XCTAssertEqual(MarkdownImageReferences.firstImages(in: nestedCodeAndComments),
                       ["media/visible.png", "media/visible-two.png"])
        let indentedCode = "    ![code](media/indented.png)\n    <img src='media/indented-html.png'>\n\n"
            + "![visible](media/visible.png)\n\n- Gallery\n\n    ![list image](media/list.png)\n\n"
            + "Outside the list.\n\n\t![tabbed code](media/tabbed.png)\n\n![last](media/last.png)"
        XCTAssertEqual(MarkdownImageReferences.firstImages(in: indentedCode),
                       ["media/visible.png", "media/list.png", "media/last.png"])
        XCTAssertTrue(MarkdownImageReferences.firstImages(in: "~~~\n![unclosed code](media/code.png)").isEmpty)
        XCTAssertTrue(MarkdownImageReferences.firstImages(in: "![missing][unknown]\n![unfinished](media/a.png").isEmpty)
        XCTAssertTrue(MarkdownImageReferences.firstImages(in: "<!-- ![hidden](media/a.png)").isEmpty)
    }

    func test_MEDIA_002_IndexReadsLateImagesAndUpdatesSavedArticleReferences() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Library")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mweb-media-index-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: fixture.appendingPathComponent("docs"), to: root.appendingPathComponent("docs"))
        let databaseURL = root.appendingPathComponent("mainlib.db")
        let database = try SQLiteDatabase(url: databaseURL, writable: true, create: true)
        for name in ["schema.sql", "seed.sql"] {
            let sql = try String(contentsOf: fixture.appendingPathComponent(name), encoding: .utf8)
            XCTAssertEqual(sqlite3_exec(database.handle, sql, nil, nil, nil), SQLITE_OK)
        }
        let longURL = root.appendingPathComponent("docs/10004.md")
        let longText = "# Long image note\n\nOriginal **summary**.\n\n"
            + String(repeating: "A paragraph without media.\n\n", count: 3_000)
            + "![Late image -w320][late]\n\n[late]: media/10006/detail.jpg\n"
        XCTAssertGreaterThan(longText.utf8.count, 65_536)
        try Data(longText.utf8).write(to: longURL)
        let databaseBefore = try Data(contentsOf: databaseURL)
        let documentBefore = try Data(contentsOf: longURL)
        let library = try MWebLibrary(rootURL: root)

        let index = try library.loadIndex()

        let prefix = "media/10006/"
        for identifier in ["10006", "10007"] {
            XCTAssertEqual(index.articles.first { $0.id == identifier }?.imageReferences,
                           ["mountain.svg", "panorama.svg", "portrait.svg", "square.png"].map { prefix + $0 })
        }
        XCTAssertEqual(index.articles.first { $0.id == "10008" }?.imageReferences,
                       ["mountain.svg", "panorama.svg", "detail.jpg", "transparent.png"].map { prefix + $0 })
        let article = try XCTUnwrap(index.articles.first { $0.id == "10004" })
        XCTAssertEqual(article.imageReferences, ["media/10006/detail.jpg"])
        let originalSummary = MWebLibrary.summary(String(decoding: documentBefore.prefix(4_096), as: UTF8.self))
        XCTAssertEqual(article.title, originalSummary.title)
        XCTAssertEqual(article.excerpt, originalSummary.excerpt)
        XCTAssertEqual(try Data(contentsOf: databaseURL), databaseBefore)
        XCTAssertEqual(try Data(contentsOf: longURL), documentBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".mweb-lite").path))

        let original = try library.loadDocument(articleID: article.id)
        let saved = try library.saveDocument(original, content: """
        # Updated image note

        ![plant](media/10006/transparent.png)
        ![mountain](media/10006/mountain.svg)
        """)
        let updated = article.updating(document: saved)
        XCTAssertEqual(updated.imageReferences, ["media/10006/transparent.png", "media/10006/mountain.svg"])
        XCTAssertEqual(updated.categoryIDs, article.categoryIDs)
        XCTAssertEqual(updated.createdAt, article.createdAt)
        XCTAssertEqual(updated.sort, article.sort)
        XCTAssertEqual(try library.loadIndex().articles.first { $0.id == article.id }?.imageReferences,
                       updated.imageReferences)
        let another = try XCTUnwrap(index.articles.first { $0.id == "10006" })
        XCTAssertEqual(another.updating(document: saved), another)

        let withoutImages = try library.saveDocument(saved, content: "# Updated image note\n\nNo images remain.")
        XCTAssertTrue(updated.updating(document: withoutImages).imageReferences.isEmpty)
    }
}
