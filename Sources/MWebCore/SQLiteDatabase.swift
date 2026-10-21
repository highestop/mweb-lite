import CSQLite
import Foundation

enum SQLiteValue: Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    var string: String? {
        switch self {
        case .text(let value): return value
        case .integer(let value): return String(value)
        case .real(let value): return String(value)
        default: return nil
        }
    }

    var integer: Int64? {
        switch self {
        case .integer(let value): return value
        case .real(let value): return Int64(exactly: value)
        case .text(let value): return Int64(value)
        default: return nil
        }
    }

    var fingerprint: String {
        switch self {
        case .null: return "null"
        case .integer(let value): return "i\(value)"
        case .real(let value): return "r\(value.bitPattern)"
        case .text(let value): return "t\(Data(value.utf8).base64EncodedString())"
        case .blob(let value): return "b\(value.base64EncodedString())"
        }
    }
}

typealias SQLiteRow = [String: SQLiteValue]

extension Dictionary where Key == String, Value == SQLiteValue {
    var fingerprint: String {
        keys.sorted().map { "\($0):\(self[$0]!.fingerprint)" }.joined(separator: "\n")
    }
}

final class SQLiteDatabase {
    private(set) var handle: OpaquePointer?

    init(url: URL, writable: Bool = false, create: Bool = false) throws {
        var flags = writable ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY
        if create { flags |= SQLITE_OPEN_CREATE }
        let result = sqlite3_open_v2(url.path, &handle, flags | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            let message = errorMessage
            sqlite3_close(handle)
            handle = nil
            throw MWebLibraryError.database(message)
        }
        sqlite3_busy_timeout(handle, 2_000)
        if writable { try execute("PRAGMA foreign_keys = ON") }
    }

    deinit { sqlite3_close(handle) }

    private var errorMessage: String {
        handle.map { String(cString: sqlite3_errmsg($0)) } ?? L10n.string("Could not open the SQLite file")
    }

    func execute(_ sql: String, bindings: [SQLiteValue] = []) throws {
        _ = try query(sql, bindings: bindings)
    }

    func rollbackIfNeeded() {
        guard sqlite3_get_autocommit(handle) == 0 else { return }
        _ = try? execute("ROLLBACK")
    }

    func query(_ sql: String, bindings: [SQLiteValue] = []) throws -> [SQLiteRow] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw MWebLibraryError.database(errorMessage)
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in bindings.enumerated() {
            let position = Int32(offset + 1)
            let result: Int32
            switch value {
            case .null: result = sqlite3_bind_null(statement, position)
            case .integer(let value): result = sqlite3_bind_int64(statement, position, value)
            case .real(let value): result = sqlite3_bind_double(statement, position, value)
            case .text(let value):
                result = sqlite3_bind_text(statement, position, value, -1, transient)
            case .blob(let value):
                result = value.withUnsafeBytes { bytes in
                    sqlite3_bind_blob(statement, position, bytes.baseAddress, Int32(bytes.count), transient)
                }
            }
            guard result == SQLITE_OK else { throw MWebLibraryError.database(errorMessage) }
        }
        var rows: [SQLiteRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else { throw MWebLibraryError.database("\(sql): \(errorMessage)") }
            var row: SQLiteRow = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                switch sqlite3_column_type(statement, column) {
                case SQLITE_INTEGER: row[name] = .integer(sqlite3_column_int64(statement, column))
                case SQLITE_FLOAT: row[name] = .real(sqlite3_column_double(statement, column))
                case SQLITE_TEXT:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    let data = Data(bytes: sqlite3_column_text(statement, column), count: count)
                    row[name] = .text(String(decoding: data, as: UTF8.self))
                case SQLITE_BLOB:
                    let count = Int(sqlite3_column_bytes(statement, column))
                    if count == 0 { row[name] = .blob(Data()) }
                    else { row[name] = .blob(Data(bytes: sqlite3_column_blob(statement, column)!, count: count)) }
                default: row[name] = .null
                }
            }
            rows.append(row)
        }
    }

    func backup(to url: URL) throws {
        let destination = try SQLiteDatabase(url: url, writable: true, create: true)
        guard let backup = sqlite3_backup_init(destination.handle, "main", handle, "main") else {
            throw MWebLibraryError.database(destination.errorMessage)
        }
        let result = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard result == SQLITE_DONE, finish == SQLITE_OK else {
            throw MWebLibraryError.database(L10n.format("Database backup failed: %@", destination.errorMessage))
        }
        // Keep the backup self-contained, including when the source uses WAL.
        try destination.execute("PRAGMA journal_mode = DELETE")
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
