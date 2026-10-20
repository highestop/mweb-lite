import CSQLite
import Foundation
import XCTest
import CaseReporting
@testable import MWebCore

final class SharedFixtureTests: CaseReportingTestCase {
    func test_FIXTURE_001_EndToEndFixtureLoadsWithExpectedDocumentsAndCategories() throws {
        // Given: the committed fixture, copied to a disposable library.
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Library")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mweb-fixture-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.copyItem(at: source.appendingPathComponent("docs"), to: root.appendingPathComponent("docs"))
        let database = try SQLiteDatabase(url: root.appendingPathComponent("mainlib.db"), writable: true, create: true)
        for name in ["schema.sql", "seed.sql"] {
            let sql = try String(contentsOf: source.appendingPathComponent(name), encoding: .utf8)
            XCTAssertEqual(sqlite3_exec(database.handle, sql, nil, nil, nil), SQLITE_OK, "Invalid fixture SQL: \(name)")
        }
        struct Manifest: Decodable {
            let version: Int
            let activeArticleIDs: [String]
            let trashedArticleIDs: [String]
            let uncategorizedArticleIDs: [String]
            let categoryIDs: [String]
            let categoryParents: [String: String]
            let categoryArticleIDs: [String: [String]]
            let imageDemoArticleIDs: [String]
            let media: [String]
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: source.appendingPathComponent("manifest.json")))

        // When: production library code opens the same fixture used by full-app tests.
        let library = try MWebLibrary(rootURL: root)
        let index = try library.loadIndex()
        let active = index.articles.filter { !$0.isTrashed }

        // Then: the fixture's manifest, content, and relationships remain usable.
        XCTAssertEqual(manifest.version, 3)
        XCTAssertEqual(active.count, 7)
        XCTAssertEqual(active.map(\.id).sorted(), manifest.activeArticleIDs)
        XCTAssertEqual(index.articles.filter(\.isTrashed).map(\.id).sorted(), manifest.trashedArticleIDs)
        XCTAssertEqual(active.filter { $0.categoryIDs.isEmpty }.map(\.id).sorted(), manifest.uncategorizedArticleIDs)
        XCTAssertEqual(manifest.categoryIDs, ["101", "102", "103", "104", "105"])
        XCTAssertEqual(index.categories.map(\.id).sorted(), manifest.categoryIDs)
        XCTAssertEqual(Set(manifest.categoryParents.keys), Set(manifest.categoryIDs))
        XCTAssertEqual(Set(manifest.categoryArticleIDs.keys), Set(manifest.categoryIDs))
        for category in index.categories {
            XCTAssertEqual(category.parentID ?? "0", manifest.categoryParents[category.id], "Parent for \(category.id)")
            var descendants: Set<String> = [category.id]
            var pending = [category.id]
            while let parentID = pending.popLast() {
                for child in index.categories where child.parentID == parentID {
                    if descendants.insert(child.id).inserted { pending.append(child.id) }
                }
            }
            let articleIDs = active.filter { !descendants.isDisjoint(with: $0.categoryIDs) }.map(\.id).sorted()
            XCTAssertEqual(articleIDs, manifest.categoryArticleIDs[category.id], "Articles under \(category.id)")
        }
        XCTAssertEqual(active.first?.id, "10001")
        XCTAssertEqual(active.first { $0.id == "10001" }?.categoryIDs, ["102"])
        XCTAssertEqual(active.first { $0.id == "10002" }?.categoryIDs, ["102"])
        XCTAssertEqual(active.first { $0.id == "10003" }?.categoryIDs, ["103"])
        XCTAssertEqual(manifest.imageDemoArticleIDs, ["10006", "10007", "10008"])
        for articleID in manifest.imageDemoArticleIDs {
            XCTAssertEqual(active.first { $0.id == articleID }?.categoryIDs, ["105"], "Image demo \(articleID)")
        }
        let imagePattern = try NSRegularExpression(pattern: #"!\[[^\]\n]*\]\(([^)\n]*)\)"#)
        let docsRoot = root.appendingPathComponent("docs").resolvingSymlinksInPath()
        var referencedMedia: Set<String> = []
        for article in active {
            let document = try library.loadDocument(articleID: article.id)
            XCTAssertFalse(document.content.isEmpty)
            XCTAssertTrue(document.content.hasPrefix("# \(article.title)"))
            guard manifest.imageDemoArticleIDs.contains(article.id) else { continue }
            let content = document.content as NSString
            let images = imagePattern.matches(in: document.content, range: NSRange(location: 0, length: content.length))
            XCTAssertGreaterThanOrEqual(images.count, 4, "Image demo \(article.id) needs at least four images")
            for image in images {
                let reference = content.substring(with: image.range(at: 1))
                let parts = reference.split(separator: "/", omittingEmptySubsequences: false)
                let isRelativeMedia = reference.hasPrefix("media/")
                    && reference.range(of: #"^[A-Za-z0-9_./-]+$"#, options: .regularExpression) != nil
                    && parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
                XCTAssertTrue(isRelativeMedia, "Unsafe image reference in \(article.id): \(reference)")
                guard isRelativeMedia else { continue }
                let mediaURL = docsRoot.appendingPathComponent(reference).standardizedFileURL.resolvingSymlinksInPath()
                XCTAssertTrue(mediaURL.path.hasPrefix(docsRoot.path + "/"), "Image escapes fixture: \(reference)")
                XCTAssertTrue(FileManager.default.fileExists(atPath: mediaURL.path), "Missing image: \(reference)")
                let manifestPath = "docs/" + reference
                XCTAssertTrue(manifest.media.contains(manifestPath), "Image absent from manifest: \(manifestPath)")
                referencedMedia.insert(manifestPath)
            }
        }
        let imageDemoMedia = Set(manifest.media.filter { $0.hasPrefix("docs/media/10006/") })
        XCTAssertEqual(imageDemoMedia, Set([
            "mountain.svg", "panorama.svg", "portrait.svg", "square.png", "detail.jpg", "transparent.png"
        ].map { "docs/media/10006/" + $0 }))
        XCTAssertTrue(imageDemoMedia.isSubset(of: referencedMedia), "Every image demo media file must be referenced")
        for path in manifest.media {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".mweb-lite").path))
    }
}
