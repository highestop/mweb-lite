import AppKit
import XCTest
import CaseReporting
@testable import MWebCore
@testable import MWebLite

final class LibraryStoreSelectionTests: CaseReportingTestCase {
    @MainActor
    func test_SAVE_001_StatusTracksAutosaveInFlightEditsAndRetry() async throws {
        XCTAssertEqual(LibraryStore().saveStatus, .unavailable)
        let root = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await open(root)
        XCTAssertEqual(store.saveStatus, .saved)

        store.edit("# Automatically saved\n")
        XCTAssertEqual(store.saveStatus, .unsaved)
        try await waitForStatus(.saved, in: store)
        let file = root.appendingPathComponent("docs/10001.md")
        XCTAssertEqual(try String(contentsOf: file), store.draft)

        // Hold the real database writer briefly so the in-flight state is observable.
        let lock = try SQLiteDatabase(url: root.appendingPathComponent("mainlib.db"), writable: true)
        try lock.execute("BEGIN IMMEDIATE")
        defer { lock.rollbackIfNeeded() }
        store.edit("# First save snapshot\n")
        let saving = Task { await store.flush() }
        try await waitForStatus(.saving, in: store)
        store.edit("# Newer edit during save\n")
        XCTAssertEqual(store.saveStatus, .saving)
        try lock.execute("ROLLBACK")
        let saved = await saving.value
        XCTAssertTrue(saved)
        XCTAssertEqual(store.saveStatus, .saved)
        XCTAssertEqual(try String(contentsOf: file), "# Newer edit during save\n")

        let original = try XCTUnwrap(store.document?.content)
        try Data("# External edit\n".utf8).write(to: file)
        store.edit("# Keep this unsaved draft\n")
        let failed = await store.flush()
        XCTAssertFalse(failed)
        XCTAssertEqual(store.saveStatus, .failed)
        store.errorMessage = nil
        XCTAssertEqual(store.saveStatus, .failed, "Dismissing the alert cannot report a successful save")
        XCTAssertEqual(try String(contentsOf: file), "# External edit\n")
        XCTAssertEqual(store.draft, "# Keep this unsaved draft\n")

        // Resolve this fixture's conflict, then exercise the same retry as Command-S.
        try Data(original.utf8).write(to: file)
        store.saveNow()
        try await waitForStatus(.saved, in: store)
        XCTAssertEqual(try String(contentsOf: file), "# Keep this unsaved draft\n")
        store.setMode(.editor)
        XCTAssertEqual(store.saveStatus, .saved)
        store.setMode(.preview)
        XCTAssertEqual(store.saveStatus, .saved)
    }

    @MainActor
    func test_SELECT_001_SelectionChangesBeforeSavingAndLoadingTheNextDocument() async throws {
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
        XCTAssertTrue(store.isSwitchingArticle)

        await waitUntilIdle(store)

        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.selectedArticleID, "10002")
        XCTAssertEqual(store.document?.articleID, "10002")
        XCTAssertEqual(store.draft, "# Article B\n")
        XCTAssertFalse(store.isSwitchingArticle)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("docs/10001.md")), "# Updated A\n")

        // Saving the older article refreshes its card without moving it or its date.
        let originalOrder = store.visibleArticles.map(\.id)
        let originalDates = store.visibleArticles.map(\.createdAt)
        XCTAssertEqual(originalOrder, ["10001", "10002"])
        store.edit("# Updated B\n\nEdited older article.\n")
        let saved = await store.flush()
        XCTAssertTrue(saved)
        XCTAssertEqual(store.selectedArticleID, "10002")
        XCTAssertEqual(store.visibleArticles.map(\.id), originalOrder)
        XCTAssertEqual(store.visibleArticles.map(\.createdAt), originalDates)
        XCTAssertEqual(store.visibleArticles.last?.title, "Updated B")
        XCTAssertGreaterThan(try XCTUnwrap(store.visibleArticles.last?.modifiedAt),
                             try XCTUnwrap(store.visibleArticles.last?.createdAt))

        store.refresh()
        await waitUntilIdle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.selectedArticleID, "10002")
        XCTAssertEqual(store.visibleArticles.map(\.id), originalOrder)
        XCTAssertEqual(store.visibleArticles.map(\.createdAt), originalDates)
    }

    @MainActor
    func test_SELECT_002_SaveConflictRestoresSelectionAndPreservesTheDraft() async throws {
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
    func test_SELECT_003_LoadFailureRestoresSelectionWithoutReplacingTheDocument() async throws {
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
    func test_SELECT_004_SelectionWhileBusyDoesNotReplaceThePendingTarget() async throws {
        let root = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try await open(root)
        XCTAssertEqual(store.mode, .preview)

        store.selectArticle("10002")
        store.selectArticle("10001")
        store.selectArticle(nil)
        store.setMode(.editor)
        store.createArticle()

        XCTAssertTrue(store.isBusy)
        XCTAssertTrue(store.isSwitchingArticle)
        XCTAssertEqual(store.selectedArticleID, "10002")
        XCTAssertEqual(store.mode, .preview)
        XCTAssertNil(store.editorFocusRequest)
        await waitUntilIdle(store)
        XCTAssertNil(store.errorMessage)
        XCTAssertFalse(store.isSwitchingArticle)
        XCTAssertEqual(store.selectedArticleID, "10002")
        XCTAssertEqual(store.document?.articleID, "10002")
        XCTAssertEqual(store.mode, .preview)
        XCTAssertNil(store.editorFocusRequest)
        XCTAssertEqual(Set(store.activeArticles.map(\.id)), ["10001", "10002"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("docs").path).sorted(),
                       ["10001.md", "10002.md"])
        XCTAssertFalse(store.hasPendingWrites)

        store.setMode(.editor)
        XCTAssertEqual(store.mode, .editor)
        XCTAssertEqual(store.editorFocusRequest?.selection, .preserveSelection)
    }

    @MainActor
    private func waitForStatus(_ status: DocumentSaveStatus, in store: LibraryStore) async throws {
        let deadline = Date().addingTimeInterval(5)
        while store.saveStatus != status, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(store.saveStatus, status)
        guard store.saveStatus == status else {
            throw NSError(domain: "SaveStatusTest", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Save status did not reach \(status)"])
        }
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
