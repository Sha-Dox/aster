import SwiftUI
import AppKit

/// Real Liquid Glass on Tahoe; material or opaque fallbacks preserve readability and accessibility.
struct GlassSurface: ViewModifier {
    var radius: CGFloat = 18
    var interactive = false
    var tinted = false
    @Environment(\.accessibilityReduceTransparency) private var reducedTransparency
    @AppStorage("glassStyle") private var glassStyle = "clear"
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if reducedTransparency || contrast == .increased || glassStyle == "solid" {
            content.background(Color(nsColor: .controlBackgroundColor), in: shape).overlay(shape.stroke(Color.primary.opacity(0.18)))
        } else if #available(macOS 26.0, *) {
            content.glassEffect((glassStyle == "clear" ? Glass.clear : Glass.regular).tint(tinted ? Color.aster.opacity(0.10) : nil).interactive(interactive), in: shape)
                .overlay(shape.stroke(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.75))
                .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
        } else {
            content.background(.ultraThinMaterial, in: shape).overlay(shape.stroke(.white.opacity(0.15)))
        }
    }
}
struct GlassGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        if #available(macOS 26.0, *) { GlassEffectContainer(spacing: 12) { content() } }
        else { content() }
    }
}
struct AppBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reducedTransparency
    @AppStorage("glassStyle") private var glassStyle = "clear"
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        ZStack {
            if reducedTransparency || contrast == .increased || glassStyle == "solid" { Color(nsColor: .windowBackgroundColor) }
            else { DesktopGlassBackdrop() }
            if !reducedTransparency && contrast != .increased && glassStyle != "solid" {
                Ellipse().fill(Color.aster.opacity(scheme == .dark ? 0.26 : 0.22)).frame(width: 690, height: 620).blur(radius: 110).offset(x: -500, y: -380)
                Ellipse().fill(Color.cyan.opacity(scheme == .dark ? 0.16 : 0.14)).frame(width: 600, height: 400).blur(radius: 120).offset(x: 520, y: 380)
            }
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}

struct DesktopGlassBackdrop: NSViewRepresentable {
    @AppStorage("glassStyle") private var glassStyle = "clear"
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = DesktopGlassEffectView(); view.material = glassStyle == "clear" ? .hudWindow : .underWindowBackground; view.blendingMode = .behindWindow; view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) { view.material = glassStyle == "clear" ? .hudWindow : .underWindowBackground }
}
final class DesktopGlassEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.isOpaque = false; window?.backgroundColor = .clear; window?.titlebarAppearsTransparent = true
    }
}
