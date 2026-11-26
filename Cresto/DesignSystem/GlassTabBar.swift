import SwiftUI
import UIKit

/// 底栏：100% 纯 SwiftUI 全液态玻璃胶囊，告别 UIKit UISegmentedControl 桥接与实心底板卡顿。
/// iOS 26 走系统 `GlassEffectContainer` + 流体 `glassEffectID` 镜片；iOS 17–25 走 `.ultraThinMaterial` + 流体镜片。
struct GlassTabBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selection: AppTab

    @Namespace private var tabNS
    @State private var dragIndex: Int?

    private var tabs: [AppTab] { AppTab.visible }
    private var activeIndex: Int {
        if let dragIndex { return dragIndex }
        return tabs.firstIndex(of: selection) ?? 0
    }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                liquidGlass26
            } else {
                liquidGlassLegacy
            }
        }
        .frame(height: 58)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
    }

    @available(iOS 26.0, *)
    private var liquidGlass26: some View {
        GlassEffectContainer(spacing: 0) {
            tabButtons(useNativeGlassLens: true)
                .padding(5)
                .glassEffect(.regular.interactive(), in: Capsule())
        }
    }

    private var liquidGlassLegacy: some View {
        tabButtons(useNativeGlassLens: false)
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
    }

    @ViewBuilder
    private func tabButtons(useNativeGlassLens: Bool) -> some View {
        GeometryReader { geo in
            let count = max(1, tabs.count)
            let slotWidth = geo.size.width / CGFloat(count)

            HStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, item in
                    let isSelected = activeIndex == index
                    Button {
                        select(index: index)
                    } label: {
                        ZStack {
                            if isSelected {
                                lensView(useNativeGlassLens: useNativeGlassLens)
                            }
                            ReiconIcon(icon: item.reicon, size: 21)
                                .foregroundStyle(isSelected ? Theme.brand : Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        let raw = Int(floor(value.location.x / max(1, slotWidth)))
                        let clamped = min(count - 1, max(0, raw))
                        if dragIndex != clamped {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                dragIndex = clamped
                            }
                        }
                    }
                    .onEnded { _ in
                        if let finalIndex = dragIndex {
                            select(index: finalIndex)
                        }
                        dragIndex = nil
                    }
            )
        }
    }

    @ViewBuilder
    private func lensView(useNativeGlassLens: Bool) -> some View {
        if #available(iOS 26.0, *), useNativeGlassLens {
            Capsule()
                .fill(Color.clear)
                .glassEffect(.regular.interactive(), in: Capsule())
                .glassEffectID("tabLens", in: tabNS)
        } else {
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
    }

    private func select(index: Int) {
        guard tabs.indices.contains(index) else { return }
        let target = tabs[index]
        guard selection != target else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
            selection = target
        }
    }
}
