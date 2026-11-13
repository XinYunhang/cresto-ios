import Foundation
import SwiftData

/// 从打包的 courses.json 导入课表。
/// 源文件由课表 Excel 转出来，不进公开仓库（含真实课表信息），CI 用 secret 写入。
enum CourseImporter {
    struct Payload: Decodable {
        var termStart: String
        var periodCount: Int
        var periodStarts: [Int]
        var courses: [CourseDTO]
    }

    struct CourseDTO: Decodable {
        var name: String
        var teacher: String
        var location: String
        var shade: Int
        var slots: [SlotDTO]
    }

    struct SlotDTO: Decodable {
        var weekday: Int
        var startPeriod: Int
        var endPeriod: Int
        var weekStart: Int
        var weekEnd: Int
        var parity: String
        var location: String?
    }

    /// 只有一门课都没有时才导入，避免覆盖用户后来的修改
    static func importIfNeeded(into context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<Course>())) ?? 0
        guard count == 0 else { return }
        guard let url = Bundle.main.url(forResource: "courses", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            AppLog.warn("没有 courses.json，跳过课表导入")
            return
        }
        do {
            try importData(data, into: context)
            AppLog.info("课表已导入")
        } catch {
            AppLog.error("课表导入失败：\(error.localizedDescription)")
        }
    }

    static func importData(_ data: Data, into context: ModelContext) throws {
        let payload = try JSONDecoder().decode(Payload.self, from: data)

        for dto in payload.courses {
            let course = Course(
                name: dto.name,
                teacher: dto.teacher,
                location: dto.location,
                shade: dto.shade
            )
            context.insert(course)

            course.slots = dto.slots.map { s in
                let slot = CourseSlot(
                    weekday: s.weekday,
                    startPeriod: s.startPeriod,
                    endPeriod: s.endPeriod,
                    weekStart: s.weekStart,
                    weekEnd: s.weekEnd,
                    parity: WeekParity(rawValue: s.parity) ?? .all,
                    location: s.location ?? ""
                )
                slot.course = course
                return slot
            }
        }

        if let settings = (try? context.fetch(FetchDescriptor<TimetableSettings>()))?.first {
            settings.periodCount = payload.periodCount
            settings.periodStartsRaw = payload.periodStarts.map(String.init).joined(separator: ",")
            if let start = Self.date(from: payload.termStart) {
                settings.termStart = start
            }
        } else {
            let settings = TimetableSettings()
            settings.periodCount = payload.periodCount
            settings.periodStartsRaw = payload.periodStarts.map(String.init).joined(separator: ",")
            if let start = Self.date(from: payload.termStart) {
                settings.termStart = start
            }
            context.insert(settings)
        }

        try context.save()
    }

    private static func date(from text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: text)
    }
}
