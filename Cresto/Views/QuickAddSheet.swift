import SwiftUI
import SwiftData
import UIKit

/// Flomo 风格悬空液态玻璃快速输入浮卡（iOS 26 走原生玻璃材质与按钮，iOS 17–25 毛玻璃兜底）。
struct QuickAddSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var text = ""
    @State private var choice: DueChoice = .today
    @State private var urgency: TaskUrgency = .mild
    @State private var tags: [String] = []
    @State private var isAddingTag = false
    @State private var tagDraft = ""
    @State private var expanded = false
    @FocusState private var focused: Bool

    private let hapticSelect = UISelectionFeedbackGenerator()

    enum DueChoice: String, CaseIterable, Identifiable {
        case today, tomorrow, none

        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return "今天"
            case .tomorrow: return "明天"
            case .none: return "无日期"
            }
        }

        var next: DueChoice {
            switch self {
            case .today: return .tomorrow
            case .tomorrow: return .none
            case .none: return .today
            }
        }

        var date: Date? {
            let calendar = Calendar.current
            switch self {
            case .today:
                return calendar.startOfDay(for: Date())
            case .tomorrow:
                return calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))
            case .none:
                return nil
            }
        }
    }

    var body: some View {
        Group {
            if expanded {
                TaskEditor(
                    defaultDate: choice.date,
                    defaultTitle: text,
                    defaultUrgency: urgency,
                    defaultTags: tags
                )
            } else {
                floatingCard
            }
        }
        .presentationDetents(expanded ? [.large] : [.height(246)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(.clear)
        .onAppear { focused = true }
        .alert("添加标签", isPresented: $isAddingTag) {
            TextField("5 个字以内", text: $tagDraft)
            Button("添加") { commitTag() }
            Button("取消", role: .cancel) { tagDraft = "" }
        }
    }

    private var floatingCard: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            cardContent
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
                .modifier(QuickCardGlassModifier(colorScheme: colorScheme))
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule()
                .fill(Theme.textTertiary.opacity(0.35))
                .frame(width: 36, height: 4)
                .frame(maxWidth: .infinity)

            TextField("现在的想法是…", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .foregroundStyle(Theme.text)
                .lineLimit(2...5)
                .focused($focused)
                .frame(minHeight: 72, alignment: .topLeading)
                .submitLabel(.done)
                .onSubmit(add)

            if !tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tags, id: \.self) { tag in
                            Button {
                                tags.removeAll { $0 == tag }
                            } label: {
                                HStack(spacing: 3) {
                                    Text("#\(tag)")
                                    ReiconIcon(icon: .xmark, size: 8)
                                }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.brand)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Theme.brandSoft))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            toolbarRow
        }
    }

    @ViewBuilder
    private var toolbarRow: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                toolbarButtons
            }
        } else {
            toolbarButtons
        }
    }

    private var toolbarButtons: some View {
        HStack(spacing: 8) {
            // # 标签
            toolIconButton(.hashtag, label: "标签") {
                isAddingTag = true
            }

            // 日期轮换胶囊
            Button {
                hapticSelect.selectionChanged()
                withAnimation(.snappy(duration: 0.18)) { choice = choice.next }
            } label: {
                HStack(spacing: 4) {
                    ReiconIcon(icon: .calendar, size: 13.5)
                    Text(choice.title)
                        .font(.system(size: 11.5, weight: .medium))
                }
                .foregroundStyle(choice == .none ? Theme.textTertiary : Theme.text)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .modifier(QuickButtonGlassModifier())
            }
            .buttonStyle(.plain)

            // 简洁三档紧急度
            Button {
                hapticSelect.selectionChanged()
                withAnimation(.snappy(duration: 0.18)) { urgency = urgency.next }
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(urgency.tint)
                        .frame(width: 7, height: 7)
                    Text(urgency.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(urgency.tint)
                }
                .padding(.horizontal, 10)
                .frame(height: 34)
                .modifier(QuickButtonGlassModifier())
            }
            .buttonStyle(.plain)

            // 展开完整编辑页
            toolIconButton(.sliderHorizontal, label: "更多选项") {
                withAnimation(.snappy(duration: 0.2)) { expanded = true }
            }

            Spacer(minLength: 4)

            // 发送 / 添加键
            Button(action: add) {
                ReiconIcon(icon: .check, size: 16)
                    .foregroundStyle(Color.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Theme.brand))
                    .modifier(QuickSendGlassModifier())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("添加待办")
        }
    }

    private func toolIconButton(_ icon: Reicon, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ReiconIcon(icon: icon, size: 15)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 34, height: 34)
                .modifier(QuickCircleGlassModifier())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func commitTag() {
        var value = tagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        tagDraft = ""
        guard !value.isEmpty else { return }
        if value.count > 5 { value = String(value.prefix(5)) }
        if !tags.contains(value) { tags.append(value) }
    }

    private func add() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = TaskItem(
            title: trimmed.isEmpty ? "一件新的事" : trimmed,
            dueDate: choice.date,
            tags: tags,
            urgency: urgency
        )
        context.insert(task)
        NotificationScheduler.sync(task)
        try? context.save()
        dismiss()
    }
}

// MARK: - 原生玻璃容器 / 按键适配

private struct QuickCardGlassModifier: ViewModifier {
    let colorScheme: ColorScheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(.ultraThinMaterial))
                .overlay(
                    shape.strokeBorder(
                        Color.white.opacity(colorScheme == .dark ? 0.16 : 0.72),
                        lineWidth: 0.6
                    )
                )
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.35 : 0.10), radius: 18, y: 6)
        }
    }
}

private struct QuickButtonGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Capsule())
        } else {
            content.background(Capsule().fill(Theme.surfaceRaised.opacity(0.85)))
        }
    }
}

private struct QuickCircleGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(Circle().fill(Theme.surfaceRaised.opacity(0.85)))
        }
    }
}

private struct QuickSendGlassModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content
        }
    }
}
