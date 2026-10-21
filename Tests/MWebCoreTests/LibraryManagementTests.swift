import CSQLite
import XCTest
import CaseReporting
@testable import MWebCore

final class LibraryManagementTests: CaseReportingTestCase {
    private var root: URL!
    private var db: SQLiteDatabase!
    private var library: MWebLibrary!

    override func setUpWithError() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Fixtures/Library")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Management-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source.appendingPathComponent("docs"), to: root.appendingPathComponent("docs"))
        db = try SQLiteDatabase(url: root.appendingPathComponent("mainlib.db"), writable: true, create: true)
        for name in ["schema.sql", "seed.sql"] {
            let sql = try String(contentsOf: source.appendingPathComponent(name), encoding: .utf8)
            XCTAssertEqual(sqlite3_exec(db.handle, sql, nil, nil, nil), SQLITE_OK)
        }
        library = try MWebLibrary(rootURL: root)
    }

    override func tearDownWithError() throws {
        library = nil
        db = nil
        if let root { try FileManager.default.removeItem(at: root) }
    }

    func test_CAT_001_CreateAndRenamePreserveDefaultsAndRelationships() throws {
        try db.execute("ALTER TABLE cat ADD COLUMN extra TEXT DEFAULT 'preserved'")
        let before = try snapshot("article")
        let instant = Date(timeIntervalSince1970: 1701000000)
        let parent = try library.createCategory(name: "  新分类 😀  ", parentID: nil, now: instant)
        let child = try library.createCategory(name: "Child", parentID: parent, now: instant)
        XCTAssertNotEqual(parent, child)
        try library.renameCategory(id: parent, name: "Renamed '分类'")
        let row = try XCTUnwrap(db.query("SELECT * FROM cat WHERE uuid = ?", bindings: [.text(parent)]).first)
        XCTAssertEqual(row["name"], .text("Renamed '分类'"))
        XCTAssertEqual(row["pid"], .integer(0))
        XCTAssertEqual(row["extra"], .text("preserved"))
        XCTAssertEqual(row["sort"], .integer(3))
        XCTAssertEqual(try library.loadIndex().categories.first { $0.id == child }?.parentID, parent)
        XCTAssertEqual(try snapshot("article"), before)
        XCTAssertEqual(try db.query("SELECT * FROM cat_article WHERE rid = ?", bindings: [.text(parent)]).count, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(".mweb-lite/backups").path))
    }

    func test_CAT_002_DeleteLeafDetachesAllStatesAndPreservesOtherMemberships() throws {
        try db.execute("INSERT INTO cat_article VALUES (103, 10001)")
        let documents = try fileSnapshot()
        let articles = try snapshot("article")
        let tags = try snapshot("tag_article")
        try library.deleteCategory(id: "103")
        XCTAssertTrue(try db.query("SELECT * FROM cat_article WHERE rid = 103").isEmpty)
        XCTAssertTrue(try db.query("SELECT * FROM cat WHERE uuid = 103").isEmpty)
        XCTAssertEqual(try library.loadIndex().articles.first { $0.id == "10001" }?.categoryIDs, ["102"])
        XCTAssertEqual(try library.loadIndex().articles.first { $0.id == "10003" }?.categoryIDs, [])
        XCTAssertEqual(try snapshot("article"), articles)
        XCTAssertEqual(try snapshot("tag_article"), tags)
        XCTAssertEqual(try fileSnapshot(), documents)
    }

    func test_CAT_003_DeleteParentPromotesChildrenAndKeepsTheirMemberships() throws {
        try db.execute("INSERT INTO cat_article VALUES (101, 10001)")
        let documents = try fileSnapshot()
        try library.deleteCategory(id: "101")
        let index = try library.loadIndex()
        XCTAssertNil(index.categories.first { $0.id == "101" })
        for id in ["102", "103"] {
            XCTAssertNil(try XCTUnwrap(index.categories.first { $0.id == id }).parentID)
        }
        XCTAssertEqual(index.articles.first { $0.id == "10001" }?.categoryIDs, ["102"])
        XCTAssertEqual(index.articles.first { $0.id == "10003" }?.categoryIDs, ["103"])
        XCTAssertEqual(index.articles.filter { !$0.isTrashed }.count, 7)
        XCTAssertEqual(try fileSnapshot(), documents)
    }

    func test_CAT_004_InvalidTargetsAndSQLFailuresLeaveNoPartialChanges() throws {
        let before = try snapshot("cat")
        let links = try snapshot("cat_article")
        XCTAssertThrowsError(try library.createCategory(name: " \n "))
        XCTAssertThrowsError(try library.createCategory(name: "Bad\u{0}name"))
        XCTAssertThrowsError(try library.createCategory(name: "Child", parentID: "missing"))
        XCTAssertThrowsError(try library.renameCategory(id: "missing", name: "Name"))
        XCTAssertThrowsError(try library.renameCategory(id: "102", name: " "))
        XCTAssertThrowsError(try library.deleteCategory(id: "missing"))
        try db.execute("CREATE TRIGGER reject_delete BEFORE DELETE ON cat BEGIN SELECT RAISE(ABORT, 'injected failure'); END")
        XCTAssertThrowsError(try library.deleteCategory(id: "101"))
        XCTAssertEqual(try snapshot("cat"), before)
        XCTAssertEqual(try snapshot("cat_article"), links)
        try db.execute("CREATE TRIGGER reject_rename BEFORE UPDATE OF name ON cat BEGIN SELECT RAISE(ABORT, 'injected failure'); END")
        XCTAssertThrowsError(try library.renameCategory(id: "102", name: "Changed"))
        try db.execute("CREATE TRIGGER reject_create BEFORE INSERT ON cat BEGIN SELECT RAISE(ABORT, 'injected failure'); END")
        XCTAssertThrowsError(try library.createCategory(name: "New"))
        XCTAssertEqual(try snapshot("cat"), before)
    }

    func test_TRASH_001_TrashChangesOnlyStateAndKeepsBytesAndRelationships() throws {
        let files = try fileSnapshot()
        let before = try XCTUnwrap(db.query("SELECT * FROM article WHERE uuid = 10006").first)
        let links = try snapshot("cat_article")
        let tags = try snapshot("tag_article")
        try library.trashDocument(articleID: "10006")
        var after = try XCTUnwrap(db.query("SELECT * FROM article WHERE uuid = 10006").first)
        XCTAssertEqual(after["state"], .integer(0))
        after["state"] = before["state"]
        XCTAssertEqual(after, before)
        XCTAssertEqual(try fileSnapshot(), files)
        XCTAssertEqual(try snapshot("cat_article"), links)
        XCTAssertEqual(try snapshot("tag_article"), tags)
        XCTAssertTrue(try XCTUnwrap(library.loadIndex().articles.first { $0.id == "10006" }).isTrashed)
        XCTAssertThrowsError(try library.loadDocument(articleID: "10006"))
    }

    func test_TRASH_002_MissingTrashedAndFailedWritesPreserveDatabase() throws {
        let before = try snapshot("article")
        let files = try fileSnapshot()
        XCTAssertThrowsError(try library.trashDocument(articleID: "missing"))
        XCTAssertThrowsError(try library.trashDocument(articleID: "10005"))
        try db.execute("CREATE TRIGGER reject_trash BEFORE UPDATE OF state ON article BEGIN SELECT RAISE(ABORT, 'injected failure'); END")
        XCTAssertThrowsError(try library.trashDocument(articleID: "10001"))
        XCTAssertEqual(try snapshot("article"), before)
        XCTAssertEqual(try fileSnapshot(), files)
    }

    private func snapshot(_ table: String) throws -> [SQLiteRow] {
        try db.query("SELECT * FROM \(table) ORDER BY rowid")
    }

    private func fileSnapshot() throws -> [String: Data] {
        let docs = root.appendingPathComponent("docs")
        let urls = FileManager.default.enumerator(at: docs, includingPropertiesForKeys: [.isRegularFileKey])!
        var result: [String: Data] = [:]
        for case let url as URL in urls where try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
            result[url.path] = try Data(contentsOf: url)
        }
        return result
    }
}
