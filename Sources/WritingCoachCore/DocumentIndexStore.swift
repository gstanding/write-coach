import Foundation

public struct DocumentMeta: Equatable {
    public var id: String
    public var path: String
    public var title: String?
    public var createdAt: Date
    public var updatedAt: Date
    public var source: String?
    public var voiceProfileId: String?
    public var bodyHash: String

    public init(
        id: String,
        path: String,
        title: String?,
        createdAt: Date,
        updatedAt: Date,
        source: String?,
        voiceProfileId: String?,
        bodyHash: String
    ) {
        self.id = id
        self.path = path
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
        self.voiceProfileId = voiceProfileId
        self.bodyHash = bodyHash
    }
}

public protocol DocumentIndexStore {
    func upsert(meta: DocumentMeta) throws
    func fetchList(query: String?, tag: String?, limit: Int, offset: Int) throws -> [DocumentMeta]
    func fetchMeta(id: String) throws -> DocumentMeta?
    func setTags(documentId: String, tagNames: [String]) throws
}

public final class DocumentIndexStoreImpl: DocumentIndexStore {
    private let conn: SQLiteConnection

    public init(dbURL: URL) throws {
        self.conn = try SQLiteConnection(path: dbURL.path)
        try bootstrapIfNeeded()
    }

    private func bootstrapIfNeeded() throws {
        try conn.exec(
            """
            PRAGMA journal_mode=WAL;
            PRAGMA foreign_keys=ON;
            CREATE TABLE IF NOT EXISTS documents (
              id TEXT PRIMARY KEY,
              path TEXT NOT NULL,
              title TEXT,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              source TEXT,
              voice_profile_id TEXT,
              body_hash TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS tags (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL UNIQUE
            );
            CREATE TABLE IF NOT EXISTS document_tags (
              document_id TEXT NOT NULL,
              tag_id TEXT NOT NULL,
              PRIMARY KEY (document_id, tag_id),
              FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE,
              FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
            );
            CREATE TABLE IF NOT EXISTS voice_profiles (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              stats_json TEXT NOT NULL,
              lexicon_json TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS imports (
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL,
              source_path TEXT,
              created_at INTEGER NOT NULL,
              result_document_id TEXT,
              log_json TEXT NOT NULL
            );
            CREATE TABLE IF NOT EXISTS suggestion_feedback (
              id TEXT PRIMARY KEY,
              document_id TEXT NOT NULL,
              rule_id TEXT NOT NULL,
              action TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              span_start INTEGER,
              span_end INTEGER,
              FOREIGN KEY (document_id) REFERENCES documents(id) ON DELETE CASCADE
            );
            CREATE INDEX IF NOT EXISTS idx_documents_updated_at ON documents(updated_at DESC);
            CREATE INDEX IF NOT EXISTS idx_documents_created_at ON documents(created_at DESC);
            """
        )
    }

    public func upsert(meta: DocumentMeta) throws {
        let stmt = try conn.prepare(
            """
            INSERT INTO documents (id, path, title, created_at, updated_at, source, voice_profile_id, body_hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              path=excluded.path,
              title=excluded.title,
              created_at=excluded.created_at,
              updated_at=excluded.updated_at,
              source=excluded.source,
              voice_profile_id=excluded.voice_profile_id,
              body_hash=excluded.body_hash;
            """
        )
        try stmt.bind(1, meta.id)
        try stmt.bind(2, meta.path)
        try stmt.bind(3, meta.title)
        try stmt.bind(4, meta.createdAt.epochMs)
        try stmt.bind(5, meta.updatedAt.epochMs)
        try stmt.bind(6, meta.source)
        try stmt.bind(7, meta.voiceProfileId)
        try stmt.bind(8, meta.bodyHash)
        _ = try stmt.step()
    }

    public func fetchMeta(id: String) throws -> DocumentMeta? {
        let stmt = try conn.prepare(
            """
            SELECT id, path, title, created_at, updated_at, source, voice_profile_id, body_hash
            FROM documents
            WHERE id = ?
            LIMIT 1;
            """
        )
        try stmt.bind(1, id)
        if try stmt.step() == 100 {
            return decodeMeta(stmt)
        }
        return nil
    }

