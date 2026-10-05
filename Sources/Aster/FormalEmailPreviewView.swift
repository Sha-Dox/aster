import SwiftUI

struct FormalEmailPreviewView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var email: Composer
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var sending = false
    @State private var didSend = false
    @State private var attemptedSend = false
    @State private var failure: String?
    let onUse: (Composer) -> Void
    let onSent: () -> Void
    init(initial: Composer, onUse: @escaping (Composer) -> Void, onSent: @escaping () -> Void) { _email = State(initialValue: initial); self.onUse = onUse; self.onSent = onSent }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Formal email preview", systemImage: "sparkles").font(.system(size: 21, weight: .semibold))
                Spacer(); Button("Cancel") { dismiss() }.disabled(sending)
            }.padding(24)
            Text("Generated from your selected text. Use full email replaces the entire draft body; nothing changes until you choose it or accept sending.").font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 18)
            VStack(spacing: 12) {
                HStack { Text("From").foregroundStyle(.secondary).frame(width: 55, alignment: .leading); Text(state.accountName); Spacer() }
                field("To", text: $email.to); field("Cc", text: $email.cc)
                field("Bcc", text: Binding(get: { email.bcc ?? "" }, set: { email.bcc = $0 }))
                field("Subject", text: $email.subject)
            }.font(.system(size: 12)).padding(.horizontal, 24).padding(.bottom, 18).disabled(sending)
            SelectedTextEditor(text: $email.body, selection: $selection, editable: !sending, label: "Editable formal email preview").padding(.horizontal, 16).frame(minHeight: 310)
            if let files = email.files, !files.isEmpty { Text("Attachments: " + files.map(\.name).joined(separator: ", ")).font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 24).padding(.bottom, 8) }
            if let failure { Text(failure).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled).padding(.horizontal, 24).padding(.bottom, 12) }
            HStack {
                Text(state.isDemo ? "Demo · no email will be delivered" : "Review before accepting").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Use full email") { onUse(email); dismiss() }.disabled(sending)
                Button(sending ? "Sending…" : "Accept & send") { send() }.buttonStyle(AccentButtonStyle()).disabled(sending || email.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (email.to.isEmpty && email.cc.isEmpty && (email.bcc ?? "").isEmpty))
            }.padding(18).modifier(GlassSurface(radius: 18)).padding(12)
        }.frame(width: 760, height: 710).background { AppBackdrop() }.tint(.aster).interactiveDismissDisabled(sending)
            .onDisappear {
                if didSend { onSent() }
                else if attemptedSend, let recovered = state.latestDraft(email.id) { onUse(recovered) }
            }
    }
    private func field(_ title: String, text: Binding<String>) -> some View { HStack { Text(title).foregroundStyle(.secondary).frame(width: 55, alignment: .leading); TextField(title, text: text).textFieldStyle(.plain) } }
    private func send() {
        guard !sending else { return }; sending = true; attemptedSend = true; failure = nil
        Task {
            do { _ = try await state.saveComposer(email, send: true, presentComposerUpdates: false); didSend = true; dismiss() }
            catch { failure = error.localizedDescription; if let recovered = state.latestDraft(email.id) { email = recovered } }
            sending = false
        }
    }
}
