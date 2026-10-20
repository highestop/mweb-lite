import Foundation
import XCTest
import CaseReporting
@testable import MWebCore

final class MWebDocumentCreationTests: CaseReportingTestCase {
    private var root: URL!
    private var database: SQLiteDatabase!
    private let now = Date(timeIntervalSince1970: 1_792_400_123.4567)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mweb-create-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
        database = try SQLiteDatabase(url: root.appendingPathComponent("mainlib.db"), writable: true, create: true)
        try database.execute("CREATE TABLE article (id INTEGER PRIMARY KEY, uuid INTEGER UNIQUE, type INTEGER DEFAULT 0, state INTEGER, docName TEXT, dateAdd INTEGER, dateModif INTEGER, dateArt INTEGER, sort INTEGER, isTop INTEGER, unknownField TEXT DEFAULT 'preserved-default')")
        try database.execute("CREATE TABLE cat (id INTEGER PRIMARY KEY, uuid INTEGER UNIQUE, pid INTEGER, name TEXT)")
        try database.execute("CREATE TABLE cat_article (id INTEGER PRIMARY KEY, rid INTEGER, aid INTEGER)")
        try database.execute("CREATE TABLE custom_table (key TEXT, value BLOB)")
        try database.execute("INSERT INTO cat VALUES (1, 100, 0, 'Parent'), (2, 200, 100, 'Child')")
        try database.execute("INSERT INTO custom_table VALUES ('keep', X'00ABFF')")
        try database.execute("INSERT INTO article (uuid, state, dateAdd, dateModif, unknownField) VALUES (111, 1, 1600000000, 1700000000, 'untouched')")
        try Data("# Existing\n".utf8).write(to: root.appendingPathComponent("docs/111.md"))
    }

    override func tearDownWithError() throws {
        database = nil
        if let root { try FileManager.default.removeItem(at: root) }
    }

    func test_CREATE_001_CreateUsesSelectedCategoryUUIDAndReopensAsEditableDocument() throws {
        let originalRows = try database.query("SELECT * FROM article")
        let library = try MWebLibrary(rootURL: root)
        let created = try library.createDocument(categoryID: "200", now: now)
        XCTAssertEqual(created.articleID, "17924001234567")
        XCTAssertEqual(created.title, "未命名文章")
        XCTAssertEqual(created.content, "# 未命名文章\n\n")
        XCTAssertEqual(try Data(contentsOf: created.fileURL), Data(created.content.utf8))
        let row = try XCTUnwrap(database.query("SELECT * FROM article WHERE uuid = ?", bindings: [.text(created.articleID)]).first)
        XCTAssertEqual(row["uuid"], .integer(17_924_001_234_567))
        XCTAssertEqual(row["state"], .integer(1))
        XCTAssertEqual(row["type"], .integer(0))
        XCTAssertEqual(row["docName"], .text(""))
        XCTAssertEqual(row["dateAdd"], .integer(1_792_400_123))
        XCTAssertEqual(row["dateModif"], row["dateAdd"])
        XCTAssertEqual(row["dateArt"], row["dateAdd"])
        XCTAssertEqual(row["sort"], .integer(0))
        XCTAssertEqual(row["isTop"], .integer(0))
        XCTAssertEqual(row["unknownField"], .text("preserved-default"))
        let relationship = try XCTUnwrap(database.query("SELECT rid, aid FROM cat_article").first)
        XCTAssertEqual(relationship, ["rid": .integer(200), "aid": .integer(17_924_001_234_567)])
        XCTAssertEqual(try database.query("SELECT * FROM article WHERE uuid = 111"), originalRows)
        XCTAssertEqual(try database.query("SELECT value FROM custom_table").first?["value"], .blob(Data([0, 0xAB, 0xFF])))

        let backup = try XCTUnwrap(created.lastBackupURL)
        let backupDatabase = try SQLiteDatabase(url: backup.appendingPathComponent("mainlib.db"))
        XCTAssertEqual(try backupDatabase.query("SELECT * FROM article"), originalRows)
        XCTAssertTrue(try backupDatabase.query("SELECT * FROM cat_article").isEmpty)
        let reopened = try MWebLibrary(rootURL: root)
        let indexed = try XCTUnwrap(reopened.loadIndex().articles.first { $0.id == created.articleID })
        XCTAssertEqual(indexed.categoryIDs, ["200"])
        XCTAssertFalse(indexed.isTrashed)
        XCTAssertTrue(indexed.isAvailable)
        let loaded = try reopened.loadDocument(articleID: created.articleID)
        let saved = try reopened.saveDocument(loaded, content: "# Edited new document\n")
        XCTAssertEqual(saved.title, "Edited new document")
        XCTAssertEqual(try reopened.loadDocument(articleID: created.articleID).content, saved.content)
    }

    func test_CREATE_002_CreateWithoutCategoryIsUncategorized() throws {
        let library = try MWebLibrary(rootURL: root)
        let created = try library.createDocument(categoryID: nil, now: now)
        XCTAssertTrue(try database.query("SELECT * FROM cat_article").isEmpty)
        XCTAssertEqual(try XCTUnwrap(library.loadIndex().articles.first { $0.id == created.articleID }).categoryIDs, [])
    }

    func test_CREATE_003_MissingCategoryRefusesCreationBeforeBackupOrFileChanges() throws {
        let before = try database.query("SELECT * FROM article")
        let library = try MWebLibrary(rootURL: root)
        for categoryID in ["999", "200 OR 1=1", "../outside"] {
            XCTAssertThrowsError(try library.createDocument(categoryID: categoryID, now: now)) { error in
                guard case MWebLibraryError.missingCategory = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
        XCTAssertEqual(try database.query("SELECT * FROM article"), before)
        XCTAssertEqual(try documentNames(), ["111.md"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".mweb-lite").path))
    }

    func test_CREATE_004_IdentifierCollisionPreservesExistingArticleAndFile() throws {
        let library = try MWebLibrary(rootURL: root)
        let created = try library.createDocument(categoryID: "200", now: now)
        let rows = try database.query("SELECT * FROM article")
        XCTAssertThrowsError(try library.createDocument(categoryID: "100", now: now)) { error in
            guard case MWebLibraryError.creationConflict = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try database.query("SELECT * FROM article"), rows)
        XCTAssertEqual(try Data(contentsOf: created.fileURL), Data(created.content.utf8))
        XCTAssertEqual(try database.query("SELECT rid FROM cat_article").map { $0["rid"] }, [.integer(200)])
    }

    func test_CREATE_005_UnindexedFileAndMediaCollisionsAreNotOverwritten() throws {
        let library = try MWebLibrary(rootURL: root)
        let file = root.appendingPathComponent("docs/17924001234567.md")
        try Data("# Unindexed content\n".utf8).write(to: file)
        XCTAssertThrowsError(try library.createDocument(categoryID: nil, now: now))
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "# Unindexed content\n")
        try FileManager.default.removeItem(at: file)
        let media = root.appendingPathComponent("docs/media/17924001234567")
        try FileManager.default.createDirectory(at: media, withIntermediateDirectories: true)
        XCTAssertThrowsError(try library.createDocument(categoryID: nil, now: now))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try database.query("SELECT * FROM article").count, 1)
    }

    func test_CREATE_006_FailedRelationshipInsertRollsBackArticleWithoutCreatingFile() throws {
        try database.execute("CREATE TRIGGER reject_link BEFORE INSERT ON cat_article BEGIN SELECT RAISE(ABORT, 'reject relationship'); END")
        let before = try database.query("SELECT * FROM article")
        XCTAssertThrowsError(try MWebLibrary(rootURL: root).createDocument(categoryID: "200", now: now))
        XCTAssertEqual(try database.query("SELECT * FROM article"), before)
        XCTAssertTrue(try database.query("SELECT * FROM cat_article").isEmpty)
        XCTAssertEqual(try documentNames(), ["111.md"])
    }

    func test_CREATE_007_FailedCommitRemovesCreatedMarkdownAndRollsBackAllRows() throws {
        // This constraint fails only at COMMIT, after the new Markdown file exists.
        try database.execute("CREATE TABLE referenced (id INTEGER PRIMARY KEY)")
        try database.execute("CREATE TABLE creation_audit (article_id INTEGER REFERENCES referenced(id) DEFERRABLE INITIALLY DEFERRED)")
        try database.execute("CREATE TRIGGER reject_creation_commit AFTER INSERT ON article BEGIN INSERT INTO creation_audit VALUES (999); END")
        let before = try database.query("SELECT * FROM article")
        XCTAssertThrowsError(try MWebLibrary(rootURL: root).createDocument(categoryID: "200", now: now)) { error in
            guard case MWebLibraryError.database(let detail) = error else { return XCTFail("Unexpected error: \(error)") }
            XCTAssertTrue(detail.contains("FOREIGN KEY constraint failed"))
        }
        XCTAssertEqual(try database.query("SELECT * FROM article"), before)
        XCTAssertTrue(try database.query("SELECT * FROM cat_article").isEmpty)
        XCTAssertTrue(try database.query("SELECT * FROM creation_audit").isEmpty)
        XCTAssertEqual(try documentNames(), ["111.md"])
    }

    func test_CREATE_008_SymlinkDestinationCannotCreateFileOutsideLibrary() throws {
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent("mweb-create-outside-\(UUID().uuidString).md")
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("docs/17924001234567.md"), withDestinationURL: outside)
        XCTAssertThrowsError(try MWebLibrary(rootURL: root).createDocument(categoryID: nil, now: now))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertEqual(try database.query("SELECT * FROM article").count, 1)
    }

    private func documentNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("docs").path).sorted()
    }
}