    public func fetchList(query: String?, tag: String?, limit: Int, offset: Int) throws -> [DocumentMeta] {
        let q = query?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasQuery = !(q ?? "").isEmpty
        let hasTag = !(tag ?? "").isEmpty

        var sql = ""
        if hasTag {
            sql = """
            SELECT d.id, d.path, d.title, d.created_at, d.updated_at, d.source, d.voice_profile_id, d.body_hash
            FROM documents d
            JOIN document_tags dt ON dt.document_id = d.id
            JOIN tags t ON t.id = dt.tag_id
            WHERE t.name = ?
            """
            if hasQuery {
                sql += " AND (d.title LIKE ? OR d.id LIKE ?)"
            }
            sql += " ORDER BY d.updated_at DESC LIMIT ? OFFSET ?;"
        } else {
            sql = """
            SELECT id, path, title, created_at, updated_at, source, voice_profile_id, body_hash
            FROM documents
            """
            if hasQuery {
                sql += " WHERE (title LIKE ? OR id LIKE ?)"
            }
            sql += " ORDER BY updated_at DESC LIMIT ? OFFSET ?;"
        }

        let stmt = try conn.prepare(sql)
        var bindIndex: Int32 = 1
        if hasTag {
            try stmt.bind(bindIndex, tag)
            bindIndex += 1
        }
        if hasQuery {
            let like = "%\(q!)%"
            try stmt.bind(bindIndex, like)
            bindIndex += 1
            try stmt.bind(bindIndex, like)
            bindIndex += 1
        }
        try stmt.bind(bindIndex, Int64(limit))
        bindIndex += 1
        try stmt.bind(bindIndex, Int64(offset))

        var out: [DocumentMeta] = []
        while try stmt.step() == 100 {
            out.append(decodeMeta(stmt))
        }
        return out
    }

    public func setTags(documentId: String, tagNames: [String]) throws {
        let cleaned = tagNames.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let unique = Array(Set(cleaned)).sorted()

        try conn.exec("BEGIN;")
        do {
            let deleteStmt = try conn.prepare("DELETE FROM document_tags WHERE document_id = ?;")
            try deleteStmt.bind(1, documentId)
            _ = try deleteStmt.step()

            let insertTagStmt = try conn.prepare("INSERT INTO tags (id, name) VALUES (?, ?) ON CONFLICT(name) DO NOTHING;")
            let selectTagStmt = try conn.prepare("SELECT id FROM tags WHERE name = ? LIMIT 1;")
            let insertLinkStmt = try conn.prepare("INSERT OR IGNORE INTO document_tags (document_id, tag_id) VALUES (?, ?);")

            for name in unique {
                let tagId = WritingCoachHash.sha256Hex(name)
                insertTagStmt.reset()
                try insertTagStmt.bind(1, tagId)
                try insertTagStmt.bind(2, name)
                _ = try insertTagStmt.step()

                selectTagStmt.reset()
                try selectTagStmt.bind(1, name)
                guard try selectTagStmt.step() == 100 else { continue }
                let resolvedId = selectTagStmt.columnText(0) ?? tagId

                insertLinkStmt.reset()
                try insertLinkStmt.bind(1, documentId)
                try insertLinkStmt.bind(2, resolvedId)
                _ = try insertLinkStmt.step()
            }

            try conn.exec("COMMIT;")
        } catch {
            try conn.exec("ROLLBACK;")
            throw error
        }
    }

    private func decodeMeta(_ stmt: SQLiteStatement) -> DocumentMeta {
        let id = stmt.columnText(0) ?? ""
        let path = stmt.columnText(1) ?? ""
        let title = stmt.columnText(2)
        let createdAt = Date(epochMs: stmt.columnInt64(3) ?? 0)
        let updatedAt = Date(epochMs: stmt.columnInt64(4) ?? 0)
        let source = stmt.columnText(5)
        let voice = stmt.columnText(6)
        let hash = stmt.columnText(7) ?? ""
        return .init(
            id: id,
            path: path,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            source: source,
            voiceProfileId: voice,
            bodyHash: hash
        )
    }
}

private extension Date {
    var epochMs: Int64 { Int64(timeIntervalSince1970 * 1000.0) }
    init(epochMs: Int64) { self = Date(timeIntervalSince1970: Double(epochMs) / 1000.0) }
}
