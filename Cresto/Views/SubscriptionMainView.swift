import SwiftUI
import SwiftData
import UIKit

private struct SubscriptionEditorContext: Identifiable {
    let id = UUID()
    let subscription: Subscription?
    let preset: SubscriptionPreset?
}

/// 订阅管理主视图（第 4 Tab）。
/// 架构：整页封装为 `SubscriptionMainView`，顶部标题区预留给后续「流水 | 订阅」双分段。
struct SubscriptionMainView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Subscription.createdAt) private var subscriptions: [Subscription]

    @AppStorage("usdToCny") private var usdToCny = 7.25
    @AppStorage("subscriptionShowCNY") private var showCNY = true

    @State private var filter: SubscriptionFilter = .all
    @State private var displayMonth = Calendar.current.date(
        from: Calendar.current.dateComponents([.year, .month], from: Date())
    ) ?? Date()
    @State private var selectedDate: Date?
    @State private var calendarCollapsed = true
    @State private var swipedID: UUID?

    @State private var editorContext: SubscriptionEditorContext?

    @State private var isRateAlertPresented = false
    @State private var rateDraft = ""

    private var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = 2   // 周一开头
        return c
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.cardGap) {
                header
                filterBar
                summaryCalendarCard
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
        .alert("USD → CNY 参考汇率", isPresented: $isRateAlertPresented) {
            TextField("7.25", text: $rateDraft)
                .keyboardType(.decimalPad)
            Button("保存") {
                if let value = Double(rateDraft.replacingOccurrences(of: ",", with: ".")), value > 0 {
                    usdToCny = value
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前汇率 1 USD = \(String(format: "%.2f", usdToCny)) CNY")
        }
    }

    // MARK: 顶部

    private var header: some View {
        HStack(alignment: .center) {
            Text("订阅")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.text)
                .tracking(-0.5)
            Spacer()
            Menu {
                Button {
                    showCNY = true
                } label: {
                    Text(showCNY ? "✓ 显示人民币折算" : "显示人民币折算")
                }
                Button {
                    showCNY = false
                } label: {
                    Text(showCNY ? "显示原币种" : "✓ 显示原币种")
                }
                Button {
                    rateDraft = String(format: "%.2f", usdToCny)
                    isRateAlertPresented = true
                } label: {
                    Text("设置汇率（1 USD = \(String(format: "%.2f", usdToCny)) CNY）")
                }
            } label: {
                HStack(spacing: 4) {
                    Text("CNY 折算")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textSecondary)
                    ReiconIcon(icon: .chevronDown, size: 9)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Theme.surfaceRaised))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("折算设置")
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    // MARK: 筛选胶囊

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(SubscriptionFilter.allCases) { item in
                    let isOn = filter == item
                    Button {
                        withAnimation(.snappy(duration: 0.18)) { filter = item }
                    } label: {
                        Text(item.title)
                            .font(.system(size: 12, weight: isOn ? .medium : .regular))
                            .foregroundStyle(isOn ? Color.white : Theme.textSecondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 6)
                            .background(
                                Capsule().fill(isOn ? Theme.brand : Theme.surface)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 1)
        }
    }

    // MARK: 月均汇总 + 月度支出进度条 + 折叠周历/月历

    private var summaryCalendarCard: some View {
        let active = subscriptions.filter { !$0.isPaused }
        let monthly = active.reduce(0) { $0 + $1.monthlyCNY(rate: usdToCny) }
        let yearly = monthly * 12
        let split = monthSpendSplit(active: active)

        return VStack(alignment: .leading, spacing: 12) {
            // 首行：月均固定英雄数字 + 月份切换 + 折叠
            HStack(alignment: .center, spacing: 6) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("本月固定")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("¥\(money(monthly))")
                            .font(.system(size: 22, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text("年化 ¥\(money(yearly, decimals: 0))")
                            .font(.system(size: 10.5))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                monthSwitcher
                collapseButton
            }

            // 月度支出双色进度条（已扣 vs 待扣）
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    let total = max(0.01, split.charged + split.pending)
                    let chargedWidth = split.totalCount > 0 ? geo.size.width * (split.charged / total) : 0
                    let pendingWidth = split.totalCount > 0 ? geo.size.width * (split.pending / total) : 0
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surfaceWell)
                        HStack(spacing: 1) {
                            if chargedWidth > 0 {
                                Rectangle()
                                    .fill(Theme.brand)
                                    .frame(width: chargedWidth)
                            }
                            if pendingWidth > 0 {
                                Rectangle()
                                    .fill(SubPalette.orange.opacity(0.60))
                                    .frame(width: pendingWidth)
                            }
                        }
                        .clipShape(Capsule())
                    }
                }
                .frame(height: 6)

                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        Circle().fill(Theme.brand).frame(width: 5, height: 5)
                        Text("已扣 ¥\(money(split.charged, decimals: 0))")
                    }
                    HStack(spacing: 4) {
                        Circle().fill(SubPalette.orange.opacity(0.75)).frame(width: 5, height: 5)
                        Text("待扣 ¥\(money(split.pending, decimals: 0))")
                    }
                    Spacer()
                    if let selectedDate {
                        Button {
                            withAnimation(.snappy(duration: 0.18)) { self.selectedDate = nil }
                        } label: {
                            Text("\(calendar.component(.month, from: selectedDate))/\(calendar.component(.day, from: selectedDate)) · 清除")
                                .foregroundStyle(Theme.brand)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .font(.system(size: 10.5))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
            }

            Rectangle()
                .fill(Theme.stroke)
                .frame(height: 0.5)

            if calendarCollapsed {
                weekRow(index: collapsedWeekIndex)
            } else {
                weekdayHeader
                VStack(spacing: 2) {
                    ForEach(Array(monthWeeks.enumerated()), id: \.offset) { _, week in
                        weekRow(cells: week)
                    }
                }
                legend
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 15)
    }

    private func monthSpendSplit(active: [Subscription]) -> (charged: Double, pending: Double, totalCount: Int) {
        let today = calendar.startOfDay(for: Date())
        var charged: Double = 0
        var pending: Double = 0
        var count = 0
        for sub in active {
            let amount = sub.cny(rate: usdToCny)
            for occ in SubscriptionMath.occurrences(for: sub, inMonthOf: displayMonth, calendar: calendar) {
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

    private var monthSwitcher: some View {
        HStack(spacing: 2) {
            Button {
                shiftMonth(-1)
            } label: {
                ReiconIcon(icon: .chevronLeft, size: 9)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text("\(calendar.component(.month, from: displayMonth))月")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .frame(minWidth: 34)

            Button {
                shiftMonth(1)
            } label: {
                ReiconIcon(icon: .chevronRight, size: 9)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 20, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var collapseButton: some View {
        Button {
            withAnimation(.snappy(duration: 0.24)) { calendarCollapsed.toggle() }
        } label: {
            ReiconIcon(icon: calendarCollapsed ? .chevronDown : .chevronUp, size: 10)
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(calendarCollapsed ? "展开月历" : "收起月历")
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                Text(day)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            Spacer()
            legendItem(color: SubPalette.orange, text: "临期")
            legendItem(color: Theme.brand, text: "待扣")
            legendItem(color: Theme.textTertiary, text: "已扣")
        }
    }

    private func legendItem(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 3.5, height: 3.5)
            Text(text)
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: 月历格子

    private func weekRow(index: Int) -> some View {
        weekRow(cells: monthWeeks.indices.contains(index) ? monthWeeks[index] : [])
    }

    private func weekRow(cells: [Date?]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                dayCell(date)
            }
            if cells.count < 7 {
                ForEach(cells.count..<7, id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, minHeight: 32)
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

                VStack(spacing: 2) {
                    ZStack {
                        if isToday {
                            Circle()
                                .fill(Theme.brandSoft)
                                .frame(width: 23, height: 23)
                        }
                        Text("\(calendar.component(.day, from: date))")
                            .font(.system(size: 12.5, weight: isToday ? .semibold : .regular))
                            .monospacedDigit()
                            .foregroundStyle(isToday ? Theme.brand : Theme.text)
                    }
                    .frame(height: 23)
                    .overlay {
                        if isSelected {
                            Circle()
                                .strokeBorder(Theme.brand, lineWidth: 1.5)
                                .frame(width: 27, height: 27)
                        }
                    }

                    Circle()
                        .fill(dotColor(dot))
                        .frame(width: 3.5, height: 3.5)
                        .opacity(dot == nil ? 0 : 1)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { toggleSelection(date) }
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
        }
    }

    private func dotColor(_ state: DotState?) -> Color {
        switch state {
        case .imminent: return SubPalette.orange
        case .pending: return Theme.brand
        case .charged: return Theme.textTertiary
        case nil: return .clear
        }
    }

    // MARK: 列表

    private var subscriptionList: some View {
        let list = visibleSubscriptions
        return VStack(spacing: Theme.cardGap) {
            if list.isEmpty {
                emptyState
            } else {
                ForEach(list) { sub in
                    SubscriptionSwipeRow(
                        sub: sub,
                        swipedID: $swipedID,
                        onTogglePause: { togglePause(sub) },
                        onDelete: { delete(sub) }
                    ) {
                        SubscriptionCardView(
                            sub: sub,
                            rate: usdToCny,
                            showCNY: showCNY
                        )
                        .onTapGesture {
                            editorContext = SubscriptionEditorContext(subscription: sub, preset: nil)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        Group {
            if subscriptions.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("快速记录常用订阅")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text("点一下直接录入")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                        ForEach(SubscriptionPreset.all) { preset in
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                editorContext = SubscriptionEditorContext(subscription: nil, preset: preset)
                            } label: {
                                HStack(spacing: 8) {
                                    BrandLogo(brand: preset.brand, size: 18)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(preset.label)
                                            .font(.system(size: 12.5, weight: .medium))
                                            .foregroundStyle(Theme.text)
                                            .lineLimit(1)
                                        Text("\(preset.currency.symbol)\(String(format: "%.0f", preset.price))/\(preset.cycle.shortTitle)")
                                            .font(.system(size: 10))
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
            } else {
                Text("当前筛选下暂无订阅")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 26)
                    .cardSurface(padding: 14)
            }
        }
    }

    // MARK: 数据

    private var visibleSubscriptions: [Subscription] {
        var list: [Subscription]
        switch filter {
        case .all:
            list = subscriptions
        case .paused:
            return Subscription.sortedForDisplay(subscriptions.filter { $0.isPaused })
        case .ai:
            list = subscriptions.filter { !$0.isPaused && $0.category == .ai }
        case .media:
            list = subscriptions.filter { !$0.isPaused && $0.category == .media }
        case .cloud:
            list = subscriptions.filter { !$0.isPaused && $0.category == .cloud }
        }
        if let selectedDate {
            list = list.filter { sub in
                SubscriptionMath.occurrences(for: sub, inMonthOf: displayMonth, calendar: calendar)
                    .contains { calendar.isDate($0, inSameDayAs: selectedDate) }
            }
        }
        return Subscription.sortedForDisplay(list)
    }

    private func shiftMonth(_ delta: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: delta, to: displayMonth) else { return }
        withAnimation(.snappy(duration: 0.2)) {
            displayMonth = newMonth
            selectedDate = nil
        }
    }

    private func toggleSelection(_ date: Date) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.snappy(duration: 0.2)) {
            if let selectedDate, calendar.isDate(selectedDate, inSameDayAs: date) {
                self.selectedDate = nil
            } else {
                selectedDate = date
            }
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

    // MARK: 月历计算

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

    /// 月历网格：周一开头，nil 为占位
    private var monthWeeks: [[Date?]] {
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: displayMonth)),
              let dayRange = calendar.range(of: .day, in: .month, for: monthStart) else { return [] }

        let leading = (calendar.component(.weekday, from: monthStart) + 5) % 7   // 周一=0
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in 0..<dayRange.count {
            cells.append(calendar.date(byAdding: .day, value: day, to: monthStart))
        }
        while cells.count % 7 != 0 { cells.append(nil) }

        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
    }

    private var collapsedWeekIndex: Int {
        let today = Date()
        guard let week = monthWeeks.firstIndex(where: { week in
            week.contains { date in
                guard let date else { return false }
                return calendar.isDate(date, inSameDayAs: today)
            }
        }) else {
            return 0
        }
        return week
    }
}

// MARK: - 订阅卡片

private struct SubscriptionCardView: View {
    let sub: Subscription
    let rate: Double
    let showCNY: Bool

    var body: some View {
        let days = SubscriptionMath.daysRemaining(for: sub)
        let isUrgent = (days ?? 999) <= 3
        let progress = SubscriptionMath.cycleProgress(for: sub)

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // 品牌托盘
                RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                    .fill(Theme.surfaceRaised)
                    .frame(width: 40, height: 40)
                    .overlay {
                        BrandLogo(brand: sub.brand, size: 24)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(sub.name)
                        .font(.system(size: 14.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)

                    Text("\(sub.cycle.title) · \(sub.displayPrice) · \(sub.payment.title)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(countdownText(days: days))
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(sub.isPaused ? Theme.textTertiary : (isUrgent ? SubPalette.orange : Theme.text))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(
                                sub.isPaused
                                    ? Theme.surfaceRaised
                                    : (isUrgent ? SubPalette.orange.opacity(0.14) : Theme.surfaceRaised)
                            )
                        )

                    if showCNY, sub.currency == .USD, !sub.isPaused {
                        Text("≈ ¥\(String(format: "%.0f", sub.cny(rate: rate)))")
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(13)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottomLeading) {
            GeometryReader { geo in
                Rectangle()
                    .fill(sub.isPaused ? Theme.textTertiary.opacity(0.35) : (isUrgent ? SubPalette.orange : Theme.brand))
                    .frame(width: geo.size.width * progress, height: 2.5)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
        }
        .cardElevation(radius: AppRadius.card)
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous))
    }

    private func countdownText(days: Int?) -> String {
        if sub.isPaused { return "已暂停" }
        guard let days else { return "—" }
        if days <= 0 { return "今天扣费" }
        return "剩 \(days) 天"
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

    private let actionWidth: CGFloat = 136
    private var isOpen: Bool { swipedID == sub.id }
    private var offset: CGFloat {
        if dragging {
            return min(0, max(-actionWidth * 1.4, dragBase + dragTranslation))
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
            .frame(width: 65)
            .frame(maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)
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
    static let green = Color(hex: 0x34C759)
}