import SwiftUI
import AsterCore

struct WritingStyleControls: View {
    @Binding var style: WritingStyle
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Writing language", text: $style.language)
                Menu("Choose language") {
                    ForEach(["Match the original email", "English", "Turkish", "German", "French", "Spanish", "Arabic", "Japanese"], id: \.self) { language in Button(language) { style.language = language } }
                }.fixedSize()
            }
            Picker("Tone", selection: $style.tone) { ForEach(WritingTone.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            Picker("Length", selection: $style.length) { ForEach(WritingLength.allCases, id: \.self) { Text($0.title).tag($0) } }.pickerStyle(.segmented)
            TextField("Your style · e.g. polite, direct, no exclamation marks", text: $style.customInstructions, axis: .vertical).lineLimit(2...4)
            TextField("Signature · e.g. Best regards, followed by your name", text: $style.signature, axis: .vertical).lineLimit(2...4)
            Text("You can type another language. Model support varies. These preferences affect the writing, while your instruction decides the answer.").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

struct ReplyAssistantView: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var workspace: WorkspaceState
    @Environment(\.dismiss) private var dismiss
    let context: ReplyAssistantContext
    @State private var intent = ""
    @State private var intentSelection = NSRange(location: 0, length: 0)
    @State private var previewSelection = NSRange(location: 0, length: 0)
    @State private var style: WritingStyle
    @State private var preview: Composer?
    @State private var generatedRequest: ReplyRequest?
    @State private var generating = false
    @State private var sending = false
    @State private var attemptedSend = false
    @State private var failure: String?
    @State private var generationTask: Task<Void, Never>?
    init(context: ReplyAssistantContext, style: WritingStyle) { self.context = context; _style = State(initialValue: style) }
    private var request: ReplyRequest { ReplyRequest(intent: intent, style: style, senderAddress: context.accountEmail, targetMessageID: context.mail.id) }
    private var currentPreview: Bool { preview != nil && generatedRequest == request }
    private var providerLabel: String {
        switch UserDefaults.standard.string(forKey: "intelligenceMode") ?? "apple" {
        case "remote": return "Uses your configured model endpoint"
        case "local": return "Local rules · choose a model in Settings to generate"
        default: return AppleIntelligenceStatus.available ? "Apple Intelligence · on this Mac" : AppleIntelligenceStatus.description
        }
    }
    private var busy: Bool { generating || sending }
    private func draftField(_ path: WritableKeyPath<Composer, String>) -> Binding<String> { Binding(get: { preview?[keyPath: path] ?? "" }, set: { preview?[keyPath: path] = $0 }) }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Reply assistant", systemImage: "sparkles").font(.system(size: 23, weight: .semibold))
                Spacer(); Button("Close") { dismiss() }.disabled(sending)
            }.padding(24)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(context.mail.subject).font(.system(size: 15, weight: .semibold))
                        Text("Replying to \(context.mail.sender.name) · from \(context.accountEmail)").font(.system(size: 11)).foregroundStyle(.secondary)
                        Text("Uses \(context.thread.count) cached messages. The model may receive shortened context.").font(.system(size: 10)).foregroundStyle(.tertiary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What do you want to say?").font(.system(size: 14, weight: .semibold))
                        Text("For example: Choose A, but replace X with Y. Ask if that works for them.").font(.system(size: 11)).foregroundStyle(.secondary)
                        SelectedTextEditor(text: $intent, selection: $intentSelection, editable: !busy, label: "Your answer and requested changes · select text to formalise", onFormalise: { text in formalise(text) }).frame(height: 110).modifier(GlassSurface(radius: 12))
                        HStack {
                            Text("Select your rough answer to turn it into a full formal reply.").font(.system(size: 11)).foregroundStyle(.secondary)
                            Spacer()
                            Button("Formalise") { if let text = try? SelectedPassage.extract(from: intent, range: intentSelection) { formalise(text) } }.disabled(busy || attemptedSend || intentSelection.length == 0)
                        }
                    }
                    DisclosureGroup("Language & writing style") {
                        WritingStyleControls(style: $style).padding(.top, 12)
                        Button("Remember this style for \(context.accountEmail)") {
                            if let profile = workspace.profiles.first(where: { $0.email == context.accountEmail }) { var policy = profile.policy; policy.writingStyle = style; workspace.updatePolicy(policy, accountID: profile.id) }
                        }.buttonStyle(.borderless).padding(.top, 12)
                    }
                    HStack {
                        Button(generating ? "Writing preview…" : preview == nil ? "Generate preview" : "Regenerate preview") { generate() }.buttonStyle(.borderedProminent).disabled(busy || attemptedSend || intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if generating { ProgressView().controlSize(.small); Button("Cancel") { generationTask?.cancel(); generating = false }.buttonStyle(.borderless) }
                        Spacer()
                        Text(providerLabel).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if preview != nil {
                        Divider()
                        HStack { Text("Email preview").font(.system(size: 16, weight: .semibold)); Spacer(); Text("Editable").font(.system(size: 11)).foregroundStyle(.secondary) }
                        if !currentPreview { Text("Your instruction or style changed. Regenerate the preview before accepting it.").font(.system(size: 11)).foregroundStyle(.orange) }
                        VStack(spacing: 12) {
                            HStack { Text("From").foregroundStyle(.secondary).frame(width: 55, alignment: .leading); Text(context.accountEmail); Spacer() }
                            field("To", path: \.to); field("Cc", path: \.cc); field("Subject", path: \.subject)
                            SelectedTextEditor(text: draftField(\.body), selection: $previewSelection, editable: !sending, label: "Editable generated email preview").frame(height: 270).modifier(GlassSurface(radius: 12))
                        }.font(.system(size: 12))
                        Text("Review the decision, substitutions, names and dates. Only Accept & send delivers this preview.").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    if let failure { Text(failure).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled) }
                }.padding(.horizontal, 26).padding(.bottom, 20).disabled(sending)
            }
            HStack {
                Label(state.isDemo ? "Demo · no email will be delivered" : "Waiting for your acceptance", systemImage: "checkmark.shield").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button("Save draft & close") { saveDraft() }.disabled(busy || !currentPreview)
                Button(sending ? "Sending…" : "Accept & send") { accept() }.buttonStyle(.borderedProminent).disabled(busy || !currentPreview || (preview?.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
            }.padding(18).modifier(GlassSurface(radius: 18)).padding(12)
        }.frame(width: 780, height: 790).background { AppBackdrop() }.tint(.aster).interactiveDismissDisabled(sending)
            .onDisappear { generationTask?.cancel() }
    }
    private func field(_ title: String, path: WritableKeyPath<Composer, String>) -> some View {
        HStack { Text(title).foregroundStyle(.secondary).frame(width: 55, alignment: .leading); TextField(title, text: draftField(path)).textFieldStyle(.plain) }
    }
    private func formalise(_ text: String) {
        guard !busy, !attemptedSend else { return }
        style.tone = .formal
        generate(selectedText: text)
    }
    private func generate(selectedText: String? = nil) {
        generationTask?.cancel(); generating = true; failure = nil
        let submitted = request
        generationTask = Task {
            do {
                let draft = try await state.generateAssistedReply(context, intent: selectedText ?? submitted.intent, style: submitted.style)
                guard !Task.isCancelled else { return }
                preview = draft; generatedRequest = submitted
            } catch is CancellationError { }
            catch { if !Task.isCancelled { failure = error.localizedDescription } }
            if !Task.isCancelled { generating = false }
        }
    }
    private func accept() {
        guard currentPreview, let draft = preview else { return }; sending = true; attemptedSend = true; failure = nil
        Task {
            do { try await state.sendAcceptedReply(context, draft: draft); dismiss() }
            catch { failure = error.localizedDescription; if let recovered = state.latestDraft(draft.id) { preview = recovered } }
            sending = false
        }
    }
    private func saveDraft() {
        guard currentPreview, let draft = preview else { return }; sending = true; failure = nil
        Task {
            do { try await state.autosave(draft); state.notice = "Generated reply saved locally. Nothing was sent."; await state.refreshCachedMail(); dismiss() }
            catch { failure = error.localizedDescription }
            sending = false
        }
    }
}
