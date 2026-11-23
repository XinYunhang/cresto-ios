import Foundation
import SwiftData

// MARK: - 枚举

enum BillingCycle: String, Codable, CaseIterable, Identifiable {
    case weekly, monthly, quarterly, yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekly: return "每周"
        case .monthly: return "每月"
        case .quarterly: return "每季"
        case .yearly: return "每年"
        }
    }

    /// 表单胶囊用的短标题
    var shortTitle: String {
        switch self {
        case .weekly: return "周"
        case .monthly: return "月"
        case .quarterly: return "季"
        case .yearly: return "年"
        }
    }

    /// 折算月均的系数
    var monthlyFactor: Double {
        switch self {
        case .weekly: return 52.0 / 12.0
        case .monthly: return 1
        case .quarterly: return 1.0 / 3.0
        case .yearly: return 1.0 / 12.0
        }
    }

    /// 周期天数（进度条用，近似值即可）
    var approximateDays: Double {
        switch self {
        case .weekly: return 7
        case .monthly: return 30.44
        case .quarterly: return 91.31
        case .yearly: return 365.25
        }
    }

    var monthStep: Int? {
        switch self {
        case .weekly: return nil
        case .monthly: return 1
        case .quarterly: return 3
        case .yearly: return 12
        }
    }
}

enum SubscriptionCurrency: String, Codable, CaseIterable, Identifiable {
    case USD, CNY

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .USD: return "$"
        case .CNY: return "¥"
        }
    }

    var title: String { rawValue }
}

enum PaymentMethod: String, Codable, CaseIterable, Identifiable {
    case visa, appleID, alipay, wechat, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .visa: return "Visa"
        case .appleID: return "Apple ID"
        case .alipay: return "支付宝"
        case .wechat: return "微信"
        case .other: return "其他"
        }
    }
}

enum SubscriptionCategory: String, Codable, CaseIterable, Identifiable {
    case ai, media, cloud, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ai: return "AI 工具"
        case .media: return "影音"
        case .cloud: return "云服务"
        case .other: return "其他"
        }
    }
}

// MARK: - 数据模型

@Model
final class Subscription {
    var id: UUID = UUID()
    var name: String = ""
    var price: Double = 0
    var currencyRaw: String = "USD"
    var cycleRaw: String = "monthly"
    /// 下一次（或最近一次）扣费日；过期后由同步逻辑按锚定日顺延
    var nextChargeDate: Date = Date()
    /// 锚定日：首次扣费日的日号（1~31），用于大小月防漂移
    var anchorDay: Int = 1
    var paymentRaw: String = "visa"
    var categoryRaw: String = "other"
    var brandRaw: String = "generic"
    var isPaused: Bool = false
    var remindEnabled: Bool = true
    var remindDaysBefore: Int = 3
    /// 已提醒的扣费周期标记（yyyy-MM-dd），保证同一周期只生成一条待办
    var lastRemindedCycleKey: String = ""
    var createdAt: Date = Date()

    init(
        name: String = "",
        price: Double = 0,
        currency: SubscriptionCurrency = .USD,
        cycle: BillingCycle = .monthly,
        nextChargeDate: Date = Date(),
        payment: PaymentMethod = .visa,
        category: SubscriptionCategory = .other,
        brand: BrandIcon = .generic,
        isPaused: Bool = false,
        remindEnabled: Bool = true,
        remindDaysBefore: Int = 3
    ) {
        self.name = name
        self.price = price
        self.currencyRaw = currency.rawValue
        self.cycleRaw = cycle.rawValue
        self.nextChargeDate = nextChargeDate
        self.anchorDay = max(1, Calendar.current.component(.day, from: nextChargeDate))
        self.paymentRaw = payment.rawValue
        self.categoryRaw = category.rawValue
        self.brandRaw = brand.rawValue
        self.isPaused = isPaused
        self.remindEnabled = remindEnabled
        self.remindDaysBefore = remindDaysBefore
        self.createdAt = Date()
    }

    var currency: SubscriptionCurrency { SubscriptionCurrency(rawValue: currencyRaw) ?? .USD }
    var cycle: BillingCycle { BillingCycle(rawValue: cycleRaw) ?? .monthly }
    var payment: PaymentMethod { PaymentMethod(rawValue: paymentRaw) ?? .visa }
    var category: SubscriptionCategory { SubscriptionCategory(rawValue: categoryRaw) ?? .other }
    var brand: BrandIcon { BrandIcon.from(raw: brandRaw) }

    var priceText: String { String(format: "%.2f", price) }
    var displayPrice: String { "\(currency.symbol)\(priceText)" }

    /// 折算月均（原币种）
    var monthlyEquivalent: Double { price * cycle.monthlyFactor }

    /// 折算月均（人民币）
    func monthlyCNY(rate: Double) -> Double {
        currency == .USD ? monthlyEquivalent * rate : monthlyEquivalent
    }

