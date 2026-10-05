import SwiftUI
import WebKit
import AsterCore

struct ReaderView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 0) {
            GlassGroup { HStack(spacing: 15) {
                Text("\(state.thread.count) MESSAGE\(state.thread.count == 1 ? "" : "S")").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(.tertiary)
                Spacer()
                tool("Archive", "archivebox") { state.moveSelected(to: "archive") }
                tool("Trash", "trash") { state.moveSelected(to: "deleteditems") }
                Menu {
                    if let mail = state.selected {
                        Button(mail.isRead ? "Mark unread" : "Mark read") { state.mutate(mail, kind: "read", value: String(!mail.isRead)) }
                        Button(mail.isFlagged ? "Unstar" : "Star") { state.mutate(mail, kind: "flag", value: String(!mail.isFlagged)) }
                        Menu("Move to") { ForEach(state.folders) { folder in Button(folder.name) { state.moveSelected(to: folder.id) } } }
                        Button("Reply all") { state.compose(mode: "replyAll") }
                        Button("Write reply with AI") { state.openReplyAssistant() }
                        Button("Write reply all with AI") { state.openReplyAssistant(replyAll: true) }
                        Button("Forward") { state.compose(mode: "forward") }
                    }
                } label: { Image(systemName: "ellipsis").font(.system(size: 16)) }.menuStyle(.borderlessButton).fixedSize().foregroundStyle(.secondary)
            }.padding(.horizontal, 15).padding(.vertical, 10).modifier(GlassSurface(radius: 20)) }.padding(.horizontal, 25).padding(.top, 32).padding(.bottom, 25).disabled(state.selected == nil)
            if let selected = state.selected {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            if let hint = state.attention.first(where: { $0.id == selected.id }) {
                                Label(hint.kind.rawValue.uppercased(), systemImage: hint.kind.symbol).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Color.aster)
                            } else { Text("CONVERSATION").font(.system(size: 9, weight: .medium)).tracking(1.5).foregroundStyle(.tertiary) }
                            Spacer()
                            Button { state.mutate(selected, kind: "flag", value: String(!selected.isFlagged)) } label: { Image(systemName: selected.isFlagged ? "star.fill" : "star").foregroundStyle(selected.isFlagged ? Color.orange : Color.secondary) }.buttonStyle(.plain).help("Star conversation")
                        }.padding(.bottom, 15)
                        Text(selected.subject).font(.system(size: 30, weight: .semibold)).tracking(-0.9).lineSpacing(2).textSelection(.enabled).padding(.bottom, 20)
                        HStack(spacing: 12) {
                            Button { state.summarize() } label: { Label("Summarize", systemImage: "text.alignleft").font(.system(size: 11, weight: .medium)).padding(.horizontal, 13).padding(.vertical, 8) }.buttonStyle(.plain).modifier(QuietGlass()).help("Summarize cached conversation · ⇧⌘S")
                            Text(AppleIntelligenceStatus.available && (UserDefaults.standard.string(forKey: "intelligenceMode") ?? "apple") == "apple" ? "Apple Intelligence · on-device" : "Original email below").font(.system(size: 10)).foregroundStyle(.tertiary)
                            Spacer()
                        }.padding(.bottom, 27)
                        if state.showSummary { summaryPanel.padding(.bottom, 28) }
                        ForEach(state.thread) { mail in
                            message(mail).padding(.bottom, 28)
                            if mail.id != state.thread.last?.id { Divider().opacity(0.45).padding(.bottom, 28) }
                        }
                        if selected.hasAttachments {
                            VStack(alignment: .leading, spacing: 10) {
                                Button { Task { await state.loadAttachments() } } label: { Label(state.isLoadingAttachments ? "Loading attachments…" : "View attachments", systemImage: "paperclip") }.buttonStyle(.bordered).controlSize(.small).disabled(state.isLoadingAttachments)
                                ForEach(state.attachments) { attachment in
                                    Button { Task { await state.download(attachment) } } label: {
                                        HStack { Image(systemName: "doc"); Text(attachment.name).lineLimit(1); Spacer(); Text(ByteCountFormatter.string(fromByteCount: Int64(attachment.size), countStyle: .file)).foregroundStyle(.secondary); Image(systemName: "arrow.down") }.font(.system(size: 11)).padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                                    }.buttonStyle(.plain)
                                }
                            }.padding(.bottom, 24)
                        }
                        HStack {
                            Button { state.compose(mode: "reply") } label: { Label("Reply", systemImage: "arrowshape.turn.up.left").font(.system(size: 12, weight: .medium)).padding(.horizontal, 18).padding(.vertical, 9) }.buttonStyle(.borderedProminent)
                            Button("Reply all") { state.compose(mode: "replyAll") }
                        Button("Write reply with AI") { state.openReplyAssistant() }
                        Button("Write reply all with AI") { state.openReplyAssistant(replyAll: true) }.buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary).padding(.leading, 10)
                            Button { state.openReplyAssistant() } label: { Label("Write with AI", systemImage: "sparkles") }.buttonStyle(.borderless).font(.system(size: 12)).padding(.leading, 10)
                            Spacer(); Text("⌘R").font(.system(size: 11)).foregroundStyle(.tertiary)
                        }.padding(.top, 8).padding(.bottom, 35)
                    }.padding(.horizontal, 39).padding(.top, 14).frame(maxWidth: 800).frame(maxWidth: .infinity)
                }
            } else {
                Spacer(); Image(systemName: "envelope.open").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(Color.aster.opacity(0.5))
                Text("Space for what matters.").font(.system(size: 21, weight: .medium)).padding(.top, 14)
                Text("Select a conversation to read the original email.").font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 4); Spacer()
            }
        }.background(Color.canvas.opacity(0.95))
    }
    private func tool(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 14)).frame(width: 22, height: 22) }.buttonStyle(.plain).padding(5).modifier(GlassSurface(radius: 12, interactive: true)).foregroundStyle(.secondary).help(title).accessibilityLabel(title)
    }
    private func message(_ mail: Mail) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .top, spacing: 12) {
                Text(initials(mail.sender.name)).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.aster).frame(width: 36, height: 36).background(Color.aster.opacity(0.09), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(mail.sender.name).font(.system(size: 12, weight: .semibold))
                    Text("\(mail.sender.address) · to \(mail.to.map(\.name).joined(separator: ", "))").font(.system(size: 10)).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Spacer(minLength: 8)
                Text(mail.date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 9)).foregroundStyle(.tertiary).multilineTextAlignment(.trailing)
            }
            if mail.isHTML { SafeHTMLView(html: mail.body).frame(height: 460).clipShape(RoundedRectangle(cornerRadius: 8)) }
            else { Text(mail.body).font(.system(size: 14)).lineSpacing(7).foregroundStyle(.primary.opacity(0.87)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }
    private var summaryPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Label("Conversation notes", systemImage: "sparkle").font(.system(size: 12, weight: .semibold)); Spacer(); Button { state.showSummary = false } label: { Image(systemName: "xmark").font(.system(size: 10)) }.buttonStyle(.plain).foregroundStyle(.secondary) }
            if state.isSummarizing { HStack { ProgressView().controlSize(.small); Text("Reading cached conversation…").font(.system(size: 11)).foregroundStyle(.secondary) } }
            else if let summary = state.summary {
                Text(summary.summary).font(.system(size: 13)).lineSpacing(4).textSelection(.enabled)
                VStack(alignment: .leading, spacing: 5) { Text("NEXT ACTION").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(Color.aster); Text(summary.action).font(.system(size: 12)).textSelection(.enabled) }
                ForEach(Array(summary.details.enumerated()), id: \.offset) { _, detail in HStack(alignment: .top, spacing: 8) { Text("·"); Text(detail) }.font(.system(size: 11)).foregroundStyle(.secondary).textSelection(.enabled) }
                HStack {
                    Text(summary.source).font(.system(size: 9)).foregroundStyle(.tertiary)
                    Spacer()
                    Button { state.openReplyAssistant() } label: { Text("Write a reply").font(.system(size: 11, weight: .medium)) }.buttonStyle(.plain).foregroundStyle(Color.aster)
                }
            } else { Text("A summary is unavailable. You can still read and reply below.").font(.system(size: 11)).foregroundStyle(.secondary) }
        }.padding(20).frame(maxWidth: .infinity, alignment: .leading).modifier(GlassSurface(radius: 20, tinted: true))
    }
    private func initials(_ name: String) -> String { name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined() }
}
/// Email is treated as hostile HTML: no JavaScript, network resources, forms, frames or automatic navigation.
struct SafeHTMLView: NSViewRepresentable {
    let html: String
    @Environment(\.colorScheme) var colorScheme
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        let dark = colorScheme == .dark
        let key = html + String(dark)
        guard context.coordinator.content != key else { return }
        context.coordinator.content = key
        let policy = "default-src 'none'; script-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src 'none'; connect-src 'none'; frame-src 'none'; form-action 'none'; base-uri 'none'"
        let document = """
        <!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="\(policy)"><meta name="viewport" content="width=device-width,initial-scale=1"><style>:root{color-scheme:\(dark ? "dark" : "light")}body{font:14px -apple-system,BlinkMacSystemFont,sans-serif;line-height:1.75;margin:0;padding:4px;color:\(dark ? "#e5e5e8" : "#303036");overflow-wrap:anywhere}img{max-width:100%;height:auto}table{max-width:100%}a{color:#7770b4}blockquote{border-left:2px solid #8884;padding-left:16px;margin-left:0}</style></head><body>\(html)</body></html>
        """
        view.loadHTMLString(document, baseURL: nil)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var content = ""
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url, ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") { NSWorkspace.shared.open(url); decisionHandler(.cancel); return }
            decisionHandler(action.request.url?.scheme == "about" && action.navigationType == .other ? .allow : .cancel)
        }
    }
}

struct QuietGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) var reducedTransparency
    func body(content: Content) -> some View {
        if reducedTransparency { content.background(Color(nsColor: .controlBackgroundColor), in: Capsule()) }
        else if #available(macOS 26.0, *) { content.glassEffect(.regular, in: Capsule()) }
        else { content.background(.thinMaterial, in: Capsule()) }
    }
}
