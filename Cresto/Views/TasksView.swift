import SwiftUI
import SwiftData

struct TasksView: View {
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<TaskItem> { !$0.isCompleted && $0.deletedAt == nil },
        sort: [SortDescriptor(\TaskItem.dueDate, order: .forward)]
    )
    private var openTasks: [TaskItem]

    @Query(
        filter: #Predicate<TaskItem> { $0.isCompleted && $0.deletedAt == nil },
        sort: [SortDescriptor(\TaskItem.completedAt, order: .reverse)]
    )
    private var doneTasks: [TaskItem]

    @Query(sort: \DailyUsage.dateKey) private var usages: [DailyUsage]

    var onAdd: () -> Void = {}

    @State private var editing: TaskItem?
    @State private var isTimePresented = false
    @State private var isEditorPresented = false
    @State private var showCompleted = false

    private var grouped: [TaskGroup: [TaskItem]] {
        Dictionary(grouping: openTasks) { TaskGroup.group(for: $0.dueDate) }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.cardGap) {
                header
                timeSummary

                if openTasks.isEmpty {
                    emptyState
                }

                ForEach(TaskGroup.allCases) { group in
                    if let tasks = grouped[group], !tasks.isEmpty {
                        section(group, tasks)
                    }
                }

                completedSection
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 132)
        }
        .sheet(isPresented: $isEditorPresented, onDismiss: { editing = nil }) {
            TaskEditor(task: editing)
        }
    }

    // MARK: 页头

    private var timeSummary: some View {
        let digest = UsageDigest.build(
            dates: UsageDigest.heatDates(weeks: 12),
            usages: usages,
            tasks: openTasks + doneTasks
        )
        let minutes = digest.today?.minutes ?? 0
        let due = digest.lastSeven.reduce(0) { $0 + $1.due }
        let done = digest.lastSeven.reduce(0) { $0 + $1.done }
        let rate = due > 0 ? "\(Int(Double(done) / Double(due) * 100))%" : "—"

        return Button {
            isTimePresented = true
        } label: {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("本周").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        Text("\(minutes / 60)").font(.system(size: 26, weight: .light))
                        Text("h").font(.system(size: 12)).foregroundStyle(Theme.textTertiary).padding(.horizontal, 3)
                        Text(String(format: "%02d", minutes % 60)).font(.system(size: 26, weight: .light))
                        Text("m").font(.system(size: 12)).foregroundStyle(Theme.textTertiary).padding(.leading, 3)
                    }
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 4) {
                    Text(rate).font(.system(size: 20, weight: .light)).monospacedDigit()
                    Text("完成率").font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
                }

                MiniHeatmap(days: Array(digest.days.suffix(21)))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cardSurface()
        .sheet(isPresented: $isTimePresented) {
            TimeDetailSheet()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("共 \(openTasks.count) 项待办 · \(doneTasks.count) 项已完成")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text("待办")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .tracking(-0.5)
            }
            Spacer()
            Button(action: onAdd) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.05)))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("新建待办")
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 6)
    }

    // MARK: 分组

    private func section(_ group: TaskGroup, _ tasks: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(group.title).font(.system(size: 11.5))
                Text("\(tasks.count)").font(.system(size: 11.5)).monospacedDigit().opacity(0.6)
                Spacer()
                if group == .overdue {
                    Image(systemName: "clock.badge.exclamationmark").font(.system(size: 11))
                }
            }
            .foregroundStyle(group == .overdue ? Theme.text : Theme.textTertiary)
            .padding(.bottom, 4)

            ForEach(tasks) { task in
                TaskRowView(task: task, onTap: {
                    editing = task
                    isEditorPresented = true
                })
                if task.id != tasks.last?.id {
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                }
            }
        }
        .cardSurface()
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { showCompleted.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Text("已完成").font(.system(size: 11.5))
                    Text("\(doneTasks.count)").font(.system(size: 11.5)).monospacedDigit().opacity(0.6)
                    Spacer()
                    Image(systemName: showCompleted ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(Theme.textTertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showCompleted {
                ForEach(doneTasks.prefix(20)) { task in
                    TaskRowView(task: task, onTap: {
                        editing = task
                        isEditorPresented = true
                    })
                }
                .padding(.top, 2)
            }
        }
        .cardSurface()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("今天没有待办")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
            Text("点右下角新建一件")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .cardSurface()
    }
}

// MARK: - 行

struct TaskRowView: View {
    @Environment(\.modelContext) private var context

    let task: TaskItem
    var compact = false
    var onTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 11) {
            Button {
                withAnimation(.snappy(duration: 0.22)) {
                    TaskActions.toggle(task, in: context)
                }
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(task.isCompleted ? Color.clear : Color.white.opacity(0.26), lineWidth: 1.5)
                    if task.isCompleted {
                        Circle().fill(Theme.ink)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.bg)
                    }
                }
                .frame(width: 19, height: 19)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isCompleted ? "标记为未完成" : "标记为完成")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.system(size: 14))
                    .foregroundStyle(task.isCompleted ? Theme.textTertiary : Theme.text)
                    .strikethrough(task.isCompleted, color: Theme.textTertiary)
                    .lineLimit(2)

                if !compact {
                    HStack(spacing: 8) {
                        if let due = task.dueDate {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar").font(.system(size: 9))
                                Text(due.taskLabel(hasTime: task.hasTime))
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(task.isOverdue ? Theme.text : Theme.textTertiary)
                        }

                        if !task.subtasks.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "checklist").font(.system(size: 9))
                                Text("\(task.doneSubtaskCount)/\(task.subtasks.count)")
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                        }

                        ForEach(task.tags.prefix(2), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1)
                                .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
                        }
                    }
                }
            }

            Spacer(minLength: 8)

            if let due = task.dueDate, !task.isCompleted {
                Text(due.taskLabel(hasTime: task.hasTime))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(task.isOverdue ? Theme.text : Theme.textTertiary)
            }

            if task.priority == .high {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .contextMenu {
            Button {
                withAnimation { TaskActions.toggle(task, in: context) }
            } label: {
                Label(task.isCompleted ? "标记为未完成" : "标记为完成", systemImage: task.isCompleted ? "arrow.uturn.backward" : "checkmark")
            }
            if let onTap {
                Button { onTap() } label: { Label("编辑", systemImage: "square.and.pencil") }
            }
            Button(role: .destructive) {
                TaskActions.delete(task, in: context)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }
}
