import Foundation
import Darwin

/// Reads the existing MWeb schema without importing, migrating, or rebuilding it.
/// All public operations are serialized; each operation uses a short-lived connection.
public final class MWebLibrary: @unchecked Sendable {
    public let rootURL: URL
    public let docsURL: URL
    public var databaseURL: URL { rootURL.appendingPathComponent("mainlib.db") }

    private let lock = NSLock()
    private let fileManager = FileManager.default
    private var sessionBackupURL: URL?
    private var backedUpArticleIDs: Set<String> = []

    public init(rootURL: URL) throws {
        self.rootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
        docsURL = self.rootURL.appendingPathComponent("docs", isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: docsURL.path, isDirectory: &isDirectory), isDirectory.boolValue,
              fileManager.fileExists(atPath: databaseURL.path) else {
            throw MWebLibraryError.invalidLibrary("请选择同时包含 mainlib.db 和 docs 文件夹的目录。")
        }
        guard isInsideRoot(docsURL), isInsideRoot(databaseURL) else {
            throw MWebLibraryError.invalidLibrary("数据库和 docs 文件夹需要位于所选文库目录内。")
        }
        let database = try SQLiteDatabase(url: databaseURL)
        let required: [String: Set<String>] = [
            "article": ["uuid", "state", "dateModif"],
            "cat": ["uuid", "name", "pid"],
            "cat_article": ["rid", "aid"]
        ]
        for (table, columns) in required {
            let available = Set(try database.query("PRAGMA table_info(\(table))").compactMap { $0["name"]?.string })
            guard columns.isSubset(of: available) else {
                throw MWebLibraryError.invalidLibrary("不支持的 MWeb 数据结构（\(table)）。原始数据没有修改。")
            }
        }
    }

    public func loadIndex() throws -> LibraryIndex {
        lock.lock()
        defer { lock.unlock() }
        let database = try SQLiteDatabase(url: databaseURL)
        try database.execute("BEGIN")
        defer { database.rollbackIfNeeded() }
        let categories = try database.query("SELECT * FROM cat").compactMap { row -> MWebCategory? in
            guard let id = row["uuid"]?.string else { return nil }
            let parentID = row["pid"]?.string
            return MWebCategory(id: id, name: row["name"]?.string ?? "未命名分类",
                                parentID: parentID == "0" ? nil : parentID,
                                sort: row["sort"]?.integer ?? 0,
                                sortType: row["sortType"]?.integer ?? 0,
                                categoryType: row["catType"]?.integer ?? 0)
        }.sorted { left, right in
            if left.sort != right.sort { return left.sort < right.sort }
            return left.id.localizedStandardCompare(right.id) == .orderedAscending
        }
        var memberships: [String: Set<String>] = [:]
        for row in try database.query("SELECT aid, rid FROM cat_article") {
            if let aid = row["aid"]?.string, let rid = row["rid"]?.string {
                memberships[aid, default: []].insert(rid)
            }
        }
        let articleRows = try database.query("SELECT * FROM article")
        try database.execute("COMMIT")
        // Cloud-backed files may take time to materialize; release the database read lock first.
        let articles = articleRows.compactMap { row -> MWebArticle? in
            guard let id = row["uuid"]?.string else { return nil }
            let data = try? Data(contentsOf: documentURL(id))
            let summary = Self.summary(data.map { String(decoding: $0.prefix(4_096), as: UTF8.self) } ?? "")
            let images = data.map { MarkdownImageReferences.firstImages(in: String(decoding: $0, as: UTF8.self)) } ?? []
            return MWebArticle(id: id, title: summary.title, excerpt: summary.excerpt,
                               modifiedAt: Self.date(row["dateModif"]), createdAt: Self.date(row["dateAdd"]),
                               categoryIDs: (memberships[id] ?? []).sorted(),
                               isTrashed: row["state"]?.integer != 1,
                               isPinned: (row["isTop"]?.integer ?? 0) != 0,
                               sort: row["sort"]?.integer ?? 0, isAvailable: data != nil,
                               imageReferences: images)
        }.sorted { left, right in
            if left.isPinned != right.isPinned { return left.isPinned }
            if left.modifiedAt != right.modifiedAt {
                return (left.modifiedAt ?? .distantPast) > (right.modifiedAt ?? .distantPast)
            }
            return left.id.localizedStandardCompare(right.id) == .orderedDescending
        }
        return LibraryIndex(categories: categories, articles: articles)
    }

