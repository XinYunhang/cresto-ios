import SwiftUI
import UIKit

/// 底栏：直接用系统的 `UISegmentedControl` 承载。
///
/// 为什么不再自己画：
/// iOS 26 的液态玻璃镜片是系统组件内部实现的——按下变亮、拖动跟手、吸附、震动都在里面。
/// 自己用 SwiftUI 拼，只能做到「一块色块在动」，做不到镜片的材质变化，
/// 而且玻璃不能嵌套玻璃（会糊）。所以把形状和动画交给系统，我们只提供四个图标。
struct GlassTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        SegmentedTabBar(selection: $selection)
            .frame(height: 52)
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
    }
}

// MARK: - UIKit 桥

private struct SegmentedTabBar: UIViewRepresentable {
    @Binding var selection: AppTab

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeUIView(context: Context) -> UISegmentedControl {
        let images = AppTab.allCases.map { tab in
            UIImage(
                systemName: tab.symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 19, weight: .regular)
            )
        }
        let control = UISegmentedControl(items: images)
        control.apportionsSegmentWidthsByContent = false
        control.selectedSegmentIndex = AppTab.allCases.firstIndex(of: selection) ?? 0
        control.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.accessibilityLabel = "主导航"
        return control
    }

    func updateUIView(_ control: UISegmentedControl, context: Context) {
        let index = AppTab.allCases.firstIndex(of: selection) ?? 0
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
            let cases = AppTab.allCases
            let index = sender.selectedSegmentIndex
            guard index >= 0, index < cases.count else { return }
            selection.wrappedValue = cases[index]
        }
    }
}
