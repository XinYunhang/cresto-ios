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

    var onAdd: () -> Void = {}

    @State private var editing: TaskItem?
    @State private var isEditorPresented = false
    @State private var showCompleted = false
    /// 当前左滑展开的行（同一时间最多一条）
    @State private var swipedID: UUID?

    private var grouped: [TaskGroup: [TaskItem]] {
        Dictionary(grouping: openTasks) { TaskGroup.group(for: $0.dueDate) }
    }

    /// 严格「当日」口径：分母 = 今天到期未完成 + 今天完成的，逾期/以后不计入
    private var todayProgress: (done: Int, total: Int) {
        let openToday = openTasks.filter { TaskGroup.group(for: $0.dueDate) == .today }.count
        let calendar = Calendar.current
        let doneToday = doneTasks.filter { task in
            guard let completedAt = task.completedAt else { return false }
            return calendar.isDateInToday(completedAt)
        }.count
        return (doneToday, doneToday + openToday)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.cardGap) {
                header

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
            .simultaneousGesture(TapGesture().onEnded {
                // 点任意空白/其他行处收起左滑删除块（simultaneous，不影响行内按钮）
                if swipedID != nil { swipedID = nil }
            })
        }
        .floatingAddButton("新建待办") {
            onAdd()
        }
        .sheet(isPresented: $isEditorPresented, onDismiss: { editing = nil }) {
            TaskEditor(task: editing)
        }
    }

    // MARK: 页头（标题 + 镂空进度环）

    private var header: some View {
        HStack(alignment: .center) {
            Text("待办")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.text)
                .tracking(-0.5)
            Spacer()
            TodayProgressRing(done: todayProgress.done, total: todayProgress.total)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    // MARK: 分组

    private func section(_ group: TaskGroup, _ tasks: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(group.title).font(.system(size: 11.5))
                Text("\(tasks.count)").font(.system(size: 11.5)).monospacedDigit().opacity(0.6)
                Spacer()
                if group == .overdue {
                    Image(systemName: "clock.badge.exclamationmark").font(.system(size: 11))
                }
            }
            .foregroundStyle(group == .overdue ? Theme.text : Theme.textTertiary)
            .padding(.top, 2)

            ForEach(tasks) { task in
                SwipeableTaskRow(
                    task: task,
                    swipedID: $swipedID,
                    onTap: {
                        editing = task
                        isEditorPresented = true
                    },
                    onDelete: { delete(task) }
                )
            }
        }
    }

    private var completedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    SwipeableTaskRow(
                        task: task,
                        swipedID: $swipedID,
                        onTap: {
                            editing = task
                            isEditorPresented = true
                        },
                        onDelete: { delete(task) }
                    )
                }
                .transition(.opacity)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("今天没有待办")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textSecondary)
            Text("点击右下角添加一件")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .cardSurface()
    }

    private func delete(_ task: TaskItem) {
        withAnimation(.snappy(duration: 0.25)) {
            TaskActions.delete(task, in: context)
            swipedID = nil
        }
    }
}

// MARK: - 镂空进度环 + 长按模糊浮层

/// 右上角镂空进度环：直径 30pt、线宽 3.25pt、圆角端点，
/// 弧线从 12 点方向顺时针填充今日完成进度；总数为 0 时进度强制 0（除零保护）。
/// 长按弹出左侧胶囊浮层（动态模糊渐显），松手停留 3 秒后模糊渐隐；
/// 3 秒内再次长按会取消上一次的延时任务，浮层不会提前消失。
struct TodayProgressRing: View {
    let done: Int
    let total: Int

    @State private var isDetailShown = false
    @State private var dismissTask: Task<Void, Never>?

    private var progress: Double {
        guard total > 0 else { return 0.0 }
        return Double(done) / Double(total)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.12), lineWidth: 3.25)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Theme.text, style: StrokeStyle(lineWidth: 3.25, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring, value: progress)
        }
        .frame(width: 30, height: 30)
        .overlay(alignment: .trailing) {
            detailPopup
                .fixedSize()
                .padding(.trailing, 38) // 圆环正左侧留 8pt
                .allowsHitTesting(false)
        }
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 0.25, pressing: pressing, perform: {})
        .onDisappear { dismissTask?.cancel() }
        .accessibilityLabel("今日进度：已完成 \(done)，共 \(total)")
    }

    /// 轻量胶囊浮层：ultraThinMaterial 底 + blur 8→0 渐显、轻微横移弹簧入场
    private var detailPopup: some View {
        Text("已完成 \(done) / \(total)")
            .font(.system(size: 12, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Capsule().fill(.ultraThinMaterial))
            .blur(radius: isDetailShown ? 0 : 8)
            .opacity(isDetailShown ? 1 : 0)
            .offset(x: isDetailShown ? 0 : 8)
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isDetailShown)
    }

    private func pressing(_ isPressing: Bool) {
        if isPressing {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // 防抖：取消上一次的消失延时
            dismissTask?.cancel()
            dismissTask = nil
            isDetailShown = true
        } else {
            // 松手：停留 3 秒后模糊消散
            dismissTask?.cancel()
            dismissTask = Task {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                isDetailShown = false
            }
        }
    }
}

// MARK: - 行卡 + 左滑删除

/// 待办行卡：自带圆角卡底（AppRadius.item），左滑露出纯红删除块——
/// 高度与圆弧角与行卡严格一致（同一 ZStack 内同 shape，无缝贴合）。
/// 只有水平位移明显大于垂直位移时才接管手势，不卡上下滚动；
/// 展开状态由外部 `swipedID` 统一管理，同一时间最多一条。
private struct SwipeableTaskRow: View {
    let task: TaskItem
    @Binding var swipedID: UUID?
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var dragging = false
    @State private var dragBase: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0

    private let revealWidth: CGFloat = 76
    private let expandThreshold: CGFloat = 44

    private var isSwiped: Bool { swipedID == task.id }

    private var offset: CGFloat {
        if dragging {
            return min(0, max(-revealWidth * 1.4, dragBase + dragTranslation))
        }
        return isSwiped ? -revealWidth : 0
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.snappy(duration: 0.25)) { onDelete() }
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 15, weight: .medium))
                    Text("删除")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .fill(Color.red)
                )
            }
            .buttonStyle(.plain)
            .allowsHitTesting(isSwiped)

            TaskRowView(task: task, onTap: onTap)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .fill(Theme.surface)
                )
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous))
                .offset(x: offset)
                .gesture(dragGesture)
        }
        .animation(dragging ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: offset)
        .onChange(of: isSwiped) { _, swiped in
            if !swiped { dragTranslation = 0 }
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    // 纵向主导：放弃本次拖拽，让给滚动
                    if dragging {
                        dragging = false
                        dragTranslation = 0
                    }
                    return
                }
                if !dragging {
                    dragging = true
                    dragBase = isSwiped ? -revealWidth : 0
                }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                guard dragging else { return }
                dragging = false
                let projected = min(0, dragBase + value.translation.width)
                if projected < -expandThreshold {
                    swipedID = task.id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else if isSwiped {
                    swipedID = nil
                }
                dragTranslation = 0
            }
    }
}
