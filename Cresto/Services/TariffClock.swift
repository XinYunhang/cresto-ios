import SwiftUI
import Foundation

/// DeepSeek 峰谷价格时段。规则是官方定价文档里的**文案**，不是接口——
/// 官方改版只改 `TariffRules` 这一张表，设置页放有定价页链接。
///
/// 判定永远按北京时间算，与设备时区无关；纯本地时钟，零 API 调用。
/// 现行规则（2026 起，V4 系列）：工作日 9–12 时、14–18 时为峰顶，
/// 其余时段 + 周末全天为峰谷，峰价 = 谷价 × 2。
enum TariffRules {
    static let timeZone = TimeZone(identifier: "Asia/Shanghai")!
    /// 峰顶时段（24 小时制，半开区间），仅工作日生效
    static let peakHours: [(Int, Int)] = [(9, 12), (14, 18)]
    static let pricingURL = URL(string: "https://api-docs.deepseek.com/zh-cn/quick_start/pricing")!
}

enum TariffPeriod {
    case peak
    case valley

    var label: String {
        switch self {
        case .peak: return "峰顶时段"
        case .valley: return "峰谷时段"
        }
    }

    /// 颜色是功能（一眼分辨贵不贵），不是装饰：谷 = 清透青绿，峰 = 温和琥珀。
    /// 低饱和、深浅主题各一版，与课程配色同一套做法。
    var bg: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? (self == .peak ? UIColor(rgb: 0x3D3222) : UIColor(rgb: 0x1E3A33))
                : (self == .peak ? UIColor(rgb: 0xF7ECD9) : UIColor(rgb: 0xDDF0E8))
        })
    }

    var fg: Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? (self == .peak ? UIColor(rgb: 0xE8C07A) : UIColor(rgb: 0x7FD6BC))
                : (self == .peak ? UIColor(rgb: 0x8A5A2B) : UIColor(rgb: 0x2E6E5E))
        })
    }
}

struct TariffMoment {
    let period: TariffPeriod
    /// 周末全天谷价
    let isWeekend: Bool
    /// 距下一次峰谷切换的秒数（> 0）
    let secondsUntilSwitch: TimeInterval
    /// 切换后进入的时段
    let nextPeriod: TariffPeriod
}

enum TariffClock {
    /// 北京时间日历
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TariffRules.timeZone
        return calendar
    }

    static func moment(now: Date = Date()) -> TariffMoment {
        let calendar = calendar
        let weekday = calendar.component(.weekday, from: now) // 1 = 周日
        let isWeekend = weekday == 1 || weekday == 7
        let period = isWeekend ? TariffPeriod.valley : period(for: calendar.component(.hour, from: now))
        let next = nextBoundary(after: now, calendar: calendar, current: period)
        return TariffMoment(
            period: period,
            isWeekend: isWeekend,
            secondsUntilSwitch: max(0, next.0.timeIntervalSince(now)),
            nextPeriod: next.1
        )
    }

    /// 北京时间 HH:mm
    static func clockText(now: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TariffRules.timeZone
        return formatter.string(from: now)
    }

    /// 当前时刻在 24 小时里的位置（0...1，按北京时间）
    static func dayFraction(now: Date) -> Double {
        let calendar = calendar
        let start = calendar.startOfDay(for: now)
        return min(1, max(0, now.timeIntervalSince(start) / 86400))
    }

    // MARK: 私有

    private static func period(for hour: Int) -> TariffPeriod {
        TariffRules.peakHours.contains { start, end in hour >= start && hour < end } ? .peak : .valley
    }

    /// 向前扫候选切换点：只有工作日的 9/12/14/18 整点会切换时段，周末全天谷价。
    private static func nextBoundary(after now: Date, calendar: Calendar, current: TariffPeriod) -> (Date, TariffPeriod) {
        var day = calendar.startOfDay(for: now)
        for _ in 0..<10 {
            let weekday = calendar.component(.weekday, from: day)
            if weekday != 1 && weekday != 7 {
                for (start, _) in TariffRules.peakHours {
                    if let atPeakStart = date(day: day, hour: start, calendar: calendar), atPeakStart > now {
                        return (atPeakStart, .peak)
                    }
                }
                for (start, end) in TariffRules.peakHours {
                    if let atPeakEnd = date(day: day, hour: end, calendar: calendar), atPeakEnd > now {
                        return (atPeakEnd, .valley)
                    }
                }
            }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }
        // 兜底：理论上到不了（10 天内必有切换点）
        return (now, current)
    }

    private static func date(day: Date, hour: Int, calendar: Calendar) -> Date? {
        var components = DateComponents()
        components.hour = hour
        return calendar.date(byAdding: components, to: day)
    }
}
