import XCTest
@testable import Aster
import AsterCore

actor FormalisationModel: IntelligenceProvider {
    var received: [FormaliseRequest] = []
    func summarize(_ thread: [Mail]) async throws -> ThreadSummary { throw MailError.message("Unused") }
    func draftReply(_ thread: [Mail]) async throws -> String { throw MailError.message("Unused") }
    func formalise(_ thread: [Mail], request: FormaliseRequest) async throws -> GeneratedEmail {
        received.append(request)
        return GeneratedEmail(subject: "Presentation preference", body: "Dear Professor,\n\nI would prefer option A with Y replacing X. Would that be acceptable?\n\nBest regards,\nAlex")
    }
}
@MainActor final class FormalEmailTests: XCTestCase {
    func testFormalisationUsesSelectionAndDoesNotReplaceOrSendOriginalDraft() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = AppState(cacheRoot: directory, persistDemoPreference: false)
        defer { state.stopBackgroundWork(); try? FileManager.default.removeItem(at: directory) }
        try await state.loadDemo(name: "student@example.com", cacheKey: "formalise-test")
        let model = FormalisationModel(); state.intelligenceOverride = model
        let draft = Composer(localID: "local-formalise", mode: "new", to: "professor@example.edu", cc: "assistant@example.edu", subject: "", body: "Other private notes. choose A, replace X with Y. More notes.")
        let text = try SelectedPassage.extract(from: draft.body, range: (draft.body as NSString).range(of: "choose A, replace X with Y."))
        let count = state.cachedCount
        let preview = try await state.formaliseSelectedText(text, in: draft)
        XCTAssertEqual(preview.id, draft.id); XCTAssertEqual(preview.to, draft.to); XCTAssertEqual(preview.cc, draft.cc)
        XCTAssertEqual(preview.subject, "Presentation preference"); XCTAssertNotEqual(preview.body, draft.body)
        XCTAssertEqual(state.cachedCount, count); XCTAssertNil(state.composer)
        let requests = await model.received
        XCTAssertEqual(requests.first?.selectedText, "choose A, replace X with Y.")
        XCTAssertEqual(requests.first?.style.tone, .formal)
        XCTAssertFalse(requests.first!.instructions.contains("Other private notes"))
        var reviewed = preview; reviewed.body += "\nReviewed edit."
        _ = try await state.saveComposer(reviewed, send: true, presentComposerUpdates: false)
        state.selection = "sentitems"; await state.refreshCachedMail()
        XCTAssertEqual(state.messages.first?.body, reviewed.body)
    }
    func testFormalisationKeepsExistingSubject() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = AppState(cacheRoot: directory, persistDemoPreference: false)
        defer { state.stopBackgroundWork(); try? FileManager.default.removeItem(at: directory) }
        try await state.loadDemo(name: "student@example.com", cacheKey: "subject-test"); state.intelligenceOverride = FormalisationModel()
        let draft = Composer(localID: "local-subject", mode: "new", to: "professor@example.edu", cc: "", subject: "My existing subject", body: "choose A")
        let preview = try await state.formaliseSelectedText("choose A", in: draft)
        XCTAssertEqual(preview.subject, "My existing subject")
    }
}
