# tarot-web · 塔罗三牌阵（WKWebView 离线嵌入版）

深色舞台 + 2.5D 羊皮纸物理牌框 + 香槟金铭牌 + 动态 RWS 插槽的三牌阵网页。
构建产物 `dist/` 完全离线：78 张 1909 公版韦特塔罗（Rider-Waite-Smith，公有领域）与全部牌库数据打包在包内，不依赖任何 CDN；音效由 Web Audio 运行时合成，无音频素材文件。

## 构建

```bash
npm install
npm run build     # 产物输出到 dist/（base: './'，全部相对路径）
```

`dist/index.html` 可直接通过 `file://` 协议加载（双击即可预览），也可托管在任意子路径下。

## 目录结构

```
tarot-web/
├─ index.html
├─ vite.config.js          # base: './'
├─ public/
│  ├─ cards/               # 78 张 RWS 公版图（Wikimedia Commons，width=480 缩略）
│  └─ tarot/               # 卡包/撕条/牌背（项目自绘素材，与原生端同源）
├─ src/
│  ├─ main.js              # 状态机 sealed → tearing → fanSelection → spreadRevealed
│  ├─ deck.js              # 78 张牌库（编号/中英文名/关键词/正逆位牌义）
│  ├─ audio.js             # Web Audio 合成音效（撕箔/微震提示/纸张摩擦/翻牌/揭晓钟琴）
│  └─ style.css            # 牌框/铭牌/插槽/全息层/安全区
└─ dist/                   # 构建产物
```

## 嵌入 iOS WKWebView

1. 将 `dist/` 目录整体拖入 Xcode 工程（勾选 Copy items if needed / Create folder references），作为蓝色文件夹资源。

2. 加载与桥接：

```swift
import WebKit

let config = WKWebViewConfiguration()
config.userContentController.add(self, name: "tarotCardTapped")   // 与网页端 messageHandlers 名字一致

let webView = WKWebView(frame: view.bounds, configuration: config)
webView.scrollView.contentInsetAdjustmentBehavior = .never

// dist 作为文件夹引用时 URL 为 Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "dist")
let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "dist")!
webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
```

3. 接收选牌事件：

```swift
extension MyViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "tarotCardTapped",
              let p = message.body as? [String: Any] else { return }
        // p["position"] "过去 · PAST" | p["number"] "IX" | p["nameEn"] "THE HERMIT"
        // p["nameZh"] "隐者" | p["isReversed"] Bool | p["keywords"] [String] | p["meaning"] String
    }
}
```

网页端在用户点击已翻开的塔罗牌时调用
`window.webkit?.messageHandlers?.tarotCardTapped?.postMessage({...})`；
在纯浏览器中预览（无 WebKit 桥）时自动回退为页内详情弹层。

## 交互流程

密封卡包 → 沿虚线向右拖动撕开（进度 ≥72% 才会撕开，否则回弹；每滑动 10pt 有微震与撕箔音效）
→ 右侧固定 40% 弧形厚卡扇（14 张，点选沿放射角外弹 30pt）→ 选满 3 张飞入三联羊皮纸牌阵
（顶部铭牌固定「过去 · PAST / 现在 · PRESENT / 未来 · FUTURE」，逆位仅插画旋转 180°）
→ 逐张点击翻转（90° 临界切换、阴影随 abs(cos) 归零消除黑竖线）→ 点击已翻开的牌触发原生桥接。

## 素材版权

- RWS 塔罗图：1909 年公有领域版本，来自 Wikimedia Commons（Pamela Colman Smith 绘制）。
- 卡包/撕条/牌背：本项目自绘素材，与原生端共用。
- 音效：Web Audio 运行时合成，无素材文件。
