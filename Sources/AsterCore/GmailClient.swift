import Foundation

public struct GmailFailure: LocalizedError {
    public let status: Int
    public let detail: String
    public var errorDescription: String? { "Gmail (\(status)): \(detail)" }
}
public struct GmailMessage: Decodable, Sendable {
    public struct Header: Decodable, Sendable { public var name: String; public var value: String }
    public struct Part: Decodable, Sendable {
        public struct Body: Decodable, Sendable { public var attachmentId: String?; public var size: Int?; public var data: String? }
        public var partId: String?
        public var mimeType: String?
        public var filename: String?
        public var headers: [Header]?
        public var body: Body?
        public var parts: [Part]?
        public var flattened: [Part] { [self] + (parts ?? []).flatMap(\.flattened) }
    }
    public var id: String
    public var threadId: String?
    public var labelIds: [String]?
    public var snippet: String?
    public var internalDate: String?
    public var payload: Part?
    public func header(_ name: String) -> String? { payload?.headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value }
    public func mail() -> Mail {
        let labels = labelIds ?? []
        let parts = payload?.flattened ?? []
        let html = parts.first { $0.mimeType == "text/html" && ($0.filename ?? "").isEmpty && $0.body?.data != nil }
        let text = parts.first { $0.mimeType == "text/plain" && ($0.filename ?? "").isEmpty && $0.body?.data != nil }
        let preferred = html ?? text
        let content = preferred?.body?.data.flatMap(Base64URL.decode).flatMap { String(data: $0, encoding: .utf8) } ?? snippet ?? ""
        var mail = Mail(id: id, threadID: threadId, folderID: Self.primaryFolder(labels), sender: AddressParser.parse(header("From") ?? "Unknown").first ?? Address("Unknown", ""), to: AddressParser.parse(header("To") ?? ""), cc: AddressParser.parse(header("Cc") ?? ""), replyTo: AddressParser.parse(header("Reply-To") ?? ""), subject: MIME.decodeHeader(header("Subject") ?? "(No subject)"), preview: MIME.decodeEntities(snippet ?? ""), body: content, isHTML: html != nil, date: Date(timeIntervalSince1970: (Double(internalDate ?? "0") ?? 0) / 1000), isRead: !labels.contains("UNREAD"), isFlagged: labels.contains("STARRED"), isDraft: labels.contains("DRAFT"), hasAttachments: parts.contains { !($0.filename ?? "").isEmpty })
        mail.bcc = AddressParser.parse(header("Bcc") ?? ""); mail.labelIDs = labels; mail.internetMessageID = header("Message-ID"); mail.references = header("References")
        return mail
    }
    public static func primaryFolder(_ labels: [String]) -> String { ["TRASH", "SPAM", "DRAFT", "SENT", "INBOX"].first { labels.contains($0) } ?? "archive" }
}
public enum Base64URL {
    public static func encode(_ data: Data) -> String { data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "") }
    public static func decode(_ string: String) -> Data? {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
public struct GmailClient: MailBackend {
    public let name = "Gmail"
    let tokens: any TokenProvider
    let session: URLSession
    public init(tokens: any TokenProvider, session: URLSession = HTTPTransport.session) { self.tokens = tokens; self.session = session }
    public func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        guard let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me" + path), url.host == "gmail.googleapis.com", url.scheme == "https", !path.contains("..") else { throw MailError.message("Invalid Gmail API URL.") }
        var request = URLRequest(url: url); request.httpMethod = method
        request.setValue("Bearer \(try await tokens.token())", forHTTPHeaderField: "Authorization")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        var (data, http) = try await HTTPTransport.execute(request, session: session)
        if http.statusCode == 401 {
            request.setValue("Bearer \(try await tokens.freshToken())", forHTTPHeaderField: "Authorization")
            (data, http) = try await HTTPTransport.execute(request, session: session)
        }
        guard (200...299).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            throw GmailFailure(status: http.statusCode, detail: (object?["error"] as? [String: Any])?["message"] as? String ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        return data
    }
    public struct Profile: Decodable, Sendable { public let emailAddress: String; public let historyId: String }
    public func profile() async throws -> Profile { try JSONDecoder().decode(Profile.self, from: await request("/profile")) }
    public func folders() async throws -> [MailFolder] {
        struct Label: Decodable { var id: String; var name: String; var type: String }
        struct Labels: Decodable { var labels: [Label] }
        let labels = try JSONDecoder().decode(Labels.self, from: await request("/labels")).labels
        let roles = ["INBOX": "inbox", "DRAFT": "drafts", "SENT": "sentitems", "TRASH": "deleteditems", "SPAM": "junkemail"]
        var folders = labels.filter { roles[$0.id] != nil || $0.type == "user" }.map { label in MailFolder(id: label.id, name: roles[label.id] == nil ? label.name : ["INBOX": "Inbox", "DRAFT": "Drafts", "SENT": "Sent", "TRASH": "Trash", "SPAM": "Junk"][label.id]!, role: roles[label.id]) }
        folders.append(MailFolder(id: "archive", name: "Archive", role: "archive"))
        return folders
    }
    public func message(_ id: String) async throws -> GmailMessage { try JSONDecoder().decode(GmailMessage.self, from: await request("/messages/\(GraphClient.component(id))?format=full")) }
    struct Ref: Decodable, Sendable { var id: String }
    struct List: Decodable { var messages: [Ref]?; var nextPageToken: String? }
    struct HistoryPage: Decodable {
        struct Change: Decodable { var message: Ref }
        struct History: Decodable { var messages: [Ref]?; var messagesAdded: [Change]?; var messagesDeleted: [Change]?; var labelsAdded: [Change]?; var labelsRemoved: [Change]? }
        var history: [History]?; var nextPageToken: String?; var historyId: String
    }
    private func cacheDraftIdentifiers(_ store: MailStore) async throws {
        struct DraftReference: Decodable { var id: String; var message: Ref }
        struct Page: Decodable { var drafts: [DraftReference]?; var nextPageToken: String? }
        var token: String?
        repeat {
            let suffix = token.map { "&pageToken=" + GraphClient.component($0) } ?? ""
            let page = try JSONDecoder().decode(Page.self, from: await request("/drafts?maxResults=500" + suffix))
            for draft in page.drafts ?? [] { try await store.setMetadata("gmailDraft:" + draft.message.id, draft.id) }
            token = page.nextPageToken
        } while token != nil
    }
    public func synchronize(store: MailStore, folders: [MailFolder], progress: @escaping @Sendable () async -> Void) async throws {
        try await cacheDraftIdentifiers(store)
        if let cursor = try await store.metadata("gmailHistory") {
            do { try await history(cursor, store: store, progress: progress); return }
            catch let failure as GmailFailure where failure.status == 404 { /* expired history: full reconciliation, cache stays visible */ }
        }
        var start: String
        if let saved = try await store.metadata("gmailSnapshotStart") { start = saved }
        else { start = try await profile().historyId; try await store.beginSnapshot("gmail"); try await store.setMetadata("gmailSnapshotStart", start) }
        var pageToken = try await store.metadata("gmailPage")
        var resetPageToken = false
        while true {
            try Task.checkCancellation()
            let suffix = pageToken.map { "&pageToken=" + GraphClient.component($0) } ?? ""
            let page: List
            do { page = try JSONDecoder().decode(List.self, from: await request("/messages?maxResults=100&includeSpamTrash=true" + suffix)) }
            catch let failure as GmailFailure where failure.status == 400 && pageToken != nil && !resetPageToken {
                start = try await profile().historyId; try await store.beginSnapshot("gmail")
                try await store.setMetadata("gmailSnapshotStart", start); try await store.setMetadata("gmailPage", "")
                pageToken = nil; resetPageToken = true; continue
            }
            let result = try await fetch(Set((page.messages ?? []).map(\.id)))
            try await store.applyMailboxPage(result.mails, removed: result.removed, snapshot: true, metadata: ["gmailPage": page.nextPageToken ?? ""])
            await progress(); pageToken = page.nextPageToken
            if pageToken == nil { break }
        }
        try await store.finishSnapshot("gmail", folder: nil, metadata: ["gmailHistory": start, "gmailSnapshotStart": "", "gmailPage": ""])
        try await history(start, store: store, progress: progress)
    }
    private func history(_ start: String, store: MailStore, progress: @escaping @Sendable () async -> Void) async throws {
        var pageToken: String?
        repeat {
            let suffix = pageToken.map { "&pageToken=" + GraphClient.component($0) } ?? ""
            let page = try JSONDecoder().decode(HistoryPage.self, from: await request("/history?startHistoryId=\(GraphClient.component(start))&maxResults=100" + suffix))
            let records = page.history ?? []
            let deleted = Set(records.flatMap { $0.messagesDeleted ?? [] }.map { $0.message.id })
            var changed: Set<String> = []
            for record in records {
                changed.formUnion((record.messages ?? []).map(\.id))
                changed.formUnion((record.messagesAdded ?? []).map { $0.message.id })
                changed.formUnion((record.labelsAdded ?? []).map { $0.message.id })
                changed.formUnion((record.labelsRemoved ?? []).map { $0.message.id })
            }
            // Fetch current state even for delete records: messages can appear in multiple records in one page.
            let result = try await fetch(changed.union(deleted))
            try await store.applyMailboxPage(result.mails, removed: result.removed, snapshot: false, metadata: page.nextPageToken == nil ? ["gmailHistory": page.historyId] : [:])
            await progress(); pageToken = page.nextPageToken
        } while pageToken != nil
    }
    private func fetch(_ ids: Set<String>) async throws -> (mails: [Mail], removed: [String]) {
        var mails: [Mail] = [], removed: [String] = []
        let values = Array(ids)
        // Bound requests to six, rather than spawning a task for every item in a large history page.
        for offset in stride(from: 0, to: values.count, by: 6) {
            try await withThrowingTaskGroup(of: (String, Mail?).self) { group in
                for id in values[offset..<min(offset + 6, values.count)] {
                    group.addTask { do { return (id, try await message(id).mail()) } catch let failure as GmailFailure where failure.status == 404 { return (id, nil) } }
                }
                for try await (id, mail) in group { if let mail { mails.append(mail) } else { removed.append(id) } }
            }
        }
        return (mails, removed)
    }
    public func apply(_ change: PendingChange) async throws {
        var add: [String] = [], remove: [String] = []
        switch change.kind {
        case "read": if change.value == "true" { remove = ["UNREAD"] } else { add = ["UNREAD"] }
        case "flag": if change.value == "true" { add = ["STARRED"] } else { remove = ["STARRED"] }
        case "move": remove = ["INBOX", "TRASH", "SPAM"].filter { $0 != change.value }; if change.value != "archive" { add = [change.value] }
        default: throw MailError.message("Unsupported Gmail operation.")
        }
        _ = try await request("/messages/\(GraphClient.component(change.messageID))/modify", method: "POST", body: ["addLabelIds": add, "removeLabelIds": remove])
    }
    struct Draft: Decodable { var id: String; var message: GmailMessage }
    public func saveDraft(_ mail: Mail, remoteID: String?, sourceID: String?, mode: String) async throws -> SavedDraft {
        let original = try await sourceID.mapAsync { try await message($0) }
        let existing: GmailMessage?
        if let remoteID {
            let draft = try JSONDecoder().decode(Draft.self, from: await request("/drafts/" + GraphClient.component(remoteID)))
            existing = try await message(draft.message.id)
        } else { existing = mode == "forward" ? original : nil }
        let preserved = try await collectAttachments(existing)
        let raw = try MIME.encode(mail, replyingTo: mode == "forward" ? nil : original?.mail(), attachments: preserved)
        var payload: [String: Any] = ["raw": Base64URL.encode(raw)]
        if mode != "forward", let original { payload["threadId"] = original.threadId }
        else if mode != "forward", let message = existing {
            payload["threadId"] = message.threadId
            var contextual = mail; contextual.internetMessageID = message.header("In-Reply-To"); contextual.references = message.header("References")
            // Carry reply headers through a draft replacement; Gmail PUT replaces the entire MIME message.
            if let parent = contextual.internetMessageID { var reference = mail; reference.internetMessageID = parent; reference.references = contextual.references; payload["raw"] = Base64URL.encode(try MIME.encode(mail, replyingTo: reference, attachments: preserved)) }
        }
        let draft = try JSONDecoder().decode(Draft.self, from: await request(remoteID.map { "/drafts/" + GraphClient.component($0) } ?? "/drafts", method: remoteID == nil ? "POST" : "PUT", body: ["message": payload]))
        // Draft responses can contain only an ID; retrieve the full MIME tree and preserve local reply context.
        var saved = try await message(draft.message.id).mail(); saved.isDraft = true
        return SavedDraft(mail: saved, draftID: draft.id)
    }
    private func collectAttachments(_ message: GmailMessage?) async throws -> [OutgoingAttachment] {
        guard let message else { return [] }
        var files: [OutgoingAttachment] = [], total = 0
        for part in message.payload?.flattened ?? [] where !(part.filename ?? "").isEmpty {
            total += part.body?.size ?? 0
            guard total <= 20_000_000 else { throw MailError.message("The existing draft’s attachments exceed the 20 MB total limit. They have been preserved on Gmail.") }
            let data: Data
            if let encoded = part.body?.data, let bytes = Base64URL.decode(encoded) { data = bytes }
            else if let id = part.body?.attachmentId { data = try await attachmentData(message.id, id) }
            else { throw MailError.message("An existing attachment could not be preserved. The Gmail draft was left intact.") }
            let contentID = part.headers?.first { $0.name.lowercased() == "content-id" }?.value.trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
            files.append(OutgoingAttachment(id: contentID?.hasPrefix("aster-") == true ? String(contentID!.dropFirst(6)) : UUID().uuidString, name: part.filename ?? "Attachment", contentType: part.mimeType ?? "application/octet-stream", data: data))
        }
        return files
    }
    public func addAttachments(_ files: [OutgoingAttachment], to draft: SavedDraft) async throws -> SavedDraft {
        guard !files.isEmpty else { return draft }
        let value = try JSONDecoder().decode(Draft.self, from: await request("/drafts/" + GraphClient.component(draft.draftID)))
        let message = try await self.message(value.message.id)
        let existing = try await collectAttachments(message)
        let ids = Set(existing.map(\.id))
        var original = message.mail(); original.internetMessageID = message.header("In-Reply-To")
        let raw = try MIME.encode(message.mail(), replyingTo: original.internetMessageID == nil ? nil : original, attachments: existing + files.filter { !ids.contains($0.id) })
        var payload: [String: Any] = ["raw": Base64URL.encode(raw)]
        if let thread = message.threadId { payload["threadId"] = thread }
        let updated = try JSONDecoder().decode(Draft.self, from: await request("/drafts/" + GraphClient.component(draft.draftID), method: "PUT", body: ["message": payload]))
        return SavedDraft(mail: try await self.message(updated.message.id).mail(), draftID: updated.id)
    }
    public func sendDraft(_ id: String) async throws { _ = try await request("/drafts/send", method: "POST", body: ["id": id]) }
    public func attachments(_ mailID: String) async throws -> [Attachment] {
        let value = try await message(mailID)
        return (value.payload?.flattened ?? []).filter { !($0.filename ?? "").isEmpty }.map {
            Attachment(id: $0.body?.attachmentId ?? "part:" + ($0.partId ?? ""), name: $0.filename ?? "Attachment", size: $0.body?.size ?? 0, contentType: $0.mimeType, contentBytes: nil, isInline: $0.headers?.contains { $0.name.lowercased() == "content-disposition" && $0.value.lowercased().hasPrefix("inline") })
        }
    }
    public func attachmentData(_ mailID: String, _ attachmentID: String) async throws -> Data {
        if attachmentID.hasPrefix("part:") {
            let part = try await message(mailID).payload?.flattened.first { $0.partId == String(attachmentID.dropFirst(5)) }
            guard let string = part?.body?.data, let data = Base64URL.decode(string) else { throw MailError.message("Attachment content is unavailable.") }; return data
        }
        struct Body: Decodable { var data: String }
        let value = try JSONDecoder().decode(Body.self, from: await request("/messages/\(GraphClient.component(mailID))/attachments/\(GraphClient.component(attachmentID))"))
        guard let data = Base64URL.decode(value.data) else { throw MailError.message("Invalid attachment encoding.") }; return data
    }
}
private extension Optional where Wrapped == String {
    func mapAsync<T>(_ transform: (String) async throws -> T) async rethrows -> T? { guard let value = self else { return nil }; return try await transform(value) }
}
