import Foundation
import SwiftData

// MARK: - 牌

struct TarotCard: Identifiable, Hashable {
    let id: Int              // 0...77（maj00→0 … maj21→21，wa01→22 … pe14→77）
    let slug: String         // 资源名：大牌 "00-fool"（Cards/*.webp），小牌 "wa01"（RWSCards/wa01.jpg）
    let rwsFile: String      // RWS 公版扫描图：RWSCards/ 下文件名
    let name: String
    let en: String
    let roman: String        // 大牌罗马数字 0~XXI；小牌为数字牌序 1~14（宫廷牌 11~14）
    let uprightKeywords: [String]
    let reversedKeywords: [String]
    let uprightText: String
    let reversedText: String

    func keywords(reversed: Bool) -> [String] { reversed ? reversedKeywords : uprightKeywords }
    func text(reversed: Bool) -> String { reversed ? reversedText : uprightText }
    func positionText(reversed: Bool) -> String { reversed ? "逆位" : "正位" }
}

// MARK: - 牌库：1909 公版韦特塔罗 78 张全套

enum TarotDeck {
    /// 全套 78 张（22 大牌 + 56 小牌）。字段名保留 major 以兼容首页/搜索页既有引用。
    static let major: [TarotCard] = { deck }()

    private static let majors: [TarotCard] = [
        .init(id: 0, slug: "00-fool", rwsFile: "maj-00.jpg", name: "愚者", en: "The Fool", roman: "0",
              uprightKeywords: ["全新开始", "勇气", "不必完美"],
              reversedKeywords: ["鲁莽", "犹豫", "准备不足"],
              uprightText: "带着还没准备好的一切出发。今天的关键是「先动」，方向可以在路上修正。",
              reversedText: "要么太冲动，要么一直等一个完美的时机。先问自己到底在怕什么。"),
        .init(id: 1, slug: "01-magician", rwsFile: "maj-01.jpg", name: "魔术师", en: "The Magician", roman: "I",
              uprightKeywords: ["行动力", "资源", "表达"],
              reversedKeywords: ["华而不实", "拖延", "自我怀疑"],
              uprightText: "手上的资源比你感觉的多。今天适合把一个想法变成具体动作，哪怕只做第一步。",
              reversedText: "想法很多，落地的很少。检查一下是不是用「再准备一下」掩盖了不敢开始。"),
        .init(id: 2, slug: "02-high-priestess", rwsFile: "maj-02.jpg", name: "女祭司", en: "The High Priestess", roman: "II",
              uprightKeywords: ["直觉", "内在", "保留"],
              reversedKeywords: ["忽视直觉", "信息不明", "自我封闭"],
              uprightText: "答案还在水面下。今天少说多听，直觉给的信号比道理可靠。",
              reversedText: "你在忽略那个早就知道答案的声音。也可能信息还不够，别急着下结论。"),
        .init(id: 3, slug: "03-empress", rwsFile: "maj-03.jpg", name: "皇后", en: "The Empress", roman: "III",
              uprightKeywords: ["滋养", "丰盛", "身体"],
              reversedKeywords: ["过度付出", "停滞", "忽略自己"],
              uprightText: "适合把生活过得具体一点：好好吃饭、好好休息。今天的好运来自「照顾」。",
              reversedText: "付出过头了。先把自己喂饱，再谈照顾别人。"),
        .init(id: 4, slug: "04-emperor", rwsFile: "maj-04.jpg", name: "皇帝", en: "The Emperor", roman: "IV",
              uprightKeywords: ["秩序", "边界", "掌控"],
              reversedKeywords: ["僵化", "控制欲", "失去弹性"],
              uprightText: "建立秩序的一天。定规则、划边界，把混乱收进框架里。",
              reversedText: "过度控制会让事情更僵。有些事放一放，反而自己会顺。"),
        .init(id: 5, slug: "05-hierophant", rwsFile: "maj-05.jpg", name: "教皇", en: "The Hierophant", roman: "V",
              uprightKeywords: ["传承", "规则", "请教"],
              reversedKeywords: ["形式主义", "反叛", "照搬"],
              uprightText: "向有经验的人请教，或者按已经验证过的流程走。今天不适合标新立异。",
              reversedText: "形式大于内容。或者你想反抗的，其实是自己给自己定的规矩。"),
        .init(id: 6, slug: "06-lovers", rwsFile: "maj-06.jpg", name: "恋人", en: "The Lovers", roman: "VI",
              uprightKeywords: ["选择", "关系", "一致"],
              reversedKeywords: ["摇摆", "失衡", "表面和谐"],
              uprightText: "今天绕不开一个选择。选那个让你更完整的方向，而不是更安全的。",
              reversedText: "摇摆本身就是消耗。先承认你其实已经偏向一边了。"),
        .init(id: 7, slug: "07-chariot", rwsFile: "maj-07.jpg", name: "战车", en: "The Chariot", roman: "VII",
              uprightKeywords: ["推进", "意志", "专注一件事"],
              reversedKeywords: ["失控", "方向不明", "用力过猛"],
              uprightText: "把注意力收到一件事上，推到能看见结果为止。方向比速度重要。",
              reversedText: "同时抓太多头，或者被情绪带着跑。先停下来对一次方向。"),
        .init(id: 8, slug: "08-strength", rwsFile: "maj-08.jpg", name: "力量", en: "Strength", roman: "VIII",
              uprightKeywords: ["耐心", "温柔的坚定", "承认脆弱"],
              reversedKeywords: ["自我怀疑", "急躁", "硬撑"],
              uprightText: "不是硬扛，是耐心。今天用温和的方式处理最难的那件事。",
              reversedText: "自我怀疑在消耗你。你比自己以为的更有余量。"),
        .init(id: 9, slug: "09-hermit", rwsFile: "maj-09.jpg", name: "隐者", en: "The Hermit", roman: "IX",
              uprightKeywords: ["独处", "内省", "提灯"],
              reversedKeywords: ["封闭", "逃避", "孤立"],
              uprightText: "需要独处。今天减少输入，把注意力收回到自己身上。",
              reversedText: "关得太久了。找一个能说真话的人，聊十分钟就够。"),
        .init(id: 10, slug: "10-wheel-of-fortune", rwsFile: "maj-10.jpg", name: "命运之轮", en: "Wheel of Fortune", roman: "X",
              uprightKeywords: ["转机", "周期", "顺势"],
              reversedKeywords: ["卡在循环里", "时机未到", "重复犯错"],
              uprightText: "事情自己在转，你不需要用力推。顺着已经出现的势头走。",
              reversedText: "卡在同一个循环里。这次换一个完全不同的做法，哪怕看起来不合理。"),
        .init(id: 11, slug: "11-justice", rwsFile: "maj-11.jpg", name: "正义", en: "Justice", roman: "XI",
              uprightKeywords: ["权衡", "因果", "诚实"],
              reversedKeywords: ["偏颇", "逃避责任", "标准动摇"],
              uprightText: "该算账了。把事实摆清楚，做那个不讨喜但正确的决定。",
              reversedText: "标准在动摇，或者你在回避自己该负的那部分。"),
        .init(id: 12, slug: "12-hanged-man", rwsFile: "maj-12.jpg", name: "倒吊人", en: "The Hanged Man", roman: "XII",
              uprightKeywords: ["暂停", "换视角", "放手"],
              reversedKeywords: ["无谓牺牲", "拖延", "钻牛角尖"],
              uprightText: "暂停不是失败。换个角度，你会发现卡住的地方本来就不必硬闯。",
              reversedText: "无谓的牺牲，或者用「再等等」拖延那个早该做的决定。"),
        .init(id: 13, slug: "13-death", rwsFile: "maj-13.jpg", name: "死神", en: "Death", roman: "XIII",
              uprightKeywords: ["结束", "清理", "重生"],
              reversedKeywords: ["抗拒结束", "抓着不放", "拖长痛苦"],
              uprightText: "某件事该结束了。让它结束，才有位置放新的东西。",
              reversedText: "抓住过去不放；唯有接纳终结，才能轻装前行。"),
        .init(id: 14, slug: "14-temperance", rwsFile: "maj-14.jpg", name: "节制", en: "Temperance", roman: "XIV",
              uprightKeywords: ["平衡", "调配", "节奏"],
              reversedKeywords: ["失衡", "过度", "走极端"],
              uprightText: "调配比例的一天。工作与休息、投入与留白，找回中间那条线。",
              reversedText: "生活或关系失衡；重新校准节奏与分量。"),
        .init(id: 15, slug: "15-devil", rwsFile: "maj-15.jpg", name: "恶魔", en: "The Devil", roman: "XV",
              uprightKeywords: ["欲望", "束缚", "习惯"],
              reversedKeywords: ["松绑", "看清", "戒断"],
              uprightText: "察觉成瘾与依赖的锁链；看清它多半是自己戴上的。",
              reversedText: "束缚在松动。你已经能看见绳子的另一头了。"),
        .init(id: 16, slug: "16-tower", rwsFile: "maj-16.jpg", name: "高塔", en: "The Tower", roman: "XVI",
              uprightKeywords: ["骤变", "崩塌", "启示"],
              reversedKeywords: ["恐惧改变", "惊魂未定", "延迟崩解"],
              uprightText: "真相刺破幻象，旧结构轰然倒塌；剧变清出了重建的地基。",
              reversedText: "在摇摇欲坠中硬撑；主动拆解，好过被动摧毁。"),
        .init(id: 17, slug: "17-star", rwsFile: "maj-17.jpg", name: "星星", en: "The Star", roman: "XVII",
              uprightKeywords: ["希望", "疗愈", "信念"],
              reversedKeywords: ["失望", "信心不足", "灵感受阻"],
              uprightText: "风暴后夜空澄澈；愿景与信心重新点亮前路。",
              reversedText: "暂时看不见光；允许自己慢慢恢复，别放弃希望。"),
        .init(id: 18, slug: "18-moon", rwsFile: "maj-18.jpg", name: "月亮", en: "The Moon", roman: "XVIII",
              uprightKeywords: ["潜意识", "幻象", "不安"],
              reversedKeywords: ["迷雾散去", "释怀", "走出恐惧"],
              uprightText: "月光下的路影影绰绰；觉察情绪与梦境传递的讯息。",
              reversedText: "困惑渐消、事实浮出水面；焦虑开始退潮。"),
        .init(id: 19, slug: "19-sun", rwsFile: "maj-19.jpg", name: "太阳", en: "The Sun", roman: "XIX",
              uprightKeywords: ["成功", "喜悦", "活力"],
              reversedKeywords: ["暂时阴霾", "过度乐观", "迟来的喜悦"],
              uprightText: "阳光普照；坦荡与热忱带来确认的成功和纯粹的快乐。",
              reversedText: "光仍在，只是被云遮住；调整预期，快乐会再来。"),
        .init(id: 20, slug: "20-judgement", rwsFile: "maj-20.jpg", name: "审判", en: "Judgement", roman: "XX",
              uprightKeywords: ["觉醒", "召唤", "重生"],
              reversedKeywords: ["自我批判", "逃避召唤", "停滞"],
              uprightText: "听见更高的召唤；盘点过往、宽恕旧账，跃入新阶段。",
              reversedText: "迟迟不回应改变；放下苛责，才能升级。"),
        .init(id: 21, slug: "21-world", rwsFile: "maj-21.jpg", name: "世界", en: "The World", roman: "XXI",
              uprightKeywords: ["圆满", "完成", "整合"],
              reversedKeywords: ["未竟", "收尾拖延", "差一步"],
              uprightText: "旅程抵达终点，世界在脚下展开；庆祝，并乘愿启新章。",
              reversedText: "只剩临门一脚；补齐遗留，才算真正圆满。")
    ]

