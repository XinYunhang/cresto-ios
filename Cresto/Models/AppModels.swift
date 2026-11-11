import SwiftUI

// MARK: - 数据模型

struct FortuneSnapshot {
    struct Metric: Identifiable {
        let id = UUID()
        var label: String
        /// 0...1
        var value: Double
    }

    var score: Int
    var headline: String
    var goodAt: String
    var avoid: String
    var keywords: [String]
    var metrics: [Metric]
}

struct UsageDay: Identifiable {
    let id = UUID()
    var weekday: String
    /// 当天分钟数
    var minutes: Int
    var isToday = false
}

// MARK: - 底栏

enum AppTab: String, CaseIterable, Identifiable {
    case overview, tasks, course, tarot, time

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "概览"
        case .tasks: return "待办"
        case .course: return "课表"
        case .tarot: return "塔罗"
        case .time: return "时间"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .tasks: return "checkmark.circle"
        case .course: return "tablecells"
        case .tarot: return "sparkles"
        case .time: return "calendar"
        }
    }
}
