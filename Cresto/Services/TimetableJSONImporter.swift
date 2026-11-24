import Foundation
import SwiftData

// MARK: - 喜鹊 timetable.json

/// 「喜鹊课表」App 导出的 timetable.json。
/// 一条 `courses[]` 是一个「星期 + 节次 + 周次」时间块，不是一门课；
/// 导入 Cresto 前要按 (name, teacher) 合并成 Course，并把 weeks 压成区间 + 单双周。
struct XiqueerTimetable: Decodable {
    var semesterName: String?
    var semesterStartDate: String?
    var totalWeeks: Int?
    var periodTimes: [PeriodTime]?
    var courses: [CourseItem]

    struct PeriodTime: Decodable {
        var section: Int
        var start: String
        var end: String
    }

    struct CourseItem: Decodable {
        var name: String
        var teacher: String?
        var location: String?
        var weekday: Int
        var startSection: Int
        var endSection: Int?
        /// 已展开的周次数组，例如 4-20 单 会导出成 [5, 7, …, 19]
        var weeks: [Int]?
        var colorIndex: Int?
    }
}

// MARK: - 导入计划

/// 解析后的预览数据：还没写进 SwiftData，确认后才替换课程。
struct TimetableImportPlan {
    struct CoursePlan: Identifiable {
        let id = UUID()
        let name: String
        let teacher: String
        let shade: Int
        let slots: [SlotPlan]
    }

    struct SlotPlan: Identifiable {
        let id = UUID()
        let weekday: Int
        let startPeriod: Int
        let endPeriod: Int
        let weekStart: Int
        let weekEnd: Int
        let parity: WeekParity
        let location: String

        var weekText: String {
            let base = weekStart == weekEnd ? "\(weekStart) 周" : "\(weekStart)-\(weekEnd) 周"
            switch parity {
            case .all: return base
            case .odd: return base + "（单）"
            case .even: return base + "（双）"
            }
        }

        var summary: String {
            var parts = ["周\(TimetableMath.weekdayName(weekday)) \(startPeriod)-\(endPeriod) 节", weekText]
            if !location.isEmpty { parts.append(location) }
            return parts.joined(separator: " · ")
        }
    }

    let semesterName: String
    /// 已校验并归一化的源开学日期；无效时为 nil
    let sourceStartDate: String?
    let totalWeeks: Int
    /// 源作息表里每节的开始分钟数（按节次排序），只在没有 Cresto 学期设置时兜底
    let sourcePeriodStarts: [Int]
    let courses: [CoursePlan]
    let warnings: [String]

    var slotCount: Int {
        courses.reduce(0) { $0 + $1.slots.count }
    }
}

// MARK: - 错误

enum XiqueerImportError: LocalizedError {
    case emptyData
    case tooLarge
    case invalidJSON(String)
    case emptyCourses
    case noValidCourses

    var errorDescription: String? {
        switch self {
        case .emptyData:
            return "没有读到任何内容。"
        case .tooLarge:
            return "文件太大，不像是课表 JSON（上限 5 MB）。"
        case .invalidJSON(let detail):
            return "这不是合法的喜鹊课表 JSON：\(detail)"
        case .emptyCourses:
            return "JSON 里没有 courses 数组，或课程为空。"
        case .noValidCourses:
            return "所有课程都缺少课程名、星期或周次，无法导入。"
        }
    }
}

// MARK: - 解析 / 转换

enum TimetableJSONImporter {
    struct WeekRun {
        let start: Int
        let end: Int
        let parity: WeekParity
    }

    private struct ItemKey: Hashable {
        let name: String
        let teacher: String
        let location: String
        let weekday: Int
        let startPeriod: Int
        let endPeriod: Int
    }

    private struct CourseKey: Hashable {
        let name: String
        let teacher: String
    }

