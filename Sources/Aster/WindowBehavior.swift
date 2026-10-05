import SwiftUI
import AppKit

@MainActor enum WindowBehavior {
    static func configure(_ window: NSWindow) {
        window.level = .normal
        window.isMovableByWindowBackground = false
        window.isMovable = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarAppearsTransparent = true
    }
}
/// Only the empty top strip initiates a drag; text and controls never do.
struct WindowDragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { TitleDragView() }
    func updateNSView(_ view: NSView, context: Context) {}
}
final class TitleDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
}
