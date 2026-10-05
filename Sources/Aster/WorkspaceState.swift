import SwiftUI
import Combine
import AsterCore

struct UnifiedMail: Identifiable {
    let account: AccountProfile
    let mail: Mail
    var id: String { account.scopedMessageID(mail.id) }
}

@MainActor final class WorkspaceState: ObservableObject {
    @Published var profiles: [AccountProfile] = []
    @Published var scope = "unified"
    @Published var readingAccountID: UUID?
    @Published var unifiedSearch = ""
    @Published var failure: String?
    @Published var connecting = false
    private var sessions: [UUID: AppState] = [:]
    private var subscriptions: [UUID: AnyCancellable] = [:]
    private let empty: AppState
    private let makeState: () -> AppState
    private let persistSettings: Bool
    init(makeState: (() -> AppState)? = nil, persistSettings: Bool = true) {
        let factory = makeState ?? { AppState() }
        self.makeState = factory; self.persistSettings = persistSettings; self.empty = factory()
    }
    private var started = false
    private var searchTask: Task<Void, Never>?
    var active: AppState {
        let id = UUID(uuidString: scope) ?? readingAccountID ?? profiles.first?.id
        return id.flatMap { sessions[$0] } ?? empty
    }
    var unifiedRows: [UnifiedMail] {
        profiles.flatMap { profile -> [UnifiedMail] in
            let mails = sessions[profile.id]?.priorityMessages ?? []
            // Provider thread identifiers are only meaningful within their own account.
            return Dictionary(grouping: mails, by: \.threadID).compactMap { $0.value.max { $0.date < $1.date } }.map { UnifiedMail(account: profile, mail: $0) }
        }.sorted { $0.mail.date > $1.mail.date }
    }
    var totalPriority: Int { sessions.values.reduce(0) { $0 + $1.priorityCount } }
    var syncingCount: Int { sessions.values.filter(\.isSyncing).count }
    func state(for id: UUID) -> AppState? { sessions[id] }
    private func saveProfiles() {
        guard persistSettings else { return }
        if let data = try? JSONEncoder().encode(profiles.filter { $0.provider != "demo" }) { UserDefaults.standard.set(data, forKey: "accounts:v1") }
    }
    private func watch(_ state: AppState, id: UUID) {
        subscriptions[id] = state.objectWillChange.sink { [weak self] in
            // Publish after the child's stored values change, so unified rows and badges stay current.
            Task { @MainActor in self?.objectWillChange.send() }
        }
    }
    private func session(for profile: AccountProfile) throws -> any AccountSession {
        if profile.provider == "google" { return try GoogleAuth(clientID: profile.clientID, accountKey: ":" + profile.id.uuidString) }
        return try MicrosoftAuth(clientID: profile.clientID, accountID: profile.identity)
    }
    func start() async {
        guard !started else { return }; started = true
        if let data = UserDefaults.standard.data(forKey: "accounts:v1"), let saved = try? JSONDecoder().decode([AccountProfile].self, from: data) { profiles = saved }
        if profiles.isEmpty && (CommandLine.arguments.contains("--demo") || UserDefaults.standard.bool(forKey: "demoMode")) { await loadDemoAccounts(); return }
        for profile in profiles {
            let state = makeState(); sessions[profile.id] = state; watch(state, id: profile.id)
            do {
                let auth = try session(for: profile)
                guard auth.identity != nil else { throw MailError.message("Reconnect \(profile.email) in Settings.") }
                state.policy = profile.policy
                try await state.loadAccount(auth, provider: profile.provider, startSync: false)
            } catch {
                let reason = error.localizedDescription
                do { state.policy = profile.policy; try await state.loadOfflineAccount(identity: profile.identity, email: profile.email, provider: profile.provider) } catch { state.accountName = profile.email }
                state.error = reason
            }
        }
        readingAccountID = profiles.first?.id
        if profiles.isEmpty && !UserDefaults.standard.bool(forKey: "accountsMigrated:v1") {
            // Migrate the previously saved single account without discarding its cache or credentials.
            let provider = UserDefaults.standard.string(forKey: "lastProvider") ?? "microsoft"
            let clientID = UserDefaults.standard.string(forKey: provider == "google" ? "googleClientID" : "clientID") ?? ""
            if !clientID.isEmpty {
                do {
                    let auth: any AccountSession = provider == "google" ? try GoogleAuth(clientID: clientID) : try MicrosoftAuth(clientID: clientID)
                    if auth.identity != nil { try await register(auth, provider: provider, clientID: clientID, id: UUID(), legacyGoogle: provider == "google") }
                } catch { failure = error.localizedDescription }
            }
            UserDefaults.standard.set(true, forKey: "accountsMigrated:v1")
        }
        if profiles.isEmpty { empty.status = "Connect a mail account" }
        Task { await syncAll() }
    }
    func connect(provider: String, reconnectID: UUID? = nil) async {
        guard !connecting else { return }; connecting = true; defer { connecting = false }
        do {
            let existing = reconnectID.flatMap { id in profiles.first { $0.id == id } }
            let id = UUID() // authorize into a new slot; an incorrect reconnect cannot overwrite another account’s credentials
            let clientID = existing?.clientID ?? UserDefaults.standard.string(forKey: provider == "google" ? "googleClientID" : "clientID") ?? ""
            let auth: any AccountSession = provider == "google" ? try GoogleAuth(clientID: clientID, accountKey: ":" + id.uuidString) : try MicrosoftAuth(clientID: clientID, accountID: existing?.identity ?? "")
            try await auth.signIn()
            if let existing, auth.identity != existing.identity {
                if provider == "google" { try? auth.signOut() }
                throw MailError.message("Choose \(existing.email) to reconnect this account. Use Connect to add a different address.")
            }
            try await register(auth, provider: provider, clientID: clientID, id: id)
            UserDefaults.standard.set(false, forKey: "demoMode")
            active.showSettings = false
            empty.showSettings = false
        } catch { failure = error.localizedDescription }
    }
    private func register(_ auth: any AccountSession, provider: String, clientID: String, id: UUID, legacyGoogle: Bool = false) async throws {
        guard let identity = auth.identity, let email = auth.username else { throw MailError.message("The connected account has no identity.") }
        // Google legacy credentials are copied into a dedicated account slot; refreshes then stay isolated.
        if legacyGoogle, let data = Keychain.readData("google-oauth:" + clientID) {
            try Keychain.saveData(data, account: "google-oauth:" + clientID + ":" + id.uuidString)
            UserDefaults.standard.set(email, forKey: "googleEmail:" + clientID + ":" + id.uuidString)
        }
        let previous = profiles.first { $0.provider == provider && $0.identity == identity }
        let profile = AccountProfile(id: id, provider: provider, clientID: clientID, identity: identity, email: email, policy: previous?.policy ?? AccountPolicy())
        let state = makeState(); state.policy = profile.policy
        try await state.loadAccount(legacyGoogle ? try session(for: profile) : auth, provider: provider, startSync: false)
        if let previous { sessions[previous.id]?.stopBackgroundWork(); sessions.removeValue(forKey: previous.id); subscriptions.removeValue(forKey: previous.id); profiles.removeAll { $0.id == previous.id } }
        sessions[id] = state; watch(state, id: id); profiles.append(profile); readingAccountID = id; scope = id.uuidString
        if persistSettings { UserDefaults.standard.set(true, forKey: "accountsMigrated:v1") }
        saveProfiles(); Task { await state.sync() }
    }
    func select(_ row: UnifiedMail) {
        guard let state = sessions[row.account.id] else { return }
        readingAccountID = row.account.id; state.selectMail(row.mail)
    }
    func updatePolicy(_ policy: AccountPolicy, accountID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == accountID }) else { return }
        profiles[index].policy = policy; saveProfiles()
        Task { await sessions[accountID]?.applyPolicy(policy) }
    }
    func removeAccount(_ id: UUID) {
        sessions[id]?.stopBackgroundWork()
        guard sessions[id]?.disconnect() != false else { failure = sessions[id]?.error; return }
        sessions.removeValue(forKey: id); subscriptions.removeValue(forKey: id); profiles.removeAll { $0.id == id }
        if readingAccountID == id { readingAccountID = profiles.first?.id }; scope = "unified"; saveProfiles()
    }
    func loadDemoAccounts() async {
        do {
            let definitions = [("personal@example.com", "demo-personal"), ("work@example.com", "demo-work")]
            for (email, key) in definitions {
                if profiles.contains(where: { $0.identity == key }) { continue }
                var policy = AccountPolicy()
                if key == "demo-personal" { policy.priorityMode = .allReceived; policy.junkMode = .includeInPriority; policy.hideJunkFolder = true }
                let profile = AccountProfile(provider: "demo", clientID: "", identity: key, email: email, policy: policy)
                let state = makeState(); state.policy = policy; try await state.loadDemo(name: email, cacheKey: key)
                profiles.append(profile); sessions[profile.id] = state; watch(state, id: profile.id)
            }
            readingAccountID = profiles.first?.id; scope = "unified"
        } catch { failure = error.localizedDescription }
    }
    func syncAll() async {
        // Each account owns its token provider, SQLite cache and mutation queue.
        await withTaskGroup(of: Void.self) { group in
            for state in sessions.values { group.addTask { await state.sync() } }
        }
    }
    func loadMore() async { for state in sessions.values { await state.loadMore() } }
    func searchChanged() {
        searchTask?.cancel(); let query = unifiedSearch
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(150)); guard !Task.isCancelled else { return }
            for state in sessions.values { guard !Task.isCancelled else { return }; await state.setPrioritySearch(query) }
        }
    }
}
