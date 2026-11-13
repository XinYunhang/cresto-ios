import SwiftUI
import UIKit

/// 材质分两层：
/// · 内容 = 实心磨砂块（无描边，靠明度分层）
/// · 玻璃 = 只给底栏和顶部圆钮
/// 颜色全部是动态色，跟着系统/手动主题走，不需要在每个视图里判断深浅。
enum Theme {
    static let bg = dynamic(dark: 0x000000, light: 0xFFFFFF)
    static let surface = dynamic(dark: 0x151517, light: 0xF2F2F5)
    static let surfaceRaised = dynamic(dark: 0x1D1D20, light: 0xE9E9EE)

    static let text = dynamic(dark: 0xFAFAFA, light: 0x0A0A0A)
    static let textSecondary = dynamic(dark: 0x9C9CA4, light: 0x6D6D76)
    static let textTertiary = dynamic(dark: 0x5F5F67, light: 0xA2A2AA)

    static let accent = text
    static let ink = text
    static let online = text
    static let mint = textSecondary

    /// 只用在列表内部的分隔线，不包边
    static let stroke = line
    static let strokeStrong = dynamicLine(dark: 0.10, light: 0.09)

    static let cardCorner: CGFloat = 20
    static let screenPadding: CGFloat = 18
    static let cardGap: CGFloat = 10

    // MARK: 构造

    private static func dynamic(dark: UInt32, light: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(rgb: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }

    private static var line: Color {
        Color(uiColor: UIColor { trait in
            UIColor(white: trait.userInterfaceStyle == .dark ? 1 : 0, alpha: 0.055)
        })
    }

    private static func dynamicLine(dark: Double, light: Double) -> Color {
        Color(uiColor: UIColor { trait in
            UIColor(white: trait.userInterfaceStyle == .dark ? 1 : 0, alpha: trait.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(rgb: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: alpha
        )
    }
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

// MARK: - 玻璃

extension View {
    /// 底栏/顶部圆钮专用。iOS 26 走系统 Liquid Glass（含触摸时的形变），旧系统退回毛玻璃。
    @ViewBuilder
    func glassCapsule(interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: Capsule())
        } else {
            self
                .background(Capsule().fill(.ultraThinMaterial))
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        }
    }

    @ViewBuilder
    func glassCircle(interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: Circle())
        } else {
            self
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5))
        }
    }
}

// MARK: - 按钮反馈

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
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
            .padding(.horizontal, small ? 8 : 10)
            .padding(.vertical, small ? 3 : 4)
            .background(Capsule().fill(Theme.surfaceRaised))
    }
}

// MARK: - 热力色阶

enum HeatScale {
    static func color(for level: Int) -> Color {
        Color(uiColor: UIColor { trait in
            let isDark = trait.userInterfaceStyle == .dark
            let white: CGFloat = isDark ? 1 : 0
            switch level {
            case 0: return UIColor(white: white, alpha: isDark ? 0.06 : 0.07)
            case 1: return UIColor(white: white, alpha: isDark ? 0.19 : 0.16)
            case 2: return UIColor(white: white, alpha: isDark ? 0.36 : 0.32)
            case 3: return UIColor(white: white, alpha: isDark ? 0.60 : 0.58)
            default: return UIColor(white: white, alpha: isDark ? 0.95 : 0.88)
            }
        })
    }
}

// MARK: - 课程配色

struct CourseTone {
    let bg: Color
    let fg: Color
}

extension Theme {
    /// 九套低饱和配色，深浅主题各一版。按课程稳定分配。
    private static let lightTones: [(UInt32, UInt32)] = [
        (0xE6E7C8, 0x62663A),
        (0xF7E3C6, 0x7C5A2B),
        (0xDCEBDB, 0x4C6A49),
        (0xE3D9F3, 0x5A4880),
        (0xF8E7E1, 0x8A5A50),
        (0xD9E3F0, 0x3F5776),
        (0xD5E6E7, 0x3B5C60),
        (0xEBDFEA, 0x6A4F68),
        (0xF1E9D9, 0x6B5C45)
    ]

    private static let darkTones: [(UInt32, UInt32)] = [
        (0x4A4B33, 0xE6E7C8),
        (0x5A4A30, 0xF7E3C6),
        (0x3F4A3E, 0xDCEBDB),
        (0x4A4058, 0xE3D9F3),
        (0x5A4340, 0xF8E7E1),
        (0x3E4756, 0xD9E3F0),
        (0x3A4A4B, 0xD5E6E7),
        (0x4E4050, 0xEBDFEA),
        (0x4A463A, 0xF1E9D9)
    ]

    static func courseTone(_ index: Int) -> CourseTone {
        let i = abs(index) % lightTones.count
        let bg = Color(uiColor: UIColor { trait in
            UIColor(rgb: trait.userInterfaceStyle == .dark ? darkTones[i].0 : lightTones[i].0)
        })
        let fg = Color(uiColor: UIColor { trait in
            UIColor(rgb: trait.userInterfaceStyle == .dark ? darkTones[i].1 : lightTones[i].1)
        })
        return CourseTone(bg: bg, fg: fg)
    }
}
