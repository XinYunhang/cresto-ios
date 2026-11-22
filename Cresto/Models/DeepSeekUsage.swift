import Foundation
import SwiftData

/// 每天一条：DeepSeek API 消耗（余额差值累计）。
/// 0 也存——「有调用但零消耗」和「没采样」是两回事（笔记 07 §6）。
@Model
final class DeepSeekDay {
    /// yyyy-MM-dd，本地时区
    var dateKey: String = ""
    var cost: Double = 0

    init(dateKey: String, cost: Double = 0) {
        self.dateKey = dateKey
        self.cost = cost
    }
}

/// 单行状态：上次采样到的余额与时间，差值累计的锚点。
@Model
final class DeepSeekState {
    var lastBalance: Double? = nil
    var lastCheck: Date? = nil

    init() {}
}

enum DeepSeekStore {
    @discardableResult
    static func state(in context: ModelContext) -> DeepSeekState {
        if let existing = try? context.fetch(FetchDescriptor<DeepSeekState>()).first {
            return existing
        }
        let state = DeepSeekState()
        context.insert(state)
        return state
    }

    /// 一次成功采样 → 差值累计 + 更新锚点 + 210 天窗口清理。
    /// 规则逐条照抄笔记 07 §3（桌面组件已验收）：
    /// bal < last → 今天 += 差值（4 位小数舍入）；bal ≥ last → 只更新 lastBalance。
    @discardableResult
    static func record(_ info: DeepSeekService.BalanceInfo, in context: ModelContext) -> Bool {
        let state = state(in: context)
        let checkDate = Date()

        var didRecordCost = false
        if let total = info.total {
            if let last = state.lastBalance, total < last {
                let delta = floor((last - total) * 10000 + 0.5) / 10000
                if delta > 0 {
                    day(for: checkDate, in: context).cost += delta
                    didRecordCost = true
                }
            }
            state.lastBalance = total
        }
        state.lastCheck = checkDate

        // 本次有采样 → 今天的行必须存在（0 也存）
        _ = day(for: checkDate, in: context)

        prune(in: context)
        try? context.save()

        // 只在真的记到消耗时广播，监听方会去刷新余额展示；
        // 无消耗的采样不广播，避免「刷新→记录→广播→再刷新」死循环
        if didRecordCost {
            NotificationCenter.default.post(name: .deepseekDataUpdated, object: nil)
        }
        return didRecordCost
    }

    /// 有则取，无则建
    @discardableResult
    static func day(for date: Date, in context: ModelContext) -> DeepSeekDay {
        let key = UsageStore.key(for: date)
        let descriptor = FetchDescriptor<DeepSeekDay>(predicate: #Predicate { $0.dateKey == key })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let record = DeepSeekDay(dateKey: key)
        context.insert(record)
        return record
    }

    /// 只保留最近 210 天（30 周窗口），排序后从头删
    static func prune(in context: ModelContext) {
        let keep = 210
        var all = (try? context.fetch(FetchDescriptor<DeepSeekDay>())) ?? []
        all.sort { $0.dateKey < $1.dateKey }
        guard all.count > keep else { return }
        for old in all.prefix(all.count - keep) {
            context.delete(old)
        }
    }
}

/// 一次算完消耗统计：阈值缓存 + 今日/累计，渲染只查表（数据变化时 build 一次）。
struct DeepSeekDigest {
    /// dateKey → cost
    let costs: [String: Double]
    /// 非零消耗的 p40 / p75 / p99 三档阈值
    let thresholds: [Double]
    /// 「今天」的锚点 = lastCheck 的日期，不用渲染时刻的 Date()（防跨天跳格）
    let anchor: Date
    let todayCost: Double
    let totalCost: Double

    static func build(days: [DeepSeekDay], lastCheck: Date?) -> DeepSeekDigest {
        let costs = Dictionary(days.map { ($0.dateKey, $0.cost) }, uniquingKeysWith: { first, _ in first })
        let anchor = lastCheck ?? Date()
        let sorted = costs.values.filter { $0 > 0 }.sorted()

        let thresholds: [Double]
        if sorted.isEmpty {
            thresholds = [0, 0, 0]
        } else {
            let pick = { (p: Double) in sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * p)) - 1)] }
            thresholds = [pick(0.40), pick(0.75), pick(0.99)]
        }

        return DeepSeekDigest(
            costs: costs,
            thresholds: thresholds,
            anchor: anchor,
            todayCost: costs[UsageStore.key(for: anchor)] ?? 0,
            totalCost: costs.values.reduce(0, +)
        )
    }
}

extension Notification.Name {
    static let deepseekDataUpdated = Notification.Name("cresto.deepseekDataUpdated")
}
