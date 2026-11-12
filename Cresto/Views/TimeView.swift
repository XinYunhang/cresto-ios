import SwiftUI
import SwiftData

struct TimeView: View {
    @Query(sort: \DailyUsage.dateKey) private var usages: [DailyUsage]
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]

    var showsTitle = true

    init(showsTitle: Bool = true) {
        self.showsTitle = showsTitle
    }

    private let heatWeeks = 17

    var body: some View {
        // 一次算完：O(任务数 + 天数)，不再在格子里重复遍历
        let digest = UsageDigest.build(
            dates: UsageDigest.heatDates(weeks: heatWeeks),
            usages: usages,
            tasks: tasks
        )

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: Theme.cardGap) {
                if showsTitle { header }
                summary(digest)
                heatmapCard(digest)
                statsCard(digest)
                weekBarsCard(digest)
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

    private func summary(_ digest: UsageDigest) -> some View {
        let week = digest.lastSeven.reduce(0) { $0 + $1.minutes }
        let previous = digest.pastDays.dropLast(7).suffix(7).reduce(0) { $0 + $1.minutes }

        return VStack(alignment: .leading, spacing: 0) {
            Text("本周累计").cardLabel()

            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text("\(week / 60)").font(.system(size: 34, weight: .light))
                Text("h").font(.system(size: 15)).foregroundStyle(Theme.textTertiary).padding(.horizontal, 3)
                Text(String(format: "%02d", week % 60)).font(.system(size: 34, weight: .light))
                Text("m").font(.system(size: 15)).foregroundStyle(Theme.textTertiary).padding(.leading, 3)
            }
            .monospacedDigit()
            .foregroundStyle(Theme.text)
            .padding(.top, 10)

            HStack(spacing: 3) {
                Image(systemName: week >= previous ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .semibold))
                Text(deltaText(current: week, previous: previous))
            }
            .font(.system(size: 11))
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func deltaText(current: Int, previous: Int) -> String {
        guard previous > 0 else {
            return current > 0 ? "本周开始记录" : "还没有记录"
        }
        let diff = current - previous
        if diff == 0 { return "和上周持平" }
        let hours = abs(diff) / 60
        let minutes = abs(diff) % 60
        let amount = hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m"
        return diff > 0 ? "比上周多 \(amount)" : "比上周少 \(amount)"
    }

    // MARK: 热力图

    private func heatmapCard(_ digest: UsageDigest) -> some View {
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
                            ForEach(0..<7, id: \.self) { row in
                                let index = column * 7 + row
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .fill(HeatScale.color(for: digest.days.indices.contains(index) ? digest.days[index].level : 0))
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

    private func statsCard(_ digest: UsageDigest) -> some View {
        let due = digest.lastSeven.reduce(0) { $0 + $1.due }
        let done = digest.lastSeven.reduce(0) { $0 + $1.done }
        let rate = due > 0 ? "\(Int(Double(done) / Double(due) * 100))%" : "—"

        return VStack(spacing: 0) {
            statRow("日均", dailyAverage(digest))
            divider
            statRow("近 7 天完成率", rate)
            divider
            statRow("连续记录", "\(digest.streak) 天")
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

    private func dailyAverage(_ digest: UsageDigest) -> String {
        let recent = digest.pastDays.suffix(30).map(\.minutes).filter { $0 > 0 }
        guard !recent.isEmpty else { return "0m" }
        let average = recent.reduce(0, +) / recent.count
        return average >= 60
            ? "\(average / 60)h \(String(format: "%02d", average % 60))m"
            : "\(average)m"
    }

    // MARK: 7 天柱状

    private func weekBarsCard(_ digest: UsageDigest) -> some View {
        let days = digest.lastSeven
        let peak = max(1, days.map(\.minutes).max() ?? 1)

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("最近 7 天").cardLabel()
                Spacer()
                Text("分钟 / 天").font(.system(size: 11.5)).foregroundStyle(Theme.textTertiary)
            }
            .padding(.bottom, 12)

            HStack(alignment: .bottom, spacing: 7) {
                ForEach(days) { day in
                    let ratio = CGFloat(day.minutes) / CGFloat(peak)
                    VStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [Theme.ink, Theme.ink.opacity(0.22)],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: 14, height: max(4, 68 * ratio))
                            .opacity(Calendar.current.isDateInToday(day.date) ? 1 : 0.85)
                            .frame(maxHeight: 68, alignment: .bottom)

                        Text(weekdayText(day.date))
                            .font(.system(size: 10))
                            .foregroundStyle(Calendar.current.isDateInToday(day.date) ? Theme.ink : Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .cardSurface()
    }

    private func weekdayText(_ date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        return ["日", "一", "二", "三", "四", "五", "六"][max(0, min(6, weekday - 1))]
    }
}
