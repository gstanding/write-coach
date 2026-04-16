import Foundation
import CSQLite3

public enum SQLiteError: Error, CustomStringConvertible {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)

    public var description: String {
        switch self {
        case .openFailed(let s): return "open_failed:\(s)"
        case .execFailed(let s): return "exec_failed:\(s)"
        case .prepareFailed(let s): return "prepare_failed:\(s)"
        case .bindFailed(let s): return "bind_failed:\(s)"
        case .stepFailed(let s): return "step_failed:\(s)"
        }
    }
}

public final class SQLiteConnection {
    private var db: OpaquePointer?

    public init(path: String) throws {
        var handle: OpaquePointer?
        if sqlite3_open(path, &handle) != SQLITE_OK {
            let msg = handle.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(handle)
            throw SQLiteError.openFailed(msg)
        }
        db = handle
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    public func exec(_ sql: String) throws {
        guard let db else { throw SQLiteError.execFailed("db_closed") }
        var err: UnsafeMutablePointer<Int8>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(err)
            throw SQLiteError.execFailed(msg)
        }
    }

    public func prepare(_ sql: String) throws -> SQLiteStatement {
        guard let db else { throw SQLiteError.prepareFailed("db_closed") }
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        return SQLiteStatement(db: db, stmt: stmt)
    }
}

public final class SQLiteStatement {
    private let db: OpaquePointer
    private var stmt: OpaquePointer?

    fileprivate init(db: OpaquePointer, stmt: OpaquePointer?) {
        self.db = db
        self.stmt = stmt
    }

    deinit {
        if let stmt { sqlite3_finalize(stmt) }
    }

    public func reset() {
        if let stmt { sqlite3_reset(stmt) }
    }

    public func bind(_ index: Int32, _ value: String?) throws {
        guard let stmt else { throw SQLiteError.bindFailed("stmt_finalized") }
        if let value {
            if sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT) != SQLITE_OK {
                throw SQLiteError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        } else {
            if sqlite3_bind_null(stmt, index) != SQLITE_OK {
                throw SQLiteError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func bind(_ index: Int32, _ value: Int64?) throws {
        guard let stmt else { throw SQLiteError.bindFailed("stmt_finalized") }
        if let value {
            if sqlite3_bind_int64(stmt, index, value) != SQLITE_OK {
                throw SQLiteError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        } else {
            if sqlite3_bind_null(stmt, index) != SQLITE_OK {
                throw SQLiteError.bindFailed(String(cString: sqlite3_errmsg(db)))
            }
        }
    }

    public func step() throws -> Int32 {
        guard let stmt else { throw SQLiteError.stepFailed("stmt_finalized") }
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_ROW || rc == SQLITE_DONE {
            return rc
        }
        throw SQLiteError.stepFailed(String(cString: sqlite3_errmsg(db)))
    }

    public func columnText(_ index: Int32) -> String? {
        guard let stmt else { return nil }
        guard let c = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: c)
    }

    public func columnInt64(_ index: Int32) -> Int64? {
        guard let stmt else { return nil }
        if sqlite3_column_type(stmt, index) == SQLITE_NULL { return nil }
        return sqlite3_column_int64(stmt, index)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
