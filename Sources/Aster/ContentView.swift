import SwiftUI
import AsterCore

extension Color {
    static let aster = Color(nsColor: NSColor(name: "AsterAccent", dynamicProvider: { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(red: 0.67, green: 0.63, blue: 0.92, alpha: 1) : NSColor(red: 0.37, green: 0.35, blue: 0.68, alpha: 1)
    }))
    static let canvas = Color(nsColor: .textBackgroundColor)
}
struct ContentView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var workspace: WorkspaceState
    @Environment(\.accessibilityReduceTransparency) var reducedTransparency
    @AppStorage("appearance") private var appearance = "system"
    @FocusState private var searching: Bool
    var body: some View {
        HStack(spacing: 8) {
            sidebar.frame(width: 212).padding(.leading, 10).padding(.vertical, 10)
            if state.isReady {
                inbox.frame(minWidth: 350, idealWidth: 410, maxWidth: 470)
                ReaderView().frame(minWidth: 440, maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 24)).shadow(color: .black.opacity(0.035), radius: 20, y: 8).padding(.trailing, 12).padding(.vertical, 12)
            } else { onboarding.frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .background { AppBackdrop() }
        .preferredColorScheme(appearance == "light" ? .light : appearance == "dark" ? .dark : nil)
        .tint(.aster)
        .overlay(alignment: .bottom) { banner.padding(.horizontal, 24).padding(.bottom, 18) }
        .sheet(isPresented: $state.showSettings) { SettingsView().environmentObject(state).presentationBackground(.clear) }
        .sheet(item: $state.replyAssistant) { ReplyAssistantView(context: $0, style: state.writingStyle).environmentObject(state).presentationBackground(.clear) }
        .sheet(item: $state.composer) { value in ComposerView(initial: value).environmentObject(state).presentationBackground(.clear) }
        .sheet(isPresented: $state.showPalette) { CommandPalette().environmentObject(state) }
        .onChange(of: state.search) { _, _ in state.searchChanged() }
        .onChange(of: state.selection) { _, _ in state.changeView() }
        .background {
            Button("Search Mail") { searching = true }.keyboardShortcut("f").hidden()
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "asterisk").font(.system(size: 24, weight: .semibold)).foregroundStyle(Color.aster)
                Text("aster").font(.system(size: 26, weight: .semibold, design: .rounded)).tracking(-0.8)
            }.padding(.top, 49).padding(.bottom, 34).padding(.leading, 25)
            Button { state.compose() } label: {
                HStack { Image(systemName: "square.and.pencil"); Text("New message"); Spacer(); Text("⌘N").font(.system(size: 11)).foregroundStyle(.secondary) }
                    .font(.system(size: 13, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 11)
            }.buttonStyle(.plain).modifier(GlassSurface(radius: 14, interactive: true, tinted: true)).padding(.horizontal, 16).padding(.bottom, 25).disabled(!state.isReady)
            VStack(spacing: 4) {
                nav("Inbox", icon: "tray", key: "inbox", count: state.messages.filter { $0.isInFolder(state.inboxID) && !$0.isRead }.count)
                nav("Priority inbox", icon: "tray.full", key: "priority", count: state.priorityCount)
                nav("Attention", icon: "sparkle", key: "attention", count: state.attention.count)
                nav("Needs reply", icon: "arrowshape.turn.up.left", key: "reply", count: state.attention.filter { $0.kind == .reply }.count)
                nav("Starred", icon: "star", key: "starred")
                if let drafts = state.folders.first(where: { $0.role == "drafts" }) { nav("Drafts", icon: "doc", key: drafts.id, count: state.messages.filter { $0.folderID == drafts.id }.count) }
                if let sent = state.folders.first(where: { $0.role == "sentitems" }) { nav("Sent", icon: "paperplane", key: sent.id) }
            }.padding(.horizontal, 12)
            Text("FOLDERS").font(.system(size: 10, weight: .semibold)).tracking(1.5).foregroundStyle(.tertiary).padding(.leading, 25).padding(.top, 32).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(state.folders.filter { !["inbox", "drafts", "sentitems"].contains($0.role ?? "") && !(state.policy.hideJunkFolder && $0.role == "junkemail") && !state.policy.hiddenFolders.contains($0.id) }) { folder in
                        nav(folder.name, icon: folder.role == "deleteditems" ? "trash" : folder.role == "archive" ? "archivebox" : "folder", key: folder.id)
                    }
                }.padding(.horizontal, 12)
            }
            Spacer(minLength: 10)
            Button { state.showPalette = true } label: {
                HStack { Image(systemName: "command"); Text("Commands"); Spacer(); Text("⌘K").font(.system(size: 11)) }.foregroundStyle(.secondary).font(.system(size: 12)).padding(12)
            }.buttonStyle(.plain).padding(.horizontal, 12)
            Divider().padding(.horizontal, 22).opacity(0.5)
            Button { state.showSettings = true } label: {
                HStack(spacing: 10) {
                    ZStack { Circle().fill(Color.aster.opacity(0.12)); Image(systemName: "person.crop.circle.fill").font(.system(size: 28)).foregroundStyle(Color.aster.opacity(0.6)) }.frame(width: 33, height: 33)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(state.isDemo ? "Demo workspace" : state.isReady ? state.providerName : "Your workspace").font(.system(size: 12, weight: .medium))
                        Text(state.isDemo ? "Explore Aster" : state.accountName.isEmpty ? "Connect an account" : state.accountName).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(); Image(systemName: "gearshape").font(.system(size: 12)).foregroundStyle(.tertiary)
                }.padding(.horizontal, 22).padding(.vertical, 21)
            }.buttonStyle(.plain)
        }
        .modifier(GlassSurface(radius: 25))
    }
    private func nav(_ title: String, icon: String, key: String, count: Int = 0) -> some View {
        Button { state.selection = key } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 14)).frame(width: 19)
                Text(title).font(.system(size: 13, weight: state.selection == key ? .semibold : .regular)).lineLimit(1)
                Spacer()
                if count > 0 { Text("\(count)").font(.system(size: 11, weight: .medium)).foregroundStyle(state.selection == key ? Color.aster : .secondary) }
            }.padding(.horizontal, 12).padding(.vertical, 10)
                .foregroundStyle(state.selection == key ? Color.aster : Color.primary.opacity(0.76))
                .background(state.selection == key ? Color.aster.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(title), \(count) items")
    }
    private var inbox: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(state.title).font(.system(size: 29, weight: .semibold)).tracking(-0.8)
                Spacer()
                Button { if state.isSyncing { state.cancelSync() } else { Task { await state.sync() } } } label: { Image(systemName: state.isSyncing ? "xmark" : "arrow.triangle.2.circlepath").frame(width: 29, height: 29) }.buttonStyle(.plain).modifier(GlassSurface(radius: 15, interactive: true)).foregroundStyle(.secondary).help(state.isSyncing ? "Pause sync" : "Sync mail · ⇧⌘R").disabled(state.isDemo)
            }.padding(.horizontal, 27).padding(.top, 49).padding(.bottom, 7)
            HStack(spacing: 6) { Circle().fill(state.status.hasPrefix("Offline") || state.status.contains("attention") || state.status.contains("paused") ? Color.orange : Color.green.opacity(0.7)).frame(width: 5, height: 5); Text(state.status).font(.system(size: 10)).foregroundStyle(.secondary); Spacer() }.padding(.horizontal, 28).padding(.bottom, 22)
            HStack(spacing: 9) {
                Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                TextField("Search this view", text: $state.search).textFieldStyle(.plain).focused($searching)
                if !state.search.isEmpty { Button { state.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain) }
                else { Text("⌘F").font(.system(size: 10)).foregroundStyle(.tertiary) }
            }.font(.system(size: 12)).padding(12).modifier(GlassSurface(radius: 16, interactive: true)).padding(.horizontal, 24)
            if (state.selection == "inbox" || state.selection == "attention") && state.search.isEmpty && !state.attention.isEmpty { briefing.padding(.top, 25) }
            HStack {
                Text(state.selection == "attention" ? "YOUR ATTENTION" : "CONVERSATIONS").font(.system(size: 9, weight: .semibold)).tracking(1.5).foregroundStyle(.tertiary)
                Spacer()
                Button { state.unreadOnly.toggle() } label: { Text(state.unreadOnly ? "Unread" : "All mail").font(.system(size: 11)); Image(systemName: "line.3.horizontal.decrease").font(.system(size: 11)) }.buttonStyle(.plain).foregroundStyle(state.unreadOnly ? Color.aster : .secondary).help("Toggle unread only")
            }.padding(.horizontal, 27).padding(.top, 25).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 3) {
                    ForEach(state.visible) { mail in
                        Button { if mail.isDraft { state.openDraft(mail) } else { state.select(mail.id) } } label: { MailRow(mail: mail, selected: state.selectedID == mail.id, hint: state.attention.first { $0.id == mail.id }?.kind) }.buttonStyle(.plain)
                            .contextMenu {
                                Button("Reply") { state.select(mail.id); state.compose(mode: "reply") }
                                Button(mail.isRead ? "Mark unread" : "Mark read") { state.mutate(mail, kind: "read", value: String(!mail.isRead)) }
                                Button(mail.isFlagged ? "Unstar" : "Star") { state.mutate(mail, kind: "flag", value: String(!mail.isFlagged)) }
                                Button("Archive") { state.select(mail.id); state.moveSelected(to: "archive") }
                                Button("Move to Trash") { state.select(mail.id); state.moveSelected(to: "deleteditems") }
                            }
                    }
                    if state.hasMoreMail { Button("Load older conversations") { Task { await state.loadMore() } }.buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.aster).padding(20) }
                    if state.visible.isEmpty {
                        ContentUnavailableView(state.search.isEmpty ? "All clear" : "No matching mail", systemImage: state.search.isEmpty ? "tray" : "magnifyingglass", description: Text(state.search.isEmpty ? "Nothing in this view needs your attention." : "Try a sender, subject, or phrase from the message.")).padding(.top, 30)
                    }
                }.padding(.horizontal, 12)
            }
            HStack { Text("\(state.visible.count) conversations"); Spacer(); Image(systemName: "internaldrive"); Text("On this Mac") }.font(.system(size: 10)).foregroundStyle(.tertiary).padding(.horizontal, 27).padding(.vertical, 15)
        }
    }
    private var briefing: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "sparkle").foregroundStyle(Color.aster)
                Text("\(state.attention.count) things need your attention").font(.system(size: 13, weight: .semibold)).tracking(-0.2)
            }
            ForEach(state.attention.prefix(state.selection == "attention" ? 8 : 3)) { item in
                Button { state.select(item.id) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: item.kind.symbol).font(.system(size: 11)).foregroundStyle(item.kind == .security ? Color.orange : Color.aster).frame(width: 15).padding(.top, 2)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.mail.preview).font(.system(size: 11, weight: .medium)).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                            Text(item.mail.sender.name).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0); Image(systemName: "arrow.up.right").font(.system(size: 9)).foregroundStyle(.tertiary).padding(.top, 3)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
            if state.selection != "attention" && state.attention.count > 3 { Button("View all \(state.attention.count) items →") { state.selection = "attention" }.font(.system(size: 10, weight: .medium)).buttonStyle(.plain).foregroundStyle(Color.aster) }
            Text("On-device hints · review the original email").font(.system(size: 9)).foregroundStyle(.tertiary)
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).modifier(GlassSurface(radius: 21, tinted: true)).padding(.horizontal, 24)
    }
    private var onboarding: some View {
        VStack(spacing: 20) {
            Image(systemName: "asterisk").font(.system(size: 62, weight: .light)).foregroundStyle(Color.aster).padding(.bottom, 8)
            Text("A little clarity.\nA lot less inbox.").font(.system(size: 40, weight: .semibold)).tracking(-1.5).multilineTextAlignment(.center)
            Text("Your mail, quietly in order. A fast, local inbox\nwith a clear view of what needs you.").font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            Button { state.showSettings = true } label: { Label("Connect your mail", systemImage: "person.badge.key").padding(.horizontal, 20).padding(.vertical, 8) }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 14)
            Text("Microsoft 365 · Outlook · Gmail · Google Workspace").font(.system(size: 11)).foregroundStyle(.secondary)
            Button("Explore the demo") { Task { await workspace.loadDemoAccounts() } }.buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12))
            Label("Cached locally. AI is optional. Your inbox stays yours.", systemImage: "lock").font(.system(size: 11)).foregroundStyle(.tertiary).padding(.top, 30)
        }
    }
    @ViewBuilder private var banner: some View {
        if let text = state.error ?? state.notice {
            HStack(spacing: 10) {
                Image(systemName: state.error == nil ? "checkmark.circle" : "exclamationmark.circle").foregroundStyle(state.error == nil ? Color.green : Color.orange)
                Text(text).font(.system(size: 12)).lineLimit(4)
                Spacer()
                Button { state.error = nil; state.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
            }.padding(14).frame(maxWidth: 720).modifier(GlassSurface(radius: 18)).shadow(color: .black.opacity(0.08), radius: 14, y: 5)
        }
    }
}
struct MailRow: View {
    let mail: Mail
    let selected: Bool
    let hint: AttentionKind?
    private func timestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    @State private var hovered = false
    @EnvironmentObject var state: AppState
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Circle().fill(mail.isRead ? Color.clear : Color.aster).frame(width: 5, height: 5).padding(.top, 7)
            VStack(alignment: .leading, spacing: 5) {
                HStack { Text(mail.sender.name).font(.system(size: 12, weight: mail.isRead ? .medium : .semibold)); Spacer(); Text(timestamp(mail.date)).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1) }
                Text(mail.subject).font(.system(size: 12, weight: selected ? .medium : .regular)).foregroundStyle(.primary.opacity(0.85)).lineLimit(1)
                Text(mail.preview).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 6) {
                    if let hint { Label(hint.rawValue, systemImage: hint.symbol).font(.system(size: 9, weight: .medium)).foregroundStyle(hint == .security ? Color.orange : Color.aster) }
                    if mail.hasAttachments { Image(systemName: "paperclip").font(.system(size: 10)).foregroundStyle(.tertiary) }
                    if mail.isFlagged { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.orange) }
                    Spacer()
                }.frame(height: hint == nil && !mail.hasAttachments && !mail.isFlagged ? 0 : 13)
            }
        }.padding(.horizontal, 13).padding(.vertical, 14)
            .background(selected ? Color.aster.opacity(0.095) : hovered ? Color.primary.opacity(0.025) : .clear, in: RoundedRectangle(cornerRadius: 11))
            .contentShape(Rectangle()).onHover { hovered = $0 }
            .accessibilityElement(children: .combine).accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
    }
}