    // 小牌：[花色前缀, 花色中文, 起始 id]
    private static let suitDefs: [(prefix: String, zh: String, base: Int)] = [
        ("wa", "权杖", 22), ("cu", "圣杯", 36), ("sw", "宝剑", 50), ("pe", "星币", 64)
    ]
    private static let rankNames: [String] = [
        "首牌", "二", "三", "四", "五", "六", "七", "八", "九", "十", "侍从", "骑士", "皇后", "国王"
    ]
    private static let rankEn: [String] = [
        "Ace of", "Two of", "Three of", "Four of", "Five of", "Six of", "Seven of", "Eight of", "Nine of", "Ten of",
        "Page of", "Knight of", "Queen of", "King of"
    ]
    private static let suitEn: [String: String] = ["wa": "Wands", "cu": "Cups", "sw": "Swords", "pe": "Pentacles"]

    // 小牌牌义（与 holo-reverse/src/tarot-data.js 对齐）：[upKw, revKw, upText, revText]，按花色各 14 张
    private static let minorMeanings: [String: [[String]]] = [
        "wa": [
            [["灵感", "迸发", "新机遇"], ["延迟", "熄火", "方向未明"], "一根燃着新芽的权杖递到手中；热情与创造就此点燃。", "热情受挫或时机未到；养一养火种，再出发。"],
            [["规划", "远见", "抉择"], ["犹疑", "计划受阻", "不安于现状"], "站在高处手握地球仪，眺望版图、筹划下一步的扩张。", "蓝图悬而未决；想走得更远，却怕迈出已知的世界。"],
            [["进展", "远航", "合作"], ["延误", "受限", "视野短浅"], "船已出港、静候回音；视野与格局正在打开。", "船期有变或格局受限；耐心调整航向。"],
            [["庆祝", "安定", "归属"], ["过渡期", "摩擦", "庆典延后"], "花门之下共举杯；家与团队的欢庆和安稳时刻。", "安顿未稳或庆祝推迟；过渡本就需要时间。"],
            [["竞争", "摩擦", "切磋"], ["回避冲突", "和解", "内耗缓解"], "众人挥杖相争；冲突消耗也磨砺人，明确规则再比拼。", "争端降温或回避对抗；寻求共赢的路。"],
            [["胜利", "认可", "凯旋"], ["不被认可", "自负", "凯旋迟到"], "骑马戴冠而行；努力被看见，掌声与荣耀如期而至。", "掌声迟到或自我膨胀；成败不必系于他人眼光。"],
            [["防守", "坚守", "立场"], ["招架不住", "放弃", "压力过载"], "居高临下逐一来敌；守住得来不易的位置。", "防线吃紧；学会取舍与求助。"],
            [["加速", "消息", "顺势"], ["延迟", "紊乱", "操之过急"], "八根权杖破空而来；事情突然提速，消息接踵而至。", "节奏乱套或行程受阻；理顺了再提速。"],
            [["坚持", "戒备", "伤后余勇"], ["力竭", "固执", "过度设防"], "带伤守阵；虽疲惫，仍不放弃最后一里路。", "弹尽粮绝还硬撑，或戒备心关上了门。"],
            [["重负", "责任", "硬扛"], ["卸下", "委托", "放不下"], "满抱权杖弯腰前行；目标近在咫尺，却已不堪重负。", "学会分派与舍弃；别把所有重量留给自己。"],
            [["探索", "热忱", "新点子"], ["三分钟热度", "幼稚", "方向漂移"], "手持初萌权杖眺望远方；好奇心点燃新的尝试。", "起步轰轰烈烈却难以为继；选定一处深耕。"],
            [["冲劲", "冒险", "行动派"], ["冲动", "鲁莽", "半途而废"], "策马疾驰，敢想敢干；行动永远快过言语。", "油门踩过了头；慢一点，反而更快到达。"],
            [["自信", "魅力", "热力"], ["自我怀疑", "妒意", "内耗"], "向日葵与黑猫在侧；由内而外的笃定与感染力。", "光芒被比较遮住；把注意力收回自己身上。"],
            [["领导", "愿景", "魄力"], ["独断", "刚愎", "愿景落空"], "以愿景聚人、以魄力成事；天生的创业者气质。", "强势压人或期望落空；倾听让火焰更旺。"]
        ],
        "cu": [
            [["爱的萌发", "情感丰盈", "共情"], ["情感阻塞", "单向付出", "心门微闭"], "圣杯满溢；一段感情或灵感之泉开始流淌。", "水流不畅；先接住自己的情绪，再去爱人。"],
            [["相遇", "联结", "对等之爱"], ["失衡", "误会", "关系紧张"], "两杯相换、两心相许；关系在真诚中建立。", "天平偏斜；及时沟通，修复裂痕。"],
            [["友谊", "欢庆", "社群"], ["三角困扰", "流言", "圈层疲惫"], "三人举杯；朋友圈的喜悦与支持扑面而来。", "关系网起波澜；适度保持距离。"],
            [["倦怠", "沉思", "错过的机会"], ["走出低潮", "接受邀请", "新的兴趣"], "树下抱臂之人对递来的杯子视而不见；重新点亮兴致。", "抬起头才发现，机会一直在等你。"],
            [["失落", "遗憾", "哀悼"], ["走出哀伤", "接纳", "原谅"], "三杯倾倒、两杯犹在；允许悲伤，也记得转身。", "眼泪流过之后，开始收拾残局。"],
            [["童真", "怀旧", "纯善"], ["困于过去", "理想化旧时光", "成长阵痛"], "旧日花园里的馈赠；温柔的记忆与单纯的善意。", "向前看；别让回忆变成标签。"],
            [["幻想", "选择过多", "迷雾"], ["拨云见日", "决断", "现实检验"], "云端七杯皆诱人；分清哪些值得落地。", "幻象散去；做出选择的时候到了。"],
            [["离开", "寻找意义", "放手"], ["徘徊", "逃避", "难以割舍"], "月食之下转身离去；放下「够好」，去追寻「真正想要」。", "走还是留反复拉扯；听听内心的指南针。"],
            [["满足", "如愿", "小小幸福"], ["表面风光", "内心空虚", "纵欲"], "满架杯盏之前抱臂而坐；这是愿望成真之牌。", "得到了却不够甜；诚实面对真正的渴望。"],
            [["圆满家庭", "和乐", "情感富足"], ["家有龃龉", "期望落差", "观念分歧"], "彩虹下的十杯；关系与家的完满图景。", "完美蓝图与现实有差距；用心修补。"],
            [["灵感", "浪漫", "情感萌动"], ["情绪化", "不成熟", "白日梦"], "杯中探出一条鱼；敏感的心灵收到创意的讯息。", "感受泛滥成内耗；温柔地落回地面。"],
            [["浪漫", "邀约", "追随心意"], ["空头支票", "情绪反复", "理想化"], "捧杯缓行；为爱与理想发出诚挚的邀请。", "承诺多于行动；看看马蹄究竟踏在哪里。"],
            [["共情", "包容", "情感智慧"], ["情绪淹没", "过度共情", "依赖"], "海边凝视圣杯；以理解与直觉托举他人。", "先给自己划一道温柔的岸。"],
            [["情绪成熟", "稳重", "以情驭事"], ["压抑", "被动攻击", "情绪泄漏"], "波涛中端坐王座；深谙水性而不被浪卷走。", "平静表面下暗流涌动；学会真实表达。"]
        ],
        "sw": [
            [["清晰", "真相", "决断"], ["思绪混乱", "误判", "言语伤人"], "高擎之剑划破迷雾；一针见血的洞察与决断。", "剑锋钝了或偏了；先理清思路，再出鞘。"],
            [["僵局", "回避", "蒙眼抉择"], ["摘下眼罩", "艰难决定", "信息浮出"], "蒙眼持双剑而坐；假装看不见的抉择悬而未决。", "拖无可拖；睁开眼看清，再做选择。"],
            [["心碎", "伤痛", "直言刺心"], ["疗愈开始", "原谅", "走出余痛"], "三剑穿心；疼痛真实存在，也终将随雨流走。", "风暴过后；慢慢拔剑，疗伤复原。"],
            [["休整", "静养", "充电"], ["休息不足", "被迫复工", "焦躁"], "石棺上的安睡；暂别战场，是为了走更远。", "该停不停；身心会自己罢工。"],
            [["惨胜", "冲突", "得不偿失"], ["释怀", "和解", "放下旧怨"], "拾剑而笑者身后是散落的败者；赢了道理，输了人心。", "不必每仗必赢；退一步海阔天空。"],
            [["过渡", "驶离", "渐入佳境"], ["旧事纠缠", "难以抽身", "同行者异议"], "摆渡人载一家人驶向对岸；离开喧嚣，走向平静。", "船开了心没走；断舍离需要决心。"],
            [["策略", "机敏", "隐瞒"], ["败露", "坦白", "自欺难安"], "抱着五柄剑溜出营帐；以巧取胜，或有所隐瞒。", "藏不住的事；主动摊牌更轻松。"],
            [["受困", "自缚", "无路之感"], ["松绑", "看出路", "夺回主动"], "蒙眼被缚立于剑林；枷锁多为心造。", "退一步看见缝隙；原来门没有锁。"],
            [["忧惧", "失眠", "午夜焦虑"], ["最坏的没来", "求助", "黎明前"], "捂脸坐起，墙上九剑如噩梦；担忧多过现实。", "说出来；恐惧就小了一半。"],
            [["谷底", "终局", "触底"], ["缓慢复原", "幸存", "拒绝认输"], "十剑加身伏地；最坏已至，天际微光将现。", "没有真正倒下；伤愈之后仍在爬升。"],
            [["好奇", "警觉", "求证"], ["口舌", "八卦", "话多过脑"], "持剑而立的少年；对新知与消息保持敏锐。", "先想后说；免得剑锋伤己。"],
            [["冲锋", "果决", "直取要害"], ["横冲直撞", "急躁", "杀伤性坦率"], "逆风疾驰；言出必行，直奔目标。", "速度快过思考；小心误伤。"],
            [["清醒", "边界", "一语中的"], ["刻薄", "防备", "心冷"], "执剑侧首的女子；凭理智与经验明断是非。", "伤后筑墙太厚；允许温柔存在。"],
            [["权威", "理性", "规则制定"], ["独裁", "冷酷", "滥用权力"], "剑指前方的智者；以逻辑与原则执掌大局。", "只讲理不讲情；权力便成了刀。"]
        ],
        "pe": [
            [["新机会", "播种", "物质起步"], ["机会溜走", "财务焦虑", "根基未稳"], "花园中递出的一枚金币；安稳回报的种子落地。", "种子没落进土里；重整资源，再来一次。"],
            [["平衡", "多线并行", "灵活"], ["顾此失彼", "超载", "失序"], "杂耍两枚金币踏浪而行；在忙碌中找到节奏。", "球掉了一颗；先排好优先级。"],
            [["协作", "匠心", "被认可"], ["配合不畅", "各行其是", "认可缺位"], "教堂里匠人与设计者共商图纸；专业赢得尊重。", "图纸没对齐；先统一目标。"],
            [["守成", "安全感", "掌控"], ["松手", "破财", "重新分配"], "怀抱金币不离身；稳当，却也可能握得太紧。", "该花的花、该放的放。"],
            [["匮乏", "被排除在外", "寒冬"], ["转机", "走出低谷", "重获接纳"], "雪夜中跛行，路过亮着彩窗的教堂；困境里被忽视的援手。", "教堂的门其实开着；伸手即可。"],
            [["慷慨", "施受", "资源流动"], ["失衡的给予", "附带条件", "依赖"], "持天平的富人撒币；给予与接受各得其所。", "恩惠变成筹码；重新平衡关系。"],
            [["耐心", "评估", "长期主义"], ["急于求成", "回报慢", "白费功夫"], "倚锄凝视累累果实；停一停，看看投入是否值得。", "收成未至或方向有误；调整了再种。"],
            [["专注", "精进", "打磨"], ["敷衍", "倦怠", "完美主义疲劳"], "长凳上一枚枚雕币；把重复做成艺术。", "手艺走了神；找回初心，或休整片刻。"],
            [["自足", "优雅", "应得的富足"], ["依赖", "虚饰", "价值感低"], "葡萄园中戴隼的贵妇；凭自己挣来的从容生活。", "富足在外、评价在内；重建自我价值。"],
            [["家业", "传承", "世代安稳"], ["家产纠纷", "传统束缚", "根基动摇"], "门拱下三代同堂与十币纹章；长久积累的富足。", "家族议题浮出水面；立好边界与规矩。"],
            [["学习", "务实", "新技能"], ["拖延", "不专注", "学无所用"], "凝视金币的年轻人；脚踏实地开启学业或事业。", "目标漂移；把书读完，再谈远方。"],
            [["稳健", "可靠", "缓慢推进"], ["停滞", "乏味", "固执守旧"], "骑役马驻足田间的骑士；不快，但从不缺席。", "太稳成了原地踏步；偶尔也要换挡。"],
            [["滋养", "富饶", "持家有道"], ["过劳", "疏于自顾", "大包大揽"], "花园王座上的慈母；把生活与事业都打理得丰盈。", "照顾完所有人；记得留一份给自己。"],
            [["富足", "稳健经营", "实业家"], ["唯利", "守财", "僵化"], "葡萄藤上的王座；以经验与资源成就大局。", "数字之外还有人；成功不止一种度量。"]
        ]
    ]

