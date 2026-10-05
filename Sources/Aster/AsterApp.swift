import SwiftUI
import AppKit

@main struct AsterApp: App {
    @StateObject private var workspace = WorkspaceState()
    private var state: AppState { workspace.active }
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Window("Aster", id: "main") {
            WorkspaceView().environmentObject(workspace).frame(minWidth: 1040, minHeight: 680)
                .task { await workspace.start() }
        }
        .defaultSize(width: 1240, height: 780)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { Button("New Message") { state.compose() }.keyboardShortcut("n") }
            CommandGroup(replacing: .appSettings) { Button("Settings…") { state.showSettings = true }.keyboardShortcut(",") }
            CommandMenu("Mail") {
                Button("Sync Mail") { Task { await workspace.syncAll() } }.keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Reply") { state.compose(mode: "reply") }.keyboardShortcut("r")
                Button("Write Reply with AI") { state.openReplyAssistant() }.keyboardShortcut("w", modifiers: [.command, .shift])
                Button("Reply All") { state.compose(mode: "replyAll") }.keyboardShortcut("r", modifiers: [.command, .option])
                Button("Forward") { state.compose(mode: "forward") }.keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                Button("Archive") { state.moveSelected(to: "archive") }.keyboardShortcut("e")
                Button("Move to Trash") { state.moveSelected(to: "deleteditems") }.keyboardShortcut(.delete)
                Button("Mark Read / Unread") { if let mail = state.selected { state.mutate(mail, kind: "read", value: String(!mail.isRead)) } }.keyboardShortcut("u", modifiers: [.command, .shift])
                Button("Star / Unstar") { if let mail = state.selected { state.mutate(mail, kind: "flag", value: String(!mail.isFlagged)) } }.keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Summarize Conversation") { state.summarize() }.keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("Next Conversation") { state.navigate(1) }.keyboardShortcut(.downArrow, modifiers: [.option])
                Button("Previous Conversation") { state.navigate(-1) }.keyboardShortcut(.upArrow, modifiers: [.option])
                Button("Command Palette") { state.showPalette = true }.keyboardShortcut("k")
            }
        }
    }
}
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.windows.first?.title = "Aster"
        if let window = NSApp.windows.first { WindowBehavior.configure(window) }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
