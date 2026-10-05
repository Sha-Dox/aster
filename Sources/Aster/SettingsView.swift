import SwiftUI
import AsterCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var workspace: WorkspaceState
    @State private var editingAccount: UUID?
    @State private var defaultStyle = WritingStyle()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("clientID") private var clientID = ""
    @AppStorage("googleClientID") private var googleClientID = ""
    @AppStorage("intelligenceMode") private var intelligenceMode = "apple"
    @AppStorage("glassStyle") private var glassStyle = "clear"
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("aiEndpoint") private var endpoint = "https://api.openai.com/v1"
    @AppStorage("aiModel") private var model = ""
    @State private var apiKey = ""
    @State private var googleSecret = ""
    @State private var signingIn = false
    @State private var saved = false
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "asterisk").foregroundStyle(Color.aster)
                Text("Your workspace").font(.system(size: 24, weight: .semibold)).tracking(-0.5)
                Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(26)
            Form {
                accountControls
                Section("Appearance") { Picker("Color scheme", selection: $appearance) { Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark") }.pickerStyle(.segmented)
                    Picker("Glass appearance", selection: $glassStyle) { Text("Clear glass").tag("clear"); Text("Frosted glass").tag("frosted"); Text("Solid").tag("solid") }.pickerStyle(.segmented)
                    Text("Clear glass shows a blurred desktop through the window. Reduce Transparency and Increase Contrast use solid surfaces.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Section("Microsoft 365 & Outlook") {
                    TextField("Entra application ID", text: $clientID)
                    Text("Public-client app · msauth.app.aster.mail://auth · Mail.ReadWrite, Mail.Send, User.Read. No client secret.").font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack { connectButton("Connect Microsoft", provider: "microsoft", enabled: !clientID.isEmpty); Text("Add multiple Microsoft addresses with this app ID.").font(.system(size: 10)).foregroundStyle(.secondary) }
                }
                Section("Gmail & Google Workspace") {
                    TextField("Google Desktop OAuth client ID", text: $googleClientID)
                    SecureField("Desktop client secret (if issued by Google)", text: $googleSecret)
                    Text("Enable Gmail API in your Google Cloud project. Use a Desktop app OAuth client. Sign-in opens your browser with PKCE and a local loopback callback. Access is limited to gmail.modify; messages are never permanently deleted.").font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack { connectButton("Connect Google", provider: "google", enabled: !googleClientID.isEmpty); Text("Each Google address gets its own saved session.").font(.system(size: 10)).foregroundStyle(.secondary) }
                    Link("Google OAuth setup ↗", destination: URL(string: "https://developers.google.com/identity/protocols/oauth2/native-app")!).font(.system(size: 11))
                }
                if let error = state.error { Section { Text(error).font(.system(size: 11)).foregroundStyle(.orange) } }
                Section("Default writing style") {
                    WritingStyleControls(style: $defaultStyle)
                    Button("Save default style") { if let data = try? JSONEncoder().encode(defaultStyle) { UserDefaults.standard.set(data, forKey: "defaultWritingStyle:v1") } }
                    Text("The reply assistant uses these defaults unless an account has its own writing style. You can override them for each preview.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Section("Intelligence") {
                    Picker("Provider", selection: $intelligenceMode) { Text("Apple Intelligence").tag("apple"); Text("Local rules only").tag("local"); Text("My cloud / local endpoint").tag("remote") }
                    Label(AppleIntelligenceStatus.description, systemImage: AppleIntelligenceStatus.available ? "checkmark.circle" : "info.circle").font(.system(size: 11)).foregroundStyle(AppleIntelligenceStatus.available ? Color.aster : .secondary)
                    Text("Apple Intelligence summaries and reply drafts run on this Mac. It requires macOS 26, supported hardware, and an available system model. Local preview notes remain usable when it is unavailable.").font(.system(size: 11)).foregroundStyle(.secondary)
                    if intelligenceMode == "remote" {
                        TextField("Base URL (ends in /v1)", text: $endpoint)
                        TextField("Model name", text: $model)
                        SecureField("API key · Keychain", text: $apiKey)
                        Button(saved ? "Key saved" : "Save API key") { do { try Keychain.save(apiKey, account: "provider"); saved = true } catch { failure = error.localizedDescription } }
                        Text("Explicit Summarize and Draft a reply actions send the cached conversation and addresses to this endpoint. No background uploads. Review your provider’s privacy policy.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if let failure { Text(failure).font(.system(size: 11)).foregroundStyle(.orange) }
                }
                Section("Local storage") {
                    Text("\(state.cachedCount) cached messages · \(state.pendingCount) changes waiting to sync").font(.system(size: 12))
                    Text("Mail is cached in Application Support/Aster. Use FileVault for protection at rest. Remote images and scripts are blocked. Disconnect retains this Mac’s cache.").font(.system(size: 11)).foregroundStyle(.secondary)
                    HStack { Button("Open cache folder") { if let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first { NSWorkspace.shared.open(url.appendingPathComponent("Aster")) } }; if state.isReady { Button("Disconnect current account") { if let id = workspace.profiles.first(where: { $0.email == state.accountName })?.id { workspace.removeAccount(id) }; dismiss() } } }
                    Button("Explore demo workspace") { Task { await workspace.loadDemoAccounts(); dismiss() } }
                }
            }.formStyle(.grouped)
        }.frame(width: 650, height: 780).background { AppBackdrop() }.tint(.aster)
            .onAppear { if let data = UserDefaults.standard.data(forKey: "defaultWritingStyle:v1"), let saved = try? JSONDecoder().decode(WritingStyle.self, from: data) { defaultStyle = saved }; editingAccount = workspace.profiles.first(where: { $0.email == state.accountName })?.id ?? workspace.profiles.first?.id; apiKey = Keychain.read("provider"); googleSecret = Keychain.read("google-client-secret") }
    }
    private var editedProfile: AccountProfile? { workspace.profiles.first { $0.id == editingAccount } }
    private func policyBinding<Value>(_ key: WritableKeyPath<AccountPolicy, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { editedProfile?.policy[keyPath: key] ?? fallback }, set: { value in
            guard let profile = editedProfile else { return }; var policy = profile.policy; policy[keyPath: key] = value; workspace.updatePolicy(policy, accountID: profile.id)
        })
    }
    @ViewBuilder private var accountControls: some View {
        if !workspace.profiles.isEmpty {
            Section("Connected accounts") {
                ForEach(workspace.profiles) { profile in
                    HStack {
                        VStack(alignment: .leading) { Text(profile.email); Text(workspace.state(for: profile.id)?.status ?? "Not connected").font(.system(size: 10)).foregroundStyle(.secondary) }
                        Spacer()
                        if profile.provider != "demo" { Button("Reconnect") { Task { await workspace.connect(provider: profile.provider, reconnectID: profile.id) } }.disabled(workspace.connecting) }
                        Button("Remove") { workspace.removeAccount(profile.id); editingAccount = workspace.profiles.first?.id }
                    }
                }
            }
            Section("Inbox controls · per account") {
                Picker("Configure address", selection: $editingAccount) { ForEach(workspace.profiles) { Text($0.email).tag(Optional($0.id)) } }
                if let profile = editedProfile {
                    Picker("Priority includes", selection: policyBinding(\.priorityMode, fallback: .important)) { ForEach(PriorityMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Picker("Junk behavior", selection: policyBinding(\.junkMode, fallback: .separate)) { ForEach(JunkMode.allCases, id: \.self) { Text($0.title).tag($0) } }
                    Toggle("Hide Junk folder in this app", isOn: policyBinding(\.hideJunkFolder, fallback: false))
                    Text("All received mail includes archived mail and custom folders. Sent, Drafts and Trash remain separate. Show in Priority includes Junk without moving messages.").font(.system(size: 11)).foregroundStyle(.secondary)
                    if profile.policy.junkMode == .moveToInbox {
                        Text("While Aster is running, synchronization moves this account’s existing and newly synced Junk to Inbox. This changes the mailbox on the server; it does not disable your provider’s spam filter or recover server-quarantined mail.").font(.system(size: 11)).foregroundStyle(.orange)
                    }
                    TextField("Always prioritize senders · comma-separated addresses", text: Binding(get: { editedProfile?.policy.prioritySenders.joined(separator: ", ") ?? "" }, set: { value in
                        guard let current = editedProfile else { return }; var policy = current.policy; policy.prioritySenders = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }; workspace.updatePolicy(policy, accountID: current.id)
                    }))
                    DisclosureGroup("Writing style for this address") {
                        WritingStyleControls(style: Binding(get: { editedProfile?.policy.writingStyle ?? defaultStyle }, set: { value in
                            guard let current = editedProfile else { return }; var policy = current.policy; policy.writingStyle = value; workspace.updatePolicy(policy, accountID: current.id)
                        })).padding(.top, 10)
                        Button("Use default writing style") { guard let current = editedProfile else { return }; var policy = current.policy; policy.writingStyle = nil; workspace.updatePolicy(policy, accountID: current.id) }.buttonStyle(.borderless)
                    }
                    DisclosureGroup("Visible folders") {
                        ForEach((workspace.state(for: profile.id)?.folders ?? []).filter { !["inbox", "drafts", "sentitems"].contains($0.role ?? "") }) { folder in
                            Toggle(folder.name, isOn: Binding(get: { !(editedProfile?.policy.hiddenFolders.contains(folder.id) ?? false) }, set: { visible in
                                guard let current = editedProfile else { return }; var policy = current.policy; if visible { policy.hiddenFolders.remove(folder.id) } else { policy.hiddenFolders.insert(folder.id) }; workspace.updatePolicy(policy, accountID: current.id)
                            }))
                        }
                    }
                    Button("All mail in Priority · include Junk") {
                        var policy = profile.policy; policy.priorityMode = .allReceived; policy.junkMode = .includeInPriority; policy.hideJunkFolder = true; workspace.updatePolicy(policy, accountID: profile.id)
                    }
                }
            }
        }
    }
    private func connectButton(_ title: String, provider: String, enabled: Bool) -> some View {
        Button(signingIn ? "Connecting…" : title) {
            signingIn = true
            Task {
                do { if provider == "google" { try Keychain.save(googleSecret, account: "google-client-secret") }; await workspace.connect(provider: provider) }
                catch { failure = error.localizedDescription }
                signingIn = false
            }
        }.disabled(signingIn || !enabled || workspace.connecting)
    }
}
