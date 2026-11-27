import SwiftUI
import UIKit

/// Reicon 线性图标（reicon.dev · MIT · 作者 Dev Chauhan）。
/// SVG 矢量资源位于 `Assets.xcassets/Reicons`，全部开启 preserves-vector-representation
/// 与 template-rendering-intent，随 foregroundStyle 着色、深浅主题自动适配。
enum Reicon: String {
    case grid = "reicon-grid"
    case gridCells = "reicon-grid2"
    case checkCircle = "reicon-check-circle"
    case calendarDays = "reicon-calendar-days"
    case wallet = "reicon-wallet"
    case moreHorizontal = "reicon-more-h"
    case setting = "reicon-setting"
    case search = "reicon-search"
    case add = "reicon-add"
    case check = "reicon-check"
    case xmark = "reicon-xmark"
    case closeCircle = "reicon-close-circle"
    case chevronRight = "reicon-chevron-right"
    case chevronLeft = "reicon-chevron-left"
    case chevronDown = "reicon-chevron-down"
    case chevronUp = "reicon-chevron-up"
    case card = "reicon-card"
    case pause = "reicon-pause"
    case play = "reicon-play"
    case arrowUpRight = "reicon-arrow-up-right"
    case arrowDownRight = "reicon-arrow-down-right"
    case refresh = "reicon-refresh"
    case share = "reicon-share"
    case download = "reicon-download"
    case edit = "reicon-edit"
    case undo = "reicon-undo"
    case trash = "reicon-trash"
    case sliderHorizontal = "reicon-slider-horizontal"
    case image = "reicon-image"
    case camera = "reicon-camera"
    case minusCircle = "reicon-minus-circle"
    case clock = "reicon-clock"
    case calendar = "reicon-calendar"
    case book = "reicon-book"
    case bell = "reicon-bell"
    case hashtag = "reicon-hashtag"
    case checklist = "reicon-checklist"
    case repeatArrows = "reicon-repeat"
    case list = "reicon-list"
    case cpu = "reicon-cpu"
    case wind = "reicon-wind"
    case star = "reicon-star"
    case flame = "reicon-flame"
}

/// 按点尺寸渲染的模板图标（替代 SF Symbol 的 `.font(.system(size:))` 用法）。
/// Reicon 图形在 24 视框内通常占 ~20，因此传入的点尺寸约等于可视高度。
struct ReiconIcon: View {
    let icon: Reicon
    var size: CGFloat = 14

    var body: some View {
        Image(uiImage: Reicon.templateImage(icon))
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: size, height: size)
    }
}

extension Reicon {
    /// 统一从资产目录取图并**强制 alwaysTemplate**：
    /// SVG 矢量资产在部分系统上会忽略 `renderingMode(.template)` / 资产里的
    /// template-rendering-intent，露出 SVG 原始黑色填充（深色模式下表现为黑块）。
    /// 走 UIImage 的 alwaysTemplate 可保证随 foregroundStyle 着色。
    static func templateImage(_ icon: Reicon) -> UIImage {
        guard let image = UIImage(named: icon.rawValue) else { return UIImage() }
        return image.withRenderingMode(.alwaysTemplate)
    }

    /// 供 iOS 26 原生 TabView / Tab 使用的精确点尺寸模板图标
    static func tabImage(_ icon: Reicon, size: CGFloat = 22) -> UIImage {
        let target = CGSize(width: size, height: size)
        guard let base = UIImage(named: icon.rawValue)?.withRenderingMode(.alwaysTemplate) else {
            return UIImage().withRenderingMode(.alwaysTemplate)
        }
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: target))
        }
        .withRenderingMode(.alwaysTemplate)
    }
}

extension Image {
    /// 需要自行控制 frame / 缩放时直接取模板 Image
    static func reicon(_ icon: Reicon) -> Image {
        Image(uiImage: Reicon.templateImage(icon))
    }
}

// MARK: - 品牌图标（Reicon 400+ Brand Logos，保留品牌原色，不参与 template 着色）

enum BrandIcon: String, CaseIterable, Identifiable {
    case openai = "brand-openai"
    case gemini = "brand-gemini"
    case google = "brand-google"
    case apple = "brand-apple"
    case appleMusic = "brand-apple-music"
    case claude = "brand-claude"
    case deepseek = "brand-deepseek"
    case icloud = "brand-icloud"
    case qqMusic = "brand-qq-music"
    case neteaseMusic = "brand-netease-music"
    case jdBaitiao = "brand-jd-baitiao"
    case bilibili = "brand-bilibili"
    case baiduNetdisk = "brand-baidu-netdisk"
    case generic

    var id: String { rawValue }

    var assetName: String {
        self == .generic ? "reicon-card" : rawValue
    }

    /// 单色品牌图标（OpenAI / Apple）走模板着色，浅色模式呈炭黑、深色模式呈纯白，避免白底隐身
    var usesAdaptiveTemplate: Bool {
        self == .openai || self == .apple
    }

    static func from(raw: String) -> BrandIcon {
        BrandIcon(rawValue: raw) ?? .generic
    }

    var displayName: String {
        switch self {
        case .gemini: return "Gemini"
        case .qqMusic: return "QQ音乐"
        case .neteaseMusic: return "网易云音乐"
        case .jdBaitiao: return "京东白条"
        case .appleMusic: return "Apple Music"
        case .icloud: return "iCloud"
        case .bilibili: return "哔哩哔哩"
        case .baiduNetdisk: return "百度网盘"
        case .openai: return "ChatGPT"
        case .claude: return "Claude"
        case .deepseek: return "DeepSeek"
        case .google: return "Google"
        case .apple: return "Apple"
        case .generic: return "通用卡片"
        }
    }

    /// 主信息色块卡片的柔和品牌主题色
    var tintColor: Color {
        switch self {
        case .gemini: return Color(hex: 0x3186FF)
        case .qqMusic: return Color(hex: 0x16B768)
        case .neteaseMusic: return Color(hex: 0xD43C33)
        case .jdBaitiao: return Color(hex: 0xE1251B)
        case .appleMusic: return Color(hex: 0xFA243C)
        case .icloud: return Color(hex: 0x3693F3)
        case .bilibili: return Color(hex: 0x00A1D6)
        case .baiduNetdisk: return Color(hex: 0x06A7FF)
        case .openai: return Color(hex: 0x10A37F)
        case .claude: return Color(hex: 0xD97757)
        case .deepseek: return Color(hex: 0x4D6BFE)
        case .google: return Color(hex: 0x4285F4)
        case .apple: return Color(hex: 0x6E7382)
        case .generic: return Theme.brand
        }
    }
}

/// 订阅服务品牌图标：品牌色原样渲染；通用订阅回退为 Reicon 线条卡图标（template）。
struct BrandLogo: View {
    let brand: BrandIcon
    var size: CGFloat = 24

    var body: some View {
        if brand == .generic {
            ReiconIcon(icon: .card, size: size)
                .foregroundStyle(Theme.text)
        } else if brand.usesAdaptiveTemplate {
            Image(uiImage: (UIImage(named: brand.assetName) ?? UIImage()).withRenderingMode(.alwaysTemplate))
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .foregroundStyle(Theme.text)
                .frame(width: size, height: size)
        } else {
            Image(brand.assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        }
    }
}