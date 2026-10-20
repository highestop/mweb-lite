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
            let activeArticleIDs: [String]
            let trashedArticleIDs: [String]
            let uncategorizedArticleIDs: [String]
            let media: [String]
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: source.appendingPathComponent("manifest.json")))

        // When: production library code opens the same fixture used by full-app tests.
        let library = try MWebLibrary(rootURL: root)
        let index = try library.loadIndex()
        let active = index.articles.filter { !$0.isTrashed }

        // Then: the fixture's manifest, content, and relationships remain usable.
        XCTAssertEqual(active.map(\.id).sorted(), manifest.activeArticleIDs)
        XCTAssertEqual(index.articles.filter(\.isTrashed).map(\.id).sorted(), manifest.trashedArticleIDs)
        XCTAssertEqual(active.filter { $0.categoryIDs.isEmpty }.map(\.id).sorted(), manifest.uncategorizedArticleIDs)
        XCTAssertEqual(Set(index.categories.map(\.id)), Set(["101", "102", "103", "104"]))
        XCTAssertEqual(index.categories.first { $0.id == "102" }?.parentID, "101")
        XCTAssertEqual(index.categories.first { $0.id == "103" }?.parentID, "101")
        XCTAssertEqual(active.first?.id, "10001")
        XCTAssertEqual(active.first { $0.id == "10001" }?.categoryIDs, ["102"])
        XCTAssertEqual(active.first { $0.id == "10002" }?.categoryIDs, ["102"])
        XCTAssertEqual(active.first { $0.id == "10003" }?.categoryIDs, ["103"])
        for article in active {
            let document = try library.loadDocument(articleID: article.id)
            XCTAssertFalse(document.content.isEmpty)
            XCTAssertTrue(document.content.hasPrefix("# \(article.title)"))
        }
        for path in manifest.media {
            XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(path).path))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".mweb-lite").path))
    }
}
