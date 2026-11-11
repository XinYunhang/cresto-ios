import SwiftUI
import SwiftData

struct OverviewView: View {
    @Environment(\.modelContext) private var context

    @Query(
        filter: #Predicate<TaskItem> { !$0.isCompleted && $0.deletedAt == nil },
        sort: [SortDescriptor(\TaskItem.dueDate, order: .forward)]
    )
    private var openTasks: [TaskItem]

    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @Query(sort: \DailyUsage.dateKey) private var usages: [DailyUsage]

    let draw: DailyTarot?
    var onOpenTarot: () -> Void
    var onOpenTime: () -> Void
    var onOpenTasks: () -> Void = {}

    @State private var editing: TaskItem?
    @State private var isEditorPresented = false
    @State private var isNewTask = false

    init(
        draw: DailyTarot?,
        onOpenTarot: @escaping () -> Void,
        onOpenTime: @escaping () -> Void,
        onOpenTasks: @escaping () -> Void = {}
    ) {
        self.draw = draw
        self.onOpenTarot = onOpenTarot
        self.onOpenTime = onOpenTime
        self.onOpenTasks = onOpenTasks
    }

    private var fortune: FortuneSnapshot { FortuneEngine.snapshot() }

    private var usageMap: [String: DailyUsage] {
        Dictionary(usages.map { ($0.dateKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var todayMinutes: Int { usageMap[UsageStore.todayKey]?.minutes ?? 0 }

    private var yesterdayMinutes: Int {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
        return usageMap[UsageStore.key(for: yesterday)]?.minutes ?? 0
    }

    /// 近 12 周（84 天），列优先：每列一周
    private var usageCells: [UsageStats.Cell] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let start = calendar.date(byAdding: .day, value: -77, to: weekStart) else { return [] }
        return (0..<84).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return UsageStats.cell(for: day, usages: usageMap, tasks: allTasks)
        }
    }

    private var todayTasks: [TaskItem] {
        let calendar = Calendar.current
        let todays = openTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDateInToday(due) || task.isOverdue
        }
        return Array((todays.isEmpty ? openTasks : todays).prefix(3))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.cardGap) {
                header
                FortuneCard(fortune: fortune)
                TodayTasksCard(
                    tasks: todayTasks,
                    totalOpen: openTasks.count,
                    onAdd: {
                        editing = nil
                        isNewTask = true
                        isEditorPresented = true
                    },
                    onSelect: { task in
                        editing = task
                        isNewTask = false
                        isEditorPresented = true
                    },
                    onOpenAll: onOpenTasks
                )
                TarotMiniCard(draw: draw, action: onOpenTarot)
                UsageCard(
                    todayMinutes: todayMinutes,
                    yesterdayMinutes: yesterdayMinutes,
                    cells: usageCells,
                    action: onOpenTime
                )
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 2)
            .padding(.bottom, 132)
        }
        .sheet(isPresented: $isEditorPresented, onDismiss: { editing = nil }) {
            if isNewTask {
                TaskEditor()
            } else {
                TaskEditor(task: editing)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text(Date().formatted(.dateTime.month().day().weekday(.abbreviated)))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text(greeting)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .tracking(-0.5)
            }

            Spacer(minLength: 12)

            HStack(spacing: 9) {
                Button {
                    // 之后接 dsh 远程：跳转到终端页
                } label: {
                    Image(systemName: "terminal")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.text)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.white.opacity(0.05)))
                        .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                        .overlay(alignment: .topTrailing) {
                            Circle()
                                .fill(Theme.online)
                                .frame(width: 5, height: 5)
                                .overlay(Circle().strokeBorder(Theme.bg, lineWidth: 2))
                                .padding(6)
                        }
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("DSH 远程连接")

                Text("N")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.07)))
                    .overlay(Circle().strokeBorder(Theme.stroke, lineWidth: 1))
                    .accessibilityHidden(true)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 6)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return "早上好"
        case 11..<14: return "中午好"
        case 14..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "还没睡？"
        }
    }
}

// MARK: - 今日运势

struct FortuneCard: View {
    let fortune: FortuneSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("今日运势").cardLabel()
                Spacer()
                HStack(spacing: 1) {
                    Text("详情")
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
            }
            .padding(.bottom, 11)

            HStack(alignment: .lastTextBaseline, spacing: 14) {
                HStack(alignment: .lastTextBaseline, spacing: 4) {
                    Text("\(fortune.score)")
                        .font(.system(size: 46, weight: .light))
                        .tracking(-2)
                        .foregroundStyle(Theme.text)
                    Text("分")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(fortune.headline)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text)
                    (
                        Text("宜 ").foregroundColor(Theme.textTertiary)
                        + Text(fortune.goodAt).foregroundColor(Theme.textSecondary)
                        + Text(" · 忌 ").foregroundColor(Theme.textTertiary)
                        + Text(fortune.avoid).foregroundColor(Theme.textSecondary)
                    )
                    .font(.system(size: 12))
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                ForEach(fortune.keywords, id: \.self) { keyword in
                    AccentChip(text: keyword)
                }
            }
            .padding(.top, 11)

