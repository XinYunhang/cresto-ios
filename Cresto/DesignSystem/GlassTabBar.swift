import SwiftUI
import UIKit

/// 底栏：四枚图标，无文字、无 FAB。
///
/// 玻璃分两层：整条胶囊是系统液态玻璃（`.interactive()` 跟随触摸提亮），
/// 选中态是一块**独立滑块**，拖动时连续跟手并横向拉伸，松手弹簧吸附。
/// 没有把滑块做成第二层玻璃——iOS 26 不支持玻璃套玻璃，会糊成一片。
struct GlassTabBar: View {
    @Binding var selection: AppTab

    @State private var barWidth: CGFloat = 0
    /// 拖动时滑块的连续位置（0...count-1）；nil 表示停在选中项
    @State private var dragFraction: CGFloat?
    @State private var isDragging = false

    private let inset: CGFloat = 8
    private let barHeight: CGFloat = 64
    private let lensHeight: CGFloat = 48
    private let impact = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        let count = CGFloat(AppTab.allCases.count)
        let segment = barWidth > 0 ? (barWidth - inset * 2) / count : 0
        let selectedIndex = CGFloat(AppTab.allCases.firstIndex(of: selection) ?? 0)
        let restingX = inset + selectedIndex * segment
        let lensX = dragFraction.map { inset + $0 * segment } ?? restingX
        let stretch: CGFloat = isDragging ? 4 : 0

        ZStack(alignment: .leading) {
            // 整条玻璃
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassCapsule()

            // 选中滑块
            if segment > 0 {
                Capsule(style: .continuous)
                    .fill(Theme.text.opacity(0.14))
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Color.white.opacity(0.10), Color.white.opacity(0.02)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                    )
                    .frame(width: max(0, segment - 4 + stretch * 2), height: lensHeight)
                    .offset(x: lensX - 2 - stretch, y: (barHeight - lensHeight) / 2)
            }

            HStack(spacing: 0) {
                ForEach(AppTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(inset)
        }
        .frame(height: barHeight)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { barWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in barWidth = newValue }
            }
        )
        .contentShape(Capsule())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard segment > 0 else { return }
                    if !isDragging {
                        isDragging = true
                        impact.prepare()
                    }
                    let raw = (value.location.x - inset) / segment
                    let fraction = min(max(raw, 0), count - 1)
                    dragFraction = fraction

                    let nearest = Int(fraction.rounded())
                    let tab = AppTab.allCases[nearest]
                    if tab != selection {
                        selection = tab
                        impact.impactOccurred()
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
                        dragFraction = nil
                    }
                }
        )
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            guard tab != selection else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                selection = tab
            }
            impact.impactOccurred()
        } label: {
            Image(systemName: tab.symbol)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(selection == tab ? Theme.text : Theme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }
}
