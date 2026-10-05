import XCTest
@testable import Aster
import AsterCore

@MainActor final class WorkspaceTests: XCTestCase {
    func testTwoAccountsKeepIdenticalMessageIDsAndRepliesIsolated() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = WorkspaceState(makeState: { AppState(cacheRoot: directory, persistDemoPreference: false) }, persistSettings: false)
        await workspace.loadDemoAccounts()
        defer { for profile in workspace.profiles { workspace.state(for: profile.id)?.stopBackgroundWork() } }
        XCTAssertEqual(workspace.profiles.count, 2)
        let first = workspace.profiles[0], second = workspace.profiles[1]
        let firstState = try XCTUnwrap(workspace.state(for: first.id)), secondState = try XCTUnwrap(workspace.state(for: second.id))
        let sharedMail = try XCTUnwrap(firstState.priorityMessages.first)
        let firstRow = UnifiedMail(account: first, mail: sharedMail)
        let secondRow = UnifiedMail(account: second, mail: sharedMail)
        XCTAssertNotEqual(firstRow.id, secondRow.id)
        workspace.select(secondRow)
        XCTAssertTrue(workspace.active === secondState)
        workspace.active.compose(mode: "reply")
        XCTAssertEqual(secondState.composer?.sourceID, sharedMail.id)
        XCTAssertNil(firstState.composer)
        secondState.composer = nil
        workspace.select(firstRow)
        XCTAssertTrue(workspace.active === firstState)
        XCTAssertEqual(workspace.active.accountName, first.email)
    }
    func testUnifiedSelectionOutsideInboxSurvivesCacheRefresh() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = AppState(cacheRoot: directory, persistDemoPreference: false)
        defer { state.stopBackgroundWork(); try? FileManager.default.removeItem(at: directory) }
        try await state.loadDemo(name: "selected@example.com", cacheKey: "workspace-regression")
        let sentID = try XCTUnwrap(state.folders.first { $0.role == "sentitems" }?.id)
        let draft = Composer(localID: "local-sent-fixture", mode: "new", to: "recipient@example.com", cc: "", subject: "Sent fixture", body: "Test")
        _ = try await state.saveComposer(draft, send: true)
        state.selection = sentID
        await state.refreshCachedMail()
        let sent = try XCTUnwrap(state.messages.first)
        state.selection = "inbox"; await state.refreshCachedMail()
        state.selectMail(sent)
        await state.refreshCachedMail()
        XCTAssertEqual(state.selected?.id, sent.id)
    }
    func testMovingJunkOnlyChangesTheConfiguredAccount() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = WorkspaceState(makeState: { AppState(cacheRoot: directory, persistDemoPreference: false) }, persistSettings: false)
        await workspace.loadDemoAccounts()
        defer { for profile in workspace.profiles { workspace.state(for: profile.id)?.stopBackgroundWork() } }
        let first = try XCTUnwrap(workspace.state(for: workspace.profiles[0].id)), second = try XCTUnwrap(workspace.state(for: workspace.profiles[1].id))
        first.selection = "junkemail"; second.selection = "junkemail"
        await first.refreshCachedMail(); await second.refreshCachedMail()
        XCTAssertEqual(first.messages.count, 1); XCTAssertEqual(second.messages.count, 1)
        var policy = first.policy; policy.junkMode = .moveToInbox; await first.applyPolicy(policy)
        await second.refreshCachedMail()
        XCTAssertTrue(first.messages.isEmpty); XCTAssertEqual(second.messages.count, 1)
        first.selection = "inbox"; await first.refreshCachedMail()
        XCTAssertTrue(first.messages.contains { $0.id == "demo-junk" })
    }

    func testDisconnectedAccountRetainsDraftAndCannotPretendToSend() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = AppState(cacheRoot: directory, persistDemoPreference: false)
        defer { state.stopBackgroundWork(); try? FileManager.default.removeItem(at: directory) }
        try await state.loadOfflineAccount(identity: "offline", email: "offline@example.com", provider: "google")
        let draft = Composer(localID: "local-offline", mode: "new", to: "recipient@example.com", cc: "", subject: "Retained draft", body: "Test")
        _ = try await state.saveComposer(draft, send: false)
        do { _ = try await state.saveComposer(draft, send: true); XCTFail("Disconnected sending must fail") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Reconnect")) }
        XCTAssertEqual(state.cachedCount, 1)
    }

}
