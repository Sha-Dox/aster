import SwiftUI
import AsterCore

struct WorkspaceView: View {
    @EnvironmentObject var workspace: WorkspaceState
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Label("Workspace", systemImage: "person.2").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Picker("Account", selection: $workspace.scope) {
                    Text("All accounts · Priority").tag("unified")
                    ForEach(workspace.profiles) { profile in Text(profile.email).tag(profile.id.uuidString) }
                }.frame(maxWidth: 340)
                Spacer()
                if workspace.profiles.count > 1 { Text("\(workspace.profiles.count) connected accounts").font(.system(size: 11)).foregroundStyle(.secondary) }
                Button { workspace.active.showSettings = true } label: { Label("Accounts & controls", systemImage: "slider.horizontal.3") }.buttonStyle(.borderless)
            }.padding(.horizontal, 24).padding(.top, 32).padding(.bottom, 12)
                .disabled(workspace.active.composer != nil || workspace.active.replyAssistant != nil)
            if workspace.scope == "unified", !workspace.profiles.isEmpty {
                UnifiedInboxView().environmentObject(workspace.active)
            } else { ContentView().environmentObject(workspace.active) }
        }.background { AppBackdrop() }
        .overlay(alignment: .bottom) {
            if let failure = workspace.failure {
                HStack { Image(systemName: "exclamationmark.circle").foregroundStyle(.orange); Text(failure).font(.system(size: 12)); Button("Dismiss") { workspace.failure = nil } }.padding(16).modifier(GlassSurface(radius: 18)).padding(20)
            }
        }
    }
}

struct UnifiedInboxView: View {
    @EnvironmentObject var workspace: WorkspaceState
    @EnvironmentObject var state: AppState
    @AppStorage("appearance") private var appearance = "system"
    @State private var unreadOnly = false
    @FocusState private var searching: Bool
    private var rows: [UnifiedMail] { workspace.unifiedRows.filter { !unreadOnly || !$0.mail.isRead } }
    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Priority inbox").font(.system(size: 29, weight: .semibold))
                        Text(workspace.syncingCount > 0 ? "Syncing \(workspace.syncingCount) accounts…" : "All your accounts, together").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await workspace.syncAll() } } label: { Image(systemName: "arrow.triangle.2.circlepath") }.buttonStyle(.borderless)
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search Priority across accounts", text: $workspace.unifiedSearch).textFieldStyle(.plain).focused($searching)
                    if !workspace.unifiedSearch.isEmpty { Button { workspace.unifiedSearch = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.padding(12).modifier(GlassSurface(radius: 16, interactive: true))
                HStack {
                    Button { state.compose() } label: { Label("New message", systemImage: "square.and.pencil") }.buttonStyle(.borderless).disabled(!state.isReady)
                    Spacer()
                    Toggle("Unread only", isOn: $unreadOnly).toggleStyle(.checkbox).font(.system(size: 11))
                }
                Picker("Send new mail from", selection: $workspace.readingAccountID) { ForEach(workspace.profiles) { Text($0.email).tag(Optional($0.id)) } }.font(.system(size: 11)).disabled(state.composer != nil)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(rows) { row in
                            Button { workspace.select(row) } label: {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(row.account.email).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.aster).padding(.horizontal, 13).padding(.top, 9)
                                    MailRow(mail: row.mail, selected: workspace.readingAccountID == row.account.id && state.selectedID == row.mail.id, hint: AttentionEngine.classify(row.mail)?.kind)
                                }
                            }.buttonStyle(.plain)
                            .contextMenu {
                                Button("Reply from \(row.account.email)") { workspace.select(row); workspace.active.compose(mode: "reply") }
                                Button(row.mail.isRead ? "Mark unread" : "Mark read") { workspace.state(for: row.account.id)?.mutate(row.mail, kind: "read", value: String(!row.mail.isRead)) }
                                Button("Archive") { workspace.select(row); workspace.active.moveSelected(to: "archive") }
                                Button("Move to Trash") { workspace.select(row); workspace.active.moveSelected(to: "deleteditems") }
                            }
                        }
                        if workspace.totalPriority > workspace.unifiedRows.count && workspace.unifiedSearch.isEmpty {
                            Button("Load older mail from all accounts") { Task { await workspace.loadMore() } }.buttonStyle(.borderless).padding(16)
                        }
                        if rows.isEmpty { ContentUnavailableView("Priority is clear", systemImage: "tray", description: Text("Change each account’s Priority settings to include more mail.")) }
                    }
                }
                Text("\(rows.count) conversations · settings apply separately to each account").font(.system(size: 10)).foregroundStyle(.secondary)
            }.padding(24).frame(minWidth: 380, idealWidth: 480, maxWidth: 550).modifier(GlassSurface(radius: 24)).padding(.leading, 12).padding(.vertical, 12)
            ReaderView().frame(minWidth: 440, maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 24)).padding(.trailing, 12).padding(.vertical, 12)
        }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .sheet(isPresented: $state.showSettings) { SettingsView().environmentObject(state).presentationBackground(.clear) }
        .sheet(item: $state.replyAssistant) { ReplyAssistantView(context: $0, style: state.writingStyle).environmentObject(state).presentationBackground(.clear) }
        .sheet(item: $state.composer) { ComposerView(initial: $0).environmentObject(state).presentationBackground(.clear) }
        .sheet(isPresented: $state.showPalette) { CommandPalette().environmentObject(state) }
        .background { Button("Search all accounts") { searching = true }.keyboardShortcut("f").hidden() }
        .onChange(of: workspace.unifiedSearch) { _, _ in workspace.searchChanged() }
        .overlay(alignment: .bottom) {
            if let text = state.error ?? state.notice {
                HStack { Text("\(state.accountName): \(text)").font(.system(size: 12)); Button("Dismiss") { state.error = nil; state.notice = nil } }.padding(14).modifier(GlassSurface(radius: 18)).padding(20)
            }
        }
    }
}
