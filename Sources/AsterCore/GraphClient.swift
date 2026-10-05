import Foundation

public protocol TokenProvider: Sendable {
    func token() async throws -> String
    func freshToken() async throws -> String
}
public extension TokenProvider { func freshToken() async throws -> String { try await token() } }
public struct GraphMessage: Decodable, Sendable {
    public struct Recipient: Decodable, Sendable { var emailAddress: Email; struct Email: Decodable, Sendable { var name: String?; var address: String? } }
    struct Body: Decodable, Sendable { var contentType: String; var content: String }
    struct Flag: Decodable, Sendable { var flagStatus: String }
    public var id: String
    var conversationId: String?
    var parentFolderId: String?
    var from: Recipient?
    var toRecipients: [Recipient]?
    var ccRecipients: [Recipient]?
    var bccRecipients: [Recipient]?
    var replyTo: [Recipient]?
    var subject: String?
    var bodyPreview: String?
    var body: Body?
    var receivedDateTime: String?
    var isRead: Bool?
    var isDraft: Bool?
    var hasAttachments: Bool?
    var flag: Flag?
    var removed: Removed?
    struct Removed: Decodable, Sendable { var reason: String? }
    enum CodingKeys: String, CodingKey { case id, conversationId, parentFolderId, from, toRecipients, ccRecipients, bccRecipients, replyTo, subject, bodyPreview, body, receivedDateTime, isRead, isDraft, hasAttachments, flag; case removed = "@removed" }
    public var isRemoved: Bool { removed != nil }
    public func mail(folder: String) -> Mail {
        func address(_ value: Recipient) -> Address { Address(value.emailAddress.name ?? value.emailAddress.address ?? "Unknown", value.emailAddress.address ?? "") }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = receivedDateTime.flatMap { formatter.date(from: $0) } ?? receivedDateTime.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        var mapped = Mail(id: id, threadID: conversationId, folderID: parentFolderId ?? folder, sender: from.map(address) ?? Address("You", ""), to: (toRecipients ?? []).map(address), cc: (ccRecipients ?? []).map(address), replyTo: (replyTo ?? []).map(address), subject: subject ?? "(No subject)", preview: bodyPreview ?? "", body: body?.content ?? bodyPreview ?? "", isHTML: body?.contentType.lowercased() == "html", date: date, isRead: isRead ?? false, isFlagged: flag?.flagStatus == "flagged", isDraft: isDraft ?? false, hasAttachments: hasAttachments ?? false)
        mapped.bcc = (bccRecipients ?? []).map(address); return mapped
    }
}
public struct GraphPage: Decodable, Sendable {
    public var value: [GraphMessage]
    public var next: String?
    public var delta: String?
    enum CodingKeys: String, CodingKey { case value; case next = "@odata.nextLink"; case delta = "@odata.deltaLink" }
}
public struct Attachment: Decodable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var size: Int
    public var contentType: String?
    public var contentBytes: String?
    public var contentId: String? = nil
    public var isInline: Bool?
}
public struct GraphFailure: LocalizedError {
    public let status: Int
    public let detail: String
    public var errorDescription: String? { "Microsoft Graph (\(status)): \(detail)" }
}
public struct GraphClient: Sendable {
    let tokens: any TokenProvider
    let session: URLSession
    public init(tokens: any TokenProvider, session: URLSession = HTTPTransport.session) { self.tokens = tokens; self.session = session }
    public static func component(_ value: String) -> String { value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value }
    public func request(_ path: String, method: String = "GET", body: [String: Any]? = nil) async throws -> Data {
        let url = URL(string: path.hasPrefix("https://") ? path : "https://graph.microsoft.com/v1.0" + path)
        // Delta URLs and API credentials are never allowed to escape Microsoft's Graph host.
        guard let url, url.scheme == "https", url.host == "graph.microsoft.com", url.user == nil, url.port == nil else { throw MailError.message("Invalid Graph URL.") }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.timeoutInterval = 40
        request.setValue("Bearer \(try await tokens.token())", forHTTPHeaderField: "Authorization")
        request.setValue("IdType=\"ImmutableId\"", forHTTPHeaderField: "Prefer")
        if let body { request.httpBody = try JSONSerialization.data(withJSONObject: body); request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        var (data, http) = try await HTTPTransport.execute(request, session: session)
        if http.statusCode == 401 {
            request.setValue("Bearer \(try await tokens.freshToken())", forHTTPHeaderField: "Authorization")
            (data, http) = try await HTTPTransport.execute(request, session: session)
        }
        guard (200...299).contains(http.statusCode) else {
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let detail = (object?["error"] as? [String: Any])?["message"] as? String ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw GraphFailure(status: http.statusCode, detail: detail)
        }
        return data
    }
    public func folders() async throws -> [MailFolder] {
        struct Folder: Decodable { var id: String; var displayName: String; var childFolderCount: Int? }
        struct Page: Decodable { var value: [Folder]; var next: String?; enum CodingKeys: String, CodingKey { case value; case next = "@odata.nextLink" } }
        var result: [MailFolder] = []
        var paths = ["/me/mailFolders?$top=100"]
        while !paths.isEmpty {
            let page = try JSONDecoder().decode(Page.self, from: await request(paths.removeFirst()))
            for folder in page.value { result.append(MailFolder(id: folder.id, name: folder.displayName)); if (folder.childFolderCount ?? 0) > 0 { paths.append("/me/mailFolders/\(Self.component(folder.id))/childFolders?$top=100") } }
            if let next = page.next { paths.append(next) }
        }
        for role in ["inbox", "drafts", "sentitems", "archive", "deleteditems", "junkemail"] {
            let known = try JSONDecoder().decode(Folder.self, from: await request("/me/mailFolders/\(role)"))
            if let index = result.firstIndex(where: { $0.id == known.id }) { result[index].role = role }
        }
        return result
    }
    public func delta(folder: String, cursor: String?) async throws -> GraphPage {
        let select = "id,conversationId,parentFolderId,from,toRecipients,ccRecipients,bccRecipients,replyTo,subject,bodyPreview,body,receivedDateTime,isRead,isDraft,hasAttachments,flag"
        return try JSONDecoder().decode(GraphPage.self, from: await request(cursor ?? "/me/mailFolders/\(Self.component(folder))/messages/delta?$select=\(select)&$top=100"))
    }
    public func apply(_ change: PendingChange) async throws {
        let path = "/me/messages/\(Self.component(change.messageID))"
        switch change.kind {
        case "read": _ = try await request(path, method: "PATCH", body: ["isRead": change.value == "true"])
        case "flag": _ = try await request(path, method: "PATCH", body: ["flag": ["flagStatus": change.value == "true" ? "flagged" : "notFlagged"]])
        case "move":
            let current = try JSONDecoder().decode(GraphMessage.self, from: await request(path + "?$select=id,parentFolderId"))
            if current.parentFolderId != change.value { _ = try await request(path + "/move", method: "POST", body: ["destinationId": change.value]) }
        default: throw MailError.message("Unsupported queued operation.")
        }
    }
    public func saveDraft(_ mail: Mail, remoteID: String?, sourceID: String?, mode: String) async throws -> Mail {
        func recipients(_ values: [Address]) -> [[String: Any]] { values.map { ["emailAddress": ["address": $0.address, "name": $0.name]] } }
        var id = remoteID
        if id == nil, let sourceID {
            let action = mode == "forward" ? "createForward" : mode == "replyAll" ? "createReplyAll" : "createReply"
            let data = try await request("/me/messages/\(Self.component(sourceID))/\(action)", method: "POST", body: [:])
            id = try JSONDecoder().decode(GraphMessage.self, from: data).id
        }
        let payload: [String: Any] = ["subject": mail.subject, "body": ["contentType": "Text", "content": mail.body], "toRecipients": recipients(mail.to), "ccRecipients": recipients(mail.cc), "bccRecipients": recipients(mail.bcc ?? [])]
        let data = try await request(id.map { "/me/messages/\(Self.component($0))" } ?? "/me/messages", method: id == nil ? "POST" : "PATCH", body: payload)
        return try JSONDecoder().decode(GraphMessage.self, from: data).mail(folder: mail.folderID)
    }
    public func attach(_ files: [OutgoingAttachment], to id: String) async throws {
        let existing = try await attachments(id)
        let present = Set(existing.compactMap(\.contentId))
        for file in files where !present.contains("aster-" + file.id) {
            guard file.data.count <= 3_000_000 else { throw MailError.message("Attachments must be 3 MB or smaller in this release.") }
            _ = try await request("/me/messages/\(Self.component(id))/attachments", method: "POST", body: ["@odata.type": "#microsoft.graph.fileAttachment", "name": file.name, "contentType": file.contentType, "contentId": "aster-" + file.id, "contentBytes": file.data.base64EncodedString()])
        }
    }
    public func sendDraft(_ id: String) async throws { _ = try await request("/me/messages/\(Self.component(id))/send", method: "POST") }
    public func attachments(_ mailID: String) async throws -> [Attachment] {
        struct Page: Decodable { var value: [Attachment]; var next: String?; enum CodingKeys: String, CodingKey { case value; case next = "@odata.nextLink" } }
        var path: String? = "/me/messages/\(Self.component(mailID))/attachments?$select=id,name,size,contentType,isInline,contentId"
        var result: [Attachment] = []
        while let current = path { let page = try JSONDecoder().decode(Page.self, from: await request(current)); result += page.value; path = page.next }
        return result
    }
    public func attachmentData(_ mailID: String, _ attachmentID: String) async throws -> Data {
        // $value supports file and item attachments without eagerly loading base64 into inbox records.
        try await request("/me/messages/\(Self.component(mailID))/attachments/\(Self.component(attachmentID))/$value")
    }
}
