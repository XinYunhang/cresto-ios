# PROGRESS

> **注意（11-22）**：塔罗部分已过期。现状态：纯原生 SwiftUI 三牌阵（过去/现在/未来），
> 78 张公版 RWS 图（Resources/RWSCards/），DailyTarot 扩为三张牌（cardID/card2ID/card3ID），
> TarotView 含 TarotPackView / TarotPosition / TarotDrawnCard / TarotDetailSheet。详见 Obsidian 06-坑与修复。

## 1. 塔罗模块文件

- `Cresto/Views/TarotView.swift`：主视图 + `TornRemainder`(Shape) + `CardFan` + `ConfettiOverlay` + `TarotReadingSheet` + `CardArt` + `AssetImage`
- `Cresto/Models/TarotDeck.swift`：`TarotCard` / `TarotDeck.major`(22 张) / `@Model DailyTarot` / `TarotService`
- `Cresto/Views/OverviewView.swift`：`TarotMiniCard`（首页折叠区）
- `Cresto/Views/SearchView.swift`：引用 `TarotDeck.major`

入口（`Cresto/Views/RootView.swift:112`）：

```swift
case .tarot:
    TarotView()
```

`TarotView` 无初始化参数，内部 `@Query` 取 `DailyTarot`，`onAppear` 调 `TarotService.ensureToday(in:)`。

## 2. 图片资源名

不在 Assets.xcassets，均为直接放进 bundle 根目录的松散文件，经 `AssetImage.image(_:)` 加载。

| 用途 | 名称 | 实际文件 |
| --- | --- | --- |
| 卡包正面 | `pack` | `Cresto/Resources/Tarot/pack.png` |
| 顶部撕条 | `torn-strip` | `Cresto/Resources/Tarot/torn-strip.png` |
| 牌背 | `back` | `Cresto/Resources/Tarot/back.png` |
| 牌面立绘 | `card.slug`（如 `00-fool`） | `Cresto/Resources/Cards/<slug>.webp` |

```swift
AssetImage.image("pack")        // TarotView.swift:99
AssetImage.image("torn-strip")  // TarotView.swift:106
AssetImage.image(backName)      // CardFan，backName = "back"
AssetImage.image(faceName)      // CardFan，faceName = card.slug
CardArt(name: card.slug)        // TarotReadingSheet.swift 内
```

## 3. 数据模型

```swift
struct TarotCard: Identifiable, Hashable {
    let id: Int
    let slug: String
    let name: String
    let en: String
    let roman: String
    let uprightKeywords: [String]
    let reversedKeywords: [String]
    let uprightText: String
    let reversedText: String

    func keywords(reversed: Bool) -> [String]
    func text(reversed: Bool) -> String
    func positionText(reversed: Bool) -> String
}
```

```swift
@Model
final class DailyTarot {
    var dateKey: String = ""      // yyyy-MM-dd
    var cardID: Int = 0
    var isReversed: Bool = false
    var isOpened: Bool = false
    var drawnAt: Date = Date()
    var card: TarotCard { TarotDeck.card(id: cardID) }
}
```

牌义弹窗数据流：

```swift
@State private var draw: DailyTarot?              // onAppear: TarotService.ensureToday(in:)
@State private var isDetailPresented = false
private var card: TarotCard { draw?.card ?? TarotDeck.major[0] }
private var isReversed: Bool { draw?.isReversed ?? false }

.sheet(isPresented: $isDetailPresented) {
    TarotReadingSheet(card: card, isReversed: isReversed)   // TarotView.swift:50
}
```

`TarotReadingSheet` 入参：`let card: TarotCard`、`let isReversed: Bool`。

## 4. 全局样式

文件：`Cresto/DesignSystem/Theme.swift`

```swift
static let bg            = dynamic(dark: 0x000000, light: 0xFFFFFF)
static let surface       = dynamic(dark: 0x151517, light: 0xF2F2F5)
static let surfaceRaised = dynamic(dark: 0x1D1D20, light: 0xE9E9EE)
static let text          = dynamic(dark: 0xFAFAFA, light: 0x0A0A0A)
static let textSecondary = dynamic(dark: 0x9C9CA4, light: 0x6D6D76)
static let textTertiary  = dynamic(dark: 0x5F5F67, light: 0xA2A2AA)

static let cardCorner: CGFloat = 20
static let screenPadding: CGFloat = 18
static let cardGap: CGFloat = 10
```

另定义：`Theme.courseTone(_ index: Int) -> CourseTone`（9 套课程配色，`bg`/`fg`）、`HeatScale.color(for:)`（5 级灰阶）、`.cardSurface(padding:)`、`.glassCapsule()` / `.glassCircle()`、`AccentChip`。

字体：无独立字体文件，全部内联 `.font(.system(size:weight:))`；`.cardLabel()` 为 12pt + `textSecondary`。
