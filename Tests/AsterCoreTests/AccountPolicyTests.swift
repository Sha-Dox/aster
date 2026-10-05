import XCTest
@testable import AsterCore

final class AccountPolicyTests: XCTestCase {
    let folders = [MailFolder(id: "INBOX", name: "Inbox", role: "inbox"), MailFolder(id: "SPAM", name: "Junk", role: "junkemail"), MailFolder(id: "SENT", name: "Sent", role: "sentitems"), MailFolder(id: "DRAFT", name: "Drafts", role: "drafts"), MailFolder(id: "TRASH", name: "Trash", role: "deleteditems")]
    func message(_ id: String, folder: String, subject: String = "Ordinary update") -> Mail {
        var mail = Mail(id: id, folderID: folder, sender: Address("Sender", "sender@example.com"), subject: subject, preview: "An ordinary message", body: "Hello", isDraft: folder == "DRAFT")
        mail.labelIDs = [folder]; return mail
    }
    func seededStore() async throws -> MailStore {
        let store = try MailStore(path: ":memory:")
        for folder in ["INBOX", "SPAM", "SENT", "DRAFT", "TRASH", "Label_1", "archive"] { try await store.save(message(folder, folder: folder)) }
        return store
    }
    func testAllReceivedWithJunkIncludesArchivesButExcludesOutgoingAndTrash() async throws {
        let store = try await seededStore(); var policy = AccountPolicy(); policy.priorityMode = .allReceived; policy.junkMode = .includeInPriority
        let rows = try await store.priority(policy: policy, folders: folders)
        XCTAssertEqual(Set(rows.map(\.id)), ["INBOX", "SPAM", "Label_1", "archive"])
        let count = try await store.priorityCount(policy: policy, folders: folders); XCTAssertEqual(count, 4)
    }
    func testInboxAndJunkPoliciesRemainIndependent() async throws {
        let store = try await seededStore(); var policy = AccountPolicy(); policy.priorityMode = .inbox
        let separate = try await store.priority(policy: policy, folders: folders); XCTAssertEqual(separate.map(\.id), ["INBOX"])
        policy.junkMode = .includeInPriority
        let included = try await store.priority(policy: policy, folders: folders); XCTAssertEqual(Set(included.map(\.id)), ["INBOX", "SPAM"])
        let junk = try await store.recent(folder: "SPAM"); XCTAssertEqual(junk.count, 1, "Presentation must not mutate the provider/cache folder.")
    }
    func testPrioritySenderAndStarOverrideOrdinaryClassification() async throws {
        let store = try await seededStore(); var policy = AccountPolicy()
        let none = try await store.priority(policy: policy, folders: folders); XCTAssertTrue(none.isEmpty)
        policy.prioritySenders = ["SENDER@EXAMPLE.COM"]
        let vip = try await store.priority(policy: policy, folders: folders); XCTAssertEqual(vip.map(\.id), ["INBOX"])
        policy.prioritySenders = []; var flagged = message("starred", folder: "INBOX"); flagged.isFlagged = true; try await store.save(flagged)
        let star = try await store.priority(policy: policy, folders: folders); XCTAssertEqual(star.map(\.id), ["starred"])
    }
    func testPrioritySearchQueriesOlderCacheAndEscapesOperators() async throws {
        let store = try MailStore(path: ":memory:"); var policy = AccountPolicy(); policy.priorityMode = .allReceived
        for i in 0..<700 { var mail = message("m\(i)", folder: "INBOX", subject: i == 0 ? "Rare old message OR token" : "Update"); mail.date = Date(timeIntervalSince1970: Double(i)); try await store.save(mail) }
        let latest = try await store.priority(policy: policy, folders: folders, limit: 500); XCTAssertFalse(latest.contains { $0.id == "m0" })
        let found = try await store.priority(policy: policy, folders: folders, search: "Rare OR"); XCTAssertEqual(found.map(\.id), ["m0"])
    }
    func testGmailMultiLabelSentIsExcludedEvenWhenAlsoInInbox() async throws {
        let store = try MailStore(path: ":memory:"); var mail = message("self", folder: "INBOX"); mail.labelIDs = ["INBOX", "SENT"]; try await store.save(mail)
        var policy = AccountPolicy(); policy.priorityMode = .allReceived; policy.junkMode = .includeInPriority
        let rows = try await store.priority(policy: policy, folders: folders); XCTAssertTrue(rows.isEmpty)
    }
    func testAccountsWithIdenticalProviderIDsStayDistinctAndPoliciesRoundTrip() throws {
        var first = AccountProfile(provider: "google", clientID: "client", identity: "google:one", email: "one@example.com")
        let second = AccountProfile(provider: "google", clientID: "client", identity: "google:two", email: "two@example.com")
        XCTAssertNotEqual(first.scopedMessageID("same-message"), second.scopedMessageID("same-message"))
        first.policy.priorityMode = .allReceived; first.policy.junkMode = .moveToInbox; first.policy.hiddenFolders = ["Label_1"]; first.policy.prioritySenders = ["vip@example.com"]
        let saved = try JSONDecoder().decode([AccountProfile].self, from: JSONEncoder().encode([first, second]))
        XCTAssertEqual(saved[0], first); XCTAssertEqual(saved[1].policy, AccountPolicy())
    }
    func testSentReplyClearsDefaultPriorityReplyHint() async throws {
        let store = try MailStore(path: ":memory:")
        var incoming = message("question", folder: "INBOX", subject: "Please confirm the plan"); incoming.threadID = "thread"; incoming.date = Date(timeIntervalSince1970: 10)
        var reply = message("reply", folder: "SENT"); reply.threadID = "thread"; reply.date = Date(timeIntervalSince1970: 20)
        try await store.save(incoming)
        let before = try await store.priority(policy: AccountPolicy(), folders: folders); XCTAssertEqual(before.map(\.id), ["question"])
        try await store.save(reply)
        let after = try await store.priority(policy: AccountPolicy(), folders: folders); XCTAssertTrue(after.isEmpty)
    }

}
