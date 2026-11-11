import Foundation
import SwiftData

/// 每天一条：本 App 前台使用秒数。
/// 热力图 = 使用时长 + 当天待办完成率的合成。
@Model
final class DailyUsage {
    /// yyyy-MM-dd
    var dateKey: String = ""
    var foregroundSeconds: Int = 0
    var updatedAt: Date = Date()

    init(dateKey: String, foregroundSeconds: Int = 0) {
        self.dateKey = dateKey
        self.foregroundSeconds = foregroundSeconds
        self.updatedAt = Date()
    }

    var minutes: Int { foregroundSeconds / 60 }
}

enum UsageStore {
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(for date: Date) -> String { formatter.string(from: date) }
    static var todayKey: String { key(for: Date()) }

    @discardableResult
    static func today(in context: ModelContext) -> DailyUsage {
        let key = todayKey
        let descriptor = FetchDescriptor<DailyUsage>(predicate: #Predicate { $0.dateKey == key })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let record = DailyUsage(dateKey: key)
        context.insert(record)
        try? context.save()
        return record
    }

    /// 累加前台秒数并落库
    static func add(seconds: Int, in context: ModelContext) {
        guard seconds > 0 else { return }
        let record = today(in: context)
        record.foregroundSeconds += seconds
        record.updatedAt = Date()
        try? context.save()
    }
}

/// 一次算完所有统计，避免在 body 里对每个格子重复遍历任务。
/// 复杂度 O(任务数 + 天数)。之前那是 O(天数 × 任务数) × 每次 body，切页就会卡住。
struct UsageDigest {
    struct Day: Identifiable {
        let id: String
        let date: Date
        let minutes: Int
        let due: Int
        let done: Int
        let level: Int
    }

    let days: [Day]

    /// 使用时长封顶 3 小时算「用满了」
    private static let minuteCap: Double = 180

    static func level(minutes: Int, due: Int, done: Int) -> Int {
        let usageScore = min(1, Double(minutes) / minuteCap)
        let mixed: Double
        if due == 0 {
            mixed = usageScore
        } else {
            mixed = usageScore * 0.55 + Double(done) / Double(due) * 0.45
        }
        switch mixed {
        case ..<0.12: return 0
        case ..<0.32: return 1
        case ..<0.52: return 2
        case ..<0.74: return 3
        default: return 4
        }
    }

    static func build(dates: [Date], usages: [DailyUsage], tasks: [TaskItem]) -> UsageDigest {
        let usageMap = Dictionary(usages.map { ($0.dateKey, $0.minutes) }, uniquingKeysWith: { first, _ in first })

        // 任务按「到期日」一次性分桶
        var counts: [String: (due: Int, done: Int)] = [:]
        counts.reserveCapacity(max(16, dates.count))
        for task in tasks {
            guard let due = task.dueDate else { continue }
            let key = UsageStore.key(for: due)
            var entry = counts[key] ?? (0, 0)
            entry.due += 1
            if task.isCompleted { entry.done += 1 }
            counts[key] = entry
        }

        let days = dates.map { date -> Day in
            let key = UsageStore.key(for: date)
            let minutes = usageMap[key] ?? 0
            let entry = counts[key] ?? (0, 0)
            return Day(
                id: key,
                date: date,
                minutes: minutes,
                due: entry.due,
                done: entry.done,
                level: level(minutes: minutes, due: entry.due, done: entry.done)
            )
        }
        return UsageDigest(days: days)
    }

    /// 从「(周数-1) 周前的周一」到「本周周日」的连续日期
    static func heatDates(weeks: Int, endingAt date: Date = Date()) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: today)?.start,
              let start = calendar.date(byAdding: .day, value: -(weeks - 1) * 7, to: weekStart) else {
            return [today]
        }
        return (0..<(weeks * 7)).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: start)
        }
    }

    /// 只取已经发生的日子，最后一个是今天
    var pastDays: [Day] {
        let today = Calendar.current.startOfDay(for: Date())
        return days.filter { $0.date <= today }
    }

    var today: Day? { pastDays.last }
    var yesterday: Day? { pastDays.dropLast().last }

    var lastSeven: [Day] { Array(pastDays.suffix(7)) }

    var streak: Int {
        var count = 0
        for day in pastDays.reversed() {
            guard day.level > 0 else { break }
            count += 1
        }
        return count
    }

    func day(for date: Date) -> Day? {
        let key = UsageStore.key(for: date)
        return days.first { $0.id == key }
    }
}
