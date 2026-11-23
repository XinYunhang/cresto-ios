import SwiftUI

/// 记账（第 4 Tab 占位页）。
/// 标注：下一步在此扩展「流水 / 订阅」双分段，本页先保留与待办/课表一致的白底大标题 + 浅灰占位卡。
struct LedgerView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: Theme.cardGap) {
                Text("记账")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .tracking(-0.5)
                    .padding(.horizontal, 2)
                    .padding(.top, 2)
                    .padding(.bottom, 6)

                placeholderCard
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.bottomScrollInset)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.bg)
    }

    /// 占位结构：顶部预留「流水 / 订阅」双分段位置，下方为开发中提示
    private var placeholderCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                ghostChip("流水", selected: true)
                ghostChip("订阅", selected: false)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("记账与订阅管理模块开发中")
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textSecondary)
                Text("下一步接入流水记录与订阅管理双分段")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func ghostChip(_ title: String, selected: Bool) -> some View {
        Text(title)
            .font(.system(size: 12, weight: selected ? .medium : .regular))
            .foregroundStyle(selected ? Theme.text : Theme.textTertiary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule().fill(selected ? Theme.surfaceRaised : Color.white.opacity(0.04))
            )
    }
}

#Preview {
    LedgerView()
        .modelContainer(PreviewData.container)
}