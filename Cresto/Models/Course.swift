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

    func startMinutes(ofPeriod period: Int) -> Int {
        let starts = periodStarts
        if starts.indices.contains(period - 1) {
            return starts[period - 1]
        }
        if let last = starts.last, period > starts.count {
            return last + (period - starts.count) * 55
        }
        return 480
    }

    func endMinutes(ofPeriod period: Int) -> Int {
        let starts = periodStarts
        if starts.indices.contains(period) {
            return starts[period] - 5
        }
        return startMinutes(ofPeriod: period) + 45
    }

    func startTime(ofPeriod period: Int) -> DateComponents {
        let minutes = startMinutes(ofPeriod: period)
        return DateComponents(hour: minutes / 60, minute: minutes % 60)
    }

    func startText(ofPeriod period: Int) -> String {
        let c = startTime(ofPeriod: period)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    func endText(ofPeriod period: Int) -> String {
        let end = endMinutes(ofPeriod: period)
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

// MARK: - 实时课程状态计算（纯算法，不改持久化 Schema）

enum CourseLiveStatus: Equatable {
    case ongoing(progress: Double, remainingMinutes: Int)
    case upcoming(minutesUntil: Int)
    case ended
}

struct CourseFocus {
    let course: Course
    let slot: CourseSlot
    let status: CourseLiveStatus
    let isToday: Bool
    let dayLabel: String
    let timeRangeText: String
    let locationText: String
}

enum TimetableLiveMath {
    static func status(
        for slot: CourseSlot,
        isToday: Bool,
        settings: TimetableSettings?,
        now: Date = Date()
    ) -> CourseLiveStatus? {
        guard isToday, let settings else { return nil }
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let nowMinutes = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        let startMin = settings.startMinutes(ofPeriod: slot.startPeriod)
        let endMin = max(startMin + 1, settings.endMinutes(ofPeriod: slot.endPeriod))

        if nowMinutes < startMin {
            return .upcoming(minutesUntil: startMin - nowMinutes)
        } else if nowMinutes < endMin {
            let progress = min(1, max(0, Double(nowMinutes - startMin) / Double(endMin - startMin)))
            return .ongoing(progress: progress, remainingMinutes: max(1, endMin - nowMinutes))
        } else {
            return .ended
        }
    }

    static func focusCourse(
        courses: [Course],
        settings: TimetableSettings?,
        now: Date = Date()
    ) -> CourseFocus? {
        let calendar = Calendar.current
        let effectiveSettings = settings ?? TimetableSettings()
        let currentWeek = effectiveSettings.weekNumber(for: now)
        let weekdayComponent = calendar.component(.weekday, from: now)
        let todayWeekday = ((weekdayComponent + 5) % 7) + 1

        let todaySlots = activeSlots(in: courses, week: currentWeek, weekday: todayWeekday)

        // 1. 优先找正在进行的课程
        for item in todaySlots {
            if let st = status(for: item.slot, isToday: true, settings: effectiveSettings, now: now),
               case .ongoing = st {
                return makeFocus(item.course, item.slot, status: st, isToday: true, dayLabel: "今天", settings: effectiveSettings)
            }
        }

        // 2. 其次找今天最近一节即将开始的课程
        for item in todaySlots {
            if let st = status(for: item.slot, isToday: true, settings: effectiveSettings, now: now),
               case .upcoming = st {
                return makeFocus(item.course, item.slot, status: st, isToday: true, dayLabel: "今天", settings: effectiveSettings)
            }
        }

        // 3. 今天已全部结束或无课：看明天的第一节
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
            let tomorrowWeek = effectiveSettings.weekNumber(for: tomorrow)
            let tomorrowWeekday = (todayWeekday % 7) + 1
            if let first = activeSlots(in: courses, week: tomorrowWeek, weekday: tomorrowWeekday).first {
                let comps = calendar.dateComponents([.hour, .minute], from: now)
                let nowMin = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
                let startMin = effectiveSettings.startMinutes(ofPeriod: first.slot.startPeriod)
                let minutesUntil = max(1, (24 * 60 - nowMin) + startMin)
                return makeFocus(
                    first.course,
                    first.slot,
                    status: .upcoming(minutesUntil: minutesUntil),
                    isToday: false,
                    dayLabel: "明天",
                    settings: effectiveSettings
                )
            }
        }

        return nil
    }

    private static func activeSlots(
        in courses: [Course],
        week: Int,
        weekday: Int
    ) -> [(course: Course, slot: CourseSlot)] {
        var result: [(course: Course, slot: CourseSlot)] = []
        for course in courses {
            for slot in course.slots where slot.weekday == weekday && slot.isActive(inWeek: week) {
                result.append((course, slot))
            }
        }
        result.sort { $0.slot.startPeriod < $1.slot.startPeriod }
        return result
    }

    private static func makeFocus(
        _ course: Course,
        _ slot: CourseSlot,
        status: CourseLiveStatus,
        isToday: Bool,
        dayLabel: String,
        settings: TimetableSettings
    ) -> CourseFocus {
        let rawLocation = slot.location.isEmpty ? course.location : slot.location
        let locationText = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        let timeRange = "\(settings.startText(ofPeriod: slot.startPeriod))-\(settings.endText(ofPeriod: slot.endPeriod))"
        return CourseFocus(
            course: course,
            slot: slot,
            status: status,
            isToday: isToday,
            dayLabel: dayLabel,
            timeRangeText: timeRange,
            locationText: locationText.isEmpty ? "教室待定" : locationText
        )
    }
}
