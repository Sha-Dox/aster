import SwiftUI
import AsterCore

struct WorkspaceView: View {
    @EnvironmentObject var workspace: WorkspaceState
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 15) {
                HStack(spacing: 9) { AsterMark(size: 30); Text("aster").font(.system(size: 23, weight: .semibold, design: .rounded)).tracking(-0.8) }
                Divider().frame(height: 22).padding(.horizontal, 5)
                Picker("Account", selection: $workspace.scope) {
                    Text("All accounts · Priority").tag("unified")
                    ForEach(workspace.profiles) { profile in Text(profile.email).tag(profile.id.uuidString) }
                }.labelsHidden().frame(maxWidth: 300).accessibilityLabel("Account")
                Spacer()
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Button { workspace.active.showSettings = true } label: { Image(systemName: "slider.horizontal.3").font(.system(size: 13)).frame(width: 34, height: 34) }.buttonStyle(.plain).modifier(GlassSurface(radius: 12, interactive: true)).help("Accounts & controls").accessibilityLabel("Accounts & controls")
            }.padding(.leading, 90).padding(.trailing, 22).padding(.top, 16).padding(.bottom, 12)
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
        HStack(spacing: 12) {
            accountRail.frame(width: 180).padding(.leading, 14).padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionEyebrow(title: "Your daily focus")
                        Text("Priority inbox").font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-0.9)
                        Text(workspace.syncingCount > 0 ? "Syncing \(workspace.syncingCount) accounts…" : "All your accounts, together").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await workspace.syncAll() } } label: { Image(systemName: "arrow.triangle.2.circlepath").frame(width: 30, height: 30) }.buttonStyle(.plain).modifier(GlassSurface(radius: 12, interactive: true)).help("Sync all accounts").accessibilityLabel("Sync all accounts")
                }
                HStack(spacing: 8) {
                    InboxMetric(count: workspace.unifiedRows.filter { !$0.mail.isRead }.count, title: "Unread", symbol: "envelope.badge")
                    InboxMetric(count: workspace.unifiedRows.filter { AttentionEngine.classify($0.mail)?.kind == .reply }.count, title: "To reply", symbol: "arrowshape.turn.up.left", accent: .teal)
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search Priority across accounts", text: $workspace.unifiedSearch).textFieldStyle(.plain).focused($searching)
                    if !workspace.unifiedSearch.isEmpty { Button { workspace.unifiedSearch = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                }.padding(12).modifier(GlassSurface(radius: 16, interactive: true))
                HStack {
                    SectionEyebrow(title: "Conversations")
                    Spacer()
                    Button { unreadOnly.toggle() } label: { Label(unreadOnly ? "Unread" : "All mail", systemImage: "line.3.horizontal.decrease").font(.system(size: 11, weight: .medium)) }.buttonStyle(.plain).foregroundStyle(unreadOnly ? Color.aster : .secondary).accessibilityLabel("Toggle unread only").accessibilityValue(unreadOnly ? "Unread" : "All mail")
                }
                Picker("Send new mail from", selection: $workspace.readingAccountID) { ForEach(workspace.profiles) { Text($0.email).tag(Optional($0.id)) } }.font(.system(size: 11)).disabled(state.composer != nil)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(rows) { row in
                            Button { workspace.select(row) } label: {
                                MailRow(mail: row.mail, selected: workspace.readingAccountID == row.account.id && state.selectedID == row.mail.id, hint: AttentionEngine.classify(row.mail)?.kind, account: row.account.email)
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
            }.padding(20).frame(minWidth: 320, idealWidth: 365, maxWidth: 410).modifier(GlassSurface(radius: 25)).padding(.vertical, 12)
            ReaderView().frame(minWidth: 400, maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 24)).padding(.trailing, 12).padding(.vertical, 12)
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
    private var accountRail: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 5) {
                SectionEyebrow(title: "Workspace")
                Text("One place.\nEvery inbox.").font(.system(size: 21, weight: .medium, design: .rounded)).tracking(-0.5)
            }.padding(.top, 8)
            Button { state.compose() } label: { HStack { Image(systemName: "square.and.pencil"); Text("Compose"); Spacer(); Text("⌘N").font(.system(size: 10)).opacity(0.7) } }.buttonStyle(AccentButtonStyle()).disabled(!state.isReady)
            VStack(alignment: .leading, spacing: 10) {
                SectionEyebrow(title: "Mailboxes")
                HStack(spacing: 9) { Image(systemName: "tray.full.fill"); Text("Priority").fontWeight(.semibold); Spacer(); Text("\(workspace.totalPriority)").font(.system(size: 10, weight: .semibold)).monospacedDigit() }.font(.system(size: 12)).foregroundStyle(Color.aster).padding(12).background(Color.aster.opacity(0.13), in: RoundedRectangle(cornerRadius: 12)).accessibilityLabel("Unified Priority inbox, selected")
            }
            ScrollView {
              VStack(alignment: .leading, spacing: 12) {
                SectionEyebrow(title: "Your accounts")
                ForEach(workspace.profiles) { profile in
                    Button { workspace.scope = profile.id.uuidString } label: {
                        HStack(spacing: 9) {
                            IdentityAvatar(name: profile.email, size: 29, symbol: profile.provider == "google" ? "envelope" : "person")
                            VStack(alignment: .leading, spacing: 4) {
                                Text(profile.email.components(separatedBy: "@").first ?? profile.email).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(profile.provider == "demo" ? "Demo account" : profile.provider == "google" ? "Google" : "Microsoft").font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).help(profile.email).accessibilityLabel("Open \(profile.email)")
                }
                Button { state.showSettings = true } label: { Label("Manage accounts", systemImage: "plus.circle").font(.system(size: 11)).foregroundStyle(.secondary) }.buttonStyle(.plain).padding(.top, 4)
              }.frame(maxWidth: .infinity, alignment: .leading)
            }.scrollIndicators(.hidden)
            Button { state.showPalette = true } label: { HStack { Image(systemName: "command"); Text("Commands"); Spacer(); Text("⌘K").font(.system(size: 10)) }.font(.system(size: 11)).foregroundStyle(.secondary) }.buttonStyle(.plain)
            Divider().opacity(0.5)
            HStack(spacing: 6) { Image(systemName: "internaldrive"); Text("Cached on this Mac") }.font(.system(size: 9)).foregroundStyle(.secondary)
        }.padding(16).frame(maxHeight: .infinity).modifier(GlassSurface(radius: 25))
    }

}
