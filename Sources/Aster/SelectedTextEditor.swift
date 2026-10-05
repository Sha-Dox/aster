import SwiftUI
import AppKit

/// Native text selection survives toolbar clicks; ranges use AppKit's UTF-16 coordinates.
struct SelectedTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var selection: NSRange
    var editable = true
    var label = "Email text"
    var onFormalise: ((String) -> Void)?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = SelectionScrollView(); scroll.hasVerticalScroller = true; scroll.drawsBackground = false
        let view = FormalisingTextView(frame: .zero)
        view.isRichText = false; view.allowsUndo = true; view.isEditable = editable; view.isSelectable = true
        view.drawsBackground = false; view.font = .systemFont(ofSize: 14); view.textColor = .textColor
        view.textContainerInset = NSSize(width: 8, height: 8)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false
        view.minSize = .zero; view.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        view.textContainer?.containerSize = NSSize(width: scroll.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        view.delegate = context.coordinator; view.string = text
        view.setAccessibilityLabel(label); view.onFormalise = onFormalise
        scroll.documentView = view
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let view = scroll.documentView as? FormalisingTextView else { return }
        context.coordinator.parent = self; context.coordinator.applying = true
        if view.string != text { view.string = text }
        view.isEditable = editable; view.onFormalise = onFormalise; view.setAccessibilityLabel(label)
        let length = (text as NSString).length
        let range = NSRange(location: min(selection.location, length), length: min(selection.length, max(0, length - min(selection.location, length))))
        if view.selectedRange() != range { view.setSelectedRange(range) }
        context.coordinator.applying = false
    }
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SelectedTextEditor
        var applying = false
        init(_ parent: SelectedTextEditor) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard !applying, let view = notification.object as? NSTextView else { return }
            parent.text = view.string; parent.selection = view.selectedRange()
        }
        func textViewDidChangeSelection(_ notification: Notification) {
            guard !applying, let view = notification.object as? NSTextView else { return }
            parent.selection = view.selectedRange()
        }
    }
}
final class SelectionScrollView: NSScrollView { override var mouseDownCanMoveWindow: Bool { false } }
final class FormalisingTextView: NSTextView {
    override var mouseDownCanMoveWindow: Bool { false }
    var onFormalise: ((String) -> Void)?
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        if onFormalise != nil {
            menu.addItem(.separator())
            let item = NSMenuItem(title: "Formalise into a complete email", action: #selector(formaliseSelection), keyEquivalent: "")
            item.target = self; item.isEnabled = selectedRange().length > 0; menu.addItem(item)
        }
        return menu
    }
    @objc private func formaliseSelection() {
        guard let range = Range(selectedRange(), in: string), !range.isEmpty else { return }
        onFormalise?(String(string[range]))
    }
}
