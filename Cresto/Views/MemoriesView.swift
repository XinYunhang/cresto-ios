import SwiftUI

/// 第 5 Tab · 纪念与随笔占位页（票根与 iOS 手记导入具体交互将在下轮实现）。
struct MemoriesView: View {
    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.cardGap) {
                header
                placeholderCard
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.bottomScrollInset)
        }
        .background(Theme.bg)
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("纪念")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.text)
                .tracking(-0.5)
            Spacer()
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private var placeholderCard: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ReiconIcon(icon: .card, size: 22)
                    .foregroundStyle(Theme.brand)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous).fill(Theme.brandSoft))

                ReiconIcon(icon: .star, size: 22)
                    .foregroundStyle(Theme.brand)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous).fill(Theme.brandSoft))
            }

            Text("纪念票根与随笔")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("叠放票夹（方案一）与 iOS 手记随笔导入已就位入口，将在下个版本完善上线。")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
        .cardSurface()
    }
}
