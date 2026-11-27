import SwiftUI
import UIKit

/// iOS 17–25 兜底悬浮玻璃底栏（iOS 26+ 已在 RootView 改走原生 TabView + Tab 液态玻璃底栏）。
/// 仅支持点按切换，移除拖拽手势防止整条底栏误拖动。
struct GlassTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: AppTab

    @Namespace private var tabNS

    private var tabs: [AppTab] { AppTab.visible }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { item in
                let isSelected = selection == item
                Button {
                    guard selection != item else { return }
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                        selection = item
                    }
                } label: {
                    ZStack {
                        if item == .overview {
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .fill(Theme.brand)
                                .frame(width: 42, height: 34)
                                .shadow(color: Theme.brand.opacity(0.28), radius: 6, y: 2)
                            ReiconIcon(icon: item.reicon, size: 19)
                                .foregroundStyle(Color.white)
                        } else {
                            if isSelected {
                                Capsule()
                                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(
                                                Color.white.opacity(colorScheme == .dark ? 0.18 : 0.68),
                                                lineWidth: 0.5
                                            )
                                    )
                                    .matchedGeometryEffect(id: "tabLens", in: tabNS)
                            }
                            ReiconIcon(icon: item.reicon, size: 20)
                                .foregroundStyle(isSelected ? Theme.brand : Theme.textSecondary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .padding(5)
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(
                    Color.white.opacity(colorScheme == .dark ? 0.18 : 0.72),
                    lineWidth: 0.6
                )
        )
        .shadow(
            color: Color.black.opacity(colorScheme == .dark ? 0.36 : 0.08),
            radius: 16,
            y: 6
        )
        .frame(height: 58)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }
}
