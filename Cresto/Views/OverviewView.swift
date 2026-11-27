import SwiftUI
import SwiftData
import UIKit

private struct HomeCountdownEditorContext: Identifiable {
    let id = UUID()
    let item: CountdownItem?
}

struct OverviewView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    @Query(
        filter: #Predicate<TaskItem> { !$0.isCompleted && $0.deletedAt == nil },
        sort: [SortDescriptor(\TaskItem.dueDate, order: .forward)]
    )
    private var openTasks: [TaskItem]

    @Query(sort: \TaskItem.createdAt) private var allTasks: [TaskItem]
    @Query(sort: \DailyUsage.dateKey) private var usages: [DailyUsage]
    @Query private var courses: [Course]
    @Query private var timetableSettings: [TimetableSettings]
    @Query(sort: \Subscription.createdAt) private var subscriptions: [Subscription]
    @Query(sort: \CountdownItem.targetDate) private var countdowns: [CountdownItem]

    @AppStorage("usdToCny") private var usdToCny = 7.25
    @AppStorage("jpyToCny") private var jpyToCny = 0.048

    var onOpenTasks: () -> Void
    var onOpenCourse: () -> Void = {}
    var onOpenSubscriptions: () -> Void = {}
    var onAddTask: () -> Void
    var onOpenSettings: () -> Void

    @State private var isSearchPresented = false
    @State private var isTimePresented = false
    @State private var countdownEditorContext: HomeCountdownEditorContext?
    @State private var now = Date()

    private let ticker = Timer.publish(every: 60, on: .main, in: .common).autoconnect()
    private let bentoHeight: CGFloat = 214

    init(
        onOpenTasks: @escaping () -> Void,
        onOpenCourse: @escaping () -> Void = {},
        onOpenSubscriptions: @escaping () -> Void = {},
        onAddTask: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void
    ) {
        self.onOpenTasks = onOpenTasks
        self.onOpenCourse = onOpenCourse
        self.onOpenSubscriptions = onOpenSubscriptions
        self.onAddTask = onAddTask
        self.onOpenSettings = onOpenSettings
    }

    var body: some View {
        let digest = UsageDigest.build(
            dates: UsageDigest.heatDates(weeks: 12),
            usages: usages,
            tasks: allTasks
        )

        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.cardGap) {
                header
                searchField
                bentoGrid(digest: digest)
                ReadingCardView(compact: true)
                todayFocusCard
                if let urgentSub = imminentSubscription {
                    imminentSubBanner(urgentSub.sub, days: urgentSub.days)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.bottomScrollInset)
        }
        .onReceive(ticker) { _ in
            guard scenePhase == .active else { return }
            now = Date()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = Date() }
        }
        .sheet(isPresented: $isSearchPresented) {
            SearchView()
        }
        .sheet(isPresented: $isTimePresented) {
            TimeDetailSheet()
        }
        .sheet(item: $countdownEditorContext) { ctx in
            CountdownEditor(item: ctx.item)
        }
        // 首页右下角 BLOUD 小黑球（与课表/待办 FAB 同锚点，52pt / 右 20 / 底 80）
        .overlay(alignment: .bottomTrailing) {
            BloudBallView()
                .padding(.trailing, FloatingAnchor.trailing)
                .padding(.bottom, FloatingAnchor.bottom)
        }
    }

    // MARK: 顶部标题（日期眉标 + 衬线体哲思句，拉开层级感）

    private var todayEyebrow: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 · EEEE"
        return formatter.string(from: now)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(todayEyebrow)
                    .font(.system(size: 11, weight: .medium))
                    .tracking(1.0)
                    .foregroundStyle(Theme.textTertiary)
                Text("人，是会思考的芦苇")
                    .font(.system(size: 22, weight: .semibold, design: .serif))
                    .tracking(0.8)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.80)
            }

            Spacer(minLength: 6)

            Button(action: onOpenSettings) {
                ReiconIcon(icon: .moreHorizontal, size: 20.5)
                    .foregroundStyle(Theme.text)
                    .frame(width: 38, height: 38)
                    .glassCircle()
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("设置")
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private var searchField: some View {
        Button {
            isSearchPresented = true
        } label: {
            HStack(spacing: 9) {
                ReiconIcon(icon: .search, size: 18)
                Text("搜索待办与课程")
                Spacer()
            }
            .font(.system(size: 14))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .cardElevation(radius: AppRadius.item)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, 2)
    }

    // MARK: Bento 驾驶舱网格

    private func bentoGrid(digest: UsageDigest) -> some View {
        HStack(alignment: .top, spacing: Theme.cardGap) {
            courseHeroCard
                .frame(maxWidth: .infinity)
                .frame(height: bentoHeight)

            VStack(spacing: Theme.cardGap) {
                countdownCard
                    .frame(maxWidth: .infinity)
                    .frame(height: (bentoHeight - Theme.cardGap) / 2)

                activityMiniCard(digest: digest)
                    .frame(maxWidth: .infinity)
                    .frame(height: (bentoHeight - Theme.cardGap) / 2)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: 左上 2×2 · 今日/明日课表概览（已移除固定上下课时刻与实时状态）

    private struct CourseOverviewSnapshot {
        let pillTitle: String
        let primaryCourse: Course
        let primarySlot: CourseSlot
        let locationText: String
        let secondaryHint: String?
    }

    private var courseOverview: CourseOverviewSnapshot? {
        guard !courses.isEmpty else { return nil }
        let calendar = Calendar.current
        let settings = timetableSettings.first ?? TimetableSettings()
        let todayWeek = settings.weekNumber(for: now)
        let weekdayComp = calendar.component(.weekday, from: now)
        let todayWeekday = ((weekdayComp + 5) % 7) + 1

        func activeOn(week: Int, weekday: Int) -> [(course: Course, slot: CourseSlot)] {
            var list: [(course: Course, slot: CourseSlot)] = []
            for course in courses {
                for slot in course.slots where slot.weekday == weekday && slot.isActive(inWeek: week) {
                    list.append((course, slot))
                }
            }
            list.sort { $0.slot.startPeriod < $1.slot.startPeriod }
            return list
        }

        let todaySlots = activeOn(week: todayWeek, weekday: todayWeekday)
        if let first = todaySlots.first {
            let locRaw = first.slot.location.isEmpty ? first.course.location : first.slot.location
            let loc = locRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            let hint = todaySlots.count > 1 ? "还有 \(todaySlots.count - 1) 门课" : nil
            return CourseOverviewSnapshot(
                pillTitle: "今日课表 · \(todaySlots.count) 节",
                primaryCourse: first.course,
                primarySlot: first.slot,
                locationText: loc.isEmpty ? "教室待定" : loc,
                secondaryHint: hint
            )
        }

        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
            let tomorrowWeek = settings.weekNumber(for: tomorrow)
            let tomorrowWeekday = (todayWeekday % 7) + 1
            let tomorrowSlots = activeOn(week: tomorrowWeek, weekday: tomorrowWeekday)
            if let first = tomorrowSlots.first {
                let locRaw = first.slot.location.isEmpty ? first.course.location : first.slot.location
                let loc = locRaw.trimmingCharacters(in: .whitespacesAndNewlines)
                let hint = tomorrowSlots.count > 1 ? "明日共 \(tomorrowSlots.count) 门" : nil
                return CourseOverviewSnapshot(
                    pillTitle: "明日首节",
                    primaryCourse: first.course,
                    primarySlot: first.slot,
                    locationText: loc.isEmpty ? "教室待定" : loc,
                    secondaryHint: hint
                )
            }
        }

        return nil
    }

    private var courseHeroCard: some View {
        let overview = courseOverview

        return Button(action: onOpenCourse) {
            if let overview {
                let tone = Theme.courseTone(overview.primaryCourse.shade)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(tone.fg)
                            .frame(width: 5, height: 5)
                        Text(overview.pillTitle)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(tone.fg)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(tone.bg))

                    Spacer(minLength: 8)

                    Text(overview.primaryCourse.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(overview.locationText)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .padding(.top, 5)

                    Spacer(minLength: 10)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("第 \(overview.primarySlot.startPeriod)-\(overview.primarySlot.endPeriod) 节")
                            Spacer()
                            if let hint = overview.secondaryHint {
                                Text(hint)
                            }
                        }
                        .font(.system(size: 11, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)

                        Capsule()
                            .fill(tone.bg)
                            .frame(height: 4)
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tone.bg.opacity(0.42), Theme.surface.opacity(0)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .cardElevation(radius: AppRadius.card)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        ReiconIcon(icon: .calendarDays, size: 17)
                            .foregroundStyle(Theme.brand)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Theme.brandSoft))
                        Spacer()
                    }

                    Spacer(minLength: 8)

                    Text(courses.isEmpty ? "暂无课表" : "今明两天无课")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)

                    Text(courses.isEmpty ? "导入或添加课程" : "轻点查看整周安排")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 4)

                    Spacer(minLength: 8)

                    HStack(spacing: 4) {
                        Text("查看课表")
                        ReiconIcon(icon: .chevronRight, size: 11)
                    }
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(Theme.brand)
                }
                .padding(15)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .cardElevation(radius: AppRadius.card)
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: 右上 1×1 · 自定义多倒数日预览（绝不默认放假）

    private var nearestCountdown: CountdownItem? {
        if let pinned = countdowns.first(where: { $0.isPinnedToHome }) {
            return pinned
        }
        if let upcoming = countdowns.first(where: { $0.daysRemaining(from: now) >= 0 }) {
            return upcoming
        }
        return countdowns.last
    }

    private var countdownCard: some View {
        let item = nearestCountdown

        return Button {
            countdownEditorContext = HomeCountdownEditorContext(item: item)
        } label: {
            if let item {
                let days = item.daysRemaining(from: now)
                let unitText = days > 0 ? "天后" : (days == 0 ? "今天" : "天前")

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        ReiconIcon(icon: .edit, size: 10.5)
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Spacer(minLength: 2)

                    if days == 0 {
                        Text("今天")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                            .foregroundStyle(item.accent.color)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text("\(abs(days))")
                                .font(.system(size: 31, weight: .bold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(item.accent.color)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                            Text(unitText)
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }

                    Spacer(minLength: 2)

                    Text(item.shortDateText)
                        .font(.system(size: 10.5, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(13)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .cardElevation(radius: AppRadius.card)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("倒数日")
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        ReiconIcon(icon: .add, size: 13)
                            .foregroundStyle(Theme.brand)
                    }

                    Spacer()

                    Text("添加日期")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("任意目标日")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.top, 2)
                }
                .padding(13)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .cardElevation(radius: AppRadius.card)
            }
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: 右下 1×1 · 使用时长 7 天柱状图

    private func activityMiniCard(digest: UsageDigest) -> some View {
        let barValues = digest.lastSeven.map(\.minutes)
        let peak = max(30, barValues.max() ?? 1)

        return Button {
            isTimePresented = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("使用 · 7天")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(usageText(digest))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.brand)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                HStack(alignment: .bottom, spacing: 5) {
                    ForEach(Array(barValues.enumerated()), id: \.offset) { index, value in
                        let isToday = index == barValues.count - 1
                        let ratio = CGFloat(value) / CGFloat(peak)
                        let barHeight = value > 0 ? max(7, min(36, ratio * 36)) : 5

                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                value == 0
                                    ? Theme.surfaceWell
                                    : (isToday ? Theme.brand : Theme.brand.opacity(0.48))
                            )
                            .frame(maxWidth: .infinity)
                            .frame(height: barHeight)
                    }
                }
                .frame(height: 38, alignment: .bottom)
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardElevation(radius: AppRadius.card)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: 下方全宽卡 · 今日聚焦待办

    private var todayTasks: [TaskItem] {
        let calendar = Calendar.current
        let todays = openTasks.filter { task in
            guard let due = task.dueDate else { return false }
            return calendar.isDateInToday(due) || task.isOverdue
        }
        return Array((todays.isEmpty ? openTasks : todays).prefix(3))
    }

    private var todayTaskProgress: (done: Int, total: Int) {
        let calendar = Calendar.current
        var done = 0
        var total = 0
        for task in allTasks where task.deletedAt == nil {
            guard let due = task.dueDate, calendar.isDateInToday(due) else { continue }
            total += 1
            if task.isCompleted { done += 1 }
        }
        return (done, total)
    }

    private var todayFocusCard: some View {
        let progress = todayTaskProgress
        let items = todayTasks

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("今日聚焦")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)

                if progress.total > 0 {
                    let allDone = progress.done == progress.total
                    Text(allDone ? "已完成" : "\(progress.done)/\(progress.total)")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(allDone ? WeReadHeat.green : Theme.brand)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule().fill(allDone ? WeReadHeat.green.opacity(0.14) : Theme.brandSoft)
                        )
                }

                Spacer()

                Button(action: onOpenTasks) {
                    HStack(spacing: 3) {
                        Text("全部")
                        ReiconIcon(icon: .chevronRight, size: 11)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            if items.isEmpty {
                HStack {
                    Text("今日待办已清空")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Button(action: onAddTask) {
                        HStack(spacing: 4) {
                            ReiconIcon(icon: .add, size: 13)
                            Text("添加")
                        }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.brand)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(Theme.brandSoft))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, task in
                        TaskRowView(task: task, compact: true, onTap: onOpenTasks)
                            .padding(.vertical, 8)
                        if index < items.count - 1 {
                            Rectangle()
                                .fill(Theme.stroke)
                                .frame(height: 0.5)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    // MARK: 临期订阅提醒条（有临近扣款才显示）

    private var imminentSubscription: (sub: Subscription, days: Int)? {
        let active = subscriptions.filter { !$0.isPaused }
        var best: (sub: Subscription, days: Int)?
        for sub in active {
            guard let days = SubscriptionMath.daysRemaining(for: sub, now: now), days <= 7 else { continue }
            if let current = best {
                if days < current.days { best = (sub, days) }
            } else {
                best = (sub, days)
            }
        }
        return best
    }

    private func imminentSubBanner(_ sub: Subscription, days: Int) -> some View {
        let isUrgent = days <= 3
        let accent = isUrgent ? SubPalette.orange : Theme.brand
        let dueText: String = {
            if days <= 0 { return "今天扣款" }
            if days == 1 { return "明天扣款" }
            return "剩 \(days) 天扣款"
        }()

        return Button(action: onOpenSubscriptions) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3, height: 22)

                BrandLogo(brand: sub.brand, size: 22)

                Text(sub.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text("· \(dueText)")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(sub.displayPrice)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)

                ReiconIcon(icon: .chevronRight, size: 11)
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardElevation(radius: AppRadius.item)
        }
        .buttonStyle(PressableStyle())
    }

    private func usageText(_ digest: UsageDigest) -> String {
        let minutes = digest.today?.minutes ?? 0
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
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
