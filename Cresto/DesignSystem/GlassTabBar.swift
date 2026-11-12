import SwiftUI
import UIKit

/// 底栏：四枚图标，没有文字，也没有 FAB。
/// 玻璃走 iOS 26 的 Liquid Glass（`.interactive()` 会跟随手指有形变）。
/// 拖动切页：手指按下后横向滑动，滑到哪个图标就切到哪页。
struct GlassTabBar: View {
    @Binding var selection: AppTab

    @Namespace private var selectionNS
    @State private var pillWidth: CGFloat = 0
    @State private var isDragging = false

    private let impact = UIImpactFeedbackGenerator(style: .light)

    init(selection: Binding<AppTab>) {
        self._selection = selection
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(8)
        .glassCapsule()
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { pillWidth = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, newValue in pillWidth = newValue }
            }
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !isDragging {
                        isDragging = true
                        impact.prepare()
                    }
                    select(at: value.location.x)
                }
                .onEnded { _ in isDragging = false }
        )
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            activate(tab)
        } label: {
            Image(systemName: tab.symbol)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(selection == tab ? Theme.text : Theme.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    if selection == tab {
                        Capsule()
                            .fill(Theme.text.opacity(0.13))
                            .matchedGeometryEffect(id: "selection", in: selectionNS)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }

    // MARK: 手势

    private func select(at x: CGFloat) {
        guard pillWidth > 0 else { return }
        let count = CGFloat(AppTab.allCases.count)
        let inset: CGFloat = 8
        let step = (pillWidth - inset * 2) / count
        let index = Int(((x - inset) / step).rounded(.down))
        let clamped = min(max(index, 0), Int(count) - 1)
        activate(AppTab.allCases[clamped])
    }

    private func activate(_ tab: AppTab) {
        guard tab != selection else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            selection = tab
        }
        impact.impactOccurred()
    }
}
