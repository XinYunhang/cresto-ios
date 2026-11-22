import SwiftUI

/// 全 App 右下角悬浮锚点（课表/待办共用，后续主页交互球复用同一坐标）：
/// 52pt 正圆、右侧内边距 20pt、底栏（58pt + 6pt 底距）正上方 16pt = bottom 80。
enum FloatingAnchor {
    static let size: CGFloat = 52
    static let trailing: CGFloat = 20
    static let bottom: CGFloat = 80
}

struct FloatingActionButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.bg)
                .frame(width: FloatingAnchor.size, height: FloatingAnchor.size)
                .background(Circle().fill(Theme.text))
                .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

extension View {
    /// 挂到全 App 统一的右下角锚点
    func floatingAddButton(_ accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        overlay(alignment: .bottomTrailing) {
            FloatingActionButton(accessibilityLabel: accessibilityLabel, action: action)
                .padding(.trailing, FloatingAnchor.trailing)
                .padding(.bottom, FloatingAnchor.bottom)
        }
    }
}
