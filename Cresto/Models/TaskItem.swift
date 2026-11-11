import Foundation
import SwiftData

// MARK: - 枚举

enum TaskPriority: Int, Codable, CaseIterable, Identifiable {
    case none = 0
    case low = 1
    case high = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return "无"
        case .low: return "低"
        case .high: return "高"
        }
    }
}

enum RepeatKind: String, Codable, CaseIterable, Identifiable {
    case none, daily, weekly, monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "不重复"
        case .daily: return "每天"
        case .weekly: return "每周"
        case .monthly: return "每月"
        }
    }

    /// 下一次到期时间
    func next(after date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .none: return nil
        case .daily: return calendar.date(byAdding: .day, value: 1, to: date)
        case .weekly: return calendar.date(byAdding: .weekOfYear, value: 1, to: date)
        case .monthly: return calendar.date(byAdding: .month, value: 1, to: date)
        }
    }
}

enum ReminderOffset: Int, Codable, CaseIterable, Identifiable {
    case none = -1
    case onTime = 0
    case min5 = 5
    case min15 = 15
    case min30 = 30
    case hour1 = 60
    case day1 = 1440

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .none: return "不提醒"
        case .onTime: return "准时"
        case .min5: return "提前 5 分钟"
        case .min15: return "提前 15 分钟"
        case .min30: return "提前 30 分钟"
        case .hour1: return "提前 1 小时"
        case .day1: return "提前 1 天"
        }
    }
}

// MARK: - 待办

@Model
final class TaskItem {
    var id: UUID = UUID()
    var title: String = ""
    var notes: String = ""

    var createdAt: Date = Date()
    var dueDate: Date?
    /// 有没有具体时刻。只有日期时，提醒默认早上 9 点
    var hasTime: Bool = false

    var isCompleted: Bool = false
    var completedAt: Date?
    var isPinned: Bool = false
    /// 软删除，留着以后做「最近删除」
    var deletedAt: Date?

    var priorityRaw: Int = 0
    var reminderRaw: Int = -1
    var repeatRaw: String = "none"
    /// 逗号分隔的标签，避开 SwiftData 的 [String] 兼容问题
    var tagsRaw: String = ""

    /// 重复任务共用同一个系列，便于以后整段修改
    var seriesId: UUID?

    @Relationship(deleteRule: .cascade, inverse: \Subtask.task)
    var subtasks: [Subtask] = []

    init(
        title: String = "",
        notes: String = "",
        dueDate: Date? = nil,
        hasTime: Bool = false,
        priority: TaskPriority = .none,
        reminder: ReminderOffset = .none,
        repeatKind: RepeatKind = .none,
        tags: [String] = []
    ) {
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.hasTime = hasTime
        self.priorityRaw = priority.rawValue
        self.reminderRaw = reminder.rawValue
        self.repeatRaw = repeatKind.rawValue
        self.tagsRaw = tags.joined(separator: ",")
        self.createdAt = Date()
    }

    // MARK: 计算属性

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .none }
        set { priorityRaw = newValue.rawValue }
    }

    var reminder: ReminderOffset {
        get { ReminderOffset(rawValue: reminderRaw) ?? .none }
        set { reminderRaw = newValue.rawValue }
    }

    var repeatKind: RepeatKind {
        get { RepeatKind(rawValue: repeatRaw) ?? .none }
        set { repeatRaw = newValue.rawValue }
    }

    var tags: [String] {
        get { tagsRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty } }
        set { tagsRaw = newValue.joined(separator: ",") }
    }

    var doneSubtaskCount: Int { subtasks.filter(\.isDone).count }

    var isOverdue: Bool {
        guard !isCompleted, let dueDate else { return false }
        return Calendar.current.startOfDay(for: dueDate) < Calendar.current.startOfDay(for: Date())
    }

    /// 真正要触发的提醒时间
    var reminderDate: Date? {
        guard let dueDate, reminder != .none else { return nil }
        let base: Date
        if hasTime {
            base = dueDate
        } else {
            // 只有日期：默认当天 9:00
            base = Calendar.current.date(
                bySettingHour: 9, minute: 0, second: 0,
                of: Calendar.current.startOfDay(for: dueDate)
            ) ?? dueDate
        }
        return base.addingTimeInterval(-Double(reminder.rawValue) * 60)
    }
}

@Model
final class Subtask {
    var id: UUID = UUID()
    var title: String = ""
    var isDone: Bool = false
    var order: Int = 0
    var task: TaskItem?

    init(title: String = "", order: Int = 0) {
        self.title = title
        self.order = order
    }
}
