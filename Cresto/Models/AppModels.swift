import SwiftUI

// MARK: - 功能开关

/// 全局开关。DeepSeek 相关 UI 默认隐藏：
/// 底层服务（DeepSeekService/TariffClock/DeepSeekUsage）、Keychain、备份通道全部完整保留，
/// 仅隐藏入口并停止自动轮询；把开关切回 true 即无损恢复。
enum FeatureFlags {
    static let enableDeepSeek = false
}

// MARK: - 底栏

enum AppTab: String, CaseIterable, Identifiable {
    case tasks, course, overview, ledger, memories, api

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tasks: return "待办"
        case .course: return "课表"
        case .overview: return "概览"
        case .ledger: return "订阅"
        case .memories: return "纪念"
        case .api: return "API"
        }
    }

    var reicon: Reicon {
        switch self {
        case .tasks: return .checkCircle
        case .course: return .calendarDays
        case .overview: return .grid
        case .ledger: return .wallet
        case .memories: return .star
        case .api: return .cpu
        }
    }

    /// 底栏实际展示的 Tab：DeepSeek 关闭时保持「待办 | 课表 | 概览(中) | 订阅 | 纪念」5 图标布局
    static var visible: [AppTab] {
        allCases.filter { $0 != .api || FeatureFlags.enableDeepSeek }
    }
}
