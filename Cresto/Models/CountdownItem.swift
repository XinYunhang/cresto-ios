import Foundation
import SwiftData
import SwiftUI

/// 倒数日主题强调色
enum CountdownAccent: String, Codable, CaseIterable, Identifiable {
    case indigo, amber, emerald, coral, violet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .indigo: return "靛蓝"
        case .amber: return "琥珀"
        case .emerald: return "翠绿"
        case .coral: return "珊瑚"
        case .violet: return "紫罗兰"
        }
    }

    var color: Color {
        switch self {
        case .indigo: return Theme.brand
        case .amber: return Color(hex: 0xF59E0B)
        case .emerald: return Color(hex: 0x2FB356)
        case .coral: return Color(hex: 0xF43F5E)
        case .violet: return Color(hex: 0x8B5CF6)
        }
    }
}

/// 多倒数日模型：支持任意标题、任意日期（过去/今天/未来）与自定义强调色。
@Model
final class CountdownItem {
    var id: UUID = UUID()
    var title: String = ""
    var targetDate: Date = Date()
    var accentRaw: String = "indigo"
    var isPinnedToHome: Bool = false
    var createdAt: Date = Date()

    init(
        title: String = "",
        targetDate: Date = Date(),
        accent: CountdownAccent = .indigo,
        isPinnedToHome: Bool = false
    ) {
        self.title = title
        self.targetDate = targetDate
        self.accentRaw = accent.rawValue
        self.isPinnedToHome = isPinnedToHome
        self.createdAt = Date()
    }

    var accent: CountdownAccent {
        CountdownAccent(rawValue: accentRaw) ?? .indigo
    }

    /// 距目标日期天数：>0 还有几天，0 今天，<0 已过去几天
    func daysRemaining(from now: Date = Date(), calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: targetDate)
        return calendar.dateComponents([.day], from: start, to: target).day ?? 0
    }

    var targetDateText: String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: targetDate)
        return "\(c.year ?? 2026)年\(c.month ?? 1)月\(c.day ?? 1)日"
    }

    var shortDateText: String {
        let c = Calendar.current.dateComponents([.month, .day], from: targetDate)
        return "\(c.month ?? 1)月\(c.day ?? 1)日"
    }
}
