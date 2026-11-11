import SwiftUI

/// 黑白极简 + 液态玻璃。
/// 规则只有一条：**只有纯白是强调色**，其余全是黑、灰、白透明度。
enum Theme {
    // 表面
    static let bg = Color(hex: 0x000000)
    static let surface = Color.white.opacity(0.045)
    static let surfaceRaised = Color(hex: 0x121212)
    static let stroke = Color.white.opacity(0.09)
    static let strokeStrong = Color.white.opacity(0.16)

    // 文字
    static let text = Color(hex: 0xFAFAFA)
    static let textSecondary = Color(hex: 0xA0A0A0)
    static let textTertiary = Color(hex: 0x5C5C5C)

    // 强调：白
    static let accent = Color(hex: 0xFAFAFA)
    static let ink = Color(hex: 0xFAFAFA)
    static let online = Color(hex: 0xFAFAFA)

    /// 旧名字保留，黑白模式下它就是次级灰
    static let mint = Color(hex: 0xA0A0A0)

    // 尺寸
    static let cardCorner: CGFloat = 22
    static let screenPadding: CGFloat = 18
    static let cardGap: CGFloat = 10
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - 卡片

private struct CardSurface: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
        content
            .padding(padding)
            .background(shape.fill(Theme.surface))
            .overlay(shape.strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

extension View {
    func cardSurface(padding: CGFloat = 15) -> some View {
        modifier(CardSurface(padding: padding))
    }

    func cardLabel() -> some View {
        font(.system(size: 12))
            .foregroundStyle(Theme.textSecondary)
            .tracking(0.4)
    }
}

// MARK: - 液态玻璃

extension View {
    /// iOS 26 用系统 Liquid Glass；旧系统退回毛玻璃。
    @ViewBuilder
    func glassCapsule(interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: Capsule()
            )
        } else {
            self
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Theme.strokeStrong, lineWidth: 1))
        }
    }
}

// MARK: - 按钮反馈

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - 标签

struct AccentChip: View {
    let text: String
    var small = false

    var body: some View {
        Text(text)
            .font(.system(size: small ? 10 : 11))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, small ? 7 : 9)
            .padding(.vertical, small ? 2 : 3)
            .background(Capsule().fill(Color.white.opacity(0.03)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
    }
}

// MARK: - 热力色阶（灰阶）

enum HeatScale {
    static func color(for level: Int) -> Color {
        switch level {
        case 0: return Color.white.opacity(0.06)
        case 1: return Color.white.opacity(0.19)
        case 2: return Color.white.opacity(0.34)
        case 3: return Color.white.opacity(0.58)
        default: return Color.white.opacity(0.93)
        }
    }
}
