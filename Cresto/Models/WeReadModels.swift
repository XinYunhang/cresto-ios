import Foundation
import SwiftData
import SwiftUI

/// 微信读书每日阅读分钟数（本地缓存，纳入备份体系）。
@Model
final class WeReadDay {
    /// yyyy-MM-dd，本地时区
    var dateKey: String = ""
    var minutes: Int = 0
    var updatedAt: Date = Date()

    init(dateKey: String, minutes: Int = 0) {
        self.dateKey = dateKey
        self.minutes = minutes
        self.updatedAt = Date()
    }
}

/// 「正在读」单书缓存（只保留 1 本）。
@Model
final class WeReadBook {
    var title: String = ""
    var author: String = ""
    var coverURL: String = ""
    /// 0...1
    var progress: Double = 0
    var updatedAt: Date = Date()

    init() {}

    var progressPercent: Int {
        Int((min(1, max(0, progress)) * 100).rounded())
    }
}

// MARK: - 同步快照（服务层产物）

struct WeReadSnapshot {
    struct Day {
        let dateKey: String
        let minutes: Int
    }

    struct Book {
        let title: String
        let author: String
        let coverURL: String
        /// 0...1
        let progress: Double
    }

    let days: [Day]
    let book: Book?
}

// MARK: - 写入 / 清理

enum WeReadStore {
    /// 一次成功拉取后落库：按 dateKey upsert 每日分钟数，单书整体覆盖；保留 60 天
    static func apply(_ snapshot: WeReadSnapshot, in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<WeReadDay>())) ?? []
        var byKey = Dictionary(existing.map { ($0.dateKey, $0) }, uniquingKeysWith: { first, _ in first })

        for day in snapshot.days {
            if let record = byKey[day.dateKey] {
                record.minutes = max(0, day.minutes)
                record.updatedAt = Date()
            } else {
                let record = WeReadDay(dateKey: day.dateKey, minutes: max(0, day.minutes))
                context.insert(record)
                byKey[day.dateKey] = record
            }
        }

        if let book = snapshot.book {
            let record = (try? context.fetch(FetchDescriptor<WeReadBook>()))?.first ?? {
                let created = WeReadBook()
                context.insert(created)
                return created
            }()
            record.title = book.title
            record.author = book.author
            record.coverURL = book.coverURL
            record.progress = min(1, max(0, book.progress))
            record.updatedAt = Date()
        }

        prune(in: context)
        try? context.save()
        NotificationCenter.default.post(name: .wereadDataUpdated, object: nil)
    }

    /// 只保留最近 60 天
    static func prune(in context: ModelContext) {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -60, to: Date()) else { return }
        let cutoffKey = UsageStore.key(for: cutoff)
        let all = (try? context.fetch(FetchDescriptor<WeReadDay>())) ?? []
        for old in all where old.dateKey < cutoffKey {
            context.delete(old)
        }
    }
}

extension Notification.Name {
    static let wereadDataUpdated = Notification.Name("cresto.wereadDataUpdated")
}

// MARK: - 近 30 天热力图数据（一次算好，渲染只查表）

struct WeReadDigest {
    struct Day: Identifiable {
        let id: String
        let date: Date
        let minutes: Int
        let level: Int
    }

    let days: [Day]

    /// 固定近 30 天、按时间正序（左上最早 → 第 5 行前两格最新）
    static func build(cached: [WeReadDay], endingAt date: Date = Date()) -> WeReadDigest {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: date)
        let byKey = Dictionary(cached.map { ($0.dateKey, $0.minutes) }, uniquingKeysWith: { first, _ in first })

        var days: [Day] = []
        for offset in stride(from: 29, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let key = UsageStore.key(for: day)
            let minutes = max(0, byKey[key] ?? 0)
            days.append(Day(id: key, date: day, minutes: minutes, level: level(minutes: minutes)))
        }
        return WeReadDigest(days: days)
    }

    /// 五档：0 无阅读；1-14 / 15-29 / 30-59 / ≥60 分钟
    static func level(minutes: Int) -> Int {
        switch minutes {
        case ..<1: return 0
        case 1...14: return 1
        case 15...29: return 2
        case 30...59: return 3
        default: return 4
        }
    }
}

// MARK: - 热力配色（5 档：未点亮暗槽 + 翠绿 4 阶梯度）

enum WeReadHeat {
    static let green = Color(hex: 0x2FB356)

    static func color(level: Int) -> Color {
        switch level {
        case 0: return Theme.surfaceWell                 // 未点亮暗槽
        case 1: return green.opacity(0.24)
        case 2: return green.opacity(0.46)
        case 3: return green.opacity(0.70)
        default: return green.opacity(0.95)
        }
    }
}