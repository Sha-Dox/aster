import Foundation

public struct Address: Codable, Hashable, Sendable {
    public var name: String
    public var address: String
    public init(_ name: String, _ address: String) { self.name = name; self.address = address }
}
public struct Mail: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var threadID: String
    public var folderID: String
    public var sender: Address
    public var to: [Address]
    public var cc: [Address]
    public var replyTo: [Address]
    public var subject: String
    public var preview: String
    public var body: String
    public var isHTML: Bool
    public var date: Date
    public var isRead: Bool
    public var isFlagged: Bool
    public var isDraft: Bool
    public var hasAttachments: Bool
    public var bcc: [Address]?
    public var labelIDs: [String]?
    public var internetMessageID: String?
    public var references: String?
    public func isInFolder(_ id: String) -> Bool { folderID == id || (labelIDs?.contains(id) ?? false) }
    public init(id: String, threadID: String? = nil, folderID: String = "inbox", sender: Address, to: [Address] = [], cc: [Address] = [], replyTo: [Address] = [], subject: String, preview: String, body: String, isHTML: Bool = false, date: Date = Date(), isRead: Bool = false, isFlagged: Bool = false, isDraft: Bool = false, hasAttachments: Bool = false) {
        self.id = id; self.threadID = threadID ?? id; self.folderID = folderID; self.sender = sender; self.to = to; self.cc = cc; self.replyTo = replyTo; self.subject = subject; self.preview = preview; self.body = body; self.isHTML = isHTML; self.date = date; self.isRead = isRead; self.isFlagged = isFlagged; self.isDraft = isDraft; self.hasAttachments = hasAttachments
    }
}
public struct MailFolder: Codable, Identifiable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var role: String?
    public init(id: String, name: String, role: String? = nil) { self.id = id; self.name = name; self.role = role }
}
public enum AttentionKind: String, Codable, Sendable, CaseIterable {
    case reply = "Needs reply", deadline = "Deadline", security = "Security", payment = "Payment"
    public var symbol: String { switch self { case .reply: return "arrowshape.turn.up.left"; case .deadline: return "clock"; case .security: return "shield.lefthalf.filled"; case .payment: return "creditcard" } }
}
public struct AttentionItem: Identifiable, Sendable {
    public var id: String { mail.id }
    public let mail: Mail
    public let kind: AttentionKind
    public let detail: String
}
/// Deterministic, on-device hints. These are deliberately conservative and never claim to be an AI analysis.
public enum AttentionEngine {
    public static func classify(_ mail: Mail) -> AttentionItem? {
        guard !mail.isDraft else { return nil }
        let text = (mail.subject + " " + mail.preview + " " + String(mail.body.prefix(8000))).lowercased()
        let kind: AttentionKind
        if ["vulnerability", "security alert", "suspicious sign-in", "high-severity"].contains(where: text.contains) { kind = .security }
        else if ["due tomorrow", "due by", "assignment is due"].contains(where: text.contains) || (mail.subject + " " + mail.preview).lowercased().contains("deadline") { kind = .deadline }
        else if ["invoice", "payment due", "overdue payment"].contains(where: text.contains) { kind = .payment }
        else if ["could you", "can you", "please confirm", "please send", "your estimate", "let me know", "following up"].contains(where: text.contains) { kind = .reply }
        else { return nil }
        return AttentionItem(mail: mail, kind: kind, detail: mail.preview)
    }
    public static func items(_ mails: [Mail], inboxID: String, sentID: String = "sentitems") -> [AttentionItem] {
        let latest = Dictionary(grouping: mails.filter { $0.isInFolder(inboxID) }, by: \.threadID).compactMap { $0.value.max { $0.date < $1.date } }
        return latest.compactMap { mail -> AttentionItem? in
            guard let hint = classify(mail) else { return nil }
            if hint.kind == .reply && mails.contains(where: { $0.threadID == mail.threadID && $0.date > mail.date && $0.isInFolder(sentID) && !$0.isDraft && $0.sender.address != mail.sender.address }) { return nil }
            return hint
        }.sorted { lhs, rhs in
            let rank: [AttentionKind: Int] = [.security: 0, .deadline: 1, .reply: 2, .payment: 3]
            if rank[lhs.kind] != rank[rhs.kind] { return rank[lhs.kind]! < rank[rhs.kind]! }
            return lhs.mail.date > rhs.mail.date
        }
    }
}
public struct ThreadSummary: Codable, Sendable {
    public let summary: String
    public let action: String
    public let details: [String]
    public let source: String
    public init(summary: String, action: String, details: [String], source: String) { self.summary = summary; self.action = action; self.details = details; self.source = source }
}
public protocol IntelligenceProvider: Sendable {
    func summarize(_ thread: [Mail]) async throws -> ThreadSummary
    func draftReply(_ thread: [Mail]) async throws -> String
    func draftReply(_ thread: [Mail], request: ReplyRequest) async throws -> String
    func formalise(_ thread: [Mail], request: FormaliseRequest) async throws -> GeneratedEmail
}
public extension IntelligenceProvider {
    func formalise(_ thread: [Mail], request: FormaliseRequest) async throws -> GeneratedEmail {
        throw MailError.message("Enable Apple Intelligence or configure a model endpoint to formalise selected text.")
    }
    func draftReply(_ thread: [Mail], request: ReplyRequest) async throws -> String {
        throw MailError.message("This provider cannot generate an instructed reply. Enable Apple Intelligence or configure a model endpoint in Settings.")
    }
}
public struct LocalIntelligence: IntelligenceProvider {
    public init() {}
    public func summarize(_ thread: [Mail]) async throws -> ThreadSummary {
        guard let mail = thread.sorted(by: { $0.date < $1.date }).last else { throw MailError.message("No messages to summarize.") }
        let hint = AttentionEngine.classify(mail)
        return ThreadSummary(summary: mail.preview, action: hint?.kind == .reply ? "Review the question and reply to \(mail.sender.name)." : "Review the original message for details.", details: [], source: "Local preview · no model used")
    }
    public func draftReply(_ thread: [Mail]) async throws -> String {
        throw MailError.message("Configure an AI provider in Settings to generate a reply. You can always write a reply yourself.")
    }
}
public enum MailError: LocalizedError {
    case message(String)
    public var errorDescription: String? { switch self { case .message(let message): return message } }
}
public struct PendingChange: Codable, Identifiable, Sendable {
    public var id: String
    public var messageID: String
    public var kind: String
    public var value: String
    public init(messageID: String, kind: String, value: String) { id = UUID().uuidString; self.messageID = messageID; self.kind = kind; self.value = value }
    public func apply(to mail: inout Mail) {
        switch kind { case "read": mail.isRead = value == "true"; case "flag": mail.isFlagged = value == "true"; case "move":
            mail.folderID = value
            if var labels = mail.labelIDs {
                labels.removeAll { ["INBOX", "TRASH", "SPAM"].contains($0) }
                if value != "archive" && !labels.contains(value) { labels.append(value) }
                mail.labelIDs = labels
            }; default: break }
    }
}
public enum DemoMail {
    public static let folders = [MailFolder(id: "inbox", name: "Inbox", role: "inbox"), MailFolder(id: "drafts", name: "Drafts", role: "drafts"), MailFolder(id: "sentitems", name: "Sent", role: "sentitems"), MailFolder(id: "archive", name: "Archive", role: "archive"), MailFolder(id: "deleteditems", name: "Trash", role: "deleteditems"), MailFolder(id: "projects", name: "Projects"), MailFolder(id: "junkemail", name: "Junk", role: "junkemail")]
    public static func messages(now: Date = Date()) -> [Mail] {
        let me = Address("You", "you@example.com")
        func mail(_ id: String, _ name: String, _ address: String, _ subject: String, _ preview: String, _ body: String, _ minutes: Double, read: Bool = false, attachment: Bool = false) -> Mail {
            Mail(id: id, sender: Address(name, address), to: [me], subject: subject, preview: preview, body: body, date: now.addingTimeInterval(-minutes * 60), isRead: read, hasAttachments: attachment)
        }
        // Fictional fixtures only; never copy a real mailbox into the public source.
        return [
            mail("volume","Casey Rivera","casey@example.com","Demo project: production estimate","Casey needs a rough production estimate.","Hello,\n\nFor this fictional project, could you share a rough estimate of the production volume for the next phase? A range is fine; please flag any uncertainty.\n\nThanks,\nCasey", 18),
            mail("assignment","Professor Taylor","taylor@example.edu","Demo course: report due tomorrow","Your sample report is due tomorrow.","Hello,\n\nThe report for this fictional course is due tomorrow at 23:59. Please include your notes and a short conclusion. This is sample inbox content.\n\nBest regards,\nProfessor Taylor", 46, attachment: true),
            mail("security","Demo Security","security@example.com","Demo dependency security alert","A sample high-severity vulnerability needs review.","A fictional dependency vulnerability needs review.\n\nPlease review the advisory and update the sample package. This message demonstrates an attention cue and does not describe a real repository.", 67),
            mail("alex","Jordan Lee","jordan@example.com","Feedback on a sample launch plan","Jordan is following up on your feedback.","Hello,\n\nCould you review the fictional launch schedule and let me know whether the proposed order works?\n\nThanks,\nJordan", 4320, read: true),
            mail("design","Morgan Ellis","morgan@example.com","Demo design review","Updated spacing and toolbar sketches.","Hello,\n\nThe sample toolbar sketches are ready for review. The fictional team will discuss spacing at the next design meeting.\n\nMorgan", 120, read: true),
            mail("linear","Demo Projects","projects@example.com","Your demo project update","Three sample tasks are complete.","Three fictional tasks are complete.\n\nThe next sample milestone is on track. This notification is included only to demonstrate the inbox.", 180, read: true),
            mail("coffee","Jamie Brooks","jamie@example.com","A sample coffee invitation","An informal message for the demo inbox.","Hello!\n\nWould Friday morning work for a coffee? This is a fictional invitation for the demo inbox.\n\nJamie", 230),
            mail("receipt","Demo Store","receipts@example.com","Your demo subscription receipt","A fictional monthly subscription receipt.","Thank you for your sample purchase.\n\nDemo subscription: one month\n\nThis fictional receipt demonstrates ordinary mail outside the default Priority inbox.", 500, read: true)
        ]
    }
}
