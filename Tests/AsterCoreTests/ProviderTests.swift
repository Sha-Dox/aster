import XCTest
@testable import AsterCore

final class GmailTests: XCTestCase {
    func client() -> GmailClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        return GmailClient(tokens: FakeTokens(), session: URLSession(configuration: config))
    }
    override func tearDown() { StubProtocol.handler = nil }
    static let messageJSON = #"{"id":"m1","threadId":"t1","labelIds":["INBOX","UNREAD","Label_1"],"snippet":"Can you confirm &amp; review?","internalDate":"1780000000000","payload":{"mimeType":"multipart/mixed","headers":[{"name":"From","value":"\"Park, Elena\" <elena@example.edu>"},{"name":"To","value":"you@example.com"},{"name":"Subject","value":"=?UTF-8?B?SGVsbG8=?="},{"name":"Message-ID","value":"<original@example.edu>"}],"parts":[{"mimeType":"text/plain","body":{"data":"SGVsbG8","size":5}},{"partId":"2","mimeType":"application/pdf","filename":"report.pdf","body":{"attachmentId":"att1","size":100}}]}}"#
    func testMultipartMappingAndMultipleLabelMembership() throws {
        let gmail = try JSONDecoder().decode(GmailMessage.self, from: Data(Self.messageJSON.utf8))
        let mail = gmail.mail()
        XCTAssertEqual(mail.sender.name, "Park, Elena"); XCTAssertEqual(mail.subject, "Hello")
        XCTAssertEqual(mail.body, "Hello"); XCTAssertTrue(mail.hasAttachments); XCTAssertFalse(mail.isRead)
        XCTAssertTrue(mail.isInFolder("INBOX")); XCTAssertTrue(mail.isInFolder("Label_1"))
        XCTAssertEqual(mail.internetMessageID, "<original@example.edu>")
    }
    func testArchivePreservesUserLabelsAndNeverCallsDelete() async throws {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertTrue(request.url!.path.hasSuffix("/modify"))
            let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(body["addLabelIds"] as? [String], []); XCTAssertTrue((body["removeLabelIds"] as? [String])!.contains("INBOX"))
            return (200, Data("{}".utf8))
        }
        try await client().apply(PendingChange(messageID: "m1", kind: "move", value: "archive"))
        var mail = try JSONDecoder().decode(GmailMessage.self, from: Data(Self.messageJSON.utf8)).mail()
        PendingChange(messageID: "m1", kind: "move", value: "archive").apply(to: &mail)
        XCTAssertFalse(mail.isInFolder("INBOX")); XCTAssertTrue(mail.isInFolder("Label_1"))
    }
    func testHistoryWatermarkOnlyAdvancesAfterLastPage() async throws {
        let store = try MailStore(path: ":memory:")
        try await store.setMetadata("gmailHistory", "100")
        StubProtocol.handler = { request in
            if request.url!.path.hasSuffix("/history") {
                if request.url!.query!.contains("pageToken=") { return (200, Data(#"{"historyId":"120"}"#.utf8)) }
                return (200, Data(#"{"history":[{"messagesAdded":[{"message":{"id":"m1"}}]}],"nextPageToken":"page2","historyId":"110"}"#.utf8))
            }
            return (200, Data(Self.messageJSON.utf8))
        }
        var observed: [String] = []
        let recorder = Watermarks()
        try await client().synchronize(store: store, folders: []) { let mark = try? await store.metadata("gmailHistory"); await recorder.append(mark ?? "missing") }
        observed = await recorder.values
        XCTAssertEqual(observed, ["100", "120"])
        let cached = try await store.all(); XCTAssertEqual(cached.count, 1)
    }
    func testInitialSnapshotFetchesMailAndCapturesPreEnumerationHistory() async throws {
        let store = try MailStore(path: ":memory:")
        var stale = DemoMail.messages()[0]; stale.id = "gone"; try await store.save(stale)
        StubProtocol.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("/profile") { return (200, Data(#"{"emailAddress":"you@example.com","historyId":"200"}"#.utf8)) }
            if path.hasSuffix("/messages") { return (200, Data(#"{"messages":[{"id":"m1"}]}"#.utf8)) }
            if path.hasSuffix("/history") { XCTAssertTrue(request.url!.query!.contains("startHistoryId=200")); return (200, Data(#"{"historyId":"202"}"#.utf8)) }
            return (200, Data(Self.messageJSON.utf8))
        }
        try await client().synchronize(store: store, folders: []) {}
        let all = try await store.all(); let cursor = try await store.metadata("gmailHistory")
        XCTAssertEqual(all.map(\.id), ["m1"]); XCTAssertEqual(cursor, "202")
    }
    func testExpiredHistoryFallsBackToSnapshot() async throws {
        let store = try MailStore(path: ":memory:"); try await store.setMetadata("gmailHistory", "old")
        StubProtocol.handler = { request in
            if request.url!.query?.contains("startHistoryId=old") == true { return (404, Data(#"{"error":{"message":"expired"}}"#.utf8)) }
            if request.url!.path.hasSuffix("/profile") { return (200, Data(#"{"emailAddress":"you@example.com","historyId":"300"}"#.utf8)) }
            if request.url!.path.hasSuffix("/history") { return (200, Data(#"{"historyId":"301"}"#.utf8)) }
            return (200, Data("{}".utf8))
        }
        try await client().synchronize(store: store, folders: []) {}
        let mark = try await store.metadata("gmailHistory"); XCTAssertEqual(mark, "301")
    }
    func testGmailDraftUsesDraftIDForSending() async throws {
        var sendID = ""
        StubProtocol.handler = { request in
            if request.url!.path.hasSuffix("/drafts/send") {
                let payload = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: String]; sendID = payload["id"]!; return (200, Data("{}".utf8))
            }
            if request.url!.path.hasSuffix("/drafts") { return (200, Data(#"{"id":"draft42","message":{"id":"m1","threadId":"t1"}}"#.utf8)) }
            return (200, Data(Self.messageJSON.utf8))
        }
        let mail = Mail(id: "local-123", sender: Address("You", "you@example.com"), to: [Address("Elena", "elena@example.edu")], subject: "Hello", preview: "", body: "A draft")
        let saved = try await client().saveDraft(mail, remoteID: nil, sourceID: nil, mode: "new")
        XCTAssertEqual(saved.mail.id, "m1"); XCTAssertEqual(saved.draftID, "draft42")
        try await client().sendDraft(saved.draftID); XCTAssertEqual(sendID, "draft42")
    }
    func testReplacingDraftPreservesAttachmentBytes() async throws {
        var putSeen = false
        StubProtocol.handler = { request in
            let path = request.url!.path
            if path.hasSuffix("/attachments/att1") { return (200, Data(#"{"data":"AP8q"}"#.utf8)) }
            if path.hasSuffix("/drafts/draft42") {
                if request.httpMethod == "PUT" {
                    putSeen = true
                    let object = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                    let message = object["message"] as! [String: Any]
                    let raw = String(decoding: Base64URL.decode(message["raw"] as! String)!, as: UTF8.self)
                    XCTAssertTrue(raw.contains("AP8q")); XCTAssertTrue(raw.contains("report%2Epdf"))
                    XCTAssertEqual(message["threadId"] as? String, "t1")
                }
                return (200, Data(#"{"id":"draft42","message":{"id":"m1"}}"#.utf8))
            }
            return (200, Data(Self.messageJSON.utf8))
        }
        var mail = DemoMail.messages()[0]; mail.body = "Revised draft"
        let result = try await client().saveDraft(mail, remoteID: "draft42", sourceID: nil, mode: "reply")
        XCTAssertTrue(putSeen); XCTAssertEqual(result.draftID, "draft42")
    }
    func testUnauthorizedRequestRefreshesCredentialsOnce() async throws {
        let tokens = RefreshingTokens()
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        var attempts = 0
        StubProtocol.handler = { request in
            attempts += 1
            if attempts == 1 { XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer stale"); return (401, Data("{}".utf8)) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fresh")
            return (200, Data("{}".utf8))
        }
        _ = try await GmailClient(tokens: tokens, session: URLSession(configuration: config)).request("/profile")
        let refreshes = await tokens.refreshes
        XCTAssertEqual(attempts, 2); XCTAssertEqual(refreshes, 1)
    }

}
actor Watermarks { var values: [String] = []; func append(_ value: String) { values.append(value) } }

final class ReliabilityTests: XCTestCase {
    func testSequentialEditsMergeInsteadOfOverwritingEachOther() async throws {
        let store = try MailStore(path: ":memory:"); let stale = DemoMail.messages()[0]; try await store.save(stale)
        try await store.queue(PendingChange(messageID: stale.id, kind: "read", value: "true"), mail: stale)
        try await store.queue(PendingChange(messageID: stale.id, kind: "flag", value: "true"), mail: stale)
        let updated = try await store.all()[0]; XCTAssertTrue(updated.isRead); XCTAssertTrue(updated.isFlagged)
    }
    func testSnapshotRetainsCacheUntilCompletionAndProtectsDraftsAndEdits() async throws {
        let store = try MailStore(path: ":memory:"); let mails = DemoMail.messages()
        for mail in mails { try await store.save(mail) }
        var draft = mails[0]; draft.id = "local-draft"; draft.isDraft = true; try await store.save(draft)
        try await store.queue(PendingChange(messageID: mails[1].id, kind: "flag", value: "true"), mail: mails[1])
        try await store.beginSnapshot("gmail")
        try await store.applyMailboxPage([mails[0]], removed: [], snapshot: true, metadata: [:])
        let before = try await store.count(); XCTAssertEqual(before, 9)
        try await store.finishSnapshot("gmail", folder: nil)
        let after = try await store.all(); XCTAssertEqual(Set(after.map(\.id)), [mails[0].id, mails[1].id, "local-draft"])
    }
    func testPagedCacheAndFullTextSearchFindOlderMail() async throws {
        let store = try MailStore(path: ":memory:")
        for index in 0..<1200 {
            let mail = Mail(id: "m\(index)", sender: Address("Sender", "sender@example.com"), subject: index == 0 ? "Rare searchable phrase" : "Update", preview: "", body: String(repeating: "Content ", count: 100), date: Date(timeIntervalSince1970: Double(index)))
            try await store.save(mail)
        }
        let recent = try await store.recent(limit: 500); XCTAssertEqual(recent.count, 500); XCTAssertEqual(recent.first?.id, "m1199")
        let ids = try await store.search("Rare searchable"); let found = try await store.matching(ids)
        XCTAssertEqual(found.first?.id, "m0")
    }
    func testRetryAfterIsBoundedAndReadRetriesNeverReplayMutations() async throws {
        XCTAssertEqual(HTTPTransport.retryDelay(header: "999", attempt: 0), 30)
        XCTAssertEqual(HTTPTransport.retryDelay(header: "-1", attempt: 0), 0)
        var attempts = 0
        StubProtocol.handler = { _ in attempts += 1; return (503, Data("{}".utf8)) }
        defer { StubProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        var request = URLRequest(url: URL(string: "https://gmail.googleapis.com/test")!); request.httpMethod = "POST"
        let (_, response) = try await HTTPTransport.execute(request, session: URLSession(configuration: config))
        XCTAssertEqual(response.statusCode, 503); XCTAssertEqual(attempts, 1)
    }
    func testMIMEPreventsHeaderInjectionAndPreservesReplyThreading() throws {
        var mail = Mail(id: "local-abc", sender: Address("You", "you@example.com"), to: [Address("Park, Elena", "elena@example.edu")], subject: "Hello 👋", preview: "", body: "First\nSecond")
        var original = mail; original.internetMessageID = "<parent@example.com>"; original.references = "<older@example.com>"
        let raw = String(data: try MIME.encode(mail, replyingTo: original), encoding: .utf8)!
        XCTAssertTrue(raw.contains("In-Reply-To: <parent@example.com>")); XCTAssertTrue(raw.replacingOccurrences(of: "\r\n ", with: " ").contains("References: <older@example.com> <parent@example.com>"))
        mail.subject = "Bad\r\nBcc: thief@example.com"; XCTAssertThrowsError(try MIME.encode(mail))
        XCTAssertEqual(AddressParser.parse("\"Park, Elena\" <elena@example.edu>, Alex <alex@example.com>").count, 2)
        XCTAssertFalse(MIME.validAddress("victim@example.com\nBcc:evil@example.com"))
    }
    func testMultipartAttachmentPreservesBinaryAndBcc() throws {
        var mail = DemoMail.messages()[0]
        mail.bcc = [Address("Private", "private@example.com")]
        let bytes = Data([0, 255, 13, 10, 128, 42])
        let raw = String(decoding: try MIME.encode(mail, attachments: [OutgoingAttachment(id: "fixture", name: "résumé.pdf", contentType: "application/pdf", data: bytes)]), as: UTF8.self)
        XCTAssertTrue(raw.contains("multipart/mixed"))
        XCTAssertTrue(raw.contains("<private@example.com>"))
        XCTAssertTrue(raw.contains("filename*=UTF-8''r%C3%A9sum%C3%A9%2Epdf"))
        XCTAssertTrue(raw.contains(bytes.base64EncodedString()))
        XCTAssertTrue(raw.contains("Content-ID: <aster-fixture>"))
        XCTAssertThrowsError(try MIME.encode(mail, attachments: [OutgoingAttachment(id: "bad", name: "file", contentType: "application/pdf\r\nX: injected", data: bytes)]))
    }
    func testGmailLabelIndexesSurviveReplacementAndRemoval() async throws {
        let store = try MailStore(path: ":memory:")
        var mail = DemoMail.messages()[0]; mail.labelIDs = ["INBOX", "Label_1"]
        try await store.save(mail)
        let first = try await store.recent(folder: "Label_1"); XCTAssertEqual(first.map(\.id), [mail.id])
        mail.labelIDs = ["INBOX", "Label_2"]; try await store.save(mail)
        let removed = try await store.count(folder: "Label_1"); let added = try await store.count(folder: "Label_2")
        XCTAssertEqual(removed, 0); XCTAssertEqual(added, 1)
        try await store.remove(mail.id)
        let final = try await store.count(folder: "Label_2"); XCTAssertEqual(final, 0)
    }
    func testAppleIntelligenceAvailabilityIsReported() {
        XCTAssertFalse(AppleIntelligenceStatus.description.isEmpty)
    }
}

final class AppleModelIntegrationTests: XCTestCase {
    func testOnDeviceSummaryWhenExplicitlyEnabled() async throws {
        guard ProcessInfo.processInfo.environment["ASTER_TEST_APPLE_INTELLIGENCE"] == "1" else { throw XCTSkip("Set ASTER_TEST_APPLE_INTELLIGENCE=1 for a hardware integration test.") }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), AppleIntelligenceStatus.available {
            let summary = try await AppleIntelligence().summarize([DemoMail.messages()[0]])
            XCTAssertFalse(summary.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertTrue(summary.source.contains("on-device"))
        } else { throw XCTSkip(AppleIntelligenceStatus.description) }
        #else
        throw XCTSkip("Foundation Models is unavailable in this SDK.")
        #endif
    }
    func testSelectedTextBecomesCompleteFormalEmail() async throws {
        guard ProcessInfo.processInfo.environment["ASTER_TEST_APPLE_INTELLIGENCE"] == "1" else { throw XCTSkip("Opt in to the on-device formalisation integration test.") }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), AppleIntelligenceStatus.available {
            var style = WritingStyle(); style.language = "English"; style.length = .brief; style.signature = "Best regards,\nAlex"
            let request = FormaliseRequest(selectedText: "I choose option A, but please change Monday to Thursday. Ask Professor Park if that works. Do not invent a reason.", style: style, senderAddress: "student@example.com", recipientAddress: "professor@example.edu", existingSubject: "")
            let email = try await AppleIntelligence().formalise([], request: request)
            XCTAssertFalse(email.subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertNotNil(email.body.range(of: #"\bA\b"#, options: .regularExpression))
            XCTAssertTrue(email.body.lowercased().contains("thursday")); XCTAssertTrue(email.body.contains("Alex"))
        } else { throw XCTSkip(AppleIntelligenceStatus.description) }
        #else
        throw XCTSkip("Foundation Models is unavailable in this SDK.")
        #endif
    }
    func testInstructedReplyChoosesRequestedOptionAndSubstitution() async throws {
        guard ProcessInfo.processInfo.environment["ASTER_TEST_APPLE_INTELLIGENCE"] == "1" else { throw XCTSkip("Opt in to the on-device writing integration test.") }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), AppleIntelligenceStatus.available {
            let mail = Mail(id: "professor-question", sender: Address("Professor Park", "professor@example.edu"), to: [Address("Alex", "student@example.com")], subject: "Presentation choice", preview: "Choose A or B", body: "Dear Alex, would you prefer option A or option B for your presentation? Option A is scheduled for Monday. Best, Professor Park")
            var style = WritingStyle(); style.language = "English"; style.tone = .formal; style.length = .brief; style.signature = "Best regards,\nAlex"
            let request = ReplyRequest(intent: "Choose option A, but ask to replace Monday with Thursday. Ask whether that change works. Do not give a reason.", style: style, senderAddress: "student@example.com", targetMessageID: mail.id)
            let body = try await AppleIntelligence().draftReply([mail], request: request)
            XCTAssertNotNil(body.range(of: #"\bA\b"#, options: .regularExpression))
            XCTAssertTrue(body.lowercased().contains("thursday")); XCTAssertTrue(body.contains("Alex"))
        } else { throw XCTSkip(AppleIntelligenceStatus.description) }
        #else
        throw XCTSkip("Foundation Models is unavailable in this SDK.")
        #endif
    }

}

actor RefreshingTokens: TokenProvider {
    var refreshes = 0
    func token() async throws -> String { "stale" }
    func freshToken() async throws -> String { refreshes += 1; return "fresh" }
}
