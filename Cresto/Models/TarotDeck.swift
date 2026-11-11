import Foundation
import SwiftData

// MARK: - 牌

struct TarotCard: Identifiable, Hashable {
    let id: Int
    /// 卡面资源名（Resources/Cards 里的文件名，不带扩展名）
    let slug: String
    let name: String
    let en: String
    let roman: String

    let uprightKeywords: [String]
    let reversedKeywords: [String]
    let uprightText: String
    let reversedText: String

    func keywords(reversed: Bool) -> [String] { reversed ? reversedKeywords : uprightKeywords }
    func text(reversed: Bool) -> String { reversed ? reversedText : uprightText }
    func positionText(reversed: Bool) -> String { reversed ? "逆位" : "正位" }
}

/// 22 张大阿尔卡那。牌义是这个 App 自己的简短版本，不是照抄书上的长文。
enum TarotDeck {
    static let major: [TarotCard] = [
        .init(id: 0, slug: "00-fool", name: "愚者", en: "The Fool", roman: "0",
              uprightKeywords: ["全新开始", "勇气", "不必完美"],
              reversedKeywords: ["鲁莽", "犹豫", "准备不足"],
              uprightText: "带着还没准备好的一切出发。今天的关键是「先动」，方向可以在路上修正。",
              reversedText: "要么太冲动，要么一直等一个完美的时机。先问自己到底在怕什么。"),

        .init(id: 1, slug: "01-magician", name: "魔术师", en: "The Magician", roman: "I",
              uprightKeywords: ["行动力", "资源", "表达"],
              reversedKeywords: ["华而不实", "拖延", "自我怀疑"],
              uprightText: "手上的资源比你感觉的多。今天适合把一个想法变成具体动作，哪怕只做第一步。",
              reversedText: "想法很多，落地的很少。检查一下是不是用「再准备一下」掩盖了不敢开始。"),

        .init(id: 2, slug: "02-high-priestess", name: "女祭司", en: "The High Priestess", roman: "II",
              uprightKeywords: ["直觉", "内在", "保留"],
              reversedKeywords: ["忽视直觉", "信息不明", "自我封闭"],
              uprightText: "答案还在水面下。今天少说多听，直觉给的信号比道理可靠。",
              reversedText: "你在忽略那个早就知道答案的声音。也可能信息还不够，别急着下结论。"),

        .init(id: 3, slug: "03-empress", name: "皇后", en: "The Empress", roman: "III",
              uprightKeywords: ["滋养", "丰盛", "身体"],
              reversedKeywords: ["过度付出", "停滞", "忽略自己"],
              uprightText: "适合把生活过得具体一点：好好吃饭、好好休息。今天的好运来自「照顾」。",
              reversedText: "付出过头了。先把自己喂饱，再谈照顾别人。"),

        .init(id: 4, slug: "04-emperor", name: "皇帝", en: "The Emperor", roman: "IV",
              uprightKeywords: ["秩序", "边界", "掌控"],
              reversedKeywords: ["僵化", "控制欲", "失去弹性"],
              uprightText: "建立秩序的一天。定规则、划边界，把混乱收进框架里。",
              reversedText: "过度控制会让事情更僵。有些事放一放，反而自己会顺。"),

        .init(id: 5, slug: "05-hierophant", name: "教皇", en: "The Hierophant", roman: "V",
              uprightKeywords: ["传承", "规则", "请教"],
              reversedKeywords: ["形式主义", "反叛", "照搬"],
              uprightText: "向有经验的人请教，或者按已经验证过的流程走。今天不适合标新立异。",
              reversedText: "形式大于内容。或者你想反抗的，其实是自己给自己定的规矩。"),

        .init(id: 6, slug: "06-lovers", name: "恋人", en: "The Lovers", roman: "VI",
              uprightKeywords: ["选择", "关系", "一致"],
              reversedKeywords: ["摇摆", "失衡", "表面和谐"],
              uprightText: "今天绕不开一个选择。选那个让你更完整的方向，而不是更安全的。",
              reversedText: "摇摆本身就是消耗。先承认你其实已经偏向一边了。"),

        .init(id: 7, slug: "07-chariot", name: "战车", en: "The Chariot", roman: "VII",
              uprightKeywords: ["推进", "意志", "专注一件事"],
              reversedKeywords: ["失控", "方向不明", "用力过猛"],
              uprightText: "把注意力收到一件事上，推到能看见结果为止。方向比速度重要。",
              reversedText: "同时抓太多头，或者被情绪带着跑。先停下来对一次方向。"),

        .init(id: 8, slug: "08-strength", name: "力量", en: "Strength", roman: "VIII",
              uprightKeywords: ["耐心", "温柔的坚定", "承认脆弱"],
              reversedKeywords: ["自我怀疑", "急躁", "硬撑"],
              uprightText: "不是硬扛，是耐心。今天用温和的方式处理最难的那件事。",
              reversedText: "自我怀疑在消耗你。你比自己以为的更有余量。"),

        .init(id: 9, slug: "09-hermit", name: "隐者", en: "The Hermit", roman: "IX",
              uprightKeywords: ["独处", "内省", "提灯"],
              reversedKeywords: ["封闭", "逃避", "孤立"],
              uprightText: "需要独处。今天减少输入，把注意力收回到自己身上。",
              reversedText: "关得太久了。找一个能说真话的人，聊十分钟就够。"),

        .init(id: 10, slug: "10-wheel-of-fortune", name: "命运之轮", en: "Wheel of Fortune", roman: "X",
              uprightKeywords: ["转机", "周期", "顺势"],
              reversedKeywords: ["卡在循环里", "时机未到", "重复犯错"],
              uprightText: "事情自己在转，你不需要用力推。顺着已经出现的势头走。",
              reversedText: "卡在同一个循环里。这次换一个完全不同的做法，哪怕看起来不合理。"),

        .init(id: 11, slug: "11-justice", name: "正义", en: "Justice", roman: "XI",
              uprightKeywords: ["权衡", "因果", "诚实"],
              reversedKeywords: ["偏颇", "逃避责任", "标准动摇"],
              uprightText: "该算账了。把事实摆清楚，做那个不讨喜但正确的决定。",
              reversedText: "标准在动摇，或者你在回避自己该负的那部分。"),

        .init(id: 12, slug: "12-hanged-man", name: "倒吊人", en: "The Hanged Man", roman: "XII",
              uprightKeywords: ["暂停", "换视角", "放手"],
              reversedKeywords: ["无谓牺牲", "拖延", "钻牛角尖"],
              uprightText: "暂停不是失败。换个角度，你会发现卡住的地方本来就不必硬闯。",
              reversedText: "无谓的牺牲，或者用「再等等」拖延那个早该做的决定。"),

        .init(id: 13, slug: "13-death", name: "死神", en: "Death", roman: "XIII",
              uprightKeywords: ["结束", "清理", "重生"],
              reversedKeywords: ["抗拒结束", "抓着不放", "拖长痛苦"],
              uprightText: "某件事该结束了。让它结束，才有位置放新的东西。",
              reversedText: "明知该放手却抓着不放。拖得越久，代价越大。"),

        .init(id: 14, slug: "14-temperance", name: "节制", en: "Temperance", roman: "XIV",
              uprightKeywords: ["平衡", "调配", "节奏"],
              reversedKeywords: ["失衡", "过度", "走极端"],
              uprightText: "调配比例的一天。工作与休息、投入与留白，找回中间那条线。",
              reversedText: "过度了。某件事占的比例已经明显失衡。"),

        .init(id: 15, slug: "15-devil", name: "恶魔", en: "The Devil", roman: "XV",
              uprightKeywords: ["欲望", "束缚", "习惯"],
              reversedKeywords: ["松绑", "看清", "戒断"],
              uprightText: "被某个欲望或习惯绑住的感觉。先看清它到底给了你什么好处。",
              reversedText: "束缚在松动。你已经能看见绳子的另一头了。"),

        .init(id: 16, slug: "16-tower", name: "塔", en: "The Tower", roman: "XVI",
              uprightKeywords: ["崩塌", "真相", "重建"],
              reversedKeywords: ["勉强维持", "延迟的崩", "自我欺骗"],
              uprightText: "旧结构在塌。别急着扶，塌掉的那部分本来就不结实。",
              reversedText: "勉力维持一个已经不适合的东西。拖下去只会让崩塌更晚、更响。"),

        .init(id: 17, slug: "17-star", name: "星星", en: "The Star", roman: "XVII",
              uprightKeywords: ["希望", "疗愈", "长远"],
              reversedKeywords: ["失去信心", "看不见进展", "过度理想化"],
              uprightText: "希望回来了。今天做的那些看起来没用的小事，正在把方向一点点照亮。",
              reversedText: "信心暂时掉了。允许自己丧一会儿，但别停。"),

        .init(id: 18, slug: "18-moon", name: "月亮", en: "The Moon", roman: "XVIII",
              uprightKeywords: ["模糊", "直觉", "别下结论"],
              reversedKeywords: ["迷雾散去", "真相浮现", "松了一口气"],
              uprightText: "雾很大，判断容易受情绪影响。今天别下最终结论。",
              reversedText: "雾在散。你担心的那件事，明天再看会清楚很多。"),

        .init(id: 19, slug: "19-sun", name: "太阳", en: "The Sun", roman: "XIX",
              uprightKeywords: ["明朗", "成果", "直接"],
              reversedKeywords: ["被遮住的乐观", "延迟", "过度乐观"],
              uprightText: "明朗、直接、有结果的一天。适合把事摊开来说。",
              reversedText: "乐观被云遮住了一点。事情在往好的方向走，只是没那么快。"),

        .init(id: 20, slug: "20-judgement", name: "审判", en: "Judgement", roman: "XX",
              uprightKeywords: ["复盘", "召唤", "做决定"],
              reversedKeywords: ["迟迟不决", "自我批判", "回避"],
              uprightText: "一次复盘和召唤。回头看，然后决定要不要继续。",
              reversedText: "迟迟不给自己一个结论。今天先做选择，哪怕选错。"),

        .init(id: 21, slug: "21-world", name: "世界", en: "The World", roman: "XXI",
              uprightKeywords: ["完成", "整合", "告一段落"],
              reversedKeywords: ["差最后一步", "不想结束", "未收尾"],
              uprightText: "一个阶段完成了。允许自己承认「做完了」，再谈下一件。",
              reversedText: "差最后一步。检查一下是不是因为不想结束而拖着。")
    ]