            HStack(alignment: .top, spacing: 10) {
                ForEach(fortune.metrics) { metric in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(metric.label)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.textTertiary)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.09))
                                Capsule()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color.white.opacity(0.45), Theme.ink],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(0, geo.size.width * metric.value))
                            }
                        }
                        .frame(height: 3)
                    }
                }
            }
            .padding(.top, 13)
        }
        .cardSurface()
    }
}

// MARK: - 今日待办

struct TodayTasksCard: View {
    let tasks: [TaskItem]
    let totalOpen: Int
    var onAdd: () -> Void
    var onSelect: (TaskItem) -> Void
    var onOpenAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onOpenAll) {
                HStack {
                    Text("今日待办").cardLabel()
                    Spacer()
                    Text("\(totalOpen) 项")
                        .font(.system(size: 11.5))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)

            if tasks.isEmpty {
                Text("今天空着，挺好")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.vertical, 12)
            } else {
                ForEach(tasks) { task in
                    TaskRowView(task: task, compact: true, onTap: { onSelect(task) })
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)
                .padding(.top, 3)

            Button(action: onAdd) {
                HStack(spacing: 8) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                    Text("添加待办")
                    Spacer()
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .cardSurface()
    }
}

// MARK: - 今日塔罗（摘要）

struct TarotMiniCard: View {
    let draw: DailyTarot?
    var action: () -> Void

    private var card: TarotCard? { draw?.card }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 13) {
                CardArt(name: card?.slug ?? "00-fool")
                    .frame(width: 44, height: 62)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.7), radius: 10, y: 5)

                VStack(alignment: .leading, spacing: 0) {
                    Text(card == nil ? "今日塔罗 · 还没抽" : "今日塔罗 · " + (card?.positionText(reversed: draw?.isReversed ?? false) ?? ""))
                        .cardLabel()
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(card?.name ?? "抽一张")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.text)
                        if let card {
                            Text(card.en)
                                .font(.system(size: 11, design: .serif))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(.top, 5)

                    HStack(spacing: 5) {
                        ForEach(card?.keywords(reversed: draw?.isReversed ?? false) ?? ["每日一抽"], id: \.self) { keyword in
                            AccentChip(text: keyword, small: true)
                        }
                    }
                    .padding(.top, 7)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .cardSurface(padding: 0)
    }
}

// MARK: - 使用时间（摘要）

struct UsageCard: View {
    let todayMinutes: Int
    let yesterdayMinutes: Int
    let cells: [UsageStats.Cell]
    var action: () -> Void

    private var deltaText: String {
        guard yesterdayMinutes > 0 else {
            return todayMinutes > 0 ? "今天刚开始" : "还没有记录"
        }
        let diff = todayMinutes - yesterdayMinutes
        if diff == 0 { return "和昨天持平" }
        return diff > 0 ? "比昨天多 \(diff) 分钟" : "比昨天少 \(-diff) 分钟"
    }

    private var isUp: Bool { todayMinutes >= yesterdayMinutes }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("使用时间").cardLabel()
                    Spacer()
                    Text("近 12 周")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.bottom, 11)

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .lastTextBaseline, spacing: 0) {
                            Text("\(todayMinutes / 60)").font(.system(size: 28, weight: .light))
                            Text("h").font(.system(size: 13)).foregroundStyle(Theme.textTertiary).padding(.horizontal, 3)
                            Text(String(format: "%02d", todayMinutes % 60)).font(.system(size: 28, weight: .light))
                            Text("m").font(.system(size: 13)).foregroundStyle(Theme.textTertiary).padding(.leading, 3)
                        }
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)

                        HStack(spacing: 3) {
                            Image(systemName: isUp ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 10, weight: .semibold))
                            Text(deltaText)
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 8)
                    }

                    Spacer(minLength: 12)

                    MiniHeatmap(cells: cells)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .cardSurface()
    }
}

struct MiniHeatmap: View {
    let cells: [UsageStats.Cell]

    private let size: CGFloat = 8
    private let gap: CGFloat = 3

    var body: some View {
        let columnCount = max(1, cells.count / 7)
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(0..<columnCount, id: \.self) { column in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        let index = column * 7 + row
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(HeatScale.color(for: index < cells.count ? cells[index].level : 0))
                            .frame(width: size, height: size)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
