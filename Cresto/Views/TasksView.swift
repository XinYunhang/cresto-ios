import SwiftUI
import SwiftData
import UIKit

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
    /// 当前元数据堆叠展开的行（互斥：切行时前一行收、新一行同时展）
    @State private var expandedMetaID: UUID?

    private var grouped: [TaskGroup: [TaskItem]] {
        Dictionary(grouping: openTasks) { TaskGroup.group(for: $0.dueDate) }
    }

    /// 严格「当日」口径：只看「到期日 = 今天」的待办（含已完成），逾期/以后一律不计。
    /// 分子也按到期日分组——今天完成的逾期任务不会虚增当日进度。
    private var todayProgress: (done: Int, total: Int) {
        let openToday = openTasks.filter { TaskGroup.group(for: $0.dueDate) == .today }.count
        let doneToday = doneTasks.filter { TaskGroup.group(for: $0.dueDate) == .today }.count
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

                // 阅读卡片：列表最底部（悬浮 FAB 与底部胶囊上方安全区内）
                ReadingCardView()
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.bottomScrollInset)
            .frame(maxWidth: .infinity)
            .clipped()
            .simultaneousGesture(TapGesture().onEnded {
                // 点任意空白/其他行处收起左滑删除块与元数据堆叠（simultaneous，不影响行内按钮）
                if swipedID != nil { swipedID = nil }
                if expandedMetaID != nil { expandedMetaID = nil }
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
                    expandedMetaID: $expandedMetaID,
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
                        expandedMetaID: $expandedMetaID,
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

/// 待办行卡：自带圆角卡底（AppRadius.item），左滑在行卡右侧露出**独立的圆角红色删除块**
/// （trash + 删除，居中在块内）——块不垫在全尺寸底板上，只按露出进度渐显，
/// 行卡合拢时完全不画，杜绝边缘透红与列表刷新时的红色闪现。
/// 手势：水平位移明显大于垂直才接管（不卡滚动）；同一时间只展开一条（外部 swipedID 管）；
/// 已展开状态下再往左滑一段 = 直接删除；点红色块 = 删除。
private struct SwipeableTaskRow: View {
    let task: TaskItem
    @Binding var swipedID: UUID?
    @Binding var expandedMetaID: UUID?
    let onTap: () -> Void
    let onDelete: () -> Void

    @State private var dragging = false
    @State private var dragBase: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0

    private let revealWidth: CGFloat = 76
    private let expandThreshold: CGFloat = 44
    /// 已展开时，再往左滑超过这个距离就触发删除
    private let secondSwipeDelete: CGFloat = 28

    private var isSwiped: Bool { swipedID == task.id }

    private var offset: CGFloat {
        if dragging {
            return min(0, max(-revealWidth * 1.4, dragBase + dragTranslation))
        }
        return isSwiped ? -revealWidth : 0
    }

    /// 删除块的渐显进度：合拢时 0（完全不画），完全露出时 1
    private var revealProgress: CGFloat {
        min(1, max(0, -offset / revealWidth))
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
                .frame(width: revealWidth)
                .frame(maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                        .fill(Color.red)
                )
            }
            .buttonStyle(.plain)
            .opacity(revealProgress)
            .allowsHitTesting(isSwiped)

            TaskRowView(task: task, expandedMetaID: $expandedMetaID, onTap: onTap)
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
        .frame(maxWidth: .infinity)
        .clipped()
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
                if isSwiped && projected <= -(revealWidth + secondSwipeDelete) {
                    // 已展开，第二次左滑 → 直接删除
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy(duration: 0.25)) { onDelete() }
                } else if projected < -expandThreshold {
                    swipedID = task.id
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } else if isSwiped {
                    swipedID = nil
                }
                dragTranslation = 0
            }
    }
}

// MARK: - 行内容