    static func plan(from data: Data) throws -> TimetableImportPlan {
        let cleaned = stripBOM(data)
        guard !cleaned.isEmpty else { throw XiqueerImportError.emptyData }
        guard cleaned.count <= 5 * 1024 * 1024 else { throw XiqueerImportError.tooLarge }

        let source: XiqueerTimetable
        do {
            source = try JSONDecoder().decode(XiqueerTimetable.self, from: cleaned)
        } catch let error as DecodingError {
            throw XiqueerImportError.invalidJSON(describe(error))
        } catch {
            throw XiqueerImportError.invalidJSON(error.localizedDescription)
        }

        guard !source.courses.isEmpty else { throw XiqueerImportError.emptyCourses }

        let totalWeeks = min(60, max(1, source.totalWeeks ?? 20))
        var warnings: [String] = []

        // 源开学日期只用于校验和预览；真正写入时保留 Cresto 当前设置。
        let rawStart = source.semesterStartDate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var normalizedStart: String?
        if rawStart.isEmpty {
            warnings.append("源文件缺少学期开始日期；导入会保留 Cresto 当前的开学周。")
        } else if let date = date(from: rawStart) {
            normalizedStart = string(from: date)
            if !isMonday(date) {
                warnings.append("源文件开学日期 \(normalizedStart ?? rawStart) 不是周一；导入会保留 Cresto 当前的开学周。")
            }
        } else {
            warnings.append("源文件开学日期「\(rawStart)」不是合法日期；导入会保留 Cresto 当前的开学周。")
        }

        let sourcePeriodStarts = (source.periodTimes ?? [])
            .filter { (1...30).contains($0.section) }
            .sorted { $0.section < $1.section }
            .compactMap { minutes(from: $0.start) }

        // 1. 清洗每条时间块，并按「课名 + 教师 + 地点 + 星期 + 节次」合并周次。
        //    喜鹊会把同一门课的 1-8 周、9-16 周拆成两条；先并周再压区间，避免重复时段。
        var itemOrder: [ItemKey] = []
        var weeksByItem: [ItemKey: Set<Int>] = [:]
        var colorByItem: [ItemKey: Int] = [:]
        var skipped = 0
        var badWeeks = Set<Int>()

        for raw in source.courses {
            let name = clean(raw.name)
            let teacher = clean(raw.teacher ?? "")
            let location = clean(raw.location ?? "")
            guard !name.isEmpty, (1...7).contains(raw.weekday) else {
                skipped += 1
                continue
            }

            let startPeriod = max(1, raw.startSection)
            let endPeriod = max(startPeriod, raw.endSection ?? startPeriod)

            let rawWeeks = raw.weeks ?? []
            for week in rawWeeks where !(1...totalWeeks).contains(week) {
                badWeeks.insert(week)
            }
            var weeks = Set(rawWeeks.filter { (1...totalWeeks).contains($0) })
            if rawWeeks.isEmpty {
                weeks = Set(1...totalWeeks)
            }
            guard !weeks.isEmpty else {
                skipped += 1
                continue
            }

            let key = ItemKey(
                name: name,
                teacher: teacher,
                location: location,
                weekday: raw.weekday,
                startPeriod: startPeriod,
                endPeriod: endPeriod
            )
            if weeksByItem[key] == nil {
                itemOrder.append(key)
                weeksByItem[key] = Set<Int>()
                colorByItem[key] = min(8, max(0, raw.colorIndex ?? 0))
            }
            var merged = weeksByItem[key] ?? []
            merged.formUnion(weeks)
            weeksByItem[key] = merged
        }

        guard !weeksByItem.isEmpty else { throw XiqueerImportError.noValidCourses }

        if skipped > 0 {
            warnings.append("已跳过 \(skipped) 条缺少课程名、星期或周次的记录。")
        }
        if !badWeeks.isEmpty {
            let values = badWeeks.sorted().map(String.init).joined(separator: "、")
            warnings.append("周次 \(values) 超出 1-\(totalWeeks)，已忽略。")
        }

        // 2. 按 (name, teacher) 合并成课程；周次按连续段压成 区间 + all/odd/even。
        var courseOrder: [CourseKey] = []
        var slotsByCourse: [CourseKey: [TimetableImportPlan.SlotPlan]] = [:]
        var shadeByCourse: [CourseKey: Int] = [:]

        for key in itemOrder {
            let courseKey = CourseKey(name: key.name, teacher: key.teacher)
            if slotsByCourse[courseKey] == nil {
                courseOrder.append(courseKey)
                slotsByCourse[courseKey] = []
                shadeByCourse[courseKey] = colorByItem[key] ?? 0
            }

            let weeks = Array(weeksByItem[key] ?? []).sorted()
            for run in splitWeekRuns(weeks) {
                let slot = TimetableImportPlan.SlotPlan(
                    weekday: key.weekday,
                    startPeriod: key.startPeriod,
                    endPeriod: key.endPeriod,
                    weekStart: run.start,
                    weekEnd: run.end,
                    parity: run.parity,
                    location: key.location
                )
                var slots = slotsByCourse[courseKey] ?? []
                if !slots.contains(where: { sameSlot($0, slot) }) {
                    slots.append(slot)
                }
                slotsByCourse[courseKey] = slots
            }
        }

        for key in courseOrder {
            var slots = slotsByCourse[key] ?? []
            slots.sort { lhs, rhs in
                if lhs.weekday != rhs.weekday { return lhs.weekday < rhs.weekday }
                if lhs.startPeriod != rhs.startPeriod { return lhs.startPeriod < rhs.startPeriod }
                if lhs.weekStart != rhs.weekStart { return lhs.weekStart < rhs.weekStart }
                return lhs.parity.rawValue < rhs.parity.rawValue
            }
            slotsByCourse[key] = slots
        }

        let courses = courseOrder.map { key in
            TimetableImportPlan.CoursePlan(
                name: key.name,
                teacher: key.teacher,
                shade: shadeByCourse[key] ?? 0,
                slots: slotsByCourse[key] ?? []
            )
        }

        return TimetableImportPlan(
            semesterName: clean(source.semesterName ?? ""),
            sourceStartDate: normalizedStart,
            totalWeeks: totalWeeks,
            sourcePeriodStarts: sourcePeriodStarts,
            courses: courses,
            warnings: warnings
        )
    }

