import Foundation
import SwiftData

/// SwiftData 容器与持久化加固：
/// · 显式存入 `Documents/CrestoData/cresto.store`（关闭隐式 CloudKit，避免容器检查触发空库重建）
/// · 首次启用自动从旧默认路径 `Application Support/default.store`（含 -wal/-shm）无损迁移
/// · 统一 `save(_:source:)` 错误日志与启动诊断日志，杜绝静默丢数
enum Persistence {
    static let schema = Schema([
        TaskItem.self,
        Subtask.self,
        Course.self,
        CourseSlot.self,
        TimetableSettings.self,
        DailyUsage.self,
        DeepSeekDay.self,
        DeepSeekState.self,
        WeReadDay.self,
        WeReadBook.self,
        Subscription.self,
        CountdownItem.self
    ])

    static var storeDirectory: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("CrestoData", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static var storeURL: URL {
        storeDirectory.appendingPathComponent("cresto.store")
    }

    static func migrateLegacyStoreIfNeeded() {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: storeURL.path) else { return }
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }

        let legacyBase = appSupport.appendingPathComponent("default.store")
        guard fm.fileExists(atPath: legacyBase.path) else { return }

        let suffixes = ["", "-wal", "-shm"]
        for suffix in suffixes {
            let src = URL(fileURLWithPath: legacyBase.path + suffix)
            let dst = URL(fileURLWithPath: storeURL.path + suffix)
            guard fm.fileExists(atPath: src.path) else { continue }
            do {
                try fm.copyItem(at: src, to: dst)
            } catch {
                AppLog.error("迁移旧库文件失败 [\(src.lastPathComponent)]：\(error.localizedDescription)")
            }
        }
        AppLog.info("已将旧数据库迁移至 Documents/CrestoData/cresto.store")
    }

    static func makeContainer() -> ModelContainer {
        migrateLegacyStoreIfNeeded()
        let config = ModelConfiguration(
            "Cresto",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            AppLog.error("SwiftData 容器创建失败：\(error.localizedDescription)")
            fatalError("SwiftData 容器创建失败：\(error)")
        }
    }

    static func save(_ context: ModelContext, source: String) {
        do {
            try context.save()
        } catch {
            AppLog.error("保存失败 [\(source)]：\(error.localizedDescription)")
        }
    }

    static func logLaunchDiagnostics(in context: ModelContext) {
        let tasks = (try? context.fetchCount(FetchDescriptor<TaskItem>())) ?? -1
        let courses = (try? context.fetchCount(FetchDescriptor<Course>())) ?? -1
        let subs = (try? context.fetchCount(FetchDescriptor<Subscription>())) ?? -1
        let countdowns = (try? context.fetchCount(FetchDescriptor<CountdownItem>())) ?? -1

        let storeBytes: Int = {
            let attrs = try? FileManager.default.attributesOfItem(atPath: storeURL.path)
            return (attrs?[.size] as? NSNumber)?.intValue ?? 0
        }()
        let kb = String(format: "%.1f", Double(storeBytes) / 1024.0)
        AppLog.info("库诊断 \(kb)KB · 待办\(tasks) 课\(courses) 订阅\(subs) 倒数\(countdowns)")
    }
}
