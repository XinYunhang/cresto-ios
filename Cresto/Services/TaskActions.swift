import Foundation
import SwiftData
import SwiftUI

/// 待办的所有写操作集中在这里，视图只调用它。
/// 勾选完成时顺便处理「重复任务」的下一次、以及通知的增删。
enum TaskActions {
    static func toggle(_ task: TaskItem, in context: ModelContext) {
        if task.isCompleted {
            task.isCompleted = false
            task.completedAt = nil
        } else {
            task.isCompleted = true
            task.completedAt = Date()
            spawnNextIfRepeating(task, in: context)
        }
        NotificationScheduler.sync(task)
        try? context.save()
    }

    static func delete(_ task: TaskItem, in context: ModelContext) {
        NotificationScheduler.cancel(id: task.id)
        context.delete(task)
        try? context.save()
    }

    /// 重复任务：完成后立刻生成下一次，保留标签、提醒、备注
    private static func spawnNextIfRepeating(_ task: TaskItem, in context: ModelContext) {
        guard task.repeatKind != .none, let due = task.dueDate else { return }
        guard let nextDate = task.repeatKind.next(after: due) else { return }

        let series = task.seriesId ?? task.id
        task.seriesId = series

        let next = TaskItem(
            title: task.title,
            notes: task.notes,
            dueDate: nextDate,
            hasTime: task.hasTime,
            priority: task.priority,
            reminder: task.reminder,
            repeatKind: task.repeatKind,
            tags: task.tags
        )
        next.seriesId = series
        context.insert(next)
        NotificationScheduler.sync(next)
    }
}

// MARK: - 日期分组

enum TaskGroup: String, CaseIterable, Identifiable {
    case overdue, today, tomorrow, thisWeek, later, none

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue: return "已逾期"
        case .today: return "今天"
        case .tomorrow: return "明天"
        case .thisWeek: return "本周"
        case .later: return "以后"
        case .none: return "待安排"
        }
    }

    static func group(for date: Date?, calendar: Calendar = .current) -> TaskGroup {
        guard let date else { return .none }
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: today, to: target).day ?? 0

        if days < 0 { return .overdue }
        if days == 0 { return .today }
        if days == 1 { return .tomorrow }
        if days <= 7 { return .thisWeek }
        return .later
    }
}

// MARK: - 格式化

extension Date {
    /// 今天 18:30 / 明天 / 11月12日 周三
    func taskLabel(hasTime: Bool) -> String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")

        let dayText: String
        if calendar.isDateInToday(self) {
            dayText = "今天"
        } else if calendar.isDateInTomorrow(self) {
            dayText = "明天"
        } else if calendar.isDateInYesterday(self) {
            dayText = "昨天"
        } else {
            formatter.dateFormat = "M月d日 EEE"
            dayText = formatter.string(from: self)
        }

        guard hasTime else { return dayText }
        formatter.dateFormat = "HH:mm"
        return "\(dayText) \(formatter.string(from: self))"
    }
}
