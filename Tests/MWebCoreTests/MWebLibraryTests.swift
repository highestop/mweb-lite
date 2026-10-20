import Foundation
import XCTest
import CaseReporting
@testable import MWebCore

final class MWebLibraryTests: CaseReportingTestCase {
    private var root: URL!
    private var database: SQLiteDatabase!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("mweb-lite-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
        database = try SQLiteDatabase(url: root.appendingPathComponent("mainlib.db"), writable: true, create: true)
        try database.execute("CREATE TABLE cat (id INTEGER PRIMARY KEY, uuid INTEGER, pid INTEGER, name TEXT, sort INTEGER, catType INTEGER, sortType INTEGER)")
        try database.execute("CREATE TABLE article (id INTEGER PRIMARY KEY, uuid INTEGER UNIQUE, state INTEGER, dateModif INTEGER, dateAdd INTEGER, docName TEXT, isTop INTEGER, sort INTEGER, unknownColumn BLOB)")
        try database.execute("CREATE TABLE cat_article (id INTEGER PRIMARY KEY, rid INTEGER, aid INTEGER)")
        try database.execute("CREATE TABLE tag_article (rid INTEGER, aid INTEGER)")
        try database.execute("CREATE TABLE settings (key TEXT, val TEXT)")
        try database.execute("INSERT INTO cat VALUES (1, 100, 0, 'Parent', 2, 12, 0), (2, 200, 100, 'Child', 1, 13, 0)")
        try database.execute("INSERT INTO article VALUES (1, 10001, 1, 1700000000, 1600000000, 'web-slug', 0, 3, X'00FEA9'), (2, 10002, 1, 1700000001, 1600000001, '', 0, 2, NULL), (3, 10003, 0, 1700000002, 1600000002, '', 0, 1, NULL)")
        try database.execute("INSERT INTO cat_article VALUES (1, 100, 10001), (2, 200, 10001), (3, 200, 10002), (4, 200, 10001)")
        try database.execute("INSERT INTO tag_article VALUES (777, 10001)")
        try database.execute("INSERT INTO settings VALUES ('unknown', 'preserve')")
        try write("# First title\n\nOriginal **body**.\n", articleID: "10001")
        try write("# 第二篇\n\n内容\n", articleID: "10002")
        try write("# Trashed\n", articleID: "10003")
    }

    override func tearDownWithError() throws {
        database = nil
        if let root { try FileManager.default.removeItem(at: root) }
    }

    func test_LIB_001_IndexUsesUUIDRelationshipsAndContentTitles() throws {
        let index = try MWebLibrary(rootURL: root).loadIndex()
        XCTAssertEqual(index.categories.map(\.id), ["200", "100"])
        XCTAssertEqual(index.categories.first?.parentID, "100")
        XCTAssertNil(index.categories.last?.parentID)
        let first = try XCTUnwrap(index.articles.first { $0.id == "10001" })
        XCTAssertEqual(first.title, "First title")
        XCTAssertEqual(first.excerpt, "Original body.")
        XCTAssertEqual(first.categoryIDs, ["100", "200"])
        XCTAssertEqual(first.modifiedAt?.timeIntervalSince1970, 1700000000)
        XCTAssertTrue(first.isAvailable)
        XCTAssertTrue(try XCTUnwrap(index.articles.first { $0.id == "10003" }).isTrashed)
        XCTAssertEqual(index.articles.filter { !$0.isTrashed }.map(\.id), ["10002", "10001"])
    }

