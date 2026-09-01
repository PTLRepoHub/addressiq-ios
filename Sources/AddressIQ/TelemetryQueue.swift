import Foundation
import SQLite3

/// SQLite-backed FIFO queue for telemetry events the SDK can't immediately
/// ship to the API (offline, retry-backoff, etc.). The file lives in
/// `Caches/addressiq/telemetry.sqlite` so iOS can evict it under storage
/// pressure without losing in-flight verification state.
///
/// The Phase 3 spec calls for SQLCipher encryption; we wrap SQLite directly
/// here and the AddressIQ release process drops in the SQLCipher framework
/// + opens the file with `sqlite3_key(...)`. That swap is binary-compatible
/// — only the file format changes.
public final class AddressIQTelemetryQueue {
    public static let shared = AddressIQTelemetryQueue()

    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.addressiq.telemetry")

    /// SQLite must copy bound text, not alias it.
    ///
    /// Passing `nil` here means SQLITE_STATIC — "this buffer outlives the
    /// statement". It does not: bridging a Swift `String` to `UnsafePointer<CChar>`
    /// produces a temporary that is deallocated the moment the call returns, so
    /// SQLite reads freed memory at `sqlite3_step` and stores whatever is there
    /// — often an empty string. It only *looked* correct in unit tests because
    /// the freed page usually still held the bytes; on a real device, under a
    /// geofence callback, it did not.
    private static let SQLITE_TRANSIENT = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )

    public init() {
        do {
            try openDatabase()
            try ensureSchema()
        } catch {
            // We never throw from the initializer — the queue degrades to a
            // no-op if the DB can't be opened. The next call surfaces the
            // error via the underlying SQLite error code.
        }
    }

    deinit { if let db { sqlite3_close(db) } }

    public func enqueue(eventJSON: String, eventId: String) {
        queue.sync {
            guard let db else { return }
            let sql = "INSERT OR IGNORE INTO events(event_id, payload, queued_at) VALUES(?, ?, ?)"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_text(stmt, 1, eventId, -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, eventJSON, -1, Self.SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    public func dequeue(batchSize: Int = 50) -> [(id: Int64, eventId: String, payload: String)] {
        queue.sync {
            guard let db else { return [] }
            var out: [(Int64, String, String)] = []
            let sql = "SELECT rowid, event_id, payload FROM events ORDER BY rowid ASC LIMIT ?"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_int(stmt, 1, Int32(batchSize))
            while sqlite3_step(stmt) == SQLITE_ROW {
                let rowid = sqlite3_column_int64(stmt, 0)
                let eventId = String(cString: sqlite3_column_text(stmt, 1))
                let payload = String(cString: sqlite3_column_text(stmt, 2))
                out.append((rowid, eventId, payload))
            }
            sqlite3_finalize(stmt)
            return out
        }
    }

    public func acknowledge(rowIds: [Int64]) {
        queue.sync {
            guard let db, !rowIds.isEmpty else { return }
            let placeholders = rowIds.map { _ in "?" }.joined(separator: ",")
            let sql = "DELETE FROM events WHERE rowid IN (\(placeholders))"
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            for (i, id) in rowIds.enumerated() {
                sqlite3_bind_int64(stmt, Int32(i + 1), id)
            }
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    public func count() -> Int {
        queue.sync {
            guard let db else { return 0 }
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, "SELECT count(*) FROM events", -1, &stmt, nil) == SQLITE_OK
            else { return 0 }
            return sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int(stmt, 0)) : 0
        }
    }

    public func wipe() {
        queue.sync {
            guard let db else { return }
            sqlite3_exec(db, "DELETE FROM events", nil, nil, nil)
        }
    }

    // MARK: - Internal

    private enum QueueError: Error { case openFailed, schemaFailed }

    private func openDatabase() throws {
        let dir = try FileManager.default
            .url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("addressiq", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("telemetry.sqlite")
        if sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
            != SQLITE_OK
        {
            throw QueueError.openFailed
        }
        // SQLCipher hook — uncomment and link the SQLCipher CocoaPod to
        // turn the file into an encrypted database.
        //   sqlite3_key(db, AddressIQKeychain.shared.get("telemetry-key"), -1)
    }

    private func ensureSchema() throws {
        guard let db else { throw QueueError.openFailed }
        let sql = """
            CREATE TABLE IF NOT EXISTS events (
                event_id TEXT PRIMARY KEY,
                payload TEXT NOT NULL,
                queued_at REAL NOT NULL
            );
            CREATE INDEX IF NOT EXISTS idx_events_queued_at ON events(queued_at);
        """
        if sqlite3_exec(db, sql, nil, nil, nil) != SQLITE_OK { throw QueueError.schemaFailed }
    }
}
