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

    var onOpenTasks: () -> Void
    var onAddTask: () -> Void
    var onOpenSettings: () -> Void

    @State private var showTasks = true
    @State private var showTime = false
    @State private var isSearchPresented = false
    @State private var isTimePresented = false

    init(
        onOpenTasks: @escaping () -> Void,
        onAddTask: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onOpenTasks = onOpenTasks
        self.onAddTask = onAddTask
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        let digest = UsageDigest.build(
            dates: UsageDigest.heatDates(weeks: 12),
            usages: usages,
            tasks: allTasks
        )

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.cardGap) {
                topRow
                greeting
                searchField

                FoldCard(title: "今日待办", summary: "\(openTasks.count) 项", isOpen: $showTasks) {
                    taskList
                }

                FoldCard(title: "使用时间", summary: "今天 " + usageText(digest), isOpen: $showTime) {
                    usageBody(digest)
                }

                Text("轻点展开")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 18)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.bottomScrollInset)
        }
        .sheet(isPresented: $isSearchPresented) {
            SearchView()
        }
        .sheet(isPresented: $isTimePresented) {
            TimeDetailSheet()
        }
    }

    // MARK: 顶部

    private var topRow: some View {
        HStack {
            Spacer()
            Button(action: onOpenSettings) {
                ReiconIcon(icon: .moreHorizontal, size: 20.5)
                    .foregroundStyle(Theme.text)
                    .frame(width: 38, height: 38)
                    .glassCircle()
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("设置")
        }
        .padding(.top, 2)
        .padding(.bottom, 8)
    }

    private var greeting: some View {
        Text(Greeting.text)
            .font(.system(size: 27, weight: .medium))
            .tracking(-0.5)
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
            .padding(.bottom, 14)
    }

    private var searchField: some View {
        Button {
            isSearchPresented = true
        } label: {
            HStack(spacing: 9) {
                ReiconIcon(icon: .search, size: 18)
                Text("搜索")
                Spacer()
            }
            .font(.system(size: 14))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                    .fill(Theme.surface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 4)
    }

    // MARK: 待办

    private var todayTasks: [TaskItem] {
        let calendar = Calendar.current
        let todays = openTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDateInToday(due) || task.isOverdue
        }
        return Array((todays.isEmpty ? openTasks : todays).prefix(4))
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            ForEach(todayTasks) { task in
                TaskRowView(task: task, compact: true, onTap: onOpenTasks)
                    .padding(.vertical, 7)
            }

            Button(action: onAddTask) {
                HStack(spacing: 8) {
                    ReiconIcon(icon: .add, size: 14.5)
                    Text("添加待办")
                    Spacer()
                }
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 时间

    private func usageText(_ digest: UsageDigest) -> String {
        let minutes = digest.today?.minutes ?? 0
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
    }

    private func usageBody(_ digest: UsageDigest) -> some View {
        Button {
            isTimePresented = true
        } label: {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline, spacing: 0) {
                        Text("\((digest.today?.minutes ?? 0) / 60)").font(.system(size: 26, weight: .light))
                        Text("h").font(.system(size: 13)).foregroundStyle(Theme.textTertiary).padding(.horizontal, 3)
                        Text(String(format: "%02d", (digest.today?.minutes ?? 0) % 60)).font(.system(size: 26, weight: .light))
                        Text("m").font(.system(size: 13)).foregroundStyle(Theme.textTertiary).padding(.leading, 3)
                    }
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)

                    HStack(spacing: 3) {
                        ReiconIcon(icon: .arrowUpRight, size: 12)
                        Text(completionText(digest))
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 8)
                }
                Spacer(minLength: 12)
                MiniHeatmap(days: digest.days)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func completionText(_ digest: UsageDigest) -> String {
        let due = digest.lastSeven.reduce(0) { $0 + $1.due }
        let done = digest.lastSeven.reduce(0) { $0 + $1.done }
        guard due > 0 else { return "本周暂无待办" }
        return "本周完成 \(Int(Double(done) / Double(due) * 100))%"
    }
}

// MARK: - 折叠卡

struct FoldCard<Content: View>: View {
    let title: String
    let summary: String
    @Binding var isOpen: Bool
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.snappy(duration: 0.26)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    Text(summary)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                    ReiconIcon(icon: isOpen ? .chevronDown : .chevronRight, size: 14.5)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 14)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 17)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 0) {
                    content
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                .fill(Theme.surface)
        )
    }
}

// MARK: - 问候

enum Greeting {
    static var text: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let name = LocalProfile.displayName
        let emoji: String
        let words: String
        switch hour {
        case 5..<11:
            words = "早上好！"; emoji = "🥱"
        case 11..<14:
            words = "中午好！"; emoji = "🫪"
        case 14..<18:
            words = "下午好！"; emoji = "☕️"
        default:
            words = "晚上好！"; emoji = "😪"
        }
        return "\(words)\(emoji) \(name)。"
    }
}

// MARK: - 时间详情

struct TimeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TimeView(showsTitle: false)
                .background(Theme.bg)
                .navigationTitle("使用时间")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { dismiss() }
                            .foregroundStyle(Theme.text)
                    }
                }
                .tint(Theme.text)
        }
        .presentationBackground(Theme.bg)
    }
}

// MARK: - 迷你热力图

struct MiniHeatmap: View {
    let days: [UsageDigest.Day]

    private let size: CGFloat = 8
    private let gap: CGFloat = 3

    var body: some View {
        let columnCount = max(1, days.count / 7)
        HStack(alignment: .bottom, spacing: gap) {
            ForEach(0..<columnCount, id: \.self) { column in
                VStack(spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        let index = column * 7 + row
                        RoundedRectangle(cornerRadius: AppRadius.tile, style: .continuous)
                            .fill(HeatScale.color(for: index < days.count ? days[index].level : 0))
                            .frame(width: size, height: size)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
