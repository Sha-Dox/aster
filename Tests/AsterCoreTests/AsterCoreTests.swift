import XCTest
@testable import AsterCore

final class MailStoreTests: XCTestCase {
    func makeStore() throws -> MailStore { try MailStore(path: ":memory:") }
    func testSearchAndQueuedEditsSurviveDelta() async throws {
        let store = try makeStore()
        let original = DemoMail.messages()[0]
        try await store.save(original)
        let matches = try await store.search("Casey production")
        XCTAssertEqual(matches, [original.id])
        var modified = original; modified.isRead = true
        let change = PendingChange(messageID: original.id, kind: "read", value: "true")
        try await store.queue(change, mail: modified)
        try await store.applyPage([original], removed: [], folder: "inbox", cursor: "cursor-1")
        let mails = try await store.all(); let cursor = try await store.metadata("delta:inbox")
        XCTAssertTrue(mails[0].isRead); XCTAssertEqual(cursor, "cursor-1")
        try await store.complete(change)
        let changes = try await store.changes(); XCTAssertTrue(changes.isEmpty)
    }
    func testTombstoneCannotEraseMovedMessage() async throws {
        let store = try makeStore()
        var mail = DemoMail.messages()[0]; mail.folderID = "archive"
        try await store.save(mail)
        try await store.applyPage([], removed: [mail.id], folder: "inbox", cursor: "inbox-link")
        var mails = try await store.all(); XCTAssertEqual(mails.count, 1)
        try await store.applyPage([], removed: [mail.id], folder: "archive", cursor: "archive-link")
        mails = try await store.all(); XCTAssertTrue(mails.isEmpty)
        let matches = try await store.search("Casey"); XCTAssertTrue(matches.isEmpty)
    }
    func testResetKeepsUnsyncedMailAndOtherFolders() async throws {
        let store = try makeStore()
        var mails = DemoMail.messages(); mails[1].folderID = "archive"
        for mail in mails { try await store.save(mail) }
        let change = PendingChange(messageID: mails[0].id, kind: "flag", value: "true")
        var edited = mails[0]; change.apply(to: &edited)
        try await store.queue(change, mail: edited)
        try await store.resetFolder("inbox")
        let retained = try await store.all()
        XCTAssertEqual(Set(retained.map(\.id)), [mails[0].id, mails[1].id])
    }
    func testDurableQueueOrderingAndCacheAcrossReopen() async throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite").path
        defer { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: path + suffix) } }
        let store = try MailStore(path: path); let mail = DemoMail.messages()[0]
        for value in ["true", "false", "true"] { try await store.queue(PendingChange(messageID: mail.id, kind: "read", value: value), mail: mail) }
        let reopened = try MailStore(path: path)
        let changes = try await reopened.changes(); let mails = try await reopened.all()
        XCTAssertEqual(changes.map(\.value), ["true", "false", "true"]); XCTAssertEqual(mails.count, 1)
    }
    func testSearchTreatsOperatorsAsLiteralText() async throws {
        let store = try makeStore(); try await store.save(DemoMail.messages()[0])
        _ = try await store.search("\" OR * NOT ( )")
        let matches = try await store.search("prod"); XCTAssertEqual(matches.count, 1)
    }
}
struct FakeTokens: TokenProvider { func token() async throws -> String { "fake-token" } }
final class StubProtocol: URLProtocol, @unchecked Sendable {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var observed = request
            if observed.httpBody == nil, let stream = observed.httpBodyStream {
                stream.open(); defer { stream.close() }
                var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let count = stream.read(&buffer, maxLength: buffer.count); if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count)) }
                observed.httpBody = data
            }
            let (status, data) = try Self.handler!(observed)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
final class GraphTests: XCTestCase {
    func client() -> GraphClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        return GraphClient(tokens: FakeTokens(), session: URLSession(configuration: config))
    }
    override func tearDown() { StubProtocol.handler = nil }
    func testDeltaMappingImmutableIDsAndTombstones() async throws {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Prefer"), "IdType=\"ImmutableId\"")
            XCTAssertTrue(request.url!.absoluteString.contains("messages/delta"))
            return (200, Data(#"{"value":[{"id":"1","conversationId":"thread","from":{"emailAddress":{"name":"Casey","address":"p@example.com"}},"subject":"Question","body":{"contentType":"html","content":"<p>Hello</p>"},"receivedDateTime":"2026-10-05T09:30:00.000Z","isRead":false},{"id":"2","@removed":{"reason":"deleted"}}],"@odata.deltaLink":"https://graph.microsoft.com/v1.0/delta"}"#.utf8))
        }
        let page = try await client().delta(folder: "inbox", cursor: nil)
        XCTAssertTrue(page.value[1].isRemoved)
        let mail = page.value[0].mail(folder: "inbox")
        XCTAssertEqual(mail.threadID, "thread"); XCTAssertTrue(mail.isHTML); XCTAssertEqual(mail.sender.name, "Casey")
    }
    func testRejectsCredentialExfiltrationURL() async throws {
        do { _ = try await client().request("https://evil.example/delta"); XCTFail("Should reject foreign host") } catch { XCTAssertTrue(error is MailError) }
    }
    func testGraphFailurePreservesStatusForExpiredDeltaRecovery() async throws {
        StubProtocol.handler = { _ in (410, Data(#"{"error":{"message":"Sync state expired"}}"#.utf8)) }
        do { _ = try await client().delta(folder: "inbox", cursor: nil); XCTFail("Should fail") }
        catch let error as GraphFailure { XCTAssertEqual(error.status, 410) }
    }
    func testMoveAndReadUseGraphMutationEndpoints() async throws {
        StubProtocol.handler = { request in
            if request.httpMethod == "GET" { return (200, Data(#"{"id":"A/id+","parentFolderId":"inbox"}"#.utf8)) }
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertTrue(request.url!.path.hasSuffix("/move"))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            return (201, Data("{}".utf8))
        }
        try await client().apply(PendingChange(messageID: "A/id+", kind: "move", value: "archive"))
    }
}
final class AttentionTests: XCTestCase {
    func testConservativeLocalHintsAndLatestThreadSelection() {
        var mails = DemoMail.messages(); XCTAssertEqual(AttentionEngine.items(mails, inboxID: "inbox").count, 4)
        var duplicate = mails[0]; duplicate.id = "newer"; duplicate.date = Date().addingTimeInterval(20); mails.append(duplicate)
        XCTAssertEqual(AttentionEngine.items(mails, inboxID: "inbox").count, 4)
        XCTAssertNil(AttentionEngine.classify(mails.first { $0.id == "design" }!))
        XCTAssertEqual(AttentionEngine.classify(mails[0])?.kind, .reply) // "no firm deadline" must not become a deadline
        var sent = mails[0]; sent.id = "sent-reply"; sent.folderID = "sentitems"; sent.sender = Address("You", "you@example.com"); sent.date = Date().addingTimeInterval(30)
        mails.append(sent)
        XCTAssertFalse(AttentionEngine.items(mails, inboxID: "inbox").contains { $0.mail.threadID == sent.threadID })
    }
    func testOfflineSummaryIsClearlyAttributed() async throws {
        let summary = try await LocalIntelligence().summarize([DemoMail.messages()[0]])
        XCTAssertTrue(summary.source.contains("no model used")); XCTAssertFalse(summary.summary.isEmpty)
    }
}
