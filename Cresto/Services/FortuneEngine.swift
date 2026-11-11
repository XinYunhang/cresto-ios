import Foundation

/// 今日运势：**本地确定性生成**。
///
/// 种子 = 生日 + 日期。同一个人的同一天，刷多少次结果都一样；断网也成立。
/// 换一天就换一套。不需要联网、不需要接口、不会因为网络抖动跳到别的星象。
enum FortuneEngine {
    /// 生日（阳历）来自 Resources/profile.plist，不进仓库。
    /// 本地生成：bash scripts/make_profile.sh 2008-06-17
    static var birthday: DateComponents { LocalProfile.birthday }

    static func snapshot(for date: Date = Date(), birthdayOverride: DateComponents? = nil) -> FortuneSnapshot {
        let profile = birthdayOverride ?? birthday
        var rng = SeededGenerator(seed: seed(birthday: profile, date: date))

        // 分数：40...98，偏高一点，别每天都很丧
        let score = 40 + Int.random(in: 0..<59, using: &rng)

        let headline = headlines[scoreBand(score)][Int.random(in: 0..<headlines[scoreBand(score)].count, using: &rng)]

        var goodIndex = Int.random(in: 0..<goods.count, using: &rng)
        var badIndex = Int.random(in: 0..<bads.count, using: &rng)
        if badIndex == goodIndex { badIndex = (badIndex + 3) % bads.count }

        // 关键词：从池子里抽 3 个不重的
        var pool = keywords
        var picked: [String] = []
        for _ in 0..<3 where !pool.isEmpty {
            picked.append(pool.remove(at: Int.random(in: 0..<pool.count, using: &rng)))
        }

        // 四维：以总分为中心上下浮动，避免「总分高但各项都低」的割裂
        let base = Double(score) / 100
        let labels = ["事业", "感情", "财运", "健康"]
        let metrics = labels.map { label -> FortuneSnapshot.Metric in
            let delta = Double(Int.random(in: -18...18, using: &rng)) / 100
            let value = min(0.97, max(0.28, base + delta))
            return .init(label: label, value: value)
        }

        return FortuneSnapshot(
            score: score,
            headline: headline,
            goodAt: goods[goodIndex],
            avoid: bads[badIndex],
            keywords: picked,
            metrics: metrics
        )
    }

    // MARK: 种子

    static func seed(birthday: DateComponents, date: Date) -> UInt64 {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let key = "\(birthday.year ?? 0)-\(birthday.month ?? 0)-\(birthday.day ?? 0)"
            + "|"
            + "\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"

        // FNV-1a
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01B3
        }
        return hash
    }

    private static func scoreBand(_ score: Int) -> Int {
        switch score {
        case ..<55: return 0
        case 55..<70: return 1
        case 70..<85: return 2
        default: return 3
        }
    }

    // MARK: 词库

    private static let headlines: [[String]] = [
        ["低空飞行", "缓一缓", "先照顾好自己", "不必用力"],
        ["稳中有进", "慢就是快", "把小事做顺", "收着点劲"],
        ["渐入佳境", "顺水推舟", "状态回来了", "可以往前一步"],
        ["高光时刻", "势如破竹", "今天适合推进", "别浪费这口气"]
    ]

    private static let keywords = [
        "专注", "沟通", "慢一点", "复盘", "早睡", "运动", "留白",
        "记录", "拒绝", "整理", "独处", "表达", "边界", "耐心",
        "断舍离", "出门", "晒太阳", "喝水", "先做五分钟"
    ]

    private static let goods = [
        "复盘", "推进难事", "当面沟通", "整理桌面", "早睡", "运动",
        "写下来", "拒绝一次", "散步", "读完一章", "把话说明白", "清空收件箱"
    ]

    private static let bads = [
        "拖延", "熬夜", "过度承诺", "情绪化回复", "多线程开工", "冲动消费",
        "翻旧账", "硬扛", "临时改计划", "追完一整季", "边吃边刷视频"
    ]
}

/// SplitMix64：小而稳，适合当确定性种子用
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
