import XCTest
@testable import Aster
import AsterCore

actor PersonalizationModel: IntelligenceProvider {
    var replies: [ReplyRequest] = []
    var formalisations: [FormaliseRequest] = []
    func summarize(_ thread: [Mail]) async throws -> ThreadSummary { throw MailError.message("Unused") }
    func draftReply(_ thread: [Mail]) async throws -> String { throw MailError.message("Unused") }
    func draftReply(_ thread: [Mail], request: ReplyRequest) async throws -> String {
        replies.append(request); return "Hello,\n\nOption A works.\n\nRegards,\n[Your name]"
    }
    func formalise(_ thread: [Mail], request: FormaliseRequest) async throws -> GeneratedEmail {
        formalisations.append(request); return GeneratedEmail(subject: "Preference", body: "Hello,\n\nOption A works.\n\nRegards,\n[Your name]")
    }
}
@MainActor final class PersonalizationFlowTests: XCTestCase {
    func testDefaultNameFlowsThroughBothWritingActionsAndAccountOverrideDoesNotLeak() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = AppState(cacheRoot: directory, persistDemoPreference: false, workspaceNameProvider: { "Alex Rivera" })
        let second = AppState(cacheRoot: directory, persistDemoPreference: false, workspaceNameProvider: { "Alex Rivera" })
        defer { first.stopBackgroundWork(); second.stopBackgroundWork(); try? FileManager.default.removeItem(at: directory) }
        try await first.loadDemo(name: "personal@example.com", cacheKey: "identity-one")
        try await second.loadDemo(name: "work@example.com", cacheKey: "identity-two")
        second.policy.senderName = "Casey"
        let model = PersonalizationModel(); first.intelligenceOverride = model; second.intelligenceOverride = model
        for (state, expected) in [(first, "Alex Rivera"), (second, "Casey")] {
            let original = try XCTUnwrap(state.messages.first); state.select(original.id)
            let context = try await state.prepareReplyAssistant()
            let reply = try await state.generateAssistedReply(context, intent: "Choose A", style: WritingStyle())
            XCTAssertTrue(reply.body.hasSuffix(expected)); XCTAssertFalse(reply.body.contains("[Your name]"))
            let draft = Composer(localID: "local-identity", mode: "new", to: "recipient@example.com", cc: "", subject: "", body: "Choose A")
            let formal = try await state.formaliseSelectedText("Choose A", in: draft)
            XCTAssertTrue(formal.body.hasSuffix(expected))
            _ = try await state.saveComposer(formal, send: true)
            state.selection = "sentitems"; await state.refreshCachedMail()
            XCTAssertEqual(state.messages.first?.sender.name, expected)
        }
        let replies = await model.replies, formal = await model.formalisations
        XCTAssertEqual(replies.map(\.senderName), ["Alex Rivera", "Casey"])
        XCTAssertEqual(formal.map(\.senderName), ["Alex Rivera", "Casey"])
        XCTAssertEqual(first.senderName, "Alex Rivera")
        second.policy.senderName = ""
        XCTAssertEqual(second.senderName, "")
        second.policy.senderName = nil
        XCTAssertEqual(second.senderName, "Alex Rivera")
    }
}
