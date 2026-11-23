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
    case chevronDown = "reicon-chevron-down"
    case chevronUp = "reicon-chevron-up"
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
}

extension Image {
    /// 需要自行控制 frame / 缩放时直接取模板 Image
    static func reicon(_ icon: Reicon) -> Image {
        Image(uiImage: Reicon.templateImage(icon))
    }
}