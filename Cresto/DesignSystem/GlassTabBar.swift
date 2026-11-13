import SwiftUI
import UIKit

/// 底栏：系统 `UISegmentedControl` 承载，iOS 26 的液态玻璃镜片由系统绘制。
/// 高度通过子类化 `intrinsicContentSize` 抬到 58pt，图标同步加大。
struct GlassTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        SegmentedTabBar(selection: $selection)
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
        let images = AppTab.allCases.map { tab in
            UIImage(
                systemName: tab.symbol,
                withConfiguration: UIImage.SymbolConfiguration(pointSize: 21, weight: .regular)
            )
        }
        let control = TallSegmentedControl(items: images)
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
