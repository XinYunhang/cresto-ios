import SwiftUI
import SwiftData
import UIKit

/// FAB 拉起来的快速添加。选好日期点「添加」就结束；
/// 要提醒 / 重复 / 子任务就点「更多选项」，原地展开成完整编辑页。
struct QuickAddSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var choice: DueChoice = .today
    @State private var urgency: TaskUrgency = .mild
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
            case .none: return "不设日期"
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
                TaskEditor(defaultDate: choice.date, defaultTitle: text, defaultUrgency: urgency)
            } else {
                quickContent
            }
        }
        .presentationDetents(expanded ? [.large] : [.height(340)])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Theme.surfaceRaised)
        .onAppear { focused = true }
    }

    private var quickContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 38, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 15)

            Text("新建待办")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 13)

            TextField("要做点什么？", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .lineLimit(1...3)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit(add)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .strokeBorder(focused ? Color.white.opacity(0.35) : Theme.stroke, lineWidth: 1)
                )

            HStack(spacing: 6) {
                ForEach(DueChoice.allCases) { item in
                    let isOn = choice == item
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { choice = item }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 12))
                            .foregroundStyle(isOn ? Theme.bg : Theme.textSecondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(isOn ? Theme.ink : Color.white.opacity(0.05)))
                            .overlay(Capsule().strokeBorder(isOn ? Color.clear : Theme.stroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)

                // 紧急程度小胶囊（设计图：日期行最右侧，点按循环 轻微→重要→紧急）
                urgencyCapsule
            }
            .padding(.top, 12)

            HStack(spacing: 6) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded = true }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 11))
                        Text("时间、提醒、子任务")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 14)

            Button(action: add) {
                Text("添加")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                            .fill(Theme.ink)
                    )
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 16)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 26)
        .background(Theme.surfaceRaised.ignoresSafeArea())
    }

    // MARK: 紧急程度胶囊

    private var urgencyCapsule: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                urgency = urgency.next
            }
            hapticSelect.selectionChanged()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(urgency.tint)
                    .frame(width: 7, height: 7)
                    .shadow(color: urgency.tint.opacity(0.85), radius: 3.5)
                Text(urgency.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(urgency.tint)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Capsule().fill(urgency.tint.opacity(0.12)))
            .overlay(Capsule().strokeBorder(urgency.tint.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("紧急程度：\(urgency.title)")
        .accessibilityHint("点按切换档位")
    }

    private func add() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = TaskItem(
            title: trimmed.isEmpty ? "一件新的事" : trimmed,
            dueDate: choice.date,
            urgency: urgency
        )
        context.insert(task)
        NotificationScheduler.sync(task)
        try? context.save()
        dismiss()
    }
}
