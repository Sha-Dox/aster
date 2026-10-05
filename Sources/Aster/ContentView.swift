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
            sidebar.frame(width: 188).padding(.leading, 10).padding(.vertical, 10)
            if state.isReady {
                inbox.frame(minWidth: 320, idealWidth: 365, maxWidth: 420)
                ReaderView().frame(minWidth: 400, maxWidth: .infinity).clipShape(RoundedRectangle(cornerRadius: 24)).shadow(color: .black.opacity(0.035), radius: 20, y: 8).padding(.trailing, 12).padding(.vertical, 12)
            } else { onboarding.frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
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
            VStack(alignment: .leading, spacing: 5) {
                SectionEyebrow(title: "Mailbox")
                Text(state.isDemo ? "Demo workspace" : state.providerName).font(.system(size: 20, weight: .medium, design: .rounded)).tracking(-0.5)
            }.padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 24)
            Button { state.compose() } label: {
                HStack { Image(systemName: "square.and.pencil"); Text("Compose"); Spacer(); Text("⌘N").font(.system(size: 10)).opacity(0.7) }
            }.buttonStyle(AccentButtonStyle()).padding(.horizontal, 16).padding(.bottom, 25).disabled(!state.isReady)
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
                }.padding(.horizontal, 16).padding(.vertical, 21)
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
                Text(state.title).font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-0.8)
                Spacer()
                Button { if state.isSyncing { state.cancelSync() } else { Task { await state.sync() } } } label: { Image(systemName: state.isSyncing ? "xmark" : "arrow.triangle.2.circlepath").frame(width: 29, height: 29) }.buttonStyle(.plain).modifier(GlassSurface(radius: 15, interactive: true)).foregroundStyle(.secondary).help(state.isSyncing ? "Pause sync" : "Sync mail · ⇧⌘R").disabled(state.isDemo)
            }.padding(.horizontal, 27).padding(.top, 24).padding(.bottom, 7)
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
                LazyVStack(spacing: 8) {
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
        }.padding(.vertical, 12).modifier(GlassSurface(radius: 25)).padding(.vertical, 12)
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
            AsterMark(size: 72).padding(.bottom, 8)
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
    var account: String? = nil
    @State private var hovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private func timestamp(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return date.formatted(date: .omitted, time: .shortened) }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            IdentityAvatar(name: mail.sender.name, size: 35)
                .overlay(alignment: .bottomTrailing) {
                    if !mail.isRead { Circle().fill(Color.aster).frame(width: 8, height: 8).overlay(Circle().stroke(Color.canvas, lineWidth: 2)).offset(x: 2, y: 2) }
                }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(mail.sender.name).font(.system(size: 12, weight: mail.isRead ? .medium : .semibold)).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(timestamp(mail.date)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(mail.subject).font(.system(size: 13, weight: mail.isRead ? .regular : .medium)).foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.leading)
                Text(mail.preview).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2).multilineTextAlignment(.leading).lineSpacing(2)
                if let account { Text(account).font(.system(size: 9, weight: .medium)).foregroundStyle(Color.aster).lineLimit(1).padding(.top, 2) }
                if hint != nil || mail.hasAttachments || mail.isFlagged {
                    HStack(spacing: 7) {
                        if let hint { Label(hint.rawValue, systemImage: hint.symbol).font(.system(size: 9, weight: .medium)).foregroundStyle(hint == .security ? Color.orange : Color.aster).padding(.horizontal, 7).padding(.vertical, 4).background((hint == .security ? Color.orange : Color.aster).opacity(0.1), in: Capsule()) }
                        if mail.hasAttachments { Image(systemName: "paperclip").font(.system(size: 10)).foregroundStyle(.secondary) }
                        if mail.isFlagged { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.orange) }
                        Spacer(minLength: 0)
                    }.padding(.top, 2)
                }
            }
        }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 17).fill(LinearGradient(colors: selected ? [Color.aster.opacity(0.20), Color.aster.opacity(0.08)] : [Color.primary.opacity(hovered ? 0.055 : 0.018), Color.primary.opacity(hovered ? 0.025 : 0.008)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay(RoundedRectangle(cornerRadius: 17).stroke(selected ? Color.aster.opacity(0.38) : Color.primary.opacity(hovered ? 0.08 : 0.035), lineWidth: 0.8))
            .overlay(alignment: .leading) { if selected { Capsule().fill(Color.aster).frame(width: 3, height: 28).padding(.leading, 1) } }
            .shadow(color: .aster.opacity(selected ? 0.08 : 0), radius: 9, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 17)).onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovered)
            .accessibilityElement(children: .combine).accessibilityAddTraits(selected ? [.isSelected, .isButton] : [.isButton])
    }
}
