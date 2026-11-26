import SwiftUI
import SwiftData
import UIKit

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
    @Query(sort: \WeReadDay.dateKey) private var readDays: [WeReadDay]
    @Query(sort: \Subscription.createdAt) private var subscriptions: [Subscription]

    @AppStorage("countdownTitle") private var countdownTitle = ""
    @AppStorage("countdownTimestamp") private var countdownTimestamp: Double = 0
    @AppStorage("usdToCny") private var usdToCny = 7.25
    @AppStorage("subscriptionShowCNY") private var showCNY = true

    var onOpenTasks: () -> Void
    var onOpenCourse: () -> Void = {}
    var onOpenSubscriptions: () -> Void = {}
    var onAddTask: () -> Void
    var onOpenSettings: () -> Void

    @State private var isSearchPresented = false
    @State private var isTimePresented = false
    @State private var isCountdownEditorPresented = false
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
                topRow
                greeting
                searchField
                bentoGrid(digest: digest)
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
        .sheet(isPresented: $isCountdownEditorPresented) {
            CountdownEditorSheet(
                title: $countdownTitle,
                timestamp: $countdownTimestamp,
                defaultDate: defaultCountdownDate
            )
        }
        // 首页右下角 BLOUD 小黑球（与课表/待办 FAB 同锚点，52pt / 右 20 / 底 80）
        .overlay(alignment: .bottomTrailing) {
            BloudBallView()
                .padding(.trailing, FloatingAnchor.trailing)
                .padding(.bottom, FloatingAnchor.bottom)
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
            .padding(.bottom, 10)
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

    // MARK: 左上 2×2 · 当前 / 下一节课

    private var courseHeroCard: some View {
        let focus = TimetableLiveMath.focusCourse(
            courses: courses,
            settings: timetableSettings.first,
            now: now
        )

        return Button(action: onOpenCourse) {
            if let focus {
                let tone = Theme.courseTone(focus.course.shade)
                VStack(alignment: .leading, spacing: 0) {
                    courseStatusPill(focus: focus, tone: tone)

                    Spacer(minLength: 8)

                    Text(focus.course.name)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    Text(focus.locationText)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .padding(.top, 5)

                    Spacer(minLength: 10)

                    courseFooter(focus: focus, tone: tone)
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

                    Text(courses.isEmpty ? "暂无课表" : "今日课程已结束")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)

                    Text(courses.isEmpty ? "导入或添加课程" : "好好休息，明天再见")
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

    private func courseStatusPill(focus: CourseFocus, tone: CourseTone) -> some View {
        let label: String
        let isOngoing: Bool
        switch focus.status {
        case .ongoing(_, let remaining):
            isOngoing = true
            label = "进行中 · 剩 \(remaining)m"
        case .upcoming(let minutes):
            isOngoing = false
            if focus.isToday {
                if minutes < 60 {
                    label = "\(minutes) 分钟后"
                } else {
                    let h = minutes / 60
                    let m = minutes % 60
                    label = m == 0 ? "\(h) 小时后" : "\(h)h\(m)m 后"
                }
            } else {
                label = "\(focus.dayLabel)首节"
            }
        case .ended:
            isOngoing = false
            label = "已结束"
        }

        return HStack(spacing: 5) {
            Circle()
                .fill(isOngoing ? Color.white : tone.fg)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .monospacedDigit()
        }
        .foregroundStyle(isOngoing ? Color.white : tone.fg)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(isOngoing ? tone.fg : tone.bg))
    }

    @ViewBuilder
    private func courseFooter(focus: CourseFocus, tone: CourseTone) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(focus.slot.startPeriod)-\(focus.slot.endPeriod) 节")
                Spacer()
                Text(focus.timeRangeText)
                    .monospacedDigit()
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.textTertiary)

            if case .ongoing(let progress, _) = focus.status {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surfaceWell)
                        Capsule()
                            .fill(tone.fg)
                            .frame(width: max(6, geo.size.width * progress))
                    }
                }
                .frame(height: 4)
            } else {
                Capsule()
                    .fill(tone.bg)
                    .frame(height: 4)
            }
        }
    }

    // MARK: 右上 1×1 · 倒数日

    private var effectiveCountdownTitle: String {
        let trimmed = countdownTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "距期末" : trimmed
    }

    private var defaultCountdownDate: Date {
        let calendar = Calendar.current
        if let termStart = timetableSettings.first?.termStart {
            return calendar.date(byAdding: .day, value: 18 * 7, to: calendar.startOfDay(for: termStart))
                ?? calendar.startOfDay(for: now)
        }
        return calendar.date(byAdding: .day, value: 45, to: calendar.startOfDay(for: now))
            ?? calendar.startOfDay(for: now)
    }

    private var targetCountdownDate: Date {
        countdownTimestamp > 0 ? Date(timeIntervalSince1970: countdownTimestamp) : defaultCountdownDate
    }

    private var countdownDaysLeft: Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: targetCountdownDate)
        return max(0, calendar.dateComponents([.day], from: start, to: end).day ?? 0)
    }

    private var countdownCard: some View {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: targetCountdownDate)
        let day = calendar.component(.day, from: targetCountdownDate)

        return Button {
            isCountdownEditorPresented = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(effectiveCountdownTitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    ReiconIcon(icon: .edit, size: 10.5)
                        .foregroundStyle(Theme.textTertiary)
                }

                Spacer(minLength: 2)

                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(countdownDaysLeft)")
                        .font(.system(size: 31, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.brand)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                    Text("天")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer(minLength: 2)

                Text("\(month)月\(day)日")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .cardElevation(radius: AppRadius.card)
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: 右下 1×1 · 阅读 / 使用时长 7 天柱状图

    private func activityMiniCard(digest: UsageDigest) -> some View {
        let readDigest = WeReadDigest.build(cached: readDays, endingAt: now)
        let readSeven = Array(readDigest.days.suffix(7))
        let totalRead = readSeven.reduce(0) { $0 + $1.minutes }
        let useReading = totalRead > 0

        let barValues: [Int] = useReading
            ? readSeven.map(\.minutes)
            : digest.lastSeven.map(\.minutes)
        let peak = max(useReading ? 30 : 30, barValues.max() ?? 1)
        let barColor = useReading ? WeReadHeat.green : Theme.brand

        let headerTitle = useReading ? "阅读 · 7天" : "使用 · 7天"
        let metricText: String = {
            if useReading {
                let todayMin = readSeven.last?.minutes ?? 0
                return todayMin > 0 ? "今日 \(todayMin)m" : "共 \(totalRead)m"
            }
            return usageText(digest)
        }()

        return Button {
            isTimePresented = true
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(headerTitle)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 2)
                    Text(metricText)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(barColor)
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
                                    : (isToday ? barColor : barColor.opacity(0.48))
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
                        .font(.system(size: 10.5, weight: .semibold))
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
        let priceText: String = {
            if showCNY, sub.currency == .USD {
                return "≈ ¥\(String(format: "%.0f", sub.cny(rate: usdToCny)))"
            }
            return sub.displayPrice
        }()

        return Button(action: onOpenSubscriptions) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(accent)
                    .frame(width: 3, height: 22)

                BrandLogo(brand: sub.brand, size: 20)

                Text(sub.name)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text("· \(dueText)")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(accent)
                    .lineLimit(1)

                Spacer(minLength: 6)

                Text(priceText)
                    .font(.system(size: 12, weight: .semibold))
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

// MARK: - 倒数日编辑弹窗

private struct CountdownEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var title: String
    @Binding var timestamp: Double
    let defaultDate: Date

    @State private var draftTitle = ""
    @State private var draftDate = Date()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.cardGap) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("标题")
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            TextField("距期末", text: $draftTitle)
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.text)
                                .multilineTextAlignment(.trailing)
                        }
                        .frame(minHeight: 50)

                        Rectangle().fill(Theme.stroke).frame(height: 0.5)

                        HStack {
                            Text("目标日期")
                                .font(.system(size: 13.5))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            DatePicker("", selection: $draftDate, displayedComponents: .date)
                                .labelsHidden()
                                .datePickerStyle(.compact)
                                .environment(\.locale, Locale(identifier: "zh_CN"))
                        }
                        .frame(minHeight: 50)
                    }
                    .cardSurface()

                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        timestamp = Calendar.current.startOfDay(for: draftDate).timeIntervalSince1970
                        dismiss()
                    } label: {
                        Text("保存倒数日")
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background(
                                RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                                    .fill(Theme.brand)
                            )
                    }
                    .buttonStyle(PressableStyle())

                    Button {
                        title = ""
                        timestamp = 0
                        dismiss()
                    } label: {
                        Text("恢复默认（按学期推算）")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 12)
            }
            .background(Theme.bg)
            .navigationTitle("编辑倒数日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        ReiconIcon(icon: .xmark, size: 11)
                            .foregroundStyle(Theme.text)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Theme.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                }
            }
        }
        .presentationBackground(Theme.bg)
        .onAppear {
            draftTitle = title
            draftDate = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : defaultDate
        }
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