    func test_LIB_002_SavePreservesUnknownMetadataAndBacksUpOriginal() throws {
        let library = try MWebLibrary(rootURL: root)
        let article = try XCTUnwrap(library.loadIndex().articles.first { $0.id == "10001" })
        let original = try library.loadDocument(articleID: "10001")
        let before = try row("10001")
        let saved = try library.saveDocument(original, content: "# Changed\n\n新内容\n")
        XCTAssertEqual(try String(contentsOf: saved.fileURL, encoding: .utf8), saved.content)
        XCTAssertEqual(saved.title, "Changed")
        let updated = article.updating(document: saved)
        XCTAssertEqual(updated.title, "Changed")
        XCTAssertEqual(updated.excerpt, "新内容")
        XCTAssertEqual(updated.modifiedAt, saved.modifiedAt)
        XCTAssertEqual(updated.categoryIDs, article.categoryIDs)
        XCTAssertEqual(updated.createdAt, article.createdAt)
        XCTAssertEqual(updated.isPinned, article.isPinned)
        XCTAssertEqual(updated.sort, article.sort)
        var after = try row("10001")
        XCTAssertGreaterThan(try XCTUnwrap(after["dateModif"]?.integer), 1700000000)
        XCTAssertLessThan(try XCTUnwrap(after["dateModif"]?.integer), 100000000000)
        after["dateModif"] = before["dateModif"]
        XCTAssertEqual(after, before)
        XCTAssertEqual(try database.query("SELECT * FROM tag_article").count, 1)
        XCTAssertEqual(try database.query("SELECT * FROM cat_article").count, 4)
        XCTAssertEqual(try database.query("SELECT val FROM settings").first?["val"], .text("preserve"))
        let backup = try XCTUnwrap(saved.lastBackupURL)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("10001.md")), original.originalData)
        let backupDB = try SQLiteDatabase(url: backup.appendingPathComponent("mainlib.db"))
        XCTAssertEqual(try backupDB.query("SELECT * FROM article WHERE uuid = 10001").first, before)
    }

    func test_LIB_003_NoOpSaveDoesNotTouchFileOrCreateBackup() throws {
        let library = try MWebLibrary(rootURL: root)
        let document = try library.loadDocument(articleID: "10001")
        let before = try row("10001")
        let saved = try library.saveDocument(document, content: document.content)
        XCTAssertNil(saved.lastBackupURL)
        XCTAssertEqual(try row("10001"), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(".mweb-lite").path))
    }

    func test_LIB_004_ExternalFileChangeRefusesSaveWithoutOverwriting() throws {
        let library = try MWebLibrary(rootURL: root)
        let original = try library.loadDocument(articleID: "10001")
        try write("# External edit\n", articleID: "10001")
        XCTAssertThrowsError(try library.saveDocument(original, content: "# My edit\n")) { error in
            guard case MWebLibraryError.conflict = error else { return XCTFail("Unexpected error: \(error)") }
        }
        XCTAssertEqual(try String(contentsOf: original.fileURL, encoding: .utf8), "# External edit\n")
        XCTAssertEqual(try row("10001")["dateModif"], .integer(1700000000))
    }

    func test_LIB_005_ExternalMetadataChangeRefusesSave() throws {
        let library = try MWebLibrary(rootURL: root)
        let original = try library.loadDocument(articleID: "10001")
        try database.execute("UPDATE article SET unknownColumn = X'AAAA' WHERE uuid = 10001")
        XCTAssertThrowsError(try library.saveDocument(original, content: "# Changed\n"))
        XCTAssertEqual(try Data(contentsOf: original.fileURL), original.originalData)
        XCTAssertEqual(try row("10001")["unknownColumn"], .blob(Data([0xAA, 0xAA])))
    }

    func test_LIB_006_FailedCommitRestoresMarkdownAndRollsBackMetadata() throws {
        // The deferred constraint fails at COMMIT, after the Markdown replacement.
        try database.execute("CREATE TABLE referenced (id INTEGER PRIMARY KEY)")
        try database.execute("CREATE TABLE save_audit (article_id INTEGER REFERENCES referenced(id) DEFERRABLE INITIALLY DEFERRED)")
        try database.execute("CREATE TRIGGER reject_commit AFTER UPDATE OF dateModif ON article BEGIN INSERT INTO save_audit VALUES (999); END")
        let library = try MWebLibrary(rootURL: root)
        let original = try library.loadDocument(articleID: "10001")
        let before = try row("10001")
        XCTAssertThrowsError(try library.saveDocument(original, content: "# Must be rolled back\n")) { error in
            guard case MWebLibraryError.database(let detail) = error else {
                return XCTFail("Expected a deferred database constraint error, got \(error)")
            }
            XCTAssertTrue(detail.contains("FOREIGN KEY constraint failed"))
        }
        XCTAssertEqual(try Data(contentsOf: original.fileURL), original.originalData)
        XCTAssertEqual(try row("10001"), before)
        XCTAssertTrue(try database.query("SELECT * FROM save_audit").isEmpty)
    }

    func test_LIB_007_BackupsKeepOneDatabaseAndBoundedMarkdownHistory() throws {
        let library = try MWebLibrary(rootURL: root)
        var document = try library.loadDocument(articleID: "10001")
        let originalData = document.originalData
        var backupURL: URL?
        for number in 0..<23 {
            document = try library.saveDocument(document, content: "# Edit \(number)\n")
            if let backupURL { XCTAssertEqual(document.lastBackupURL, backupURL) }
            backupURL = document.lastBackupURL
        }
        let backup = try XCTUnwrap(backupURL)
        XCTAssertEqual(try Data(contentsOf: backup.appendingPathComponent("10001.md")), originalData)
        let snapshots = try FileManager.default.contentsOfDirectory(at: backup.appendingPathComponent("10001"), includingPropertiesForKeys: nil)
        XCTAssertEqual(snapshots.count, 20)
        let sessions = try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent(".mweb-lite/backups"), includingPropertiesForKeys: nil)
        XCTAssertEqual(sessions.count, 1)
    }

    func test_LIB_008_OnlineBackupIncludesCommittedWALChanges() throws {
        try database.execute("PRAGMA journal_mode = WAL")
        try database.execute("UPDATE article SET docName = 'committed-in-wal' WHERE uuid = 10001")
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("mainlib.db-wal").path))
        let library = try MWebLibrary(rootURL: root)
        let original = try library.loadDocument(articleID: "10001")
        let saved = try library.saveDocument(original, content: "# WAL save\n")
        let backup = try XCTUnwrap(saved.lastBackupURL)
        let backupDB = try SQLiteDatabase(url: backup.appendingPathComponent("mainlib.db"))
        let metadata = try XCTUnwrap(backupDB.query("SELECT * FROM article WHERE uuid = 10001").first)
        XCTAssertEqual(metadata["docName"], .text("committed-in-wal"))
        XCTAssertEqual(metadata["dateModif"], .integer(1700000000))
        XCTAssertEqual(try String(contentsOf: saved.fileURL, encoding: .utf8), "# WAL save\n")
    }

    func test_LIB_009_BackupsRemainPrivateAndOriginalPermissionsArePreserved() throws {
        let file = root.appendingPathComponent("docs/10001.md")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let library = try MWebLibrary(rootURL: root)
        let original = try library.loadDocument(articleID: "10001")
        let saved = try library.saveDocument(original, content: "# Private edit\n")
        let backup = try XCTUnwrap(saved.lastBackupURL)
        XCTAssertEqual(try permissions(backup), 0o700)
        XCTAssertEqual(try permissions(backup.appendingPathComponent("mainlib.db")), 0o600)
        XCTAssertEqual(try permissions(backup.appendingPathComponent("10001.md")), 0o600)
        XCTAssertEqual(try permissions(file), 0o600)
        let snapshots = try FileManager.default.contentsOfDirectory(at: backup.appendingPathComponent("10001"), includingPropertiesForKeys: nil)
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(try permissions(XCTUnwrap(snapshots.first)), 0o600)
    }

    func test_LIB_010_RefusesTrashedMissingAndInvalidUTF8Documents() throws {
        let library = try MWebLibrary(rootURL: root)
        XCTAssertThrowsError(try library.loadDocument(articleID: "10003"))
        XCTAssertThrowsError(try library.loadDocument(articleID: "99999"))
        let file = root.appendingPathComponent("docs/10001.md")
        try Data([0xFF, 0xFE]).write(to: file)
        XCTAssertThrowsError(try library.loadDocument(articleID: "10001"))
    }

    func test_LIB_011_MissingFileDoesNotHideOtherArticles() throws {
        try FileManager.default.removeItem(at: root.appendingPathComponent("docs/10002.md"))
        let index = try MWebLibrary(rootURL: root).loadIndex()
        XCTAssertEqual(index.articles.count, 3)
        XCTAssertFalse(try XCTUnwrap(index.articles.first { $0.id == "10002" }).isAvailable)
        XCTAssertTrue(try XCTUnwrap(index.articles.first { $0.id == "10001" }).isAvailable)
    }

    func test_LIB_012_RejectsUnsupportedSchemaWithoutCreatingFiles() throws {
        let empty = root.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        XCTAssertThrowsError(try MWebLibrary(rootURL: empty))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: empty.path).isEmpty)
        try database.execute("ALTER TABLE article RENAME COLUMN dateModif TO changed")
        XCTAssertThrowsError(try MWebLibrary(rootURL: root))
    }

    func test_LIB_013_SymlinkCannotWriteOutsideSelectedLibrary() throws {
        let outside = root.appendingPathComponent("../mweb-lite-outside-\(UUID().uuidString).md").standardizedFileURL
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data("# Outside".utf8).write(to: outside)
        let target = root.appendingPathComponent("docs/10001.md")
        try FileManager.default.removeItem(at: target)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: outside)
        XCTAssertThrowsError(try MWebLibrary(rootURL: root).loadDocument(articleID: "10001"))
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "# Outside")
    }

    func test_LIB_014_UTF8BOMAndCRLFRemainIntact() throws {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("# Title\r\n\r\nBody\r\n".utf8)
        try data.write(to: root.appendingPathComponent("docs/10001.md"))
        let library = try MWebLibrary(rootURL: root)
        let original = try library.loadDocument(articleID: "10001")
        let saved = try library.saveDocument(original, content: original.content.replacingOccurrences(of: "Body", with: "Changed"))
        XCTAssertTrue(try Data(contentsOf: saved.fileURL).starts(with: [0xEF, 0xBB, 0xBF]))
        XCTAssertTrue(saved.content.contains("\r\n"))
        XCTAssertEqual(saved.title, "Title")
    }

    private func write(_ content: String, articleID: String) throws {
        try Data(content.utf8).write(to: root.appendingPathComponent("docs/\(articleID).md"))
    }

    private func row(_ articleID: String) throws -> SQLiteRow {
        try XCTUnwrap(database.query("SELECT * FROM article WHERE uuid = ?", bindings: [.text(articleID)]).first)
    }

    private func permissions(_ url: URL) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap(attributes[.posixPermissions] as? NSNumber).intValue
    }
}