    /// [4,5,6,8] → 4-6 all + 8 all；[5,7,…,19] → 5-19 odd；[4,6,…,20] → 4-20 even。
    static func splitWeekRuns(_ weeks: [Int]) -> [WeekRun] {
        let values = Array(Set(weeks.filter { $0 > 0 })).sorted()
        guard !values.isEmpty else { return [] }

        var runs: [WeekRun] = []
        var index = 0
        while index < values.count {
            let start = values[index]
            let step = (index + 1 < values.count && values[index + 1] - values[index] == 2) ? 2 : 1
            var endIndex = index
            while endIndex + 1 < values.count, values[endIndex + 1] - values[endIndex] == step {
                endIndex += 1
            }
            let end = values[endIndex]
            let parity: WeekParity
            if step == 1 || start == end {
                parity = .all
            } else {
                parity = start % 2 == 1 ? .odd : .even
            }
            runs.append(WeekRun(start: start, end: end, parity: parity))
            index = endIndex + 1
        }
        return runs
    }

    static func date(from text: String) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        return formatter.date(from: String(trimmed.prefix(10)))
    }

    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        return formatter.string(from: date)
    }

    // MARK: 私有

    private static func sameSlot(_ lhs: TimetableImportPlan.SlotPlan, _ rhs: TimetableImportPlan.SlotPlan) -> Bool {
        lhs.weekday == rhs.weekday
            && lhs.startPeriod == rhs.startPeriod
            && lhs.endPeriod == rhs.endPeriod
            && lhs.weekStart == rhs.weekStart
            && lhs.weekEnd == rhs.weekEnd
            && lhs.parity == rhs.parity
            && lhs.location == rhs.location
    }

    private static func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMonday(_ date: Date) -> Bool {
        Calendar(identifier: .gregorian).component(.weekday, from: date) == 2
    }

    private static func minutes(from clock: String) -> Int? {
        let parts = clock.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    private static func stripBOM(_ data: Data) -> Data {
        guard data.count >= 3 else { return data }
        if [UInt8](data.prefix(3)) == [0xEF, 0xBB, 0xBF] {
            return Data(data.dropFirst(3))
        }
        return data
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "缺少字段「\(path(context.codingPath + [key]))」"
        case .typeMismatch(_, let context):
            return "字段「\(path(context.codingPath))」类型不正确"
        case .valueNotFound(_, let context):
            return "字段「\(path(context.codingPath))」为空"
        case .dataCorrupted(let context):
            return "JSON 格式错误：\(context.debugDescription)"
        @unknown default:
            return "JSON 格式错误"
        }
    }

    private static func path(_ codingPath: [CodingKey]) -> String {
        guard !codingPath.isEmpty else { return "根对象" }
        var result = ""
        for key in codingPath {
            if let index = key.intValue {
                result += "[\(index)]"
            } else {
                result += result.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return result
    }
}

// MARK: - 入库

enum XiqueerCourseImporter {
    struct Result {
        let courseCount: Int
        let slotCount: Int
        let snapshot: URL?
    }

    /// 替换全部课程。开学日期 / 作息保留 Cresto 当前设置；
    /// 只有完全没有学期设置时才用源文件兜底。
    @discardableResult
    static func apply(_ plan: TimetableImportPlan, in context: ModelContext) throws -> Result {
        let existing = (try? context.fetch(FetchDescriptor<Course>())) ?? []
        let snapshot = existing.isEmpty ? nil : BackupService.makeSnapshot(in: context)

        existing.forEach { context.delete($0) }
        try? context.save()

        for coursePlan in plan.courses {
            // 教室挂在 slot 上；Course.location 留空（单双周可能换教室）
            let course = Course(
                name: coursePlan.name,
                teacher: coursePlan.teacher,
                location: "",
                shade: coursePlan.shade
            )
            context.insert(course)

            for slotPlan in coursePlan.slots {
                let slot = CourseSlot(
                    weekday: slotPlan.weekday,
                    startPeriod: slotPlan.startPeriod,
                    endPeriod: slotPlan.endPeriod,
                    weekStart: slotPlan.weekStart,
                    weekEnd: slotPlan.weekEnd,
                    parity: slotPlan.parity,
                    location: slotPlan.location
                )
                slot.course = course
                course.slots.append(slot)
                context.insert(slot)
            }
        }

        if (try? context.fetch(FetchDescriptor<TimetableSettings>()))?.first == nil {
            let settings = TimetableSettings()
            if let text = plan.sourceStartDate, let start = TimetableJSONImporter.date(from: text) {
                settings.termStart = start
            }
            if !plan.sourcePeriodStarts.isEmpty {
                settings.periodCount = plan.sourcePeriodStarts.count
                settings.periodStartsRaw = plan.sourcePeriodStarts.map(String.init).joined(separator: ",")
            }
            context.insert(settings)
        }

        try context.save()
        return Result(courseCount: plan.courses.count, slotCount: plan.slotCount, snapshot: snapshot)
    }
}