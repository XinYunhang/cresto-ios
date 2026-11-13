import Foundation
import SwiftData

/// 一门课可以有多个上课时段（一周上两次），所以 Course 和 CourseSlot 分开。
/// 这个结构参照了国内课程表 App（WakeUp / LightTable）的通用做法：
/// 课程信息 + 若干「星期 / 节次 / 周次」的时间块。
@Model
final class Course {
    var id: UUID = UUID()
    var name: String = ""
    var teacher: String = ""
    var location: String = ""
    var note: String = ""
    /// 黑白主题下用来区分不同课程的灰阶档位 0...4
    var shade: Int = 0

    @Relationship(deleteRule: .cascade, inverse: \CourseSlot.course)
    var slots: [CourseSlot] = []

    init(name: String = "", teacher: String = "", location: String = "", shade: Int = 0) {
        self.name = name
        self.teacher = teacher
        self.location = location
        self.shade = shade
    }
}

@Model
final class CourseSlot {
    var id: UUID = UUID()
    /// 1 = 周一 ... 7 = 周日
    var weekday: Int = 1
    var startPeriod: Int = 1
    var endPeriod: Int = 2
    var weekStart: Int = 1
    var weekEnd: Int = 20
    /// all / odd / even
    var parityRaw: String = "all"
    /// 单双周可能在不同教室，所以地点挂在时间块上
    var location: String = ""
    var course: Course?

    init(weekday: Int = 1, startPeriod: Int = 1, endPeriod: Int = 2, weekStart: Int = 1, weekEnd: Int = 20, parity: WeekParity = .all, location: String = "") {
        self.weekday = weekday
        self.startPeriod = startPeriod
        self.endPeriod = endPeriod
        self.weekStart = weekStart
        self.weekEnd = weekEnd
        self.parityRaw = parity.rawValue
        self.location = location
    }

    var parity: WeekParity {
        get { WeekParity(rawValue: parityRaw) ?? .all }
        set { parityRaw = newValue.rawValue }
    }

    var periodSpan: Int { max(1, endPeriod - startPeriod + 1) }

    func isActive(inWeek week: Int) -> Bool {
        guard week >= weekStart, week <= weekEnd else { return false }
        switch parity {
        case .all: return true
        case .odd: return week % 2 == 1
        case .even: return week % 2 == 0
        }
    }
}

enum WeekParity: String, Codable, CaseIterable, Identifiable {
    case all, odd, even
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "每周"
        case .odd: return "单周"
        case .even: return "双周"
        }
    }
}

/// 学期设置：开学日期 + 节次时间，全局只有一条
@Model
final class TimetableSettings {
    var id: UUID = UUID()
    var termStart: Date = TimetableSettings.defaultTermStart
    var periodCount: Int = 12
    /// 每节课开始时间，单位：从 0 点起的分钟数
    var periodStartsRaw: String = "480,535,600,655,840,895,960,1015,1140,1195,1250,1305"

    init() {}

    static var defaultTermStart: Date {
        let calendar = Calendar.current
        let now = Date()
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return calendar.startOfDay(for: monday)
    }

    var periodStarts: [Int] {
        periodStartsRaw.split(separator: ",").compactMap { Int($0) }
    }

    func startTime(ofPeriod period: Int) -> DateComponents {
        let minutes = periodStarts.indices.contains(period - 1) ? periodStarts[period - 1] : 480
        return DateComponents(hour: minutes / 60, minute: minutes % 60)
    }

    func startText(ofPeriod period: Int) -> String {
        let c = startTime(ofPeriod: period)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    func endText(ofPeriod period: Int) -> String {
        let starts = periodStarts
        guard starts.indices.contains(period) else { return startText(ofPeriod: period) }
        // 下一节开始前 5 分钟算这节结束
        let end = starts[period] - 5
        return String(format: "%02d:%02d", end / 60, end % 60)
    }

    /// 当前是第几教学周
    func weekNumber(for date: Date = Date()) -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: termStart)
        let day = calendar.startOfDay(for: date)
        let days = calendar.dateComponents([.day], from: start, to: day).day ?? 0
        return max(1, days / 7 + 1)
    }

    /// 某一周的周一
    func monday(ofWeek week: Int) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .day, value: (week - 1) * 7, to: calendar.startOfDay(for: termStart)) ?? termStart
    }
}
