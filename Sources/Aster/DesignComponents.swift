import SwiftUI

/// Shared native visual language; avatar colors remain stable across launches.
struct IdentityAvatar: View {
    let name: String
    var size: CGFloat = 36
    var symbol: String?
    private var accent: Color {
        let palette: [Color] = [.aster, .teal, .indigo, .orange, .pink, .blue]
        return palette[name.utf8.reduce(0) { ($0 + Int($1)) % palette.count }]
    }
    private var initials: String { name.split(whereSeparator: { $0 == " " || $0 == "@" }).prefix(2).compactMap(\.first).map(String.init).joined().uppercased() }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.34, style: .continuous)
                .fill(LinearGradient(colors: [accent.opacity(0.27), accent.opacity(0.09)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let symbol { Image(systemName: symbol).font(.system(size: size * 0.4, weight: .semibold)) }
            else { Text(initials).font(.system(size: size * 0.32, weight: .semibold, design: .rounded)) }
        }.foregroundStyle(accent).frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: size * 0.34).stroke(accent.opacity(0.18), lineWidth: 0.7)).accessibilityHidden(true)
    }
}
struct AsterMark: View {
    var size: CGFloat = 34
    var body: some View {
        Image(systemName: "asterisk").font(.system(size: size * 0.56, weight: .bold))
            .foregroundStyle(.white).frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(red: 0.40, green: 0.31, blue: 0.76), Color(red: 0.27, green: 0.25, blue: 0.58)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: size * 0.32))
            .overlay(RoundedRectangle(cornerRadius: size * 0.32).stroke(.white.opacity(0.3), lineWidth: 0.7))
            .shadow(color: .aster.opacity(0.25), radius: 10, y: 4).accessibilityHidden(true)
    }
}
struct AccentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 9)
            .background(LinearGradient(colors: [Color(red: 0.40, green: 0.31, blue: 0.76), Color(red: 0.27, green: 0.25, blue: 0.58)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.24), lineWidth: 0.7))
            .shadow(color: .aster.opacity(configuration.isPressed ? 0.05 : 0.24), radius: 10, y: 4)
            .opacity(enabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
    }
}
struct InboxMetric: View {
    let count: Int
    let title: String
    let symbol: String
    var accent: Color = .aster
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(accent)
            Text("\(count)").font(.system(size: 15, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
        }.padding(.horizontal, 9).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
    }
}
struct SectionEyebrow: View {
    let title: String
    var body: some View { Text(title.uppercased()).font(.system(size: 9, weight: .bold)).tracking(1.8).foregroundStyle(.secondary) }
}
