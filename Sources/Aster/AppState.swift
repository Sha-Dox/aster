import SwiftUI
import CryptoKit
import UniformTypeIdentifiers
import AsterCore

struct DraftFile: Codable, Identifiable {
    var id: String
    var name: String
    var path: String
    var contentType: String
    var size: Int
}
struct Composer: Identifiable, Codable {
    var id = UUID()
    var localID: String
    var remoteID: String?
    var sourceID: String?
    var mode: String
    var to: String
    var cc: String
    var bcc: String? = nil
    var files: [DraftFile]? = nil
    var subject: String
    var body: String
}
struct ReplyAssistantContext: Identifiable {
    let id = UUID()
    let mail: Mail
    let thread: [Mail]
    let accountEmail: String
    let session: UUID
    let replyAll: Bool
}
@MainActor final class AppState: ObservableObject {
    private let cacheRoot: URL?
    private let persistDemoPreference: Bool
    private let workspaceNameProvider: () -> String
    init(cacheRoot: URL? = nil, persistDemoPreference: Bool = true, workspaceNameProvider: @escaping () -> String = { UserDefaults.standard.string(forKey: "senderName") ?? "" }) { self.cacheRoot = cacheRoot; self.persistDemoPreference = persistDemoPreference; self.workspaceNameProvider = workspaceNameProvider }
    @Published var policy = AccountPolicy()
    @Published var priorityMessages: [Mail] = []
    @Published var priorityCount = 0
    var prioritySearch = ""
    @Published var messages: [Mail] = []
    @Published var folders: [MailFolder] = []
    @Published var selection = "inbox"
    @Published var selectedID: String?
    @Published private var selectionMemory: Mail?
    @Published var search = ""
    @Published var searchIDs: Set<String>?
    @Published var isDemo = false
    @Published var isReady = false
    @Published var isSyncing = false
    @Published var status = "Local-first mail"
    @Published var error: String?
    @Published var notice: String?
    @Published var accountName = ""
    @Published var summary: ThreadSummary?
    @Published var isSummarizing = false
    @Published var showSummary = false
    @Published var showSettings = false
    @Published var showPalette = false
    @Published var composer: Composer?
    @Published var replyAssistant: ReplyAssistantContext?
    var intelligenceOverride: (any IntelligenceProvider)?
    private var recoveredDrafts: [UUID: Composer] = [:]
    private var generatedReplies: [UUID: UUID] = [:]
    private var sendingReplies: Set<UUID> = []
    private var acceptedReplies: Set<UUID> = []
    @Published var attachments: [Attachment] = []
    @Published var isLoadingAttachments = false
    @Published var unreadOnly = false
    private var store: MailStore?
    private var auth: (any AccountSession)?
    private var backend: (any MailBackend)?
    private var generation = UUID()
    private var summaryTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    var inboxID: String { folders.first { $0.role == "inbox" }?.id ?? "inbox" }
    @Published var attention: [AttentionItem] = []
    @Published var pendingCount = 0
    @Published var cachedCount = 0
    @Published var viewCount = 0
    @Published var providerName = "Workspace"
    @Published var loadedLimit = 500
    @Published private var conversation: [Mail] = []
    private var threadTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var draftRequest = UUID()
    var hasMoreMail: Bool { search.isEmpty && viewCount > loadedLimit && !["attention", "reply"].contains(selection) }
    var selected: Mail? { messages.first { $0.id == selectedID } ?? (selectionMemory?.id == selectedID ? selectionMemory : nil) }
    var thread: [Mail] { guard let selected else { return [] }; return (conversation.first?.threadID == selected.threadID ? conversation : messages.filter { $0.threadID == selected.threadID }).filter { !$0.isDraft }.sorted { $0.date < $1.date } }
    var visible: [Mail] {
        let filtered = messages.filter { mail in
            let match: Bool
            switch selection {
            case "attention": match = attention.contains { $0.id == mail.id }
            case "reply": match = attention.contains { $0.id == mail.id && $0.kind == .reply }
            case "priority": match = true
            case "starred": match = mail.isFlagged
            default: match = mail.isInFolder(selection == "inbox" ? inboxID : selection)
            }
            return match && (!unreadOnly || !mail.isRead) && (searchIDs?.contains(mail.id) ?? true)
        }
        return Dictionary(grouping: filtered, by: \.threadID).compactMap { $0.value.max { $0.date < $1.date } }.sorted { $0.date > $1.date }
    }
    var title: String {
        switch selection { case "inbox": return "Inbox"; case "priority": return "Priority inbox"; case "attention": return "Attention"; case "reply": return "Needs reply"; case "starred": return "Starred"; default: return folders.first { $0.id == selection }?.name ?? "Inbox" }
    }
    var intelligence: any IntelligenceProvider {
        if let intelligenceOverride { return intelligenceOverride }
        let defaults = UserDefaults.standard
        if defaults.string(forKey: "intelligenceMode") == "remote", let url = URL(string: defaults.string(forKey: "aiEndpoint") ?? ""), let model = defaults.string(forKey: "aiModel"), !model.isEmpty {
            return RemoteIntelligence(endpoint: url, model: model, key: Keychain.read("provider"))
        }
        #if canImport(FoundationModels)
        if (defaults.string(forKey: "intelligenceMode") ?? "apple") == "apple", #available(macOS 26.0, *), AppleIntelligenceStatus.available { return AppleIntelligence() }
        #endif
        return LocalIntelligence()
    }
    func start() async {
        do {
            if CommandLine.arguments.contains("--demo") || UserDefaults.standard.bool(forKey: "demoMode") { try await loadDemo(); return }
            let provider = UserDefaults.standard.string(forKey: "lastProvider") ?? "microsoft"
            let key = provider == "google" ? "googleClientID" : "clientID"
            if !(UserDefaults.standard.string(forKey: key) ?? "").isEmpty { await resume(provider: provider) }
            else { status = "Connect a mail account" }
        } catch { self.error = error.localizedDescription }
    }
    private func database(_ name: String) throws -> MailStore {
        let support = try cacheRoot ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Aster", isDirectory: true)
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: support.path)
        let hash = SHA256.hash(data: Data(name.utf8)).map { String(format: "%02x", $0) }.joined()
        let path = support.appendingPathComponent(hash + ".sqlite").path
        let database = try MailStore(path: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        return database
    }
    private func resetSession() {
        generation = UUID(); pollingTask?.cancel(); summaryTask?.cancel(); searchTask?.cancel()
        syncTask?.cancel(); syncTask = nil; replyAssistant = nil; recoveredDrafts = [:]; generatedReplies = [:]; sendingReplies = []; acceptedReplies = []; threadTask?.cancel(); backend = nil; conversation = []; attention = []; store = nil; messages = []; folders = []; selectedID = nil; selectionMemory = nil; summary = nil; search = ""; searchIDs = nil; selection = "inbox"; showSummary = false; error = nil; notice = nil; isSyncing = false; isSummarizing = false; isReady = false; attachments = []; loadedLimit = 500; pendingCount = 0; cachedCount = 0; priorityMessages = []; priorityCount = 0
    }
    func loadDemo(name: String = "Demo workspace", cacheKey: String = "demo") async throws {
        resetSession(); auth = nil; isDemo = true; providerName = "Demo"; accountName = name
        let database = try database(cacheKey); store = database; try await database.upgradeIndexes()
        if try await database.metadata("seeded") == nil {
            for mail in DemoMail.messages() { try await database.save(mail) }
            try await database.setMetadata("seeded", "1")
        }
        if cacheKey.hasPrefix("demo-"), try await database.metadata("multi-demo:v1") == nil {
            let junk = Mail(id: "demo-junk", folderID: "junkemail", sender: Address("Weekly digest", "digest@example.com"), to: [Address("You", name)], subject: "Your weekly reading list", preview: "A message your provider put in Junk", body: "This is a safe demo message. Include Junk in Priority or move it back to Inbox using this account’s settings.")
            let archived = Mail(id: "demo-archived", folderID: "archive", sender: Address("Travel", "travel@example.com"), to: [Address("You", name)], subject: "Saved travel confirmation", preview: "Archived mail can appear in All received Priority", body: "This message remains archived on the provider while All received mail brings it into your Priority view.")
            try await database.save(junk); try await database.save(archived); try await database.setMetadata("multi-demo:v1", "1")
        }
        folders = DemoMail.folders; await reloadCache(session: generation); isReady = true
        selectedID = visible.first?.id; status = "Demo · saved on this Mac"
        if persistDemoPreference { UserDefaults.standard.set(true, forKey: "demoMode") }
    }
    func resume(provider: String) async {
        do {
            let candidate = try accountSession(provider)
            if candidate.identity != nil {
                try await loadAccount(candidate, provider: provider)
                UserDefaults.standard.set(false, forKey: "demoMode"); UserDefaults.standard.set(provider, forKey: "lastProvider")
            }
            else { status = "Connect a mail account" }
        } catch { self.error = error.localizedDescription }
    }
    private func accountSession(_ provider: String) throws -> any AccountSession {
        if provider == "google" { return try GoogleAuth(clientID: UserDefaults.standard.string(forKey: "googleClientID") ?? "") }
        return try MicrosoftAuth(clientID: UserDefaults.standard.string(forKey: "clientID") ?? "")
    }
    func connect(provider: String = "microsoft") async {
        do {
            let candidate = try accountSession(provider)
            try await candidate.signIn()
            try await loadAccount(candidate, provider: provider)
            UserDefaults.standard.set(false, forKey: "demoMode"); UserDefaults.standard.set(provider, forKey: "lastProvider"); showSettings = false
        } catch { self.error = error.localizedDescription }
    }
    func loadAccount(_ auth: any AccountSession, provider: String, startSync: Bool = true) async throws {
        resetSession(); self.auth = auth; isDemo = false; accountName = auth.username ?? "Mail account"
        guard let identity = auth.identity else { throw MailError.message("No authenticated account is available.") }
        let database = try database(identity); store = database; try await database.upgradeIndexes()
        backend = provider == "google" ? GmailClient(tokens: auth) : MicrosoftBackend(tokens: auth)
        providerName = backend?.name ?? "Mail"
        if let data = try await database.metadata("folders")?.data(using: .utf8) { folders = try JSONDecoder().decode([MailFolder].self, from: data) }
        await reloadCache(session: generation)
        isReady = true; selectedID = visible.first?.id; status = "Showing cached mail"
        if startSync { await sync() }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
                guard let self else { break }
                if NSApp.isActive { await self.sync() }
            }
        }
    }
    func loadOfflineAccount(identity: String, email: String, provider: String) async throws {
        resetSession(); auth = nil; isDemo = false; accountName = email; providerName = provider == "google" ? "Gmail" : "Microsoft"
        let database = try database(identity); store = database; try await database.upgradeIndexes()
        if let data = try await database.metadata("folders")?.data(using: .utf8) { folders = try JSONDecoder().decode([MailFolder].self, from: data) }
        await reloadCache(session: generation); isReady = true; status = "Reconnect account · cached mail available"
    }
    func stopBackgroundWork() { pollingTask?.cancel(); syncTask?.cancel(); summaryTask?.cancel(); searchTask?.cancel(); threadTask?.cancel() }
    @discardableResult func disconnect() -> Bool {
        do { try auth?.signOut(); resetSession(); auth = nil; isDemo = false; status = "Connect a mail account"; return true } catch { self.error = error.localizedDescription; return false }
    }
    func sync() async {
        guard syncTask == nil, !isDemo, backend != nil else { return }
        let session = generation
        let task = Task { await performSync() }; syncTask = task
        await task.value
        if generation == session { syncTask = nil }
    }
    func cancelSync() { syncTask?.cancel(); status = "Sync paused · cached mail available" }
    private func drainChanges(backend: any MailBackend, store: MailStore) async throws {
        for change in try await store.changes() {
            try Task.checkCancellation()
            do { try await backend.apply(change) }
            catch let failure as GraphFailure where failure.status == 404 { }
            catch let failure as GmailFailure where failure.status == 404 { }
            try await store.complete(change)
        }
    }
    private func performSync() async {
        guard !isSyncing, let backend, let store else { return }
        let session = generation
        isSyncing = true; status = "Syncing with \(backend.name)…"
        defer { if generation == session { isSyncing = false } }
        do {
            try await drainChanges(backend: backend, store: store)
            let fetched = try await backend.folders()
            guard generation == session else { return }
            folders = fetched
            try await store.setMetadata("folders", String(decoding: JSONEncoder().encode(fetched), as: UTF8.self))
            try await backend.synchronize(store: store, folders: fetched) { [weak self] in
                await self?.reloadCache(session: session)
            }
            if policy.junkMode == .moveToInbox { try await restoreJunk() }
            try await drainChanges(backend: backend, store: store)
            guard generation == session else { return }
            pendingCount = try await store.changes().count
            await reloadCache(session: session)
            status = pendingCount == 0 ? "Up to date · cached on this Mac" : "\(pendingCount) changes waiting to sync"
            self.error = nil
        } catch is CancellationError {
            if generation == session { status = "Sync paused · cached mail available" }
        } catch {
            guard generation == session else { return }
            let ns = error as NSError
            status = ns.domain == NSURLErrorDomain ? "Offline · cached mail available" : "Sync needs attention · cached mail available"
            self.error = error.localizedDescription
        }
    }
    func applyPolicy(_ value: AccountPolicy) async {
        let enableJunkRecovery = value.junkMode == .moveToInbox && policy.junkMode != .moveToInbox
        policy = value
        await reloadCache(session: generation)
        if enableJunkRecovery {
            if isDemo { do { try await restoreJunk(); await reloadCache(session: generation) } catch { self.error = error.localizedDescription } }
            else { await sync() }
        }
    }
    func setPrioritySearch(_ query: String) async { prioritySearch = query; await reloadCache(session: generation) }
    func refreshCachedMail() async { await reloadCache(session: generation) }
    func restoreJunk() async throws {
        guard let store, let junk = folders.first(where: { $0.role == "junkemail" }) else { return }
        // Bound each batch, but continue until all cached junk has been routed. The queue is durable.
        while true {
            try Task.checkCancellation()
            let batch = try await store.recent(limit: 100, folder: junk.id)
            if batch.isEmpty { break }
            for mail in batch {
                let change = PendingChange(messageID: mail.id, kind: "move", value: inboxID)
                if isDemo { try await store.applyLocal(change, fallback: mail) } else { try await store.queue(change, mail: mail) }
            }
            if let backend, !isDemo { try await drainChanges(backend: backend, store: store) }
        }
    }
    private var cacheFolder: String {
        switch selection { case "inbox", "attention", "reply": return inboxID; case "starred": return "@starred"; default: return selection }
    }
    func changeView() {
        selectedID = nil; selectionMemory = nil; conversation = []; loadedLimit = 500; summary = nil; showSummary = false
        Task { await reloadCache(session: generation); if let id = visible.first?.id { select(id) } }
    }
    private func reloadCache(session: UUID) async {
        do {
            guard let store else { return }
            let view = selection; let priorityQuery = prioritySearch; let currentPolicy = policy
            let hints = try await store.attention(inbox: inboxID, sent: folders.first { $0.role == "sentitems" }?.id ?? "sentitems")
            let priority = try await store.priority(policy: currentPolicy, folders: folders, limit: priorityQuery.isEmpty ? loadedLimit : 1000, search: priorityQuery)
            let totalPriority = try await store.priorityCount(policy: policy, folders: folders)
            let cached = selection == "priority" ? try await store.priority(policy: policy, folders: folders, limit: loadedLimit, search: search) : try await store.recent(limit: loadedLimit, folder: cacheFolder)
            let count = try await store.count()
            let folderCount = try await store.count(folder: cacheFolder)
            var currentSelected: Mail?
            if let id = selectedID { currentSelected = try await store.message(id) }
            guard generation == session, selection == view, prioritySearch == priorityQuery, policy == currentPolicy else { return }
            selectionMemory = currentSelected
            priorityMessages = priority; priorityCount = totalPriority
            attention = hints; messages = ["attention", "reply"].contains(selection) ? hints.map(\.mail) : cached; cachedCount = count; viewCount = selection == "priority" ? totalPriority : folderCount
            if !search.isEmpty { await runSearch() }
            if selectedID == nil { selectedID = visible.first?.id }
        } catch { if generation == session { self.error = error.localizedDescription } }
    }
    func loadMore() async { loadedLimit += 500; await reloadCache(session: generation) }
    func selectMail(_ mail: Mail) {
        if !messages.contains(where: { $0.id == mail.id }) { messages.append(mail) }
        select(mail.id)
    }
    func select(_ id: String) {
        if !messages.contains(where: { $0.id == id }), let hinted = attention.first(where: { $0.id == id }) { messages.append(hinted.mail) }
        selectionMemory = messages.first { $0.id == id } ?? selectionMemory
        selectedID = id; summary = nil; showSummary = false; summaryTask?.cancel(); isSummarizing = false; attachments = []
        threadTask?.cancel()
        if let mail = selected, let store {
            let session = generation
            threadTask = Task {
                do { let cached = try await store.thread(mail.threadID); if selectedID == id && generation == session && !Task.isCancelled { conversation = cached } }
                catch { if generation == session { self.error = error.localizedDescription } }
            }
        }
        if let mail = selected, !mail.isRead { mutate(mail, kind: "read", value: "true") }
    }
    func navigate(_ direction: Int) {
        let rows = visible; guard !rows.isEmpty else { return }
        let index = rows.firstIndex { $0.id == selectedID } ?? 0
        select(rows[min(max(index + direction, 0), rows.count - 1)].id)
    }
    func mutate(_ mail: Mail, kind: String, value: String) {
        guard let store else { return }
        var updated = mail
        let change = PendingChange(messageID: mail.id, kind: kind, value: value); change.apply(to: &updated)
        let session = generation
        Task {
            do {
                if isDemo { try await store.applyLocal(change, fallback: updated) } else { try await store.queue(change, mail: updated) }
                guard session == generation else { return }
                pendingCount = try await store.changes().count
                await reloadCache(session: session)
                if kind == "move" { selectedID = visible.first?.id }
                if !isDemo { await sync() }
            } catch { self.error = error.localizedDescription }
        }
    }
    func moveSelected(to roleOrID: String) {
        guard let mail = selected else { return }
        guard let folder = folders.first(where: { $0.role == roleOrID || $0.id == roleOrID }) else { error = "This account does not have that folder. Choose a destination from Move to."; return }
        let session = generation
        Task {
            let members = (try? await store?.thread(mail.threadID)) ?? messages.filter { $0.threadID == mail.threadID }
            guard generation == session else { return }
            for member in members where member.isInFolder(mail.folderID) { mutate(member, kind: "move", value: folder.id) }
        }
    }
    func searchChanged() {
        searchTask?.cancel()
        searchTask = Task { try? await Task.sleep(for: .milliseconds(120)); guard !Task.isCancelled else { return }; await runSearch() }
    }
    private func runSearch() async {
        let query = search; let session = generation; let view = selection
        do {
            if view == "priority", let store {
                let matches = try await store.priority(policy: policy, folders: folders, limit: query.isEmpty ? loadedLimit : 1000, search: query)
                guard query == search, generation == session, selection == view else { return }
                searchIDs = nil; messages = matches; return
            }
            let ids = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : try await store?.search(query, folder: cacheFolder)
            if query == search && session == generation && selection == view {
                searchIDs = ids
                if let ids, let store { messages = try await store.matching(ids) }
                else if let store { messages = ["attention", "reply"].contains(selection) ? attention.map(\.mail) : try await store.recent(limit: loadedLimit, folder: cacheFolder) }
            }
        } catch { self.error = error.localizedDescription }
    }
    func summarize() {
        guard !isSummarizing, selected != nil else { return }
        let mails = thread; let id = selectedID; let session = generation; let provider = intelligence
        showSummary = true; isSummarizing = true
        summaryTask = Task {
            do { let result = try await provider.summarize(mails); guard !Task.isCancelled, selectedID == id, generation == session else { return }; summary = result }
            catch { if !Task.isCancelled && generation == session { self.error = error.localizedDescription } }
            if selectedID == id && generation == session { isSummarizing = false }
        }
    }
    private func makeComposer(mode: String, mail: Mail?, generated: String?, quoteOriginal: Bool = true) -> Composer {

        let recipients = mail.map { value in
            value.sender.address.lowercased() == accountName.lowercased() ? value.to : value.replyTo.isEmpty ? [value.sender] : value.replyTo
        } ?? []
        var cc = mode == "replyAll" ? (mail?.to ?? []) + (mail?.cc ?? []) : []
        var seen = Set(recipients.map { $0.address.lowercased() }); seen.insert(accountName.lowercased())
        cc = cc.filter { seen.insert($0.address.lowercased()).inserted }
        let subject = mail.map { (mode == "forward" ? "Fwd: " : $0.subject.lowercased().hasPrefix("re:") ? "" : "Re: ") + $0.subject } ?? ""
        let quote = quoteOriginal ? mail.map { "\n\n\n— Original message —\nFrom: \($0.sender.name) <\($0.sender.address)>\n\($0.isHTML ? MIME.plainText($0.body) : $0.body)" } ?? "" : ""
        var value = Composer(localID: "local-" + UUID().uuidString, mode: mode, to: mode == "forward" ? "" : recipients.map(\.address).joined(separator: ", "), cc: cc.map(\.address).joined(separator: ", "), subject: subject, body: (generated ?? "") + quote)
        value.sourceID = mail?.id
        return value
    }
    func compose(mode: String = "new", generated: String? = nil) {
        let mail = mode == "new" ? nil : selected
        guard mode == "new" || mail != nil else { return }
        composer = makeComposer(mode: mode, mail: mail, generated: generated)
    }
    var senderName: String { SenderPersonalization.resolve(workspaceName: workspaceNameProvider(), accountName: policy.senderName) }
    var senderIdentity: String { senderName.isEmpty ? accountName : "\(senderName) <\(accountName)>" }
    var writingStyle: WritingStyle {
        if let style = policy.writingStyle { return style }
        if let data = UserDefaults.standard.data(forKey: "defaultWritingStyle:v1"), let style = try? JSONDecoder().decode(WritingStyle.self, from: data) { return style }
        return WritingStyle()
    }
    func prepareReplyAssistant(replyAll: Bool = false) async throws -> ReplyAssistantContext {
        guard let mail = selected, !mail.isDraft else { throw MailError.message("Select an incoming conversation first.") }
        let session = generation
        let cached = try await store?.thread(mail.threadID) ?? [mail]
        guard session == generation, selectedID == mail.id else { throw CancellationError() }
        return ReplyAssistantContext(mail: mail, thread: cached.isEmpty ? [mail] : cached, accountEmail: accountName, session: session, replyAll: replyAll)
    }
    func openReplyAssistant(replyAll: Bool = false) {
        Task {
            do { replyAssistant = try await prepareReplyAssistant(replyAll: replyAll) }
            catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }
    func generateAssistedReply(_ context: ReplyAssistantContext, intent: String, style: WritingStyle) async throws -> Composer {
        guard context.session == generation, context.accountEmail == accountName else { throw MailError.message("This account changed. Open the reply assistant again.") }
        let request = ReplyRequest(intent: intent, style: style, senderAddress: context.accountEmail, targetMessageID: context.mail.id, senderName: senderName)
        try request.validate()
        let body = try await intelligence.draftReply(context.thread, request: request)
        try Task.checkCancellation()
        guard context.session == generation else { throw CancellationError() }
        let clean = SenderPersonalization.finish(body, name: request.senderName, signature: style.signature)
        guard !clean.isEmpty, clean.count <= 30_000 else { throw MailError.message("The generated reply is empty or too long. Adjust your instructions and try again.") }
        let draft = makeComposer(mode: context.replyAll ? "replyAll" : "reply", mail: context.mail, generated: clean, quoteOriginal: false)
        generatedReplies[draft.id] = context.id
        return draft
    }
    func sendAcceptedReply(_ context: ReplyAssistantContext, draft: Composer) async throws {
        guard context.session == generation, context.accountEmail == accountName, replyAssistant?.id == context.id else { throw MailError.message("The reply preview belongs to a different session. Open it again before sending.") }
        guard generatedReplies[draft.id] == context.id, !acceptedReplies.contains(draft.id), !sendingReplies.contains(draft.id) else { throw MailError.message("Generate and review a new reply preview before sending.") }
        sendingReplies.insert(draft.id); defer { sendingReplies.remove(draft.id) }
        _ = try await saveComposer(draft, send: true, presentComposerUpdates: false)
        acceptedReplies.insert(draft.id)
    }
    func formaliseSelectedText(_ selectedText: String, in draft: Composer) async throws -> Composer {
        let session = generation; let email = accountName
        var style = writingStyle; style.tone = .formal
        if draft.sourceID == nil && style.language == "Match the original email" { style.language = "Match the selected text" }
        let context: [Mail]
        if let source = draft.sourceID, let original = try await store?.message(source) { context = try await store?.thread(original.threadID) ?? [original] }
        else { context = [] }
        let request = FormaliseRequest(selectedText: selectedText, style: style, senderAddress: email, recipientAddress: draft.to, existingSubject: draft.subject, targetMessageID: draft.sourceID, senderName: senderName)
        try request.validate()
        let generated = try await intelligence.formalise(context, request: request)
        try Task.checkCancellation()
        guard session == generation, email == accountName else { throw CancellationError() }
        let body = SenderPersonalization.finish(generated.body, name: request.senderName, signature: style.signature)
        let subject = generated.subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, body.count <= 30_000, subject.count <= 998, !subject.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else { throw MailError.message("The generated email is empty or has an invalid subject. Try again.") }
        var preview = draft; preview.body = body
        if preview.subject.isEmpty { preview.subject = subject }
        return preview
    }
    func latestDraft(_ id: UUID) -> Composer? { recoveredDrafts[id] }
    func openDraft(_ mail: Mail) {
        let request = UUID(); draftRequest = request
        let session = generation
        Task {
            do {
                var value = Composer(localID: mail.id, remoteID: mail.id.hasPrefix("local-") || isDemo ? nil : mail.id, mode: "new", to: mail.to.map(\.address).joined(separator: ", "), cc: mail.cc.map(\.address).joined(separator: ", "), subject: mail.subject, body: mail.isHTML ? MIME.plainText(mail.body) : mail.body)
                value.bcc = (mail.bcc ?? []).map(\.address).joined(separator: ", ")
                if let text = try await store?.metadata("draft:" + mail.id), let data = text.data(using: .utf8), let saved = try? JSONDecoder().decode(Composer.self, from: data) { value = saved }
                else if providerName == "Gmail", !mail.id.hasPrefix("local-") {
                    guard let id = try await store?.metadata("gmailDraft:" + mail.id) else { throw MailError.message("Synchronize Gmail before opening this remote draft. Its cached draft identifier is missing.") }
                    value.remoteID = id
                }
                if generation == session && draftRequest == request { composer = value }
            } catch { if generation == session { self.error = error.localizedDescription } }
        }
    }
    private func plainText(_ html: String) -> String {
        html.replacingOccurrences(of: "(?i)<br\\s*/?>|</p>|</div>", with: "\n", options: .regularExpression).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression).replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&")
    }
    func generateReply() async { openReplyAssistant() }
    func importAttachments(existing: [DraftFile]) async throws -> [DraftFile] {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = false; panel.canChooseFiles = true
        guard await presentFilePanel(panel) == .OK else { return [] }
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Aster/DraftAttachments", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var result: [DraftFile] = [], total = existing.reduce(0) { $0 + $1.size }
        for url in panel.urls {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            guard size <= 3_000_000 && total + size <= 20_000_000 else { throw MailError.message("Use files up to 3 MB each, with a 20 MB total limit.") }
            let id = UUID().uuidString; let target = directory.appendingPathComponent(id)
            let bytes = try Data(contentsOf: url)
            guard bytes.count <= 3_000_000, total + bytes.count <= 20_000_000 else { throw MailError.message("The attachment is too large.") }
            try bytes.write(to: target, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
            result.append(DraftFile(id: id, name: url.lastPathComponent, path: target.path, contentType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream", size: bytes.count)); total += bytes.count
        }
        return result
    }
    func autosave(_ value: Composer) async throws {
        try SenderPersonalization.validate(senderName)
        guard let store else { return }
        let folder = folders.first { $0.role == "drafts" }?.id ?? "drafts"
        var mail = Mail(id: value.localID, threadID: value.sourceID.flatMap { source in messages.first { $0.id == source }?.threadID }, folderID: folder, sender: Address(senderName.isEmpty ? "You" : senderName, accountName), to: AddressParser.parse(value.to), cc: AddressParser.parse(value.cc), subject: value.subject, preview: String(value.body.prefix(160)), body: value.body, isRead: true, isDraft: true)
        mail.bcc = AddressParser.parse(value.bcc ?? ""); mail.hasAttachments = !(value.files ?? []).isEmpty
        try await store.saveDraft(mail, context: String(decoding: JSONEncoder().encode(value), as: UTF8.self))
    }
    func saveComposer(_ value: Composer, send: Bool, presentComposerUpdates: Bool = true) async throws -> Composer {
        try SenderPersonalization.validate(senderName)
        guard let store else { throw MailError.message("No mailbox is open.") }
        let session = generation
        let to = AddressParser.parse(value.to), cc = AddressParser.parse(value.cc), bcc = AddressParser.parse(value.bcc ?? "")
        guard !send || (!(to + cc + bcc).isEmpty && (to + cc + bcc).allSatisfy { MIME.validAddress($0.address) }) else { throw MailError.message("Enter valid recipient addresses, separated by commas.") }
        let folderID = folders.first { $0.role == "drafts" }?.id ?? "drafts"
        var mail = Mail(id: value.localID, threadID: value.sourceID.flatMap { source in messages.first { $0.id == source }?.threadID }, folderID: folderID, sender: Address(senderName.isEmpty ? "You" : senderName, accountName), to: to, cc: cc, subject: value.subject, preview: String(value.body.prefix(160)), body: value.body, isRead: true, isDraft: true)
        mail.bcc = bcc; mail.hasAttachments = !(value.files ?? []).isEmpty
        var result = value
        notice = nil
        // Saving is always local first. Network failure preserves the draft.
        if send, try await store.metadata("send:" + value.id.uuidString) != nil {
            throw MailError.message("A previous send attempt is unresolved. Check Sent and synchronize before creating another message; automatic resending is blocked to avoid duplicates.")
        }
        try await store.saveDraft(mail, context: String(decoding: JSONEncoder().encode(value), as: UTF8.self))
        if send, !isDemo, backend == nil { await reloadCache(session: session); throw MailError.message("Reconnect this account before sending. Your local draft is retained.") }
        if !isDemo, let backend {
            do {
                var saved = try await backend.saveDraft(mail, remoteID: value.remoteID, sourceID: value.sourceID, mode: value.mode)
                var remote = saved.mail
                guard session == generation else { throw CancellationError() }
                try await store.save(remote); if remote.id != mail.id { try await store.remove(mail.id) }
                mail = remote; result.remoteID = saved.draftID; result.localID = remote.id; result.sourceID = nil
                try await store.setMetadata("draft:" + result.localID, String(decoding: JSONEncoder().encode(result), as: UTF8.self))
                recoveredDrafts[value.id] = result
                if presentComposerUpdates { composer = result } // persist the remote ID before sending so retries don't create another draft
                if send {
                    let files = try (value.files ?? []).map { file -> OutgoingAttachment in
                        let data = try Data(contentsOf: URL(fileURLWithPath: file.path))
                        guard data.count <= 3_000_000 else { throw MailError.message("Attachments must be 3 MB or smaller.") }
                        return OutgoingAttachment(id: file.id, name: file.name, contentType: file.contentType, data: data)
                    }
                    guard files.reduce(0, { $0 + $1.data.count }) <= 20_000_000 else { throw MailError.message("Attachments exceed the 20 MB total limit.") }
                    saved = try await backend.addAttachments(files, to: saved)
                    guard session == generation else { throw CancellationError() }
                    remote = saved.mail
                    if result.localID != remote.id { try await store.remove(result.localID) }
                    result.localID = remote.id; result.remoteID = saved.draftID
                    try await store.saveDraft(remote, context: String(decoding: JSONEncoder().encode(result), as: UTF8.self))
                    recoveredDrafts[value.id] = result
                    if presentComposerUpdates { composer = result }
                    try await store.setMetadata("send:" + value.id.uuidString, "pending")
                    do { try await backend.sendDraft(saved.draftID); try await store.setMetadata("send:" + value.id.uuidString, "accepted") }
                    catch { throw MailError.message("Sending could not be confirmed. Your draft is retained; sync and check Sent before retrying. \(error.localizedDescription)") }
                    try await store.remove(remote.id)
                }
            } catch {
                await reloadCache(session: session)
                if send { throw error }
                notice = "Draft saved locally. Provider sync unavailable: \(error.localizedDescription)"
            }
        } else if send {
            mail.folderID = folders.first { $0.role == "sentitems" }?.id ?? "sentitems"; mail.isDraft = false; try await store.save(mail)
        }
        await reloadCache(session: session)
        if send { notice = isDemo ? "Demo message saved to Sent. No email was delivered." : "Message accepted by the mail provider."; await sync() }
        else if notice == nil { notice = "Draft saved." }
        return result
    }
    func loadAttachments() async {
        guard let mail = selected, !isLoadingAttachments else { return }
        if isDemo { notice = "This demo message illustrates attachments. Connect a mail account to download real files."; return }
        guard let backend else { return }
        isLoadingAttachments = true; defer { isLoadingAttachments = false }
        do { let fetched = try await backend.attachments(mail.id); if selectedID == mail.id { attachments = fetched.filter { $0.isInline != true } } } catch { self.error = error.localizedDescription }
    }
    func download(_ attachment: Attachment) async {
        guard let backend, let mail = selected else { return }
        let panel = NSSavePanel(); panel.nameFieldStringValue = URL(fileURLWithPath: attachment.name).lastPathComponent
        guard await presentFilePanel(panel) == .OK, let url = panel.url else { return }
        do { let data = try await backend.attachmentData(mail.id, attachment.id); try data.write(to: url, options: .atomic); notice = "Attachment saved." } catch { self.error = error.localizedDescription }
    }
    private func presentFilePanel(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
        await withCheckedContinuation { continuation in
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
            } else { panel.begin { continuation.resume(returning: $0) } }
        }
    }

}