    public func loadDocument(articleID: String) throws -> MWebDocument {
        lock.lock()
        defer { lock.unlock() }
        let database = try SQLiteDatabase(url: databaseURL)
        let row = try articleRow(articleID, database: database)
        let url = try documentURL(articleID)
        let data = try Data(contentsOf: url)
        return try document(articleID: articleID, row: row, data: data, url: url)
    }

    /// Creates a Markdown document using MWeb's timestamp identifiers and category UUIDs.
    public func createDocument(categoryID: String? = nil) throws -> MWebDocument {
        try createDocument(categoryID: categoryID, now: Date())
    }

    // A fixed clock lets tests exercise identifier collisions without racing the wall clock.
    func createDocument(categoryID: String?, now: Date) throws -> MWebDocument {
        lock.lock()
        defer { lock.unlock() }
        guard let identifier = Int64(exactly: floor(now.timeIntervalSince1970 * 10_000)), identifier > 0 else {
            throw MWebLibraryError.invalidDocument("无法生成新文章标识。")
        }
        let articleID = String(identifier)
        let url = try documentURL(articleID)
        let database = try SQLiteDatabase(url: databaseURL, writable: true)
        try database.execute("BEGIN IMMEDIATE")
        defer { database.rollbackIfNeeded() }

        var categoryUUID: SQLiteValue?
        if let categoryID {
            guard let category = try database.query("SELECT uuid FROM cat WHERE uuid = ?", bindings: [.text(categoryID)]).first,
                  let uuid = category["uuid"] else { throw MWebLibraryError.missingCategory }
            categoryUUID = uuid
        }
        let mediaURL = docsURL.appendingPathComponent("media", isDirectory: true).appendingPathComponent(articleID)
        guard try database.query("SELECT uuid FROM article WHERE uuid = ?", bindings: [.integer(identifier)]).isEmpty,
              !itemExists(url), !itemExists(mediaURL) else { throw MWebLibraryError.creationConflict }

        // Only known fields are supplied. Other columns retain the schema's defaults.
        let schema = try database.query("PRAGMA table_info(article)")
        let columns = Set(schema.compactMap { $0["name"]?.string })
        let timestamp = Int64(now.timeIntervalSince1970)
        var values: [(String, SQLiteValue)] = [("uuid", .integer(identifier)), ("state", .integer(1)),
                                              ("dateModif", .integer(timestamp))]
        for name in ["dateAdd", "dateArt"] where columns.contains(name) {
            values.append((name, .integer(timestamp)))
        }
        let fallbacks: [(String, SQLiteValue)] = [("type", .integer(0)), ("docName", .text("")),
                                                 ("sort", .integer(0)), ("isTop", .integer(0))]
        for (name, value) in fallbacks {
            if let field = schema.first(where: { $0["name"]?.string == name }), field["dflt_value"] == .null {
                values.append((name, value))
            }
        }
        let backupURL = try makeDatabaseBackup()
        let fieldNames = values.map(\.0).joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: values.count).joined(separator: ", ")
        try database.execute("INSERT INTO article (\(fieldNames)) VALUES (\(placeholders))", bindings: values.map(\.1))
        if let categoryUUID {
            try database.execute("INSERT INTO cat_article (rid, aid) VALUES (?, ?)",
                                 bindings: [categoryUUID, .integer(identifier)])
        }

