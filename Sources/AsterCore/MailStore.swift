import Foundation
import CSQLite

/// All SQLite work is serialized off the UI actor. Delta pages and their cursor commit together.
public actor MailStore {
    private var db: OpaquePointer?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public init(path: String) throws {
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw MailError.message("Could not open the local mail cache.") }
        let schema = """
        PRAGMA journal_mode=WAL;
        PRAGMA foreign_keys=ON;
        CREATE TABLE IF NOT EXISTS mail(id TEXT PRIMARY KEY, folder TEXT, thread TEXT, date REAL, payload BLOB);
        CREATE INDEX IF NOT EXISTS mail_folder ON mail(folder,date);
        CREATE INDEX IF NOT EXISTS mail_thread ON mail(thread,date);
        CREATE TABLE IF NOT EXISTS membership(id TEXT REFERENCES mail(id) ON DELETE CASCADE,folder TEXT,PRIMARY KEY(id,folder));
        CREATE INDEX IF NOT EXISTS membership_folder ON membership(folder,id);
        CREATE TABLE IF NOT EXISTS senders(id TEXT PRIMARY KEY REFERENCES mail(id) ON DELETE CASCADE,address TEXT);
        CREATE INDEX IF NOT EXISTS senders_address ON senders(address,id);
        CREATE TABLE IF NOT EXISTS hints(id TEXT PRIMARY KEY REFERENCES mail(id) ON DELETE CASCADE,kind TEXT);
        CREATE TABLE IF NOT EXISTS sync_seen(scope TEXT,id TEXT,PRIMARY KEY(scope,id));
        CREATE TABLE IF NOT EXISTS metadata(key TEXT PRIMARY KEY,value TEXT);
        CREATE TABLE IF NOT EXISTS pending(sequence INTEGER PRIMARY KEY AUTOINCREMENT,id TEXT UNIQUE,payload BLOB);
        CREATE VIRTUAL TABLE IF NOT EXISTS mail_search USING fts5(id UNINDEXED,content,tokenize='unicode61');
        """
        sqlite3_busy_timeout(db, 5000)
        guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else { let e = String(cString: sqlite3_errmsg(db)); sqlite3_close(db); throw MailError.message(e) }
    }
    deinit { sqlite3_close(db) }
    private func run(_ sql: String, _ bindings: [Any] = []) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { throw failure() }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in bindings.enumerated() {
            let index = Int32(offset + 1)
            if let data = value as? Data { _ = data.withUnsafeBytes { sqlite3_bind_blob(stmt, index, $0.baseAddress, Int32(data.count), transient) } }
            else if let number = value as? Double { sqlite3_bind_double(stmt, index, number) }
            else { sqlite3_bind_text(stmt, index, String(describing: value), -1, transient) }
        }
        return stmt
    }
    private func failure() -> MailError { .message(String(cString: sqlite3_errmsg(db))) }
    private func execute(_ sql: String, _ bindings: [Any] = []) throws {
        let stmt = try run(sql, bindings); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_DONE else { throw failure() }
    }
    private func blob<T: Decodable>(_ stmt: OpaquePointer?, column: Int32 = 0) throws -> T {
        let count = Int(sqlite3_column_bytes(stmt, column))
        guard let bytes = sqlite3_column_blob(stmt, column) else { throw MailError.message("Invalid cache record.") }
        return try decoder.decode(T.self, from: Data(bytes: bytes, count: count))
    }
    private func write(_ mail: Mail) throws {
        try execute("INSERT OR REPLACE INTO mail VALUES(?,?,?,?,?)", [mail.id, mail.folderID, mail.threadID, mail.date.timeIntervalSince1970, try encoder.encode(mail)])
        for folder in Set([mail.folderID] + (mail.labelIDs ?? []) + (mail.isFlagged ? ["@starred"] : [])) { try execute("INSERT OR IGNORE INTO membership VALUES(?,?)", [mail.id, folder]) }
        try execute("INSERT OR REPLACE INTO senders VALUES(?,?)", [mail.id, mail.sender.address.lowercased()])
        if let hint = AttentionEngine.classify(mail) { try execute("INSERT OR REPLACE INTO hints VALUES(?,?)", [mail.id, hint.kind.rawValue]) }
        try execute("DELETE FROM mail_search WHERE id=?", [mail.id])
        try execute("INSERT INTO mail_search(id,content) VALUES(?,?)", [mail.id, "\(mail.sender.name) \(mail.sender.address) \(mail.subject) \(mail.preview) \(mail.body)"])
    }
    public func all() throws -> [Mail] { try recent(limit: Int.max) }
    public func recent(limit: Int = 500, folder: String? = nil) throws -> [Mail] {
        let query = folder == nil ? "SELECT payload FROM mail ORDER BY date DESC LIMIT ?" : "SELECT m.payload FROM mail m JOIN membership f ON f.id=m.id WHERE f.folder=? ORDER BY m.date DESC LIMIT ?"
        let stmt = try run(query, folder.map { [$0, String(limit)] } ?? [String(limit)]); defer { sqlite3_finalize(stmt) }
        var result: [Mail] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(try blob(stmt)) }
        return result
    }
    private func priorityPredicate(_ policy: AccountPolicy, folders: [MailFolder]) -> (String, [String]) {
        let inbox = folders.first { $0.role == "inbox" }?.id ?? "inbox"
        let junk = folders.first { $0.role == "junkemail" }?.id ?? "junkemail"
        let excluded = folders.filter { ["sentitems", "drafts", "deleteditems"].contains($0.role ?? "") }.map(\.id)
        var clauses: [String] = [], bindings: [String] = []
        for folder in excluded { clauses.append("NOT EXISTS (SELECT 1 FROM membership f WHERE f.id=m.id AND f.folder=?)"); bindings.append(folder) }
        // Draft state is checked via the folder index; all provider and local drafts are stored in Drafts.
        if policy.junkMode == .separate { clauses.append("NOT EXISTS (SELECT 1 FROM membership f WHERE f.id=m.id AND f.folder=?)"); bindings.append(junk) }
        if policy.priorityMode != .allReceived {
            var allowed = ["EXISTS (SELECT 1 FROM membership f WHERE f.id=m.id AND f.folder=?)"]
            bindings.append(inbox)
            if policy.junkMode != .separate { allowed.append("EXISTS (SELECT 1 FROM membership f WHERE f.id=m.id AND f.folder=?)"); bindings.append(junk) }
            clauses.append("(" + allowed.joined(separator: " OR ") + ")")
        }
        if policy.priorityMode == .important {
            let sent = folders.first { $0.role == "sentitems" }?.id ?? "sentitems"
            var important = ["EXISTS (SELECT 1 FROM hints h WHERE h.id=m.id AND (h.kind!='Needs reply' OR NOT EXISTS (SELECT 1 FROM mail replied JOIN membership rf ON rf.id=replied.id AND rf.folder=? WHERE replied.thread=m.thread AND replied.date>m.date)))", "EXISTS (SELECT 1 FROM membership f WHERE f.id=m.id AND f.folder='@starred')"]
            bindings.append(sent)
            if policy.junkMode != .separate { important.append("EXISTS (SELECT 1 FROM membership f WHERE f.id=m.id AND f.folder=?)"); bindings.append(junk) }
            // Sender addresses are persisted separately, avoiding JSON scans of every message body.
            for sender in policy.prioritySenders.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).filter({ !$0.isEmpty }) {
                important.append("EXISTS (SELECT 1 FROM senders s WHERE s.id=m.id AND s.address=?)"); bindings.append(sender)
            }
            clauses.append("(" + important.joined(separator: " OR ") + ")")
        }
        return (clauses.isEmpty ? "1" : clauses.joined(separator: " AND "), bindings)
    }
    public func priority(policy: AccountPolicy, folders: [MailFolder], limit: Int = 500, search: String = "") throws -> [Mail] {
        let (predicate, values) = priorityPredicate(policy, folders: folders)
        var whereClause = predicate, bindings = values
        let terms = search.split(whereSeparator: { $0.isWhitespace }).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }.joined(separator: " AND ")
        if !terms.isEmpty { whereClause += " AND m.id IN (SELECT id FROM mail_search WHERE mail_search MATCH ?)"; bindings.append(terms) }
        bindings.append(String(limit))
        let stmt = try run("SELECT m.payload FROM mail m WHERE " + whereClause + " ORDER BY m.date DESC LIMIT ?", bindings); defer { sqlite3_finalize(stmt) }
        var result: [Mail] = []; while sqlite3_step(stmt) == SQLITE_ROW { let mail: Mail = try blob(stmt); if !mail.isDraft { result.append(mail) } }; return result
    }
    public func priorityCount(policy: AccountPolicy, folders: [MailFolder]) throws -> Int {
        let (predicate, bindings) = priorityPredicate(policy, folders: folders)
        let stmt = try run("SELECT COUNT(*) FROM mail m WHERE " + predicate, bindings); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw failure() }; return Int(sqlite3_column_int64(stmt, 0))
    }
    public func search(_ query: String, folder: String? = nil) throws -> Set<String> {
        let terms = query.split(whereSeparator: { $0.isWhitespace }).map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }.joined(separator: " AND ")
        guard !terms.isEmpty else { return [] }
        let query = "SELECT id FROM mail_search WHERE mail_search MATCH ?" + (folder == nil ? "" : " AND id IN (SELECT id FROM membership WHERE folder=?)")
        let stmt = try run(query, folder.map { [terms, $0] } ?? [terms]); defer { sqlite3_finalize(stmt) }
        var ids: Set<String> = []
        while sqlite3_step(stmt) == SQLITE_ROW { ids.insert(String(cString: sqlite3_column_text(stmt, 0))) }
        return ids
    }
    public func metadata(_ key: String) throws -> String? {
        let stmt = try run("SELECT value FROM metadata WHERE key=?", [key]); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        let value = String(cString: sqlite3_column_text(stmt, 0)); return value.isEmpty ? nil : value
    }
    public func setMetadata(_ key: String, _ value: String) throws { try execute("INSERT OR REPLACE INTO metadata VALUES(?,?)", [key,value]) }
    public func changes() throws -> [PendingChange] {
        let stmt = try run("SELECT payload FROM pending ORDER BY sequence"); defer { sqlite3_finalize(stmt) }
        var result: [PendingChange] = []
        while sqlite3_step(stmt) == SQLITE_ROW { result.append(try blob(stmt)) }
        return result
    }
    public func queue(_ change: PendingChange, mail: Mail) throws {
        try transaction {
            try execute("INSERT INTO pending(id,payload) VALUES(?,?)", [change.id, try encoder.encode(change)])
            var current = try message(mail.id) ?? mail
            change.apply(to: &current); try write(current)
        }
    }
    public func applyLocal(_ change: PendingChange, fallback: Mail) throws {
        var current = try message(fallback.id) ?? fallback
        change.apply(to: &current); try transaction { try write(current) }
    }
    public func message(_ id: String) throws -> Mail? {
        let stmt = try run("SELECT payload FROM mail WHERE id=?", [id]); defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) == SQLITE_ROW ? try blob(stmt) : nil
    }
    public func complete(_ change: PendingChange) throws { try execute("DELETE FROM pending WHERE id=?", [change.id]) }
    public func save(_ mail: Mail) throws { try transaction { try write(mail) } }
    public func remove(_ id: String) throws {
        try execute("DELETE FROM mail WHERE id=?", [id]); try execute("DELETE FROM mail_search WHERE id=?", [id])
    }
    public func applyPage(_ mails: [Mail], removed: [String], folder: String, cursor: String) throws {
        let pending = try changes()
        try transaction {
            // A tombstone is folder-scoped: a move's source-folder delta must not erase its destination copy.
            for id in removed {
                let stmt = try run("SELECT folder FROM mail WHERE id=?", [id]); defer { sqlite3_finalize(stmt) }
                if sqlite3_step(stmt) == SQLITE_ROW, String(cString: sqlite3_column_text(stmt, 0)) == folder,
                   !pending.contains(where: { $0.messageID == id }) { try remove(id) }
            }
            for var mail in mails {
                for change in pending where change.messageID == mail.id { change.apply(to: &mail) }
                try write(mail)
                if try metadata("snapshot:" + folder) != nil { try execute("INSERT OR IGNORE INTO sync_seen VALUES(?,?)", [folder, mail.id]) }
            }
            try setMetadata("delta:\(folder)", cursor)
        }
    }
    /// Called only after Graph expires a delta cursor. Other folders and unsynced edits remain intact.
    public func resetFolder(_ folder: String) throws {
        let pendingIDs = Set(try changes().map(\.messageID))
        try transaction { for mail in try all() where mail.folderID == folder && !pendingIDs.contains(mail.id) { try remove(mail.id) }; try execute("DELETE FROM metadata WHERE key=?", ["delta:\(folder)"]) }
    }
    public func upgradeIndexes() throws {
        guard try metadata("indexes:v3") == nil else { return }
        let existing = try all()
        try transaction { for mail in existing { try write(mail) }; try setMetadata("indexes:v3", "1") }
    }
    public func attention(inbox: String, sent: String, limit: Int = 500) throws -> [AttentionItem] {
        let query = """
        SELECT m.payload,h.kind FROM mail m
        JOIN membership f ON f.id=m.id AND f.folder=? JOIN hints h ON h.id=m.id
        WHERE NOT EXISTS (SELECT 1 FROM mail newer JOIN membership nf ON nf.id=newer.id AND nf.folder=? WHERE newer.thread=m.thread AND newer.date>m.date)
        AND (h.kind!=? OR NOT EXISTS (SELECT 1 FROM mail replied JOIN membership rf ON rf.id=replied.id AND rf.folder=? WHERE replied.thread=m.thread AND replied.date>m.date))
        ORDER BY CASE h.kind WHEN 'Security' THEN 0 WHEN 'Deadline' THEN 1 WHEN 'Needs reply' THEN 2 ELSE 3 END,m.date DESC LIMIT ?
        """
        let stmt = try run(query, [inbox, inbox, AttentionKind.reply.rawValue, sent, String(limit)]); defer { sqlite3_finalize(stmt) }
        var items: [AttentionItem] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let mail: Mail = try blob(stmt)
            if let kind = AttentionKind(rawValue: String(cString: sqlite3_column_text(stmt, 1))) { items.append(AttentionItem(mail: mail, kind: kind, detail: mail.preview)) }
        }
        return items
    }
    public func count(folder: String? = nil) throws -> Int {
        let stmt = try run(folder == nil ? "SELECT COUNT(*) FROM mail" : "SELECT COUNT(*) FROM membership WHERE folder=?", folder.map { [$0] } ?? []); defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { throw failure() }; return Int(sqlite3_column_int64(stmt, 0))
    }
    public func thread(_ id: String) throws -> [Mail] {
        let stmt = try run("SELECT payload FROM mail WHERE thread=? ORDER BY date", [id]); defer { sqlite3_finalize(stmt) }
        var mails: [Mail] = []; while sqlite3_step(stmt) == SQLITE_ROW { mails.append(try blob(stmt)) }; return mails
    }
    public func matching(_ ids: Set<String>, limit: Int = 1000) throws -> [Mail] {
        // Chunk IDs to remain below older SQLite bind-variable limits.
        var result: [Mail] = []; let values = Array(ids)
        for offset in stride(from: 0, to: values.count, by: 500) {
            let chunk = Array(values[offset..<min(offset + 500, values.count)])
            let stmt = try run("SELECT payload FROM mail WHERE id IN (" + Array(repeating: "?", count: chunk.count).joined(separator: ",") + ")", chunk)
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW { result.append(try blob(stmt)) }
        }
        return Array(result.sorted { $0.date > $1.date }.prefix(limit))
    }
    public func saveDraft(_ mail: Mail, context: String) throws {
        try transaction { try write(mail); try setMetadata("draft:" + mail.id, context) }
    }
    public func beginSnapshot(_ scope: String) throws {
        try transaction { try execute("DELETE FROM sync_seen WHERE scope=?", [scope]); try setMetadata("snapshot:" + scope, "1") }
    }
    public func finishSnapshot(_ scope: String, folder: String?, metadata: [String: String] = [:]) throws {
        guard try self.metadata("snapshot:" + scope) != nil else { return }
        let protected = Set(try changes().map(\.messageID))
        let sql = "SELECT payload FROM mail WHERE id NOT IN (SELECT id FROM sync_seen WHERE scope=?)" + (folder == nil ? "" : " AND folder=?")
        let stmt = try run(sql, folder.map { [scope, $0] } ?? [scope]); defer { sqlite3_finalize(stmt) }
        var obsolete: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW { let mail: Mail = try blob(stmt); if !protected.contains(mail.id) && !mail.id.hasPrefix("local-") { obsolete.append(mail.id) } }
        try transaction {
            for id in obsolete { try remove(id) }
            for (key, value) in metadata { try setMetadata(key, value) }
            try execute("DELETE FROM sync_seen WHERE scope=?", [scope]); try execute("DELETE FROM metadata WHERE key=?", ["snapshot:" + scope])
        }
    }
    public func applyMailboxPage(_ mails: [Mail], removed: [String], snapshot: Bool, metadata: [String: String]) throws {
        let pending = try changes(); let protected = Set(pending.map(\.messageID))
        try transaction {
            for id in removed where !protected.contains(id) { try remove(id) }
            for var mail in mails {
                for change in pending where change.messageID == mail.id { change.apply(to: &mail) }; try write(mail)
                if snapshot { try execute("INSERT OR IGNORE INTO sync_seen VALUES(?,?)", ["gmail", mail.id]) }
            }
            for (key, value) in metadata { try setMetadata(key, value) }
        }
    }
    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") } catch { try? execute("ROLLBACK"); throw error }
    }
}
