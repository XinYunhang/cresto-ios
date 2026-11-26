import SwiftUI
import UIKit

/// 材质分两层：
/// · 内容 = 物理质感实心卡（浅色白玉瓷片浮于高级灰底 / 深色炭黑磨砂与顶部微亮高光，配柔和弥散阴影）
/// · 玻璃 = 只给底栏和顶部圆钮
/// 颜色全部是动态色，跟着系统/手动主题走，不需要在每个视图里判断深浅。
enum Theme {
    static let bg = dynamic(dark: 0x0E1015, light: 0xF2F3F7)
    static let surface = dynamic(dark: 0x171A22, light: 0xFFFFFF)
    static let surfaceRaised = dynamic(dark: 0x222633, light: 0xECEEF3)
    /// 未点亮暗槽（热力图空格 / 进度条轨道）
    static let surfaceWell = dynamic(dark: 0x11131A, light: 0xE5E8F0)

    static let text = dynamic(dark: 0xF7F8FA, light: 0x111318)
    static let textSecondary = dynamic(dark: 0x9CA3B2, light: 0x5E6472)
    static let textTertiary = dynamic(dark: 0x676E7E, light: 0x969DA9)

    /// 全局主强调色：沉稳靛蓝 / 钴蓝
    static let brand = dynamic(dark: 0x6B8AFF, light: 0x3B5BDB)
    static let brandSoft = dynamic(dark: 0x1E2640, light: 0xEBF0FF)

    static let accent = brand
    static let ink = text
    static let online = text
    static let mint = textSecondary

    /// DeepSeek 消耗热力色：谷价同族的低饱和青绿（用户拍板），热力格与图例共用
    static let costHeat = dynamic(dark: 0x7FD6BC, light: 0x2E6E5E)

    /// 复选框未完成描边（浅色深色自适应）
    static let checkboxBorder = dynamicLine(dark: 0.28, light: 0.22)

    /// 只用在列表内部的分隔线，不包边
    static let stroke = dynamicLine(dark: 0.08, light: 0.07)
    static let strokeStrong = dynamicLine(dark: 0.12, light: 0.11)

    static let screenPadding: CGFloat = 18
    static let cardGap: CGFloat = 10

    /// 所有 Tab 页 ScrollView 的统一底部留白：
    /// 底栏 64（58+6）+ FAB 52 + 间距 18 + 余量 ≈ 150，保证最后一张卡（含「正在读」展开）
    /// 完全滑过悬浮底栏与 + 按钮之上。
    static let bottomScrollInset: CGFloat = 150

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

/// 全 App 圆角 Token，统一以 `RoundedRectangle(cornerRadius:, style: .continuous)` 消费（Squircle 手感）。
/// card 大卡/Bento/弹窗容器 · item 列表行卡/输入框/次级模块 · control 小按钮/分段 ·
/// grid 课表等密集格 · tile 热力格等微块 · pill 用 Capsule，不设新档。
enum AppRadius {
    static let card: CGFloat = 20
    static let item: CGFloat = 14
    static let control: CGFloat = 10
    static let grid: CGFloat = 8
    static let tile: CGFloat = 2
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

private struct CardElevationModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme
    var radius: CGFloat
    var fill: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(shape.fill(fill))
            .overlay(
                Group {
                    if colorScheme == .dark {
                        shape.strokeBorder(
                            LinearGradient(
                                colors: [Color.white.opacity(0.11), Color.white.opacity(0.02)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.6
                        )
                    } else {
                        shape.strokeBorder(Color.white.opacity(0.9), lineWidth: 0.5)
                    }
                }
            )
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.045),
                radius: colorScheme == .dark ? 10 : 12,
                x: 0,
                y: 4
            )
    }
}

private struct CardSurface: ViewModifier {
    var padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .cardElevation(radius: AppRadius.card)
    }
}

extension View {
    func cardElevation(radius: CGFloat = AppRadius.card, fill: Color = Theme.surface) -> some View {
        modifier(CardElevationModifier(radius: radius, fill: fill))
    }

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
    /// 九套低饱和高级莫兰迪配色，深浅主题各一版。按课程稳定分配。
    private static let lightTones: [(UInt32, UInt32)] = [
        (0xECEFD4, 0x555B2E),
        (0xFAECD6, 0x7A5422),
        (0xDFEFE3, 0x386646),
        (0xEAE2F8, 0x564182),
        (0xFAE8E4, 0x8A4B43),
        (0xE0EAF8, 0x335580),
        (0xDCF0F2, 0x2F5E64),
        (0xF2E4F0, 0x6D4668),
        (0xF5EDE0, 0x6A573B)
    ]

    private static let darkTones: [(UInt32, UInt32)] = [
        (0x464830, 0xECEFD4),
        (0x57462C, 0xFAECD6),
        (0x36493B, 0xDFEFE3),
        (0x463B59, 0xEAE2F8),
        (0x583E3B, 0xFAE8E4),
        (0x364357, 0xE0EAF8),
        (0x33494B, 0xDCF0F2),
        (0x4E3C4D, 0xF2E4F0),
        (0x4A4336, 0xF5EDE0)
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

// MARK: - 丝滑深浅主题切换

enum ThemeTransition {
    static func style(for mode: String) -> UIUserInterfaceStyle {
        switch mode {
        case "dark": return .dark
        case "light": return .light
        default: return .unspecified
        }
    }

    @MainActor
    static func apply(_ mode: String, animated: Bool = true) {
        let target = style(for: mode)
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }

        for window in windows {
            if animated {
                UIView.transition(
                    with: window,
                    duration: 0.36,
                    options: [.transitionCrossDissolve, .allowUserInteraction]
                ) {
                    window.overrideUserInterfaceStyle = target
                }
            } else {
                window.overrideUserInterfaceStyle = target
            }
        }
    }
}
