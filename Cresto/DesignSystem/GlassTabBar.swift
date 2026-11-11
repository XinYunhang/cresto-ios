import SwiftUI

/// 底部：一枚液态玻璃胶囊 + 一枚纯白圆形 FAB。
/// 白只出现在 FAB 上，胶囊里靠透明度分层。
struct GlassTabBar: View {
    @Binding var selection: AppTab
    var onAdd: () -> Void

    @Namespace private var selectionNS

    init(selection: Binding<AppTab>, onAdd: @escaping () -> Void) {
        self._selection = selection
        self.onAdd = onAdd
    }

    var body: some View {
        HStack(spacing: 11) {
            tabPill
            addButton
        }
    }

    // MARK: 胶囊

    private var tabPill: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(8)
        .glassCapsule()
        .shadow(color: .black.opacity(0.9), radius: 28, y: 16)
    }

    private func tabButton(_ tab: AppTab) -> some View {
        Button {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
                selection = tab
            }
        } label: {
            Image(systemName: tab.symbol)
                .font(.system(size: 21, weight: .regular))
                .foregroundStyle(selection == tab ? Theme.text : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            .background {
                if selection == tab {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                        .overlay(
                            Capsule().strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                        )
                        .matchedGeometryEffect(id: "selection", in: selectionNS)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selection == tab ? .isSelected : [])
    }

    // MARK: FAB

    private var addButton: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(.black)
                .frame(width: 74, height: 74)
                .background(Circle().fill(Theme.ink))
                .overlay(Circle().strokeBorder(Color.white, lineWidth: 1))
                .shadow(color: .black.opacity(0.9), radius: 24, y: 14)
                .shadow(color: .white.opacity(0.10), radius: 26)
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("新建待办")
    }
}
