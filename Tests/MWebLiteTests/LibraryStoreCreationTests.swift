import AppKit
import XCTest
import CaseReporting
@testable import MWebCore
@testable import MWebLite

final class LibraryStoreCreationTests: CaseReportingTestCase {
    @MainActor
    func test_STORE_001_PendingCreationWaitsForPriorSaveAndInheritsCategory() async throws {
        let root = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await open(root)
        store.selectedCategory = "100"
        store.search = "no matching title"
        store.edit("# Saved before creation\n")

        store.createArticle()

        XCTAssertTrue(store.hasPendingWrites)
        let finished = await store.finishPendingWrites()
        XCTAssertTrue(finished)
        XCTAssertFalse(store.hasPendingWrites)
        XCTAssertFalse(store.isBusy)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("docs/10001.md")), "# Saved before creation\n")
        let createdID = try XCTUnwrap(store.document?.articleID)
        XCTAssertNotEqual(createdID, "10001")
        XCTAssertEqual(store.visibleArticles.first?.id, createdID)
        XCTAssertEqual(store.articles.first(where: { $0.id == createdID })?.categoryIDs, ["100"])
        XCTAssertTrue(store.visibleArticles.contains(where: { $0.id == createdID }))
        XCTAssertTrue(store.search.isEmpty)
        XCTAssertEqual(store.mode, .editor)
    }

    @MainActor
    func test_STORE_002_ConflictingDraftPreventsCreationAndPreservesDraft() async throws {
        let root = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await open(root)
        store.edit("# Unsaved draft\n")
        try Data("# External edit\n".utf8).write(to: root.appendingPathComponent("docs/10001.md"))

        store.createArticle()
        let finished = await store.finishPendingWrites()

        XCTAssertFalse(finished)
        XCTAssertTrue(store.saveBlocked)
        XCTAssertEqual(store.document?.articleID, "10001")
        XCTAssertEqual(store.draft, "# Unsaved draft\n")
        XCTAssertEqual(try MWebLibrary(rootURL: root).loadIndex().articles.count, 1)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("docs/10001.md")), "# External edit\n")
    }

    @MainActor
    func test_STORE_003_TrashUsesTargetAndMaintainsSelectionThroughLastArticle() async throws {
        let root = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let library = try MWebLibrary(rootURL: root)
        let other = try library.createDocument()
        let store = try await open(root, expectedID: other.articleID)
        store.edit("# Keep current draft\n")
        store.trashArticle("10001")
        XCTAssertTrue(store.hasPendingWrites)
        let finished = await store.finishPendingWrites()
        XCTAssertTrue(finished)
        XCTAssertEqual(store.document?.articleID, other.articleID)
        XCTAssertEqual(store.draft, "# Keep current draft\n")
        XCTAssertEqual(store.activeArticles.count, 1)
        XCTAssertTrue(try library.loadIndex().articles.first { $0.id == "10001" }!.isTrashed)
        store.trashArticle(other.articleID)
        let cleared = await store.finishPendingWrites()
        XCTAssertTrue(cleared)
        XCTAssertNil(store.document)
        XCTAssertEqual(store.draft, "")
        XCTAssertTrue(store.visibleArticles.isEmpty)
        XCTAssertEqual(store.saveStatus, .unavailable)
    }

    @MainActor
    func test_STORE_004_ConflictingDraftBlocksManagementWrites() async throws {
        let root = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await open(root)
        store.edit("# Unsaved draft\n")
        try Data("# External edit\n".utf8).write(to: root.appendingPathComponent("docs/10001.md"))
        let actions: [() -> Void] = [
            { store.trashArticle("10001") },
            { store.createCategory(name: "Blocked", parentID: nil) },
            { store.renameCategory(id: "100", name: "Blocked") },
            { store.deleteCategory(id: "100") }
        ]
        for action in actions {
            action()
            let finished = await store.finishPendingWrites()
            XCTAssertFalse(finished)
            XCTAssertTrue(store.saveBlocked)
            XCTAssertEqual(store.draft, "# Unsaved draft\n")
            let index = try MWebLibrary(rootURL: root).loadIndex()
            XCTAssertEqual(index.categories.map(\.name), ["Category"])
            XCTAssertEqual(index.articles.filter { !$0.isTrashed }.count, 1)
        }
    }

    @MainActor
    func test_STORE_005_CategoryOperationsRefreshCountsAndKeepCurrentEditor() async throws {
        let root = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let db = try SQLiteDatabase(url: root.appendingPathComponent("mainlib.db"), writable: true)
        try db.execute("INSERT INTO cat_article VALUES (100, 10001)")
        let store = try await open(root)
        store.selectedCategory = "100"
        store.edit("# Saved before category change\n")
        store.createCategory(name: "Child", parentID: "100")
        let created = await store.finishPendingWrites()
        XCTAssertTrue(created)
        let childID = try XCTUnwrap(store.categories.first { $0.name == "Child" }?.id)
        XCTAssertEqual(store.selectedCategory, childID)
        store.renameCategory(id: childID, name: "Renamed")
        let renamed = await store.finishPendingWrites()
        XCTAssertTrue(renamed)
        XCTAssertEqual(store.categories.first { $0.id == childID }?.name, "Renamed")
        store.selectedCategory = "100"
        store.deleteCategory(id: "100")
        let deleted = await store.finishPendingWrites()
        XCTAssertTrue(deleted)
        XCTAssertEqual(store.selectedCategory, "all")
        XCTAssertNil(store.categories.first { $0.id == childID }?.parentID)
        XCTAssertEqual(store.document?.articleID, "10001")
        XCTAssertEqual(store.draft, "# Saved before category change\n")
        XCTAssertEqual(store.activeArticles.first?.categoryIDs, [])
        store.edit("# Edit after category removal\n")
        let saved = await store.finishPendingWrites()
        XCTAssertTrue(saved)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("docs/10001.md")), store.draft)
    }

    @MainActor
    private func open(_ root: URL, expectedID: String = "10001") async throws -> LibraryStore {
        _ = NSApplication.shared
        let store = LibraryStore()
        store.open(root, remember: false)
        let deadline = Date().addingTimeInterval(5)
        while store.isBusy, Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertFalse(store.isBusy)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.document?.articleID, expectedID)
        return store
    }

    private func makeLibrary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MWebLite-Store-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
        let database = try SQLiteDatabase(url: root.appendingPathComponent("mainlib.db"), writable: true, create: true)
        try database.execute("CREATE TABLE article (id INTEGER PRIMARY KEY, uuid INTEGER UNIQUE, state INTEGER, dateAdd INTEGER, dateModif INTEGER)")
        try database.execute("CREATE TABLE cat (uuid INTEGER PRIMARY KEY, name TEXT, pid INTEGER)")
        try database.execute("CREATE TABLE cat_article (rid INTEGER, aid INTEGER)")
        try database.execute("INSERT INTO cat VALUES (100, 'Category', 0)")
        try database.execute("INSERT INTO article VALUES (1, 10001, 1, 1700000000, 1700000000)")
        try Data("# Original\n".utf8).write(to: root.appendingPathComponent("docs/10001.md"))
        return root
    }
}
