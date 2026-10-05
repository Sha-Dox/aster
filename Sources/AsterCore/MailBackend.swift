import Foundation

public struct SavedDraft: Sendable {
    public let mail: Mail
    public let draftID: String
    public init(mail: Mail, draftID: String) { self.mail = mail; self.draftID = draftID }
}
public protocol MailBackend: Sendable {
    var name: String { get }
    func folders() async throws -> [MailFolder]
    func synchronize(store: MailStore, folders: [MailFolder], progress: @escaping @Sendable () async -> Void) async throws
    func apply(_ change: PendingChange) async throws
    func saveDraft(_ mail: Mail, remoteID: String?, sourceID: String?, mode: String) async throws -> SavedDraft
    func addAttachments(_ files: [OutgoingAttachment], to draft: SavedDraft) async throws -> SavedDraft
    func sendDraft(_ id: String) async throws
    func attachments(_ mailID: String) async throws -> [Attachment]
    func attachmentData(_ mailID: String, _ attachmentID: String) async throws -> Data
}
public struct MicrosoftBackend: MailBackend {
    public let name = "Microsoft 365"
    public let graph: GraphClient
    public init(tokens: any TokenProvider) { graph = GraphClient(tokens: tokens) }
    public func folders() async throws -> [MailFolder] { try await graph.folders() }
    public func apply(_ change: PendingChange) async throws { try await graph.apply(change) }
    public func saveDraft(_ mail: Mail, remoteID: String?, sourceID: String?, mode: String) async throws -> SavedDraft {
        let saved = try await graph.saveDraft(mail, remoteID: remoteID, sourceID: sourceID, mode: mode)
        return SavedDraft(mail: saved, draftID: saved.id)
    }
    public func addAttachments(_ files: [OutgoingAttachment], to draft: SavedDraft) async throws -> SavedDraft { try await graph.attach(files, to: draft.mail.id); return draft }
    public func sendDraft(_ id: String) async throws { try await graph.sendDraft(id) }
    public func attachments(_ mailID: String) async throws -> [Attachment] { try await graph.attachments(mailID) }
    public func attachmentData(_ mailID: String, _ attachmentID: String) async throws -> Data { try await graph.attachmentData(mailID, attachmentID) }
    public func synchronize(store: MailStore, folders: [MailFolder], progress: @escaping @Sendable () async -> Void) async throws {
        let ordered = folders.sorted { priority($0) < priority($1) }
        for folder in ordered {
            var cursor = try await store.metadata("delta:\(folder.id)")
            var didReset = false
            if cursor == nil { try await store.beginSnapshot(folder.id) }
            repeat {
                try Task.checkCancellation()
                let page: GraphPage
                do { page = try await graph.delta(folder: folder.id, cursor: cursor) }
                catch let failure as GraphFailure where failure.status == 410 && !didReset {
                    // Keep the readable cache until the fresh enumeration finishes. Resetting the cursor is sufficient;
                    // snapshot reconciliation after completion removes obsolete records without a blank inbox.
                    try await store.beginSnapshot(folder.id); cursor = nil; didReset = true; continue
                }
                guard let next = page.next ?? page.delta else { throw MailError.message("Microsoft did not provide a sync cursor.") }
                try await store.applyPage(page.value.filter { !$0.isRemoved }.map { $0.mail(folder: folder.id) }, removed: page.value.filter(\.isRemoved).map(\.id), folder: folder.id, cursor: next)
                cursor = page.next
            } while cursor != nil
            try await store.finishSnapshot(folder.id, folder: folder.id)
            await progress()
        }
    }
    private func priority(_ folder: MailFolder) -> Int { folder.role == "inbox" ? 0 : folder.role == "sentitems" ? 1 : 2 }
}