    private static let minors: [TarotCard] = {
        var cards: [TarotCard] = []
        for (prefix, zh, base) in suitDefs {
            let meanings = minorMeanings[prefix]!
            for r in 1...14 {
                let m = meanings[r - 1]
                let id = base + r - 1
                let slug = "\(prefix)\(String(format: "%02d", r))"
                cards.append(TarotCard(
                    id: id,
                    slug: slug,
                    rwsFile: "\(prefix)\(String(format: "%02d", r)).jpg",
                    name: "\(zh)\(rankNames[r - 1])",
                    en: r <= 10 ? "\(rankEn[r - 1]) \(suitEn[prefix]!)" : "\(rankEn[r - 1]) \(suitEn[prefix]!)",
                    roman: "\(r)",
                    uprightKeywords: m[0],
                    reversedKeywords: m[1],
                    uprightText: m[2],
                    reversedText: m[3]
                ))
            }
        }
        return cards
    }()

    private static let deck: [TarotCard] = majors + minors

    static func card(id: Int) -> TarotCard {
        guard id >= 0, id < deck.count else { return deck[0] }
        return deck[id]
    }
}

// MARK: - 每日一抽

@Model
final class DailyTarot {
    var dateKey: String = ""      // yyyy-MM-dd
    var cardID: Int = 0           // 当日核心牌（0...77）
    var card2ID: Int = 0
    var card3ID: Int = 0
    var isReversed: Bool = false
    var isReversed2: Bool = false
    var isReversed3: Bool = false
    var isOpened: Bool = false
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
            cardID: Int.random(in: 0..<TarotDeck.major.count),
            isReversed: Bool.random()
        )
        context.insert(draw)
        try? context.save()
        return draw
    }

    /// 一包三张的开牌结果落库：core = 现在位（首页小卡显示），past/future 随行
    static func commitSpread(_ record: DailyTarot, in context: ModelContext,
                             core: Int, past: Int, future: Int,
                             reversedCore: Bool, reversedPast: Bool, reversedFuture: Bool) {
        record.cardID = core
        record.card2ID = past
        record.card3ID = future
        record.isReversed = reversedCore
        record.isReversed2 = reversedPast
        record.isReversed3 = reversedFuture
        record.isOpened = true
        record.drawnAt = Date()
        try? context.save()
        AppLog.info("塔罗开牌：核心 \(TarotDeck.card(id: core).name)，另抽 \(TarotDeck.card(id: past).name)/\(TarotDeck.card(id: future).name)")
    }

    static func markUnopened(_ record: DailyTarot, in context: ModelContext) {
        record.isOpened = false
        try? context.save()
    }
}
