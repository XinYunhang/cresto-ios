import Foundation
import SwiftData

/// 从打包的 courses.json 导入课表。
/// 源文件由课表 Excel 转出，不进公开仓库（含真实课表信息），CI 用 secret 写入。
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

    /// 老版本的示例课表，升级安装时清掉
    private static let legacySampleNames: Set<String> = [
        "移动应用开发", "交互设计基础", "线性代数"
    ]

    static func importIfNeeded(into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Course>())) ?? []

        if existing.isEmpty {
            importBundled(into: context)
            return
        }

        // 升级场景：只有旧示例课时，清掉再导
        let allSample = existing.allSatisfy { legacySampleNames.contains($0.name) }
        if allSample {
            existing.forEach { context.delete($0) }
            try? context.save()
            AppLog.info("已清空 \(existing.count) 门示例课，开始导入真实课表")
            importBundled(into: context)
        } else {
            AppLog.info("已有 \(existing.count) 门课，跳过自动导入")
        }
    }

    /// 手动重导：删光现有课程后导入打包数据（课表管理里调用）
    static func reimport(into context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<Course>())) ?? []
        existing.forEach { context.delete($0) }
        try? context.save()
        AppLog.info("手动重导课表：先清空 \(existing.count) 门")
        importBundled(into: context)
    }

    @discardableResult
    private static func importBundled(into context: ModelContext) -> Bool {
        guard let url = Bundle.main.url(forResource: "courses", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            AppLog.warn("没有 courses.json，课表为空")
            return false
        }
        do {
            let payload = try importData(data, into: context)
            AppLog.info("课表已导入：\(payload.courses.count) 门课")
            return true
        } catch {
            AppLog.error("课表导入失败：\(error.localizedDescription)")
            return false
        }
    }

    static func importData(_ data: Data, into context: ModelContext) throws -> Payload {
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
        return payload
    }

    private static func date(from text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: text)
    }
}