/// 行的可见内容（勾选框 + 标题 + 元数据堆叠）。首页 OverviewView 的 compact 行也用它
/// （compact 不带堆叠元数据，保持首页卡内轻量）。
/// 卡底、左滑手势与删除块由 SwipeableTaskRow 包一层，这里保持透明可复用。
struct TaskRowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let task: TaskItem
    var compact = false
    /// 互斥展开（spec：只有当前行展开，切行时前一行收、新一行同时展）；首页 compact 行为 nil
    var expandedMetaID: Binding<UUID?>? = nil
    var onTap: (() -> Void)?

    private var isMetaExpanded: Bool { expandedMetaID?.wrappedValue == task.id }

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
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

            HStack(alignment: .center, spacing: 8) {
                // 标题：tail 截断、布局优先级低于右侧元数据——元数据展开只压缩标题，绝不反推整屏宽度
                Text(task.title)
                    .font(.system(size: 14))
                    .foregroundStyle(task.isCompleted ? Theme.textTertiary : Theme.text)
                    .strikethrough(task.isCompleted, color: Theme.textTertiary)
                    .lineLimit(compact ? 2 : 1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(0)

                if !compact {
                    MetaStack(
                        chips: metaChips,
                        isExpanded: isMetaExpanded,
                        reduceMotion: reduceMotion,
                        onToggle: {
                            expandedMetaID?.wrappedValue = (expandedMetaID?.wrappedValue == task.id) ? nil : task.id
                        }
                    )
                    .layoutPriority(1)
                }
            }

            if compact, let due = task.dueDate, !task.isCompleted {
                Spacer(minLength: 8)
                Text(due.taskLabel(hasTime: task.hasTime))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundStyle(task.isOverdue ? Theme.text : Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
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

    // MARK: stacked-metadata

    /// 元数据胶囊：紧急程度 / 日期 / 提醒 / 重复 / 子任务 / 标签
    private var metaChips: [MetaChipData] {
        var chips: [MetaChipData] = []
        if let due = task.dueDate {
            chips.append(MetaChipData(icon: "calendar", text: due.taskLabel(hasTime: task.hasTime)))
        }
        for tag in task.tags.prefix(1) {
            chips.append(MetaChipData(icon: "tag", text: tag))
        }
        if task.reminder != .none {
            chips.append(MetaChipData(icon: "bell", text: task.reminder.title))
        }
        if task.repeatKind != .none {
            chips.append(MetaChipData(icon: "arrow.triangle.2.circlepath", text: task.repeatKind.title))
        }
        if !task.subtasks.isEmpty {
            chips.append(MetaChipData(icon: "checklist", text: "\(task.doneSubtaskCount)/\(task.subtasks.count)"))
        }

        // 紧急度固定贴最右（叠放最上层、收起时不被其他胶囊盖住），并保证进前三不被截断
        if task.urgency != .mild {
            if chips.count >= 3 {
                chips = Array(chips.prefix(2))
            }
            chips.append(MetaChipData(
                icon: task.urgency.symbol,
                text: task.urgency.title,
                urgency: task.urgency
            ))
        } else if chips.count > 3 {
            chips = Array(chips.prefix(3))
        }
        return chips
    }
}

// MARK: - 元数据堆叠（stacked-metadata 复刻）

struct MetaChipData: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
    /// 非 nil = 发光圆点紧急度标签（收起只露圆点，展开显示 ● 档位）
    var urgency: TaskUrgency? = nil
}

/// stacked-metadata 复刻（v8.2 性能修订）：三枚胶囊右锚叠放，展开时 offset 回 0 铺开。
/// 收起/展开只改 transform（offset 叠入 ≤60pt，行容器已 clipped 不会外溢），
/// 间距与尺寸恒定、文字 fixedSize——零布局重排；互斥由外部 expandedMetaID 管理。
private struct MetaStack: View {
    let chips: [MetaChipData]
    let isExpanded: Bool
    let reduceMotion: Bool
    let onToggle: () -> Void

    private var spring: Animation {
        .spring(response: 0.34, dampingFraction: 0.84)
    }

    var body: some View {
        Button(action: onToggle) {
            // 展开/收起只做 transform 偏移（GPU 合成），不改间距/宽度——
            // 不触发文字重排与整行 relayout，点击展开不再卡顿
            HStack(spacing: 4) {
                let visible = Array(chips.prefix(3))
                ForEach(visible.indices, id: \.self) { index in
                    chipView(visible[index])
                        .offset(x: CGFloat(2 - index) * 30 * (isExpanded ? 0 : 1))
                }
            }
            .animation(reduceMotion ? nil : spring, value: isExpanded)
        }
        .buttonStyle(.plain)
        .disabled(chips.isEmpty)
        .opacity(chips.isEmpty ? 0 : 1)
        .accessibilityValue(isExpanded ? "已展开" : "已收起")
    }

    @ViewBuilder
    private func chipView(_ chip: MetaChipData) -> some View {
        if let urgency = chip.urgency {
            MetaUrgencyChip(tier: urgency, isExpanded: isExpanded, reduceMotion: reduceMotion)
        } else {
            MetaChipInline(chip: chip)
        }
    }
}

/// 紧急度标签：尺寸与普通标签完全一致（26pt 胶囊、同内边距）。
/// 收起 = 磨砂玻璃底 + 档位色透出 + 圆点柔光 + 文字虚化成一片色晕（透过模糊玻璃的观感）；
/// 展开 = 清晰「● 档位」胶囊。全程固定尺寸，不做宽度/布局动画，点击零重排。
private struct MetaUrgencyChip: View {
    let tier: TaskUrgency
    let isExpanded: Bool
    let reduceMotion: Bool

    private var textWidth: CGFloat {
        let font = UIFont.systemFont(ofSize: 10.5, weight: .medium)
        return ((tier.title as NSString).size(withAttributes: [.font: font]).width).rounded(.up) + 1
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(tier.tint)
                .frame(width: 9, height: 9)
                .shadow(color: tier.tint.opacity(0.85), radius: 4)

            Text(tier.title)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(tier.tint)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: textWidth, alignment: .leading)
                .clipped()
                .blur(radius: isExpanded ? 0 : 3.5)
                .opacity(isExpanded ? 1 : 0.5)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(
            ZStack {
                Capsule().fill(.ultraThinMaterial)                       // 磨砂玻璃
                Capsule().fill(tier.tint.opacity(isExpanded ? 0.14 : 0.30)) // 收起时颜色更透
            }
        )
        .overlay(Capsule().strokeBorder(tier.tint.opacity(0.38), lineWidth: 1))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isExpanded)
        .accessibilityLabel("紧急程度 \(tier.title)")
    }
}

/// 单枚元数据胶囊（spec 小屏当量：9px 水平内边距、4px 图标间距、3px 同场景背景色描边=重叠分界）
private struct MetaChipInline: View {
    let chip: MetaChipData

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: chip.icon)
                .font(.system(size: 10, weight: .medium))
            Text(chip.text)
                .font(.system(size: 10.5))
                .fixedSize(horizontal: true, vertical: false)
                .lineLimit(1)
        }
        .foregroundStyle(Theme.textTertiary)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(Capsule().fill(Theme.surfaceRaised))
        .overlay(Capsule().strokeBorder(Theme.surface, lineWidth: 3))
        .fixedSize()
    }
}

// MARK: - 流式布局

/// 简单流式布局：胶囊逐个排，放不下换行（iOS 17 Layout 协议）
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
