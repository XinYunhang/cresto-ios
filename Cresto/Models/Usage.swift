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
    static func key(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

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

    static func map(in context: ModelContext) -> [String: DailyUsage] {
        let all = (try? context.fetch(FetchDescriptor<DailyUsage>())) ?? []
        return Dictionary(all.map { ($0.dateKey, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

// MARK: - 合成评分

enum UsageStats {
    struct Cell: Identifiable {
        let id: String
        let date: Date
        let minutes: Int
        let dueCount: Int
        let doneCount: Int
        let level: Int

        /// 完成率，当天没有待办时就是使用强度
        var completionRate: Double {
            dueCount == 0 ? 0 : Double(doneCount) / Double(dueCount)
        }
    }

    /// 使用时长封顶 3 小时，算「用满了」
    private static let minuteCap: Double = 180

    static func level(minutes: Int, dueCount: Int, doneCount: Int) -> Int {
        let usageScore = min(1, Double(minutes) / minuteCap)
        let rate = dueCount == 0 ? usageScore : Double(doneCount) / Double(dueCount)
        let mixed = dueCount == 0 ? usageScore : usageScore * 0.55 + rate * 0.45

        switch mixed {
        case ..<0.12: return 0
        case ..<0.32: return 1
        case ..<0.52: return 2
        case ..<0.74: return 3
        default: return 4
        }
    }

    /// 某一天的任务情况：当天到期的算总数，完成的算处理数
    static func taskCounts(for date: Date, tasks: [TaskItem]) -> (due: Int, done: Int) {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        var due = 0
        var done = 0
        for task in tasks {
            guard let taskDate = task.dueDate else { continue }
            guard calendar.isDate(calendar.startOfDay(for: taskDate), inSameDayAs: day) else { continue }
            due += 1
            if task.isCompleted { done += 1 }
        }
        return (due, done)
    }

    static func cell(
        for date: Date,
        usages: [String: DailyUsage],
        tasks: [TaskItem]
    ) -> Cell {
        let key = UsageStore.key(for: date)
        let minutes = usages[key]?.minutes ?? 0
        let counts = taskCounts(for: date, tasks: tasks)
        return Cell(
            id: key,
            date: date,
            minutes: minutes,
            dueCount: counts.due,
            doneCount: counts.done,
            level: level(minutes: minutes, dueCount: counts.due, doneCount: counts.done)
        )
    }

    /// 连续记录天数（level > 0）
    static func streak(cells: [Cell], today: Date = Date()) -> Int {
        let calendar = Calendar.current
        var streak = 0
        var day = calendar.startOfDay(for: today)
        let map = Dictionary(cells.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        while true {
            let key = UsageStore.key(for: day)
            guard let cell = map[key], cell.level > 0 else { break }
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }
}
