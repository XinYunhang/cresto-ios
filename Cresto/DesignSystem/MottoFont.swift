import SwiftUI
import UIKit
import CoreText

/// 首页哲思语录专用衬线体（内置精简 SIL OFL `Noto Serif SC SemiBold` 子集 `MottoSerif.ttf`，仅 4.6KB）。
/// 解决系统 `.font(.system(..., design: .serif))` 仅对拉丁字母生效、简体中文仍回落到苹方无衬线体的问题。
enum MottoFont {
    private static let postScriptName = "NotoSerifSC-SemiBold"
    private static var registered = false

    static func registerIfNeeded() {
        guard !registered else { return }
        registered = true
        guard let url = Bundle.main.url(forResource: "MottoSerif", withExtension: "ttf") else {
            AppLog.warn("未找到 MottoSerif.ttf，首页标题将回退系统字体")
            return
        }
        var error: Unmanaged<CFError>?
        let ok = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        if !ok {
            let msg = (error?.takeRetainedValue() as Error?)?.localizedDescription ?? "未知错误"
            AppLog.warn("注册 MottoSerif 失败：\(msg)")
        }
    }

    static func motto(size: CGFloat) -> Font {
        registerIfNeeded()
        if UIFont(name: postScriptName, size: size) != nil {
            return .custom(postScriptName, size: size)
        }
        if UIFont(name: "STSongti-SC-Bold", size: size) != nil {
            return .custom("STSongti-SC-Bold", size: size)
        }
        return .system(size: size, weight: .light, design: .serif)
    }
}
