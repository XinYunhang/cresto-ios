import SwiftUI
import SwiftData
import WebKit

/// 塔罗 Tab：WKWebView 承载 tarot-web 构建产物（dist/ 文件夹引用，完全离线）。
///
/// 桥接协议（与 tarot-web/src/main.js 对齐）：
///   web → native：
///     tarotSpreadCommitted { core, present, future, reversedCore, reversedPresent, reversedFuture }
///       —— 牌扇选满 3 张时提交，id 形如 "major-09"，映射 TarotDeck.major 并落库（选牌即持久化）
///     tarotCardTapped { id, position, number, nameEn, nameZh, isReversed, keywords, meaning }
///       —— 点击已翻开的牌 → 原生 TarotReadingSheet 牌义弹层
///     tarotRedraw {}
///       —— 重新抽牌时把当日记录标记为未拆（首页继续显示旧牌，不剧透）
///   native → web：
///     documentStart 注入 window.__TAROT_BOOT__ = { opened, spread: [{id, reversed} × 3] }
///       —— 当日已抽过时，网页直接呈现三牌阵翻开的牌面
struct TarotView: View {
    @Environment(\.modelContext) private var context
    @Query private var draws: [DailyTarot]
    @State private var detail: CardDetail?

    struct CardDetail: Identifiable {
        let id: Int
        let card: TarotCard
        let reversed: Bool
    }

    private var today: DailyTarot? {
        draws.first { $0.dateKey == TarotService.todayKey }
    }

    var body: some View {
        TarotWebContainer(
            boot: TarotBootState(record: today),
            onCardTapped: { card, reversed in
                detail = CardDetail(id: card.id, card: card, reversed: reversed)
            },
            onSpreadCommitted: { core, present, future, rc, rp, rf in
                let record = TarotService.ensureToday(in: context)
                TarotService.commitSpread(
                    record, in: context,
                    core: core, present: present, future: future,
                    reversedCore: rc, reversedPresent: rp, reversedFuture: rf
                )
            },
            onRedraw: {
                TarotService.markUnopened(TarotService.ensureToday(in: context), in: context)
            }
        )
        .background(Theme.bg)
        .onAppear {
            TarotService.ensureToday(in: context)
        }
        .sheet(item: $detail) { d in
            TarotReadingSheet(card: d.card, isReversed: d.reversed)
        }
    }
}

// MARK: - 启动态

/// 注入网页的启动状态：当日已抽过时携带三张牌（id + 逆位标记），网页跳过撕包流程直接呈现牌阵。
struct TarotBootState: Encodable {
    struct BootCard: Encodable {
        let id: String
        let reversed: Bool
    }

    let opened: Bool
    let spread: [BootCard]?

    init(record: DailyTarot?) {
        if let r = record, r.isOpened {
            opened = true
            spread = [
                BootCard(id: Self.majorID(r.cardID), reversed: r.isReversed),
                BootCard(id: Self.majorID(r.card2ID), reversed: r.isReversed2),
                BootCard(id: Self.majorID(r.card3ID), reversed: r.isReversed3)
            ]
        } else {
            opened = false
            spread = nil
        }
    }

    /// DailyTarot 的 major 序号（0...21）→ 网页牌库 id（"major-09"）
    static func majorID(_ n: Int) -> String {
        "major-\(String(format: "%02d", max(0, min(21, n))))"
    }

    var json: String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else { return #"{"opened":false}"# }
        return string
    }
}

// MARK: - WKWebView 容器