    /// 原币 → 人民币（用于卡片 ≈ 行）
    func cny(rate: Double) -> Double {
        currency == .USD ? price * rate : price
    }
}

// MARK: - 日期算法（锚定日顺延，防大小月漂移）

enum SubscriptionMath {
    /// 在 date 基础上按周期前进/后退 steps 个周期。
    /// 月/季/年始终按 `anchorDay` 生成目标月份的“有效日”：
    /// 1 月 31 日 → 2 月 28/29 日 → 3 月 31 日（不永久漂移）。
    static func advance(
        _ date: Date,
        cycle: BillingCycle,
        anchorDay: Int,
        by steps: Int,
        calendar: Calendar = .current
    ) -> Date {
        if cycle == .weekly {
            return calendar.date(byAdding: .day, value: 7 * steps, to: date) ?? date
        }
        guard let monthStep = cycle.monthStep else { return date }
        let comps = calendar.dateComponents([.year, .month, .hour, .minute], from: date)
        guard let monthStart = calendar.date(from: DateComponents(year: comps.year, month: comps.month, day: 1)),
              let targetMonth = calendar.date(byAdding: .month, value: monthStep * steps, to: monthStart),
              let dayRange = calendar.range(of: .day, in: .month, for: targetMonth) else {
            return date
        }
        let day = min(max(1, anchorDay), dayRange.count)
        var targetComps = calendar.dateComponents([.year, .month], from: targetMonth)
        targetComps.day = day
        targetComps.hour = comps.hour ?? 9
        targetComps.minute = comps.minute ?? 0
        return calendar.date(from: targetComps) ?? date
    }

    /// 下一次扣费日（从今天起算；已暂停则原样返回）
    static func upcomingCharge(for sub: Subscription, now: Date = Date(), calendar: Calendar = .current) -> Date {
        guard !sub.isPaused else { return sub.nextChargeDate }
        let today = calendar.startOfDay(for: now)
        var date = sub.nextChargeDate
        var guardCount = 0
        while calendar.startOfDay(for: date) < today, guardCount < 400 {
            date = advance(date, cycle: sub.cycle, anchorDay: sub.anchorDay, by: 1, calendar: calendar)
            guardCount += 1
        }
        return date
    }

    /// 距离下次扣费还有几天（暂停返回 nil）
    static func daysRemaining(for sub: Subscription, now: Date = Date(), calendar: Calendar = .current) -> Int? {
        guard !sub.isPaused else { return nil }
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: upcomingCharge(for: sub, now: now, calendar: calendar))
        return calendar.dateComponents([.day], from: today, to: target).day
    }

    /// 当前计费周期已消耗比例 0...1（进度条）
    static func cycleProgress(for sub: Subscription, now: Date = Date(), calendar: Calendar = .current) -> Double {
        guard !sub.isPaused, let remaining = daysRemaining(for: sub, now: now, calendar: calendar) else { return 0 }
        let length = max(1, sub.cycle.approximateDays)
        let fraction = 1 - (Double(max(0, remaining)) / length)
        return min(1, max(0, fraction))
    }

    /// 某订阅在指定月份内的扣费发生日（用于月历圆点与按日筛选）
    static func occurrences(
        for sub: Subscription,
        inMonthOf monthDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [Date] {
        guard !sub.isPaused else { return [] }
        guard let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: monthDate)),
              let monthEnd = calendar.date(byAdding: .month, value: 1, to: monthStart) else { return [] }

        var date = upcomingCharge(for: sub, now: now, calendar: calendar)
        var guardCount = 0
        while date >= monthEnd, guardCount < 400 {
            date = advance(date, cycle: sub.cycle, anchorDay: sub.anchorDay, by: -1, calendar: calendar)
            guardCount += 1
        }
        var result: [Date] = []
        while date >= monthStart, guardCount < 800 {
            result.append(date)
            date = advance(date, cycle: sub.cycle, anchorDay: sub.anchorDay, by: -1, calendar: calendar)
            guardCount += 1
        }
        return result.reversed()
    }
}

// MARK: - 列表排序 / 筛选

enum SubscriptionFilter: String, CaseIterable, Identifiable {
    case all, ai, media, cloud, paused

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .ai: return "AI 工具"
        case .media: return "影音"
        case .cloud: return "云服务"
        case .paused: return "已暂停"
        }
    }
}

extension Subscription {
    /// 生效中按剩余天数升序，已暂停排末尾
    static func sortedForDisplay(_ list: [Subscription], now: Date = Date()) -> [Subscription] {
        let active = list.filter { !$0.isPaused }.sorted {
            (SubscriptionMath.daysRemaining(for: $0, now: now) ?? 9999)
                < (SubscriptionMath.daysRemaining(for: $1, now: now) ?? 9999)
        }
        let paused = list.filter { $0.isPaused }.sorted { $0.name < $1.name }
        return active + paused
    }
}