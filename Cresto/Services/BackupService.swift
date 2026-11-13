import Foundation
import SwiftData

// MARK: - 备份文件格式

struct BackupFile: Codable {
    var version: Int = 1
    var createdAt: Date = Date()
    var tasks: [TaskDTO] = []
    var courses: [CourseDTO] = []
    var settings: SettingsDTO?
    var tarot: [TarotDTO] = []
    var usage: [UsageDTO] = []

    var totalItems: Int {
        tasks.count + courses.count + tarot.count + usage.count
    }

    struct TaskDTO: Codable {
        var id: UUID
        var title: String
        var notes: String
        var createdAt: Date
        var dueDate: Date?
        var hasTime: Bool
        var isCompleted: Bool
        var completedAt: Date?
        var isPinned: Bool
        var deletedAt: Date?
        var priorityRaw: Int
        var reminderRaw: Int
        var repeatRaw: String
        var tagsRaw: String
        var seriesId: UUID?
        var subtasks: [SubtaskDTO]
    }

    struct SubtaskDTO: Codable {
        var id: UUID
        var title: String
        var isDone: Bool
        var order: Int
    }

    struct CourseDTO: Codable {
        var id: UUID
        var name: String
        var teacher: String
        var location: String
        var note: String
        var shade: Int
        var slots: [SlotDTO]
    }

    struct SlotDTO: Codable {
        var id: UUID
        var weekday: Int
        var startPeriod: Int
        var endPeriod: Int
        var weekStart: Int
        var weekEnd: Int
        var parityRaw: String
    }

    struct SettingsDTO: Codable {
        var termStart: Date
        var periodCount: Int
        var periodStartsRaw: String
    }

    struct TarotDTO: Codable {
        var dateKey: String
        var cardID: Int
        var isReversed: Bool
        var drawnAt: Date
    }

    struct UsageDTO: Codable {
        var dateKey: String
        var foregroundSeconds: Int
        var updatedAt: Date
    }
}

// MARK: - 快照

struct SnapshotInfo: Identifiable, Hashable {
    let url: URL
    let date: Date
    let bytes: Int
    let itemCount: Int

    var id: URL { url }
    var name: String { url.deletingPathExtension().lastPathComponent }
}

enum BackupError: LocalizedError {
    case unreadable
    case decode(String)

    var errorDescription: String? {
        switch self {
        case .unreadable: return "备份文件读不出来"
        case .decode(let detail): return "备份格式不对：\(detail)"
        }
    }
}

enum BackupService {
    /// 最多留 10 份，多了删最旧的
    private static let keepCount = 10
    private static let folderName = "Backups"

    // MARK: 目录

    static var directory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent(folderName, isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static let fileFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    // MARK: 导出数据

    static func buildBackup(from context: ModelContext) -> BackupFile {
        let tasks = (try? context.fetch(FetchDescriptor<TaskItem>())) ?? []
        let courses = (try? context.fetch(FetchDescriptor<Course>())) ?? []
        let settings = (try? context.fetch(FetchDescriptor<TimetableSettings>()))?.first
        let tarot = (try? context.fetch(FetchDescriptor<DailyTarot>())) ?? []
        let usage = (try? context.fetch(FetchDescriptor<DailyUsage>())) ?? []

        return BackupFile(
            version: 1,
            createdAt: Date(),
            tasks: tasks.map { task in
                BackupFile.TaskDTO(
                    id: task.id,
                    title: task.title,
                    notes: task.notes,
                    createdAt: task.createdAt,
                    dueDate: task.dueDate,
                    hasTime: task.hasTime,
                    isCompleted: task.isCompleted,
                    completedAt: task.completedAt,
                    isPinned: task.isPinned,
                    deletedAt: task.deletedAt,
                    priorityRaw: task.priorityRaw,
                    reminderRaw: task.reminderRaw,
                    repeatRaw: task.repeatRaw,
                    tagsRaw: task.tagsRaw,
                    seriesId: task.seriesId,
                    subtasks: task.subtasks
                        .sorted { $0.order < $1.order }
                        .map { BackupFile.SubtaskDTO(id: $0.id, title: $0.title, isDone: $0.isDone, order: $0.order) }
                )
            },
            courses: courses.map { course in
                BackupFile.CourseDTO(
                    id: course.id,
                    name: course.name,
                    teacher: course.teacher,
                    location: course.location,
                    note: course.note,
                    shade: course.shade,
                    slots: course.slots.map {
                        BackupFile.SlotDTO(
                            id: $0.id,
                            weekday: $0.weekday,
                            startPeriod: $0.startPeriod,
                            endPeriod: $0.endPeriod,
                            weekStart: $0.weekStart,
                            weekEnd: $0.weekEnd,
                            parityRaw: $0.parityRaw
                        )
                    }
                )
            },
            settings: settings.map {
                BackupFile.SettingsDTO(
                    termStart: $0.termStart,
                    periodCount: $0.periodCount,
                    periodStartsRaw: $0.periodStartsRaw
                )
            },
            tarot: tarot.map {
                BackupFile.TarotDTO(dateKey: $0.dateKey, cardID: $0.cardID, isReversed: $0.isReversed, drawnAt: $0.drawnAt)
            },
            usage: usage.map {
                BackupFile.UsageDTO(dateKey: $0.dateKey, foregroundSeconds: $0.foregroundSeconds, updatedAt: $0.updatedAt)
            }
        )
    }

    // MARK: 写快照

    @discardableResult
    static func makeSnapshot(in context: ModelContext) -> URL? {
        let backup = buildBackup(from: context)
        return write(backup, name: "cresto-\(fileFormatter.string(from: Date()))")
    }

    /// 每天第一次打开时自动存一份
    static func makeDailySnapshotIfNeeded(in context: ModelContext) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let today = formatter.string(from: Date())

        let exists = snapshots().contains { $0.name.hasPrefix("cresto-\(today)") }
        guard !exists else { return }
        makeSnapshot(in: context)
        AppLog.info("自动快照完成")
    }

    private static func write(_ backup: BackupFile, name: String) -> URL? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(backup) else { return nil }

        let url = directory.appendingPathComponent(name).appendingPathExtension("json")
        do {
            try data.write(to: url, options: .atomic)
            prune()
            return url
        } catch {
            AppLog.error("写快照失败：\(error.localizedDescription)")
            return nil
        }
    }

    // MARK: 快照列表

    static func snapshots() -> [SnapshotInfo] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey]
        )) ?? []

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> SnapshotInfo? in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let date = values?.contentModificationDate ?? .distantPast
                let bytes = values?.fileSize ?? 0
                return SnapshotInfo(url: url, date: date, bytes: bytes, itemCount: countItems(at: url))
            }
            .sorted { $0.date > $1.date }
    }

    private static func countItems(at url: URL) -> Int {
        guard let data = try? Data(contentsOf: url),
              let backup = try? decoder().decode(BackupFile.self, from: data) else { return 0 }
        return backup.totalItems
    }

    private static func prune() {
        let list = snapshots()
        guard list.count > keepCount else { return }
        for old in list.dropFirst(keepCount) {
            try? FileManager.default.removeItem(at: old.url)
        }
    }

    // MARK: 读 / 恢复

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func load(from url: URL) throws -> BackupFile {
        guard let data = try? Data(contentsOf: url) else { throw BackupError.unreadable }
        do {
            return try decoder().decode(BackupFile.self, from: data)
        } catch {
            throw BackupError.decode(error.localizedDescription)
        }
    }

    /// 恢复：先解码（失败就什么都不动），再清空，再写回
    static func restore(from url: URL, in context: ModelContext) throws {
        let backup = try load(from: url)
        try apply(backup, in: context)
        AppLog.info("已恢复快照：\(url.lastPathComponent)（\(backup.totalItems) 条）")
    }

    static func apply(_ backup: BackupFile, in context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<Subtask>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<TaskItem>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<CourseSlot>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<Course>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<TimetableSettings>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<DailyTarot>()) { context.delete(item) }
        for item in try context.fetch(FetchDescriptor<DailyUsage>()) { context.delete(item) }

        for dto in backup.tasks {
            let task = TaskItem(title: dto.title, notes: dto.notes)
            task.id = dto.id
            task.createdAt = dto.createdAt
            task.dueDate = dto.dueDate
            task.hasTime = dto.hasTime
            task.isCompleted = dto.isCompleted
            task.completedAt = dto.completedAt
            task.isPinned = dto.isPinned
            task.deletedAt = dto.deletedAt
            task.priorityRaw = dto.priorityRaw
            task.reminderRaw = dto.reminderRaw
            task.repeatRaw = dto.repeatRaw
            task.tagsRaw = dto.tagsRaw
            task.seriesId = dto.seriesId
            context.insert(task)

            task.subtasks = dto.subtasks.map { s in
                let subtask = Subtask(title: s.title, order: s.order)
                subtask.id = s.id
                subtask.isDone = s.isDone
                return subtask
            }
        }

        for dto in backup.courses {
            let course = Course(name: dto.name, teacher: dto.teacher, location: dto.location, shade: dto.shade)
            course.id = dto.id
            course.note = dto.note
            context.insert(course)

            course.slots = dto.slots.map { s in
                let slot = CourseSlot(
                    weekday: s.weekday,
                    startPeriod: s.startPeriod,
                    endPeriod: s.endPeriod,
                    weekStart: s.weekStart,
                    weekEnd: s.weekEnd
                )
                slot.id = s.id
                slot.parityRaw = s.parityRaw
                slot.course = course
                return slot
            }
        }

        if let settingsDTO = backup.settings {
            let settings = TimetableSettings()
            settings.termStart = settingsDTO.termStart
            settings.periodCount = settingsDTO.periodCount
            settings.periodStartsRaw = settingsDTO.periodStartsRaw
            context.insert(settings)
        } else if (try? context.fetch(FetchDescriptor<TimetableSettings>()))?.isEmpty ?? true {
            context.insert(TimetableSettings())
        }

        for dto in backup.tarot {
            let draw = DailyTarot(dateKey: dto.dateKey, cardID: dto.cardID, isReversed: dto.isReversed)
            draw.drawnAt = dto.drawnAt
            context.insert(draw)
        }

        for dto in backup.usage {
            let record = DailyUsage(dateKey: dto.dateKey, foregroundSeconds: dto.foregroundSeconds)
            record.updatedAt = dto.updatedAt
            context.insert(record)
        }

        try context.save()
        NotificationCenter.default.post(name: .dataRestored, object: nil)
    }
}

extension Notification.Name {
    static let dataRestored = Notification.Name("cresto.dataRestored")
}
