import SwiftUI
import SwiftData
import UIKit

private struct SubscriptionEditorContext: Identifiable {
    let id = UUID()
    let subscription: Subscription?
    let preset: SubscriptionPreset?
}

/// 订阅管理主视图（第 4 Tab · 方案 A Bento 双核 + 无框横向列表）。
/// · 无分类筛选、无列表框线，主页面零汇率/折算杂项（USD/JPY 折算仅在详情/添加页显示）
/// · 点击右上角液态玻璃日历圆钮，自动展开存在最近还款的当月，支持切月、重点高亮与点日仅展示图标
struct SubscriptionMainView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subscription.createdAt) private var subscriptions: [Subscription]

    @AppStorage("usdToCny") private var usdToCny = 7.25
    @AppStorage("jpyToCny") private var jpyToCny = 0.048

    @State private var isCalendarOpen = false
    @State private var displayMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var selectedDate: Date?
    @State private var swipedID: UUID?
    @State private var editorContext: SubscriptionEditorContext?

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2   // 周一开头
        return c
    }

    private var sortedSubscriptions: [Subscription] {
        Subscription.sortedForDisplay(subscriptions)
    }

    private var nextActiveSubscription: Subscription? {
        sortedSubscriptions.first { !$0.isPaused }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.cardGap) {
                header
                if isCalendarOpen {
                    calendarDrawer
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                bentoTop
                subscriptionList
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, Theme.bottomScrollInset)
            .frame(maxWidth: .infinity)
            .clipped()
            .simultaneousGesture(TapGesture().onEnded {
                if swipedID != nil { swipedID = nil }
            })
        }
        .background(Theme.bg)
        .floatingAddButton("添加订阅") {
            editorContext = SubscriptionEditorContext(subscription: nil, preset: nil)
        }
        .sheet(item: $editorContext) { ctx in
            SubscriptionEditor(subscription: ctx.subscription, initialPreset: ctx.preset)
        }
    }

    // MARK: 顶部（标准左标题 + 右液态玻璃日历圆钮）

    private var header: some View {
        HStack(alignment: .center) {
            Text("订阅")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.text)
                .tracking(-0.5)
            Spacer()
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(.snappy(duration: 0.25)) {
                    if !isCalendarOpen {
                        jumpToNearestChargeMonth()
                    }
                    isCalendarOpen.toggle()
                }
            } label: {
                ReiconIcon(icon: .calendarDays, size: 19)
                    .foregroundStyle(isCalendarOpen ? Theme.brand : Theme.text)
                    .frame(width: 38, height: 38)
                    .glassCircle()
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("还款日历")
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private func jumpToNearestChargeMonth() {
        let now = Date()
        let active = subscriptions.filter { !$0.isPaused }
        let nearest = active
            .map { SubscriptionMath.upcomingCharge(for: $0, now: now, calendar: calendar) }
            .min() ?? now
        if let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: nearest)) {
            displayMonth = monthStart
            selectedDate = nearest
        }
    }

    // MARK: 日历抽屉（自动定位最近还款月 + 重点强调 + 点日只展示图标）

    private var calendarDrawer: some View {
        let monthNum = calendar.component(.month, from: displayMonth)
        let yearNum = calendar.component(.year, from: displayMonth)
        let selectedSubs = selectedDate.map { subscriptionsDue(on: $0) } ?? []

        return VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text("\(yearNum)年\(monthNum)月")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)

                Spacer()

                HStack(spacing: 4) {
                    Button { shiftMonth(-1) } label: {
                        ReiconIcon(icon: .chevronLeft, size: 11)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Theme.surfaceRaised))
                    }
                    .buttonStyle(.plain)

                    Button { shiftMonth(1) } label: {
                        ReiconIcon(icon: .chevronRight, size: 11)
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Theme.surfaceRaised))
                    }
                    .buttonStyle(.plain)
                }
            }

            weekdayHeader

            VStack(spacing: 4) {
                ForEach(Array(monthWeeks.enumerated()), id: \.offset) { _, week in
                    weekRow(cells: week)
                }
            }

            if !selectedSubs.isEmpty {
                Rectangle().fill(Theme.stroke).frame(height: 0.5)
                // 只展示当日还款项目图标（不堆文字），点击图标直接查看/编辑
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(selectedSubs) { sub in
                            Button {
                                editorContext = SubscriptionEditorContext(subscription: sub, preset: nil)
                            } label: {
                                BrandLogo(brand: sub.brand, size: 32)
                                    .padding(4)
                                    .background(
                                        RoundedRectangle(cornerRadius: AppRadius.control, style: .continuous)
                                            .fill(Theme.surfaceRaised)
                                    )
                            }
                            .buttonStyle(PressableStyle())
                            .accessibilityLabel(sub.name)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                Text(day)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func weekRow(cells: [Date?]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                dayCell(date)
            }
            if cells.count < 7 {
                ForEach(cells.count..<7, id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, minHeight: 34)
                }
            }
        }
    }

    private func dayCell(_ date: Date?) -> some View {
        Group {
            if let date {
                let key = UsageStore.key(for: date)
                let isToday = calendar.isDateInToday(date)
                let isSelected = selectedDate.map { calendar.isDate($0, inSameDayAs: date) } ?? false
                let dot = dayDots[key]
                let hasCharge = dot != nil

                let circleFill: Color = {
                    if isSelected { return Theme.brand }
                    if dot == .imminent { return SubPalette.orange.opacity(0.18) }
                    if dot == .pending { return Theme.brandSoft }
                    if isToday { return Theme.surfaceRaised }
                    return .clear
                }()

                let textColor: Color = {
                    if isSelected { return Color.white }
                    if dot == .imminent { return SubPalette.orange }
                    if dot == .pending { return Theme.brand }
                    return Theme.text
                }()

                VStack(spacing: 2) {
                    ZStack {
                        Circle()
                            .fill(circleFill)
                            .frame(width: 26, height: 26)
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: 12.5, weight: hasCharge || isToday || isSelected ? .semibold : .regular, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(textColor)
                    }
                    .frame(height: 26)

                    Circle()
                        .fill(dotColor(dot, isSelected: isSelected))
                        .frame(width: 4, height: 4)
                        .opacity(hasCharge ? 1 : 0)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy(duration: 0.2)) {
                        if let selectedDate, calendar.isDate(selectedDate, inSameDayAs: date) {
                            self.selectedDate = nil
                        } else {
                            selectedDate = date
                        }
                    }
                }
            } else {
                Color.clear.frame(maxWidth: .infinity, minHeight: 34)
            }
        }
    }

    private func dotColor(_ state: DotState?, isSelected: Bool) -> Color {
        if isSelected { return Theme.brand }
        switch state {
        case .imminent: return SubPalette.orange
        case .pending: return Theme.brand
        case .charged: return Theme.textTertiary
        case nil: return .clear
        }
    }

    // MARK: 方案 A 顶部 Bento 双核区

    private var bentoTop: some View {
        let active = subscriptions.filter { !$0.isPaused }
        let monthly = active.reduce(0) { $0 + $1.monthlyCNY(usdRate: usdToCny, jpyRate: jpyToCny) }
        let yearly = monthly * 12
        let split = monthSpendSplit(active: active)

        return HStack(alignment: .top, spacing: Theme.cardGap) {
            // 左主卡：本月固定 + 已扣/待扣双色轨
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("本月固定")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(active.count) 项")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.brand)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(Theme.brandSoft))
                }

                Spacer(minLength: 6)

                Text("¥\(money(monthly, decimals: 0))")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("年化 ¥\(money(yearly, decimals: 0))")
                    .font(.system(size: 11, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)

                Spacer(minLength: 10)

                VStack(alignment: .leading, spacing: 5) {
                    GeometryReader { geo in
                        let total = max(0.01, split.charged + split.pending)
                        let cw = split.totalCount > 0 ? geo.size.width * (split.charged / total) : 0
                        let pw = split.totalCount > 0 ? geo.size.width * (split.pending / total) : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.surfaceWell)
                            HStack(spacing: 1) {
                                if cw > 0 { Rectangle().fill(Theme.brand).frame(width: cw) }
                                if pw > 0 { Rectangle().fill(SubPalette.orange.opacity(0.68)).frame(width: pw) }
                            }
                            .clipShape(Capsule())
                        }
                    }
                    .frame(height: 5)

                    HStack {
                        Text("已扣 ¥\(money(split.charged, decimals: 0))")
                        Spacer()
                        Text("待扣 ¥\(money(split.pending, decimals: 0))")
                    }
                    .font(.system(size: 10.5, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .frame(height: 148, alignment: .topLeading)
            .cardElevation(radius: AppRadius.card)

            // 右聚焦卡：下一笔扣费（图标 + 名称 + 价格 + 无框大号强调日期）
            nextChargeBentoCard
                .frame(width: 148, height: 148)
        }
    }

    @ViewBuilder
    private var nextChargeBentoCard: some View {
        if let next = nextActiveSubscription {
            Button {
                editorContext = SubscriptionEditorContext(subscription: next, preset: nil)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        BrandLogo(brand: next.brand, size: 28)
                        Spacer(minLength: 4)
                        framelessCountdown(for: next, numberSize: 20, unitSize: 10.5)
                    }

                    Spacer(minLength: 8)

                    Text("下一笔扣费")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)

                    Text(next.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .padding(.top, 2)

                    Text(next.displayPrice)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 3)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .cardElevation(radius: AppRadius.card)
            }
            .buttonStyle(PressableStyle())
        } else {
            Button {
                editorContext = SubscriptionEditorContext(subscription: nil, preset: nil)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    ReiconIcon(icon: .card, size: 22)
                        .foregroundStyle(Theme.brand)
                    Spacer()
                    Text("下一笔扣费")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.textTertiary)
                    Text("待添加")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .padding(.top, 2)
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .cardElevation(radius: AppRadius.card)
            }
            .buttonStyle(PressableStyle())
        }
    }

    // MARK: 订阅列表（无框横向排列 + 从近到远）

    private var subscriptionList: some View {
        let list = sortedSubscriptions
        return VStack(spacing: 0) {
            if list.isEmpty {
                emptyPresetsCard
                    .padding(.top, 4)
            } else {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, sub in
                    SubscriptionSwipeRow(
                        sub: sub,
                        swipedID: $swipedID,
                        onTogglePause: { togglePause(sub) },
                        onDelete: { delete(sub) }
                    ) {
                        Button {
                            editorContext = SubscriptionEditorContext(subscription: sub, preset: nil)
                        } label: {
                            HStack(spacing: 13) {
                                BrandLogo(brand: sub.brand, size: 34)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(sub.name)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(sub.isPaused ? Theme.textTertiary : Theme.text)
                                        .lineLimit(1)

                                    HStack(spacing: 4) {
                                        Text(sub.displayPrice)
                                            .font(.system(size: 13, weight: .medium, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundStyle(Theme.textSecondary)
                                        Text("· \(sub.cycle.title)")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(Theme.textTertiary)
                                    }
                                }

                                Spacer(minLength: 8)

                                framelessCountdown(for: sub, numberSize: 22, unitSize: 11)
                            }
                            .padding(.vertical, 13)
                            .padding(.horizontal, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.bg)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if index < list.count - 1 {
                        Rectangle()
                            .fill(Theme.stroke)
                            .frame(height: 0.5)
                            .padding(.leading, 51)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    /// 无框倒计时展示：数字大于文字且用强调色（圆体）；≥10 天直接显示 M 月 d 日
    @ViewBuilder
    private func framelessCountdown(for sub: Subscription, numberSize: CGFloat, unitSize: CGFloat) -> some View {
        if sub.isPaused {
            Text("已暂停")
                .font(.system(size: unitSize + 1))
                .foregroundStyle(Theme.textTertiary)
        } else {
            let days = SubscriptionMath.daysRemaining(for: sub) ?? 0
            let accentColor = days <= 3 ? SubPalette.orange : Theme.brand

            if days <= 0 {
                Text("今天")
                    .font(.system(size: numberSize - 3, weight: .bold, design: .rounded))
                    .foregroundStyle(SubPalette.orange)
            } else if days < 10 {
                HStack(alignment: .lastTextBaseline, spacing: 2) {
                    Text("\(days)")
                        .font(.system(size: numberSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accentColor)
                    Text("天后")
                        .font(.system(size: unitSize))
                        .foregroundStyle(Theme.textSecondary)
                }
            } else {
                let target = SubscriptionMath.upcomingCharge(for: sub, calendar: calendar)
                let m = calendar.component(.month, from: target)
                let d = calendar.component(.day, from: target)
                HStack(alignment: .lastTextBaseline, spacing: 1.5) {
                    Text("\(m)")
                        .font(.system(size: numberSize - 2, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.brand)
                    Text("月")
                        .font(.system(size: unitSize))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(d)")
                        .font(.system(size: numberSize - 2, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.brand)
                    Text("日")
                        .font(.system(size: unitSize))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private var emptyPresetsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("快速添加订阅")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Text("点一下直接录入")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                ForEach(SubscriptionPreset.all.prefix(8)) { preset in
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        editorContext = SubscriptionEditorContext(subscription: nil, preset: preset)
                    } label: {
                        HStack(spacing: 8) {
                            BrandLogo(brand: preset.brand, size: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(preset.label)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                Text("\(preset.currency.symbol)\(preset.currency == .JPY ? String(format: "%.0f", preset.price) : String(format: "%.0f", preset.price))/\(preset.cycle.shortTitle)")
                                    .font(.system(size: 10, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer(minLength: 2)
                            ReiconIcon(icon: .add, size: 12)
                                .foregroundStyle(Theme.brand)
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                                .fill(Theme.surfaceRaised)
                        )
                    }
                    .buttonStyle(PressableStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    // MARK: 数据与操作

    private func subscriptionsDue(on date: Date) -> [Subscription] {
        subscriptions.filter { sub in
            guard !sub.isPaused else { return false }
            return SubscriptionMath.occurrences(for: sub, inMonthOf: displayMonth, calendar: calendar)
                .contains { calendar.isDate($0, inSameDayAs: date) }
        }
    }

    private func monthSpendSplit(active: [Subscription]) -> (charged: Double, pending: Double, totalCount: Int) {
        let today = calendar.startOfDay(for: Date())
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today)) ?? today
        var charged: Double = 0
        var pending: Double = 0
        var count = 0
        for sub in active {
            let amount = sub.cny(usdRate: usdToCny, jpyRate: jpyToCny)
            for occ in SubscriptionMath.occurrences(for: sub, inMonthOf: currentMonthStart, calendar: calendar) {
                count += 1
                if calendar.startOfDay(for: occ) < today {
                    charged += amount
                } else {
                    pending += amount
                }
            }
        }
        return (charged, pending, count)
    }

    private func shiftMonth(_ delta: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: delta, to: displayMonth) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            displayMonth = newMonth
            selectedDate = nil
        }
    }

    private func togglePause(_ sub: Subscription) {
        withAnimation(.snappy(duration: 0.2)) {
            sub.isPaused.toggle()
        }
        if sub.isPaused {
            SubscriptionReminderService.cancelPendingNotifications(for: sub)
        } else {
            sub.lastRemindedCycleKey = ""
        }
        try? context.save()
        SubscriptionReminderService.sync(fetchAll(), in: context)
    }

    private func delete(_ sub: Subscription) {
        SubscriptionReminderService.cancelPendingNotifications(for: sub)
        withAnimation(.snappy(duration: 0.25)) {
            context.delete(sub)
            swipedID = nil
        }
        try? context.save()
    }

    private func fetchAll() -> [Subscription] {
        (try? context.fetch(FetchDescriptor<Subscription>())) ?? []
    }

    private func money(_ value: Double, decimals: Int = 2) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = decimals
        formatter.maximumFractionDigits = decimals
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.\(decimals)f", value)
    }

    // MARK: 月历点位计算

    private enum DotState: Int, Comparable {
        case charged = 0
        case pending = 1
        case imminent = 2

        static func < (lhs: DotState, rhs: DotState) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private var dayDots: [String: DotState] {
        let today = calendar.startOfDay(for: Date())
        var result: [String: DotState] = [:]
        for sub in subscriptions where !sub.isPaused {
            for occurrence in SubscriptionMath.occurrences(for: sub, inMonthOf: displayMonth, calendar: calendar) {
                let day = calendar.startOfDay(for: occurrence)
                let state: DotState
                if day < today {
                    state = .charged
                } else {
                    let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
                    state = days <= 3 ? .imminent : .pending
                }
                let key = UsageStore.key(for: occurrence)
                if let existing = result[key] {
                    result[key] = max(existing, state)
                } else {
                    result[key] = state
                }
            }
        }
        return result
    }

    private var monthWeeks: [[Date?]] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth)),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }

        let leading = (calendar.component(.weekday, from: monthStart) + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in 0..<dayRange.count {
            cells.append(calendar.date(byAdding: .day, value: day, to: monthStart))
        }
        while cells.count % 7 != 0 { cells.append(nil) }

        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }
}

// MARK: - 左滑操作（暂停/恢复 + 删除）

private struct SubscriptionSwipeRow<Content: View>: View {
    let sub: Subscription
    @Binding var swipedID: UUID?
    let onTogglePause: () -> Void
    let onDelete: () -> Void
    @ViewBuilder var content: Content

    @State private var dragging = false
    @State private var dragBase: CGFloat = 0
    @State private var dragTranslation: CGFloat = 0

    private let actionWidth: CGFloat = 132
    private var isOpen: Bool { swipedID == sub.id }
    private var offset: CGFloat {
        if dragging {
            return min(0, max(-actionWidth * 1.35, dragBase + dragTranslation))
        }
        return isOpen ? -actionWidth : 0
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 6) {
                actionButton(
                    title: sub.isPaused ? "恢复" : "暂停",
                    icon: sub.isPaused ? .play : .pause,
                    background: Theme.surfaceRaised,
                    foreground: Theme.text
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy(duration: 0.2)) { onTogglePause() }
                }
                actionButton(
                    title: "删除",
                    icon: .trash,
                    background: Color.red,
                    foreground: .white
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy(duration: 0.22)) { onDelete() }
                }
            }
            .opacity(min(1, max(0, -offset / actionWidth)))
            .allowsHitTesting(isOpen)

            content
                .offset(x: offset)
                .gesture(dragGesture)
        }
        .frame(maxWidth: .infinity)
        .animation(dragging ? nil : .spring(response: 0.3, dampingFraction: 0.85), value: offset)
    }

    private func actionButton(
        title: String,
        icon: Reicon,
        background: Color,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ReiconIcon(icon: icon, size: 14)
                Text(title).font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(foreground)
            .frame(width: 62)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                    .fill(background)
            )
        }
        .buttonStyle(.plain)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    if dragging {
                        dragging = false
                        dragTranslation = 0
                    }
                    return
                }
                if !dragging {
                    dragging = true
                    dragBase = isOpen ? -actionWidth : 0
                }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                guard dragging else { return }
                dragging = false
                let projected = min(0, dragBase + value.translation.width)
                if projected < -actionWidth * 0.45 {
                    swipedID = sub.id
                } else if isOpen {
                    swipedID = nil
                }
                dragTranslation = 0
            }
    }
}

// MARK: - 配色

enum SubPalette {
    static let orange = Color(hex: 0xF59E0B)
    static let green = Color(hex: 0x2FB356)
}