        let data = Data("# 未命名文章\n\n".utf8)
        var wroteFile = false
        var writtenByteCount = 0
        var createdFileInfo: stat?
        do {
            try coordinatedWrite(url: url) { coordinatedURL in
                guard isInsideRoot(coordinatedURL) else { throw MWebLibraryError.invalidDocument("文章文件位于文库目录外。") }
                // Exclusive creation avoids requiring hard-link support on the library's volume.
                let descriptor = Darwin.open(coordinatedURL.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o600)
                guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                wroteFile = true
                defer { Darwin.close(descriptor) }
                var info = stat()
                guard fstat(descriptor, &info) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
                createdFileInfo = info
                try data.withUnsafeBytes { bytes in
                    while writtenByteCount < bytes.count {
                        let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: writtenByteCount), bytes.count - writtenByteCount)
                        if count < 0, errno == EINTR { continue }
                        guard count > 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: count == 0 ? Int(EIO) : Int(errno)) }
                        writtenByteCount += count
                    }
                }
                guard fsync(descriptor) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
            }
            let row = try articleRow(articleID, database: database)
            let created = try document(articleID: articleID, row: row, data: data, url: url, backupURL: backupURL)
            try database.execute("COMMIT")
            return created
        } catch {
            database.rollbackIfNeeded()
            if wroteFile {
                do {
                    try coordinatedWrite(url: url) { coordinatedURL in
                        var currentInfo = stat()
                        guard let createdFileInfo, isInsideRoot(coordinatedURL), lstat(coordinatedURL.path, &currentInfo) == 0,
                              currentInfo.st_dev == createdFileInfo.st_dev, currentInfo.st_ino == createdFileInfo.st_ino,
                              try Data(contentsOf: coordinatedURL) == data.prefix(writtenByteCount) else {
                            throw MWebLibraryError.conflict
                        }
                        try fileManager.removeItem(at: coordinatedURL)
                    }
                } catch {
                    throw MWebLibraryError.creationRecoveryRequired(documentURL: url, backupURL: backupURL)
                }
            }
            throw error
        }
    }

    /// Updates only the Markdown file and dateModif. Unknown columns and all relationships stay intact.
    public func saveDocument(_ original: MWebDocument, content: String) throws -> MWebDocument {
        lock.lock()
        defer { lock.unlock() }
        guard original.libraryURL == rootURL else { throw MWebLibraryError.conflict }
        let url = try documentURL(original.articleID)
        let database = try SQLiteDatabase(url: databaseURL, writable: true)
        try database.execute("BEGIN IMMEDIATE")
        defer { database.rollbackIfNeeded() }
        let before = try articleRow(original.articleID, database: database)
        guard before.fingerprint == original.metadataFingerprint,
              try Data(contentsOf: url) == original.originalData else {
            throw MWebLibraryError.conflict
        }
        guard content != original.content else { return original }

        var data = Data(content.utf8)
        if original.originalData.starts(with: [0xEF, 0xBB, 0xBF]), !data.starts(with: [0xEF, 0xBB, 0xBF]) {
            data.insert(contentsOf: [0xEF, 0xBB, 0xBF], at: 0)
        }
        let backupURL = try makeBackup(articleID: original.articleID, originalData: original.originalData)
        let attributes = try fileManager.attributesOfItem(atPath: url.path)
        let permissions = attributes[.posixPermissions]
        let modified = Int64(Date().timeIntervalSince1970)
        try database.execute("UPDATE article SET dateModif = ? WHERE uuid = ?",
                             bindings: [.integer(modified), .text(original.articleID)])
        var wroteFile = false
        var after: SQLiteRow = [:]
        do {
            try coordinatedWrite(url: url) { coordinatedURL in
                // Check once more after acquiring the file coordinator's write access.
                guard try Data(contentsOf: coordinatedURL) == original.originalData else {
                    throw MWebLibraryError.conflict
                }
                try data.write(to: coordinatedURL, options: .atomic)
                wroteFile = true
                if let permissions { try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: coordinatedURL.path) }
            }
            after = try articleRow(original.articleID, database: database)
            try database.execute("COMMIT")
        } catch {
            database.rollbackIfNeeded()
            if wroteFile {
                do {
                    try coordinatedWrite(url: url) { coordinatedURL in
                        // Never replace a newer edit made by another process during recovery.
                        guard try Data(contentsOf: coordinatedURL) == data else {
                            throw MWebLibraryError.conflict
                        }
                        try original.originalData.write(to: coordinatedURL, options: .atomic)
                        if let permissions { try fileManager.setAttributes([.posixPermissions: permissions], ofItemAtPath: coordinatedURL.path) }
                    }
                } catch {
                    throw MWebLibraryError.recoveryRequired(backupURL)
                }
            }
            throw error
        }
        return try document(articleID: original.articleID, row: after, data: data, url: url, backupURL: backupURL)
    }

    private func articleRow(_ articleID: String, database: SQLiteDatabase) throws -> SQLiteRow {
        guard let row = try database.query("SELECT * FROM article WHERE uuid = ?", bindings: [.text(articleID)]).first else {
            throw MWebLibraryError.missingArticle
        }
        guard row["state"]?.integer == 1 else { throw MWebLibraryError.trashedArticle }
        return row
    }

    private func document(articleID: String, row: SQLiteRow, data: Data, url: URL, backupURL: URL? = nil) throws -> MWebDocument {
        guard let content = String(data: data, encoding: .utf8) else {
            throw MWebLibraryError.invalidDocument("文件不是有效的 UTF-8 Markdown，未作任何转换。")
        }
        return MWebDocument(articleID: articleID, title: Self.summary(content).title, content: content,
                            fileURL: url, modifiedAt: Self.date(row["dateModif"]), lastBackupURL: backupURL,
                            originalData: data, metadataFingerprint: row.fingerprint, libraryURL: rootURL)
    }

    private func documentURL(_ articleID: String) throws -> URL {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        guard !articleID.isEmpty, articleID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw MWebLibraryError.invalidDocument("文章标识不合法。")
        }
        let url = docsURL.appendingPathComponent(articleID).appendingPathExtension("md")
        guard isInsideRoot(url) else { throw MWebLibraryError.invalidDocument("文章文件位于文库目录外。") }
        return url
    }

    private func isInsideRoot(_ url: URL) -> Bool {
        url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(rootURL.path + "/")
    }

    private func itemExists(_ url: URL) -> Bool {
        fileManager.fileExists(atPath: url.path) || (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    private func makeDatabaseBackup() throws -> URL {
        let destination: URL
        if let sessionBackupURL {
            destination = sessionBackupURL
        } else {
            let directory = rootURL.appendingPathComponent(".mweb-lite/backups", isDirectory: true)
            guard isInsideRoot(directory) else { throw MWebLibraryError.invalidLibrary("备份目录位于文库外。") }
            let stamp = Int64(Date().timeIntervalSince1970 * 1_000)
            destination = directory.appendingPathComponent("\(stamp)-\(UUID().uuidString)", isDirectory: true)
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true,
                                            attributes: [.posixPermissions: 0o700])
            // A separate reader can back up committed data while our writer owns a RESERVED lock.
            let reader = try SQLiteDatabase(url: databaseURL)
            try reader.backup(to: destination.appendingPathComponent("mainlib.db"))
            sessionBackupURL = destination
        }
        guard isInsideRoot(destination) else { throw MWebLibraryError.invalidLibrary("备份目录位于文库外。") }
        return destination
    }

    private func makeBackup(articleID: String, originalData: Data) throws -> URL {
        let destination = try makeDatabaseBackup()
        if !backedUpArticleIDs.contains(articleID) {
            let originalURL = destination.appendingPathComponent("\(articleID).md")
            try originalData.write(to: originalURL, options: .atomic)
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: originalURL.path)
            backedUpArticleIDs.insert(articleID)
        }
        let snapshots = destination.appendingPathComponent(articleID, isDirectory: true)
        guard isInsideRoot(snapshots) else { throw MWebLibraryError.invalidLibrary("备份目录位于文库外。") }
        try fileManager.createDirectory(at: snapshots, withIntermediateDirectories: true)
        let stamp = Int64(Date().timeIntervalSince1970 * 1_000)
        let snapshotURL = snapshots.appendingPathComponent("\(stamp)-\(UUID().uuidString).md")
        try originalData.write(to: snapshotURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshotURL.path)
        let saved = try fileManager.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: [.creationDateKey])
            .filter { $0.pathExtension == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        // Retention only touches snapshots generated by this session, never the original documents.
        for old in saved.prefix(max(0, saved.count - 20)) { try? fileManager.removeItem(at: old) }
        return destination
    }

    private func coordinatedWrite(url: URL, action: (URL) throws -> Void) throws {
        var coordinationError: NSError?
        var actionError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinatedURL in
            do { try action(coordinatedURL) }
            catch { actionError = error }
        }
        if let actionError { throw actionError }
        if let coordinationError { throw coordinationError }
    }

    private static func date(_ value: SQLiteValue?) -> Date? {
        value?.integer.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    static func summary(_ markdown: String) -> (title: String, excerpt: String) {
        let lines = markdown.replacingOccurrences(of: "\u{FEFF}", with: "").components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return ("无标题", "") }
        let title = first.replacingOccurrences(of: "^#{1,6}\\s+", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+#+$", with: "", options: .regularExpression)
        let excerpt = lines.dropFirst().filter { !$0.hasPrefix("```") && !$0.hasPrefix("~~~") }
            .joined(separator: " ")
            .replacingOccurrences(of: "!?\\[([^\\]]*)\\]\\([^)]*\\)", with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "[#*_`>]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return (String(title.prefix(200)), String(excerpt.prefix(160)))
    }
}
