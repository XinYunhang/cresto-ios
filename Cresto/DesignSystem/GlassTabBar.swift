import SwiftUI
import UIKit

/// 底栏：系统 `UISegmentedControl` 承载，iOS 26 的液态玻璃镜片由系统绘制。
/// 高度通过子类化 `intrinsicContentSize` 抬到 58pt，图标同步加大。
struct GlassTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: AppTab

    var body: some View {
        ZStack {
            // 实心底板：内容不再透过底栏（系统镜片只在本板之上做镜面/高光）
            Capsule(style: .continuous)
                .fill(Theme.surface)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(
                            colorScheme == .dark ? Color.white.opacity(0.09) : Color.white.opacity(0.9),
                            lineWidth: 0.5
                        )
                )
                .shadow(
                    color: Color.black.opacity(colorScheme == .dark ? 0.30 : 0.06),
                    radius: 12,
                    y: 4
                )

            SegmentedTabBar(selection: $selection)
        }
        .frame(height: 58)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}

// MARK: - UIKit 桥

private final class TallSegmentedControl: UISegmentedControl {
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 58)
    }
}

private struct SegmentedTabBar: UIViewRepresentable {
    @Binding var selection: AppTab

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeUIView(context: Context) -> UISegmentedControl {
        let images = AppTab.visible.map { tab in
            Self.tabBarImage(tab.reicon)
        }
        let control = TallSegmentedControl(items: images)
        control.apportionsSegmentWidthsByContent = false
        control.selectedSegmentIndex = AppTab.visible.firstIndex(of: selection) ?? 0
        control.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.accessibilityLabel = "主导航"
        return control
    }

    /// Reicon 模板矢量 → 22pt 渲染图（UISegmentedControl 用）
    static func tabBarImage(_ icon: Reicon) -> UIImage {
        let target = CGSize(width: 22, height: 22)
        guard let base = UIImage(named: icon.rawValue)?.withRenderingMode(.alwaysTemplate) else {
            return UIImage().withRenderingMode(.alwaysTemplate)
        }
        let renderer = UIGraphicsImageRenderer(size: target)
        return renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: target))
        }
        .withRenderingMode(.alwaysTemplate)
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        let index = AppTab.visible.firstIndex(of: selection) ?? 0
        if control.selectedSegmentIndex != index {
            control.selectedSegmentIndex = index
        }
    }

    final class Coordinator: NSObject {
        private let selection: Binding<AppTab>

        init(selection: Binding<AppTab>) {
            self.selection = selection
        }

        @objc func valueChanged(_ sender: UISegmentedControl) {
            let cases = AppTab.visible
            let index = sender.selectedSegmentIndex
            guard index >= 0, index < cases.count else { return }
            selection.wrappedValue = cases[index]
        }
    }
}
