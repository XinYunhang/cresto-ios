import SwiftUI
import SwiftData

struct TimeView: View {
    @Query(sort: \DailyUsage.dateKey) private var usages: [DailyUsage]
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]

    private let heatWeeks = 17
    private let dayCount = 7

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.cardGap) {
                header
                summary
                heatmapCard
                statsCard
                weekBarsCard
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 132)
        }
    }

    // MARK: 页头

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(Date().formatted(.dateTime.month().day())) · 近 \(heatWeeks) 周")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text("时间")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .tracking(-0.5)
            }
            Spacer()
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 2)
    }

    // MARK: 本周

    private var summary: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("本周累计").cardLabel()

            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("\(weekTotal / 60)").font(.system(size: 34, weight: .light))
                Text("h").font(.system(size: 15)).foregroundStyle(Theme.textTertiary).padding(.horizontal, 3)
                Text(String(format: "%02d", weekTotal % 60)).font(.system(size: 34, weight: .light))
                Text("m").font(.system(size: 15)).foregroundStyle(Theme.textTertiary).padding(.leading, 3)
            }
            .monospacedDigit()
            .foregroundStyle(Theme.text)
            .padding(.top, 10)

            HStack(spacing: 3) {
                Image(systemName: weekDelta >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                Text(deltaText)
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 热力图

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("活跃热力图").cardLabel()
                Spacer()
                HStack(spacing: 3) {
                    Text("少")
                    ForEach(0..<5, id: \.self) { level in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(HeatScale.color(for: level))
                            .frame(width: 7, height: 7)
                    }
                    Text("多")
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            }
            .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 3) {
                    ForEach(0..<heatWeeks, id: \.self) { column in
                        VStack(spacing: 3) {
                            ForEach(0..<dayCount, id: \.self) { row in
                                let index = column * dayCount + row
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(HeatScale.color(for: heatCells.indices.contains(index) ? heatCells[index].level : 0))
                                    .frame(width: 9, height: 9)
                            }
                        }
                    }
                }

                HStack {
                    Text("\(heatWeeks) 周前")
                    Spacer()
                    Text("本周")
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: 统计

    private var statsCard: some View {
        VStack(spacing: 0) {
            statRow("日均", dailyAverageText)
            divider
            statRow("近 7 天完成率", completionText)
            divider
            statRow("连续记录", "\(streakDays) 天")
        }
        .cardSurface(padding: 0)
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(Theme.text)
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
    }

    // MARK: 7 天柱状

    private var weekBarsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近 7 天").cardLabel()
                Spacer()
                Text("分钟 / 天").font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.bottom, 12)

            HStack(alignment: .bottom, spacing: 7) {
                ForEach(lastSeven) { cell in
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Theme.ink, Theme.ink.opacity(0.22)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 14, height: max(4, 68 * barRatio(cell)))
                            .opacity(isToday(cell) ? 1 : 0.85)
                            .frame(maxHeight: 68, alignment: .bottom)

                        Text(weekdayText(cell.date))
                            .font(.system(size: 10))
                            .foregroundStyle(isToday(cell) ? Theme.ink : Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .cardSurface()
    }

    // MARK: 数据

    private var usageMap: [String: DailyUsage] {
        Dictionary(usages.map { ($0.dateKey, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var heatCells: [UsageStats.Cell] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let start = calendar.date(byAdding: .day, value: -(heatWeeks - 1) * 7, to: weekStart) else {
            return []
        }
        return (0..<(heatWeeks * dayCount)).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start) ?? start
            return UsageStats.cell(for: day, usages: usageMap, tasks: tasks)
        }
    }

    private var lastSeven: [UsageStats.Cell] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return UsageStats.cell(for: day, usages: usageMap, tasks: tasks)
        }
    }

    private var weekTotal: Int {
        lastSeven.reduce(0) { $0 + $1.minutes }
    }

    private var previousWeekTotal: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (7..<14).reduce(0) { sum, offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return sum }
            return sum + (usageMap[UsageStore.key(for: day)]?.minutes ?? 0)
        }
    }

    private var weekDelta: Int { weekTotal - previousWeekTotal }

    private var deltaText: String {
        guard previousWeekTotal > 0 else {
            return weekTotal > 0 ? "本周开始记录" : "还没有记录"
        }
        if weekDelta == 0 { return "和上周持平" }
        let hours = abs(weekDelta) / 60
        let minutes = abs(weekDelta) % 60
        let amount = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        return weekDelta > 0 ? "比上周多 \(amount)" : "比上周少 \(amount)"
    }

    private var dailyAverageText: String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let recent = (0..<30).compactMap { offset -> Int? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let minutes = usageMap[UsageStore.key(for: day)]?.minutes ?? 0
            return minutes > 0 ? minutes : nil
        }
        guard !recent.isEmpty else { return "0m" }
        let average = recent.reduce(0, +) / recent.count
        return average >= 60
            ? "\(average / 60)h \(String(format: "%02d", average % 60))m"
            : "\(average)m"
    }

    private var completionText: String {
        let due = lastSeven.reduce(0) { $0 + $1.dueCount }
        let done = lastSeven.reduce(0) { $0 + $1.doneCount }
        guard due > 0 else { return "—" }
        return "\(Int(Double(done) / Double(due) * 100))%"
    }

    private var streakDays: Int {
        UsageStats.streak(cells: heatCells)
    }

    private func barRatio(_ cell: UsageStats.Cell) -> CGFloat {
        let peak = lastSeven.map(\.minutes).max() ?? 1
        guard peak > 0 else { return 0 }
        return CGFloat(cell.minutes) / CGFloat(peak)
    }

    private func isToday(_ cell: UsageStats.Cell) -> Bool {
        Calendar.current.isDateInToday(cell.date)
    }

    private func weekdayText(_ date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        return ["日", "一", "二", "三", "四", "五", "六"][max(0, min(6, weekday - 1))]
    }
}
