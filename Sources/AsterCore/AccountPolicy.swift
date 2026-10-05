import Foundation

public enum PriorityMode: String, Codable, CaseIterable, Sendable {
    case important, inbox, allReceived
    public var title: String { switch self { case .important: return "Important mail"; case .inbox: return "Entire inbox"; case .allReceived: return "All received mail" } }
}
public enum JunkMode: String, Codable, CaseIterable, Sendable {
    case separate, includeInPriority, moveToInbox
    public var title: String { switch self { case .separate: return "Keep separate"; case .includeInPriority: return "Show in Priority"; case .moveToInbox: return "Move to Inbox on sync" } }
}
public struct AccountPolicy: Codable, Equatable, Sendable {
    public var priorityMode: PriorityMode = .important
    public var junkMode: JunkMode = .separate
    public var hideJunkFolder = false
    public var hiddenFolders: Set<String> = []
    public var prioritySenders: [String] = []
    public var writingStyle: WritingStyle?
    public init() {}
}
public struct AccountProfile: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var provider: String
    public var clientID: String
    public var identity: String
    public var email: String
    public var policy: AccountPolicy
    public init(id: UUID = UUID(), provider: String, clientID: String, identity: String, email: String, policy: AccountPolicy = AccountPolicy()) {
        self.id = id; self.provider = provider; self.clientID = clientID; self.identity = identity; self.email = email; self.policy = policy
    }
    public func scopedMessageID(_ messageID: String) -> String { id.uuidString + ":" + messageID }
}
