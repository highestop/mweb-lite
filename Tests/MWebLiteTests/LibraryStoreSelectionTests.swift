import AppKit
import XCTest
@testable import MWebCore
@testable import MWebLite

final class LibraryStoreSelectionTests: XCTestCase {
    @MainActor
    func testSelectionChangesBeforeSavingAndLoadingTheNextDocument() async throws {
        let root = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await open(root)
        store.edit("# Updated A\n")

        store.selectArticle("10002")

        // List feedback must not wait for either file operation to finish.
        XCTAssertEqual(store.selectedArticleID, "10002")
        XCTAssertEqual(store.document?.articleID, "10001")
        XCTAssertEqual(store.draft, "# Updated A\n")
        XCTAssertTrue(store.isBusy)

        await waitUntilIdle(store)

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.selectedArticleID, "10002")
        XCTAssertEqual(store.document?.articleID, "10002")
        XCTAssertEqual(store.draft, "# Article B\n")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("docs/10001.md")), "# Updated A\n")
    }

    @MainActor
    func testSaveConflictRestoresSelectionAndPreservesTheDraft() async throws {
        let root = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await open(root)
        store.edit("# Unsaved A\n")
        try Data("# External A\n".utf8).write(to: root.appendingPathComponent("docs/10001.md"))

        store.selectArticle("10002")
        XCTAssertEqual(store.selectedArticleID, "10002")
        await waitUntilIdle(store)

        XCTAssertTrue(store.saveBlocked)
        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.selectedArticleID, "10001")
        XCTAssertEqual(store.document?.articleID, "10001")
        XCTAssertEqual(store.draft, "# Unsaved A\n")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("docs/10001.md")), "# External A\n")
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("docs/10002.md")), "# Article B\n")
    }

    @MainActor
    func testLoadFailureRestoresSelectionWithoutReplacingTheDocument() async throws {
        let root = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await open(root)
        try FileManager.default.removeItem(at: root.appendingPathComponent("docs/10002.md"))

        store.selectArticle("10002")
        XCTAssertEqual(store.selectedArticleID, "10002")
        await waitUntilIdle(store)

        XCTAssertNotNil(store.errorMessage)
        XCTAssertEqual(store.selectedArticleID, "10001")
        XCTAssertEqual(store.document?.articleID, "10001")
        XCTAssertEqual(store.draft, "# Article A\n")
    }

    @MainActor
    func testSelectionWhileBusyDoesNotReplaceThePendingTarget() async throws {
        let root = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await open(root)

        store.selectArticle("10002")
        store.selectArticle("10001")
        store.selectArticle(nil)

        XCTAssertTrue(store.isBusy)
        XCTAssertEqual(store.selectedArticleID, "10002")
        await waitUntilIdle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.selectedArticleID, "10002")
        XCTAssertEqual(store.document?.articleID, "10002")
    }

    @MainActor
    private func open(_ root: URL) async throws -> LibraryStore {
        _ = NSApplication.shared
        let store = LibraryStore()
        store.open(root, remember: false)
        await waitUntilIdle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.document?.articleID, "10001")
        XCTAssertEqual(store.selectedArticleID, "10001")
        return store
    }

    @MainActor
    private func waitUntilIdle(_ store: LibraryStore, file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(5)
        while store.isBusy, Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertFalse(store.isBusy, "The library operation did not finish.", file: file, line: line)
    }

    private func makeLibrary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MWebLite-Selection-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("docs"), withIntermediateDirectories: true)
        let database = try SQLiteDatabase(url: root.appendingPathComponent("mainlib.db"), writable: true, create: true)
        try database.execute("CREATE TABLE article (id INTEGER PRIMARY KEY, uuid INTEGER UNIQUE, state INTEGER, dateAdd INTEGER, dateModif INTEGER)")
        try database.execute("CREATE TABLE cat (uuid INTEGER PRIMARY KEY, name TEXT, pid INTEGER)")
        try database.execute("CREATE TABLE cat_article (rid INTEGER, aid INTEGER)")
        try database.execute("INSERT INTO article VALUES (1, 10001, 1, 1700000100, 1700000100)")
        try database.execute("INSERT INTO article VALUES (2, 10002, 1, 1700000000, 1700000000)")
        try Data("# Article A\n".utf8).write(to: root.appendingPathComponent("docs/10001.md"))
        try Data("# Article B\n".utf8).write(to: root.appendingPathComponent("docs/10002.md"))
        return root
    }
}
