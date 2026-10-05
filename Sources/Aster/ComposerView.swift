import SwiftUI
import AsterCore

struct ComposerView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var draft: Composer
    @State private var busy = false
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var formalPreview: Composer?
    @State private var formalisingTask: Task<Void, Never>?
    @State private var failure: String?
    @State private var autosaveTask: Task<Void, Never>?
    @State private var saveStatus = "Draft saved on this Mac"
    init(initial: Composer) { _draft = State(initialValue: initial) }
    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(draft.mode == "new" ? "New message" : draft.mode == "forward" ? "Forward" : "Reply").font(.system(size: 19, weight: .semibold)); Spacer(); Button("Save & close") { save(send: false, close: true) }.disabled(busy) }.padding(24)
            Divider()
            VStack(spacing: 12) {
                HStack { Text("From").font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 55, alignment: .leading); Text(state.accountName).font(.system(size: 13, weight: .medium)).textSelection(.enabled); Spacer() }
                field("To", text: $draft.to)
                field("Cc", text: $draft.cc)
                field("Bcc", text: Binding(get: { draft.bcc ?? "" }, set: { draft.bcc = $0 }))
                field("Subject", text: $draft.subject)
            }.padding(24).disabled(busy)
            Divider().padding(.horizontal, 24)
            HStack {
                Text(selection.length > 0 ? "Selected text → complete formal email" : "Select rough text below, then Formalise").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { formalise() } label: { Label(busy ? "Working…" : "Formalise", systemImage: "sparkles") }.buttonStyle(.borderless).disabled(busy || selection.length == 0).help("Create a full formal email from only the selected text")
            }.padding(.horizontal, 24).padding(.top, 14)
            SelectedTextEditor(text: $draft.body, selection: $selection, editable: !busy, label: "Draft body · select text to formalise", onFormalise: { text in formalise(text: text) }).padding(20).frame(minHeight: 270)
            if let files = draft.files, !files.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(files) { file in
                            HStack(spacing: 7) { Image(systemName: "doc"); Text(file.name).lineLimit(1); Button { draft.files?.removeAll { $0.id == file.id }; scheduleAutosave() } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).disabled(busy) }.font(.system(size: 11)).padding(9).modifier(GlassSurface(radius: 12))
                        }
                    }.padding(.horizontal, 24).padding(.vertical, 4)
                }.frame(height: 47)
            }
            if let failure { Text(failure).font(.system(size: 12)).foregroundStyle(.orange).textSelection(.enabled).padding(.horizontal, 24).padding(.bottom, 12) }
            HStack {
                Label(state.isDemo ? "Demo · no mail will be delivered" : saveStatus, systemImage: "lock").font(.system(size: 11)).foregroundStyle(.secondary)
                Spacer()
                Button { do { let files = try state.importAttachments(existing: draft.files ?? []); draft.files = (draft.files ?? []) + files; scheduleAutosave() } catch { failure = error.localizedDescription } } label: { Image(systemName: "paperclip") }.help("Attach files · up to 3 MB each").disabled(busy)
                if busy { ProgressView().controlSize(.small) }
                Button("Save draft") { save(send: false, close: false) }.disabled(busy)
                Button("Send") { save(send: true, close: true) }.buttonStyle(AccentButtonStyle()).disabled(busy || (draft.to.isEmpty && draft.cc.isEmpty && (draft.bcc ?? "").isEmpty)).keyboardShortcut(.return, modifiers: [.command, .shift])
            }.padding(18).modifier(GlassSurface(radius: 18)).padding(12)
        }.frame(width: 760, height: 730).background { AppBackdrop() }.interactiveDismissDisabled().tint(.aster)
            .onChange(of: draft.body) { _, _ in scheduleAutosave() }
            .onChange(of: draft.subject) { _, _ in scheduleAutosave() }
            .onChange(of: draft.to) { _, _ in scheduleAutosave() }
            .onChange(of: draft.cc) { _, _ in scheduleAutosave() }
            .onChange(of: draft.bcc) { _, _ in scheduleAutosave() }
            .sheet(item: $formalPreview) { preview in
                FormalEmailPreviewView(initial: preview, onUse: { value in draft = value; selection = NSRange(location: 0, length: 0); scheduleAutosave() }, onSent: { dismiss() }).environmentObject(state).presentationBackground(.clear)
            }
            .onDisappear { autosaveTask?.cancel(); formalisingTask?.cancel() }
    }
    private func formalise(text: String? = nil) {
        guard !busy else { return }
        do {
            let selected = try text ?? SelectedPassage.extract(from: draft.body, range: selection)
            busy = true; failure = nil; autosaveTask?.cancel()
            let original = draft
            formalisingTask = Task {
                do {
                    let result = try await state.formaliseSelectedText(selected, in: original)
                    guard !Task.isCancelled else { return }; formalPreview = result
                } catch is CancellationError { }
                catch { if !Task.isCancelled { failure = error.localizedDescription } }
                if !Task.isCancelled { busy = false }
            }
        } catch { failure = error.localizedDescription }
    }
    private func scheduleAutosave() {
        guard !busy else { return }
        autosaveTask?.cancel(); saveStatus = "Saving draft…"
        let value = draft
        autosaveTask = Task {
            do { try await Task.sleep(for: .milliseconds(700)); try Task.checkCancellation(); try await state.autosave(value); if !Task.isCancelled { saveStatus = "Draft saved on this Mac" } }
            catch is CancellationError { }
            catch { failure = error.localizedDescription; saveStatus = "Draft needs attention" }
        }
    }
    private func field(_ title: String, text: Binding<String>) -> some View { HStack { Text(title).font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 55, alignment: .leading); TextField(title == "Subject" ? "A clear subject" : "name@example.com", text: text).textFieldStyle(.plain).font(.system(size: 13)) } }
    private func save(send: Bool, close: Bool) {
        autosaveTask?.cancel(); busy = true; failure = nil
        Task {
            do { draft = try await state.saveComposer(draft, send: send); if close { dismiss() } }
            catch { failure = error.localizedDescription; if let current = state.composer, current.id == draft.id { draft = current } }
            busy = false
        }
    }
}
struct CommandPalette: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    @FocusState private var focused: Bool
    private var actions: [(String, String, () -> Void)] {
        [("Go to Priority inbox", "tray.full", { state.selection = "priority" }), ("New message", "square.and.pencil", { state.compose() }), ("Reply", "arrowshape.turn.up.left", { state.compose(mode: "reply") }), ("Archive conversation", "archivebox", { state.moveSelected(to: "archive") }), ("Summarize conversation", "text.alignleft", { state.summarize() }), ("Go to Inbox", "tray", { state.selection = "inbox" }), ("Go to Attention", "sparkle", { state.selection = "attention" }), ("Sync mail", "arrow.triangle.2.circlepath", { Task { await state.sync() } }), ("Settings", "gearshape", { state.showSettings = true })].filter { query.isEmpty || $0.0.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("What would you like to do?", text: $query).textFieldStyle(.plain).focused($focused).onSubmit { runFirst() } }.font(.system(size: 16)).padding(.bottom, 10)
            ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                Button { dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { action.2() } } label: { HStack(spacing: 13) { Image(systemName: action.1).frame(width: 22).foregroundStyle(Color.aster); Text(action.0); Spacer(); Image(systemName: "return").foregroundStyle(.tertiary) }.font(.system(size: 13)).padding(10).contentShape(Rectangle()) }.buttonStyle(.plain)
            }
            if actions.isEmpty { Text("No commands found").foregroundStyle(.secondary).padding() }
        }.padding(25).frame(width: 450).onAppear { focused = true }
    }
    private func runFirst() { guard let action = actions.first else { return }; dismiss(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { action.2() } }
}