struct TarotWebContainer: UIViewRepresentable {
    let boot: TarotBootState
    var onCardTapped: (TarotCard, Bool) -> Void
    var onSpreadCommitted: (Int, Int, Int, Bool, Bool, Bool) -> Void
    var onRedraw: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let controller = configuration.userContentController
        controller.add(context.coordinator, name: "tarotCardTapped")
        controller.add(context.coordinator, name: "tarotSpreadCommitted")
        controller.add(context.coordinator, name: "tarotRedraw")
        // documentStart 注入启动态（早于页面模块脚本执行）
        controller.addUserScript(
            WKUserScript(
                source: "window.__TAROT_BOOT__ = \(boot.json);",
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.indicatorStyle = .white

        // dist 以文件夹引用打入 bundle 根目录（project.yml: tarot-web/dist, type: folder）
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "dist") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            AppLog.info("塔罗 WebView：加载 \(url.lastPathComponent)（boot.opened=\(boot.opened)）")
        } else {
            AppLog.warn("塔罗 WebView：bundle 缺少 dist/index.html（检查 project.yml 的 tarot-web/dist folder 引用）")
            webView.loadHTMLString(Self.fallbackHTML, baseURL: nil)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static let fallbackHTML = """
    <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
    <style>body{margin:0;height:100vh;display:flex;align-items:center;justify-content:center;background:#0d0d10;
    color:#8a8a94;font-family:-apple-system,system-ui,sans-serif;font-size:14px}</style></head>
    <body>塔罗资源缺失，请重新构建（tarot-web/dist 未打入包内）</body></html>
    """

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let parent: TarotWebContainer

        init(parent: TarotWebContainer) {
            self.parent = parent
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }
            switch message.name {
            case "tarotSpreadCommitted":
                guard let core = Self.majorIndex(body["core"]),
                      let present = Self.majorIndex(body["present"]),
                      let future = Self.majorIndex(body["future"]) else {
                    AppLog.warn("塔罗桥接：tarotSpreadCommitted 载荷无效")
                    return
                }
                let rc = (body["reversedCore"] as? Bool) ?? false
                let rp = (body["reversedPresent"] as? Bool) ?? false
                let rf = (body["reversedFuture"] as? Bool) ?? false
                DispatchQueue.main.async {
                    self.parent.onSpreadCommitted(core, present, future, rc, rp, rf)
                }
            case "tarotCardTapped":
                guard let id = body["id"] as? String,
                      let index = Self.majorIndex(id) else { return }
                let card = TarotDeck.card(id: index)
                let reversed = (body["isReversed"] as? Bool) ?? false
                DispatchQueue.main.async {
                    self.parent.onCardTapped(card, reversed)
                }
            case "tarotRedraw":
                DispatchQueue.main.async {
                    self.parent.onRedraw()
                }
            default:
                break
            }
        }

        /// "major-09" → 9；越界或格式不符返回 nil
        private static func majorIndex(_ any: Any?) -> Int? {
            guard let id = any as? String, id.hasPrefix("major-"),
                  let n = Int(id.dropFirst(6)), (0...21).contains(n) else { return nil }
            return n
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            AppLog.info("塔罗 WebView：页面加载完成")
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            AppLog.warn("塔罗 WebView：导航失败 \(error.localizedDescription)")
        }
    }
}

// MARK: - 牌义弹层（点击已翻开的牌时由原生呈现）

struct TarotReadingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let card: TarotCard
    let isReversed: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    CardArt(name: card.slug)
                        .frame(width: 168, height: 250)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(card.name).font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(card.en).font(.system(size: 12, design: .serif))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Text("\(card.positionText(reversed: isReversed)) · 大阿尔卡纳 \(card.roman)")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textTertiary)

                    HStack(spacing: 6) {
                        ForEach(card.keywords(reversed: isReversed), id: \.self) { keyword in
                            AccentChip(text: keyword)
                        }
                    }

                    Text(card.text(reversed: isReversed))
                        .font(.system(size: 13))
                        .lineSpacing(5)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .multilineTextAlignment(.leading)
                        .cardSurface()
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 16)
            }
            .background(Theme.bg)
            .navigationTitle("牌义")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }.foregroundStyle(Theme.text)
                }
            }
            .tint(Theme.text)
        }
        .presentationBackground(Theme.bg)
    }
}

// MARK: - 素材加载

/// Bundle 松散素材显式加载 + 进程内缓存。
/// 首页（OverviewView）与搜索页（SearchView）的 CardArt 依赖此加载器。
enum AssetImage {
    private static var cache: [String: UIImage] = [:]

    static func ui(_ name: String) -> UIImage? {
        if let hit = cache[name] { return hit }
        var loaded: UIImage?
        if let image = UIImage(named: name) {
            loaded = image
        } else {
            for ext in ["png", "webp", "jpg", "jpeg"] {
                if let url = Bundle.main.url(forResource: name, withExtension: ext),
                   let image = UIImage(contentsOfFile: url.path) {
                    loaded = image
                    break
                }
            }
        }
        if loaded == nil {
            AppLog.warn("素材缺失：\(name)")
        } else {
            cache[name] = loaded
        }
        return loaded
    }

    static func image(_ name: String) -> Image {
        if let ui = ui(name) { return Image(uiImage: ui) }
        return Image(systemName: "rectangle.dashed")
    }
}

// MARK: - 卡面

struct CardArt: View {
    let name: String
    var grayscale = false

    var body: some View {
        Group {
            if let image = Self.load(name) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                ZStack {
                    Theme.surface
                    Image(systemName: "sparkles")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .saturation(grayscale ? 0 : 1)
    }

    static func load(_ name: String) -> UIImage? {
        AssetImage.ui(name)
    }
}
