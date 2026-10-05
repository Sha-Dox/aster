import XCTest
@testable import Aster
import AsterCore

actor TestReplyModel: IntelligenceProvider {
    var requests: [ReplyRequest] = []
    func summarize(_ thread: [Mail]) async throws -> ThreadSummary { throw MailError.message("Unused") }
    func draftReply(_ thread: [Mail]) async throws -> String { throw MailError.message("An explicit instruction is required") }
    func draftReply(_ thread: [Mail], request: ReplyRequest) async throws -> String {
        requests.append(request)
        return "Dear Professor,\n\nI would prefer option A, with Y replacing X. Would that work for you?\n\nBest regards,\nAlex"
    }
}
@MainActor final class ReplyAssistantTests: XCTestCase {
    func testGenerationCreatesOnlyPreviewAndExplicitAcceptanceSendsEditedText() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = AppState(cacheRoot: directory, persistDemoPreference: false)
        defer { state.stopBackgroundWork(); try? FileManager.default.removeItem(at: directory) }
        try await state.loadDemo(name: "student@example.com", cacheKey: "assistant-test")
        let model = TestReplyModel(); state.intelligenceOverride = model
        let original = try XCTUnwrap(state.messages.first); state.select(original.id)
        let context = try await state.prepareReplyAssistant(); state.replyAssistant = context
        let count = state.cachedCount
        var style = WritingStyle(); style.language = "English"; style.signature = "Alex"
        var preview = try await state.generateAssistedReply(context, intent: "Choose A, replace X with Y", style: style)
        XCTAssertEqual(state.cachedCount, count); XCTAssertNil(state.composer)
        XCTAssertEqual(preview.sourceID, original.id); XCTAssertEqual(preview.to, original.sender.address)
        XCTAssertFalse(preview.body.contains("Original message"))
        let captured = await model.requests; XCTAssertEqual(captured.first?.intent, "Choose A, replace X with Y"); XCTAssertEqual(captured.first?.style, style)
        preview.body += "\nEdited during review."
        try await state.sendAcceptedReply(context, draft: preview)
        state.selection = "sentitems"; await state.refreshCachedMail()
        XCTAssertEqual(state.messages.first?.body, preview.body)
        XCTAssertNil(state.composer, "Acceptance must not open another composer sheet")
        do { try await state.sendAcceptedReply(context, draft: preview); XCTFail("A preview cannot be accepted twice") } catch { }
    }
    func testPreviewCannotBeSentThroughAnotherAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = AppState(cacheRoot: directory, persistDemoPreference: false), second = AppState(cacheRoot: directory, persistDemoPreference: false)
        defer { first.stopBackgroundWork(); second.stopBackgroundWork(); try? FileManager.default.removeItem(at: directory) }
        try await first.loadDemo(name: "one@example.com", cacheKey: "one"); try await second.loadDemo(name: "two@example.com", cacheKey: "two")
        first.intelligenceOverride = TestReplyModel()
        let original = try XCTUnwrap(first.messages.first); first.select(original.id)
        let context = try await first.prepareReplyAssistant(); first.replyAssistant = context
        let preview = try await first.generateAssistedReply(context, intent: "Choose A", style: WritingStyle())
        let before = second.cachedCount
        do { try await second.sendAcceptedReply(context, draft: preview); XCTFail("Cross-account acceptance must fail") } catch { }
        XCTAssertEqual(second.cachedCount, before)
    }
}