    static func card(id: Int) -> TarotCard {
        major.first { $0.id == id } ?? major[0]
    }
}

// MARK: - 每日一抽

@Model
final class DailyTarot {
    /// yyyy-MM-dd，一天一条
    var dateKey: String = ""
    var cardID: Int = 0
    var isReversed: Bool = false
    var drawnAt: Date = Date()

    init(dateKey: String, cardID: Int, isReversed: Bool) {
        self.dateKey = dateKey
        self.cardID = cardID
        self.isReversed = isReversed
        self.drawnAt = Date()
    }

    var card: TarotCard { TarotDeck.card(id: cardID) }
}

enum TarotService {
    static var todayKey: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    /// 今天的那一张：没有就抽一张存下来，重开 App 也不会变
    @discardableResult
    static func ensureToday(in context: ModelContext) -> DailyTarot {
        let key = todayKey
        let descriptor = FetchDescriptor<DailyTarot>(
            predicate: #Predicate { $0.dateKey == key },
            sortBy: [SortDescriptor(\.drawnAt, order: .reverse)]
        )
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let draw = DailyTarot(
            dateKey: key,
            cardID: Int.random(in: 0...21),
            isReversed: Bool.random()
        )
        context.insert(draw)
        try? context.save()
        return draw
    }

    /// 重新抽：覆盖今天那条记录
    static func redraw(_ draw: DailyTarot, in context: ModelContext) {
        var next = draw.cardID
        while next == draw.cardID {
            next = Int.random(in: 0...21)
        }
        draw.cardID = next
        draw.isReversed = Bool.random()
        draw.drawnAt = Date()
        try? context.save()
        AppLog.info("重新抽牌：\(draw.card.name) \(draw.isReversed ? "逆位" : "正位")")
    }
}
