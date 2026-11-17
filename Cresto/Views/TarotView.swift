import SwiftUI
import SwiftData
import UIKit

// MARK: - 塔罗 Tab · 纯原生三牌阵
//
// 本文件只负责塔罗模块：
// · 78 张 RWS 牌库来自 TarotDeck.major（全可选绑定，无强制解包）
// · 2.5D 羊皮纸厚卡框 + 香槟金位置铭牌 + 倾斜全息镭射
// · 轻点出原生牌义 sheet，重新抽牌按钮避开底部 4-Tab 胶囊栏
// 不引用任何 WebView / 网页资源。

struct TarotView: View {
    @Environment(\.modelContext) private var context

    @State private var cards: [TarotDrawnCard] = []
    @State private var detail: TarotDrawnCard?
    @State private var appeared = false

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                        .padding(.top, 10)

                    Spacer(minLength: 12)

                    cardRow(totalWidth: proxy.size.width)

                    Spacer(minLength: 12)

                    Text("轻点牌面查看详解 · 按住拖动看镭射")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.bottom, 12)

                    drawButton
                        .padding(.bottom, 96)   // 让开底部 4-Tab 悬浮胶囊栏
                }
                .padding(.horizontal, 16)
            }
        }
        .sheet(item: $detail) { item in
            TarotDetailSheet(drawn: item)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            guard !appeared else { return }
            appeared = true
            redraw(commit: true)
        }
    }

    // MARK: 头部

    private var header: some View {
        VStack(spacing: 5) {
            Text("塔罗 · 三牌阵")
                .font(.system(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.text)

            Text("PAST · PRESENT · FUTURE")
                .font(.system(size: 9.5, weight: .medium, design: .serif))
                .kerning(2.4)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: 三张牌

    private func cardRow(totalWidth: CGFloat) -> some View {
        // 左右各留 16pt，三张牌之间各 8pt：(W - 16*2 - 8*2) / 3 = (W - 48) / 3
        // 向下取整，避免小数宽度累积后挤出屏幕
        let cardWidth = max(60, ((totalWidth - 48) / 3).rounded(.down))
        return HStack(alignment: .center, spacing: 8) {
            ForEach(cards) { item in
                TarotCardView(drawn: item, width: cardWidth) {
                    detail = item
                }
                .transition(.asymmetric(
                    insertion: .offset(y: 30).combined(with: .opacity),
                    removal: .opacity
                ))
            }
        }
        .padding(.vertical, 8)   // 给顶部铭牌与底部纸边留出完整显示空间
        .frame(maxWidth: .infinity)
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: cards.map(\.id))
    }

    // MARK: 重新抽牌

    private var drawButton: some View {
        Button {
            redraw(commit: true)
        } label: {
            Text("重新抽牌 · Draw again")
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(Color(hex: 0x141414))
                .padding(.horizontal, 22)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(.white)
                        .shadow(color: .black.opacity(0.18), radius: 10, y: 6)
                )
        }
        .buttonStyle(PressableStyle())
        .accessibilityHint("重新随机抽取过去、现在、未来三张牌")
    }

    // MARK: 逻辑

    /// 从 78 张牌里不重复抽 3 张，随机分配正逆位
    private static func drawCards() -> [TarotDrawnCard] {
        var deck = TarotDeck.major
        guard deck.count >= 3 else { return [] }
        deck.shuffle()
        return (0..<3).map { index in
            TarotDrawnCard(
                card: deck[index],
                reversed: Bool.random(),
                position: TarotPosition.allCases[index]
            )
        }
    }

    private func redraw(commit: Bool) {
        let drawn = Self.drawCards()
        guard drawn.count == 3 else { return }

        withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) {
            cards = drawn
        }

        if commit {
            persist(drawn)
        }

        let summary = drawn
            .map { "\($0.position.shortName)\($0.card.name)\($0.reversed ? "逆位" : "正位")" }
            .joined(separator: " · ")
        AppLog.info("塔罗三牌阵已抽取：\(summary)")
    }

    /// 把这次三牌阵同步到「今日塔罗」，首页小卡显示“现在”位
    private func persist(_ drawn: [TarotDrawnCard]) {
        guard drawn.count == 3 else { return }
        let past = drawn[0]
        let present = drawn[1]
        let future = drawn[2]
        let record = TarotService.ensureToday(in: context)
        TarotService.commitSpread(
            record,
            in: context,
            core: present.card.id,
            past: past.card.id,
            future: future.card.id,
            reversedCore: present.reversed,
            reversedPast: past.reversed,
            reversedFuture: future.reversed
        )
    }
}

// MARK: - 抽到的牌

enum TarotPosition: Int, CaseIterable, Identifiable {
    case past
    case present
    case future

    var id: Int { rawValue }

    var shortName: String {
        switch self {
        case .past: return "过去"
        case .present: return "现在"
        case .future: return "未来"
        }
    }

    /// 香槟金铭牌文案
    var label: String {
        switch self {
        case .past: return "过去 · PAST"
        case .present: return "现在 · PRESENT"
        case .future: return "未来 · FUTURE"
        }
    }
}

struct TarotDrawnCard: Identifiable {
    let id = UUID()
    let card: TarotCard
    let reversed: Bool
    let position: TarotPosition
}

// MARK: - 2.5D 羊皮纸物理牌框

struct TarotCardView: View {
    let drawn: TarotDrawnCard
    let width: CGFloat
    var interactive: Bool = true
    var onTap: () -> Void = {}

    @State private var drag: CGSize = .zero
    @State private var pressed = false

    /// 固定 1 : 1.68 的塔罗牌比例
    private var height: CGFloat { width * 1.68 }
    private var gold: Color { Color(hex: 0xC5A059) }
    private var ink: Color { Color(hex: 0x4A3B26) }

    var body: some View {
        let maxTilt: CGFloat = 14
        let tiltY = max(-maxTilt, min(maxTilt, drag.width / 12))
        let tiltX = max(-maxTilt, min(maxTilt, -drag.height / 14))

        let card = ZStack {
            // 三层微错位暖金纸边，做出实体厚卡纸的侧面
            paperEdge(offset: 6, color: 0xB5A17B)
            paperEdge(offset: 4, color: 0xCBB994)
            paperEdge(offset: 2, color: 0xDFD1B4)
            face
        }
        .frame(width: width, height: height)
        .rotation3DEffect(.degrees(Double(tiltX)), axis: (x: 1, y: 0, z: 0), perspective: 0.55)
        .rotation3DEffect(.degrees(Double(tiltY)), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .scaleEffect(pressed ? 1.035 : 1)
        .shadow(color: .black.opacity(0.30), radius: 12, x: 0, y: 14)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: pressed)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(drawn.position.label)，\(drawn.card.name)，\(drawn.reversed ? "逆位" : "正位")")
        .accessibilityAddTraits(.isButton)

        if interactive {
            card
                .gesture(dragGesture)
                .onTapGesture {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onTap()
                }
        } else {
            card
        }
    }

    // MARK: 拖动（3D 微倾 + 松手回弹；轻点由 onTapGesture 单独处理）

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                pressed = true
                drag = value.translation
            }
            .onEnded { _ in
                pressed = false
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    drag = .zero
                }
            }
    }

    // MARK: 卡面

    private var face: some View {
        let innerWidth = width * 0.86
        let topInset = height * 0.06                 // 给顶部位置铭牌留出的净空
        let bottomBlock = max(28, height * 0.155)    // 底部编号/牌名/正逆位
        let innerHeight = max(60, height - topInset - bottomBlock - height * 0.02)

        return ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color(hex: 0xF4ECD8))
                .overlay(
                    RadialGradient(
                        colors: [Color(hex: 0xFFFCF1).opacity(0.7), .clear],
                        center: UnitPoint(x: 0.28, y: 0.16),
                        startRadius: 0,
                        endRadius: height * 0.9
                    )
                )

            VStack(spacing: 0) {
                // 中间金色画框：插画以 scaledToFill 填满整个内框
                illustration(width: innerWidth, height: innerHeight)
                    .padding(.top, topInset)

                Spacer(minLength: 0)

                // 底部居中：编号 · 中文牌名 + 正/逆位小标
                VStack(spacing: max(1, height * 0.006)) {
                    Text("\(drawn.card.roman) · \(drawn.card.name)")
                        .font(.system(size: max(9, width * 0.088), weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, width * 0.04)

                    Text(drawn.reversed ? "逆位 · REVERSED" : "正位 · UPRIGHT")
                        .font(.system(size: max(5.5, width * 0.049), weight: .semibold, design: .serif))
                        .kerning(width * 0.007)
                        .foregroundStyle(Color(hex: drawn.reversed ? 0x8A4A33 : 0x5A4A30))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.bottom, height * 0.035)
            }

            holoEffect
        }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(gold.opacity(0.55), lineWidth: 0.8)
        )
        .overlay(alignment: .top) { nameplate }
    }

    /// 浅色羊皮纸上的全息镭射：
    /// 高饱和彩虹用 overlay 叠色，再叠一道白色斜向高光（screen），起止点跟随拖动。
    private var holoEffect: some View {
        let nx = max(-0.32, min(0.32, drag.width / max(1, width)))
        let ny = max(-0.32, min(0.32, drag.height / max(1, width)))

        return ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0xFF1F6B), Color(hex: 0xFF8A00), Color(hex: 0xFFE600),
                    Color(hex: 0x33E07A), Color(hex: 0x00C2FF), Color(hex: 0x6A5BFF),
                    Color(hex: 0xFF3DDA)
                ],
                startPoint: UnitPoint(x: 0.02 + nx, y: -0.22 + ny),
                endPoint: UnitPoint(x: 0.98 + nx, y: 1.22 + ny)
            )
            .blendMode(.overlay)
            .opacity(0.45)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.34),
                    .init(color: .white.opacity(0.9), location: 0.47),
                    .init(color: .clear, location: 0.60)
                ],
                startPoint: UnitPoint(x: 0.10 + nx * 1.6, y: -0.10 + ny * 1.6),
                endPoint: UnitPoint(x: 0.90 + nx * 1.6, y: 1.10 + ny * 1.6)
            )
            .blendMode(.screen)
            .opacity(0.35)
        }
        .allowsHitTesting(false)
    }

    /// 内框插画：正位正常，逆位只把插画旋转 180°，外框/铭牌/牌名保持正向
    @ViewBuilder
    private func illustration(width innerWidth: CGFloat, height innerHeight: CGFloat) -> some View {
        ZStack {
            if let image = TarotArt.image(named: drawn.card.rwsFile) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: innerWidth, height: innerHeight)
                    .clipped()
                    .rotationEffect(.degrees(drawn.reversed ? 180 : 0))
            } else {
                // 图片缺失：复古衬线文字占位，不崩溃
                VStack(spacing: max(3, width * 0.035)) {
                    Text(drawn.card.roman)
                        .font(.system(size: max(10, width * 0.12), weight: .semibold, design: .serif))
                        .foregroundStyle(gold)
                    Rectangle()
                        .fill(gold.opacity(0.55))
                        .frame(width: width * 0.24, height: 0.8)
                    Text(drawn.card.name)
                        .font(.system(size: max(9, width * 0.095), weight: .semibold, design: .serif))
                        .foregroundStyle(ink)
                    Text(drawn.card.en)
                        .font(.system(size: max(5.5, width * 0.045), design: .serif))
                        .foregroundStyle(ink.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.6)
                        .padding(.horizontal, width * 0.05)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    LinearGradient(
                        colors: [Color(hex: 0xF7F0DE), Color(hex: 0xEADFC7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
        }
        .frame(width: innerWidth, height: innerHeight)
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(gold, lineWidth: 1.5)
        )
    }

    private var nameplate: some View {
        Text(drawn.position.label)
            .font(.system(size: max(6.5, width * 0.062), weight: .semibold, design: .serif))
            .kerning(width * 0.006)
            .foregroundStyle(Color(hex: 0x33291A))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, width * 0.055)
            .padding(.vertical, max(2, width * 0.018))
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xF2E5C5), Color(hex: 0xDECBA4), Color(hex: 0xC8B083)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .strokeBorder(Color(hex: 0x8A744D).opacity(0.45), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
            .offset(y: -max(7, width * 0.06))
    }

    private func paperEdge(offset: CGFloat, color: UInt32) -> some View {
        RoundedRectangle(cornerRadius: 11, style: .continuous)
            .fill(Color(hex: color))
            .offset(y: offset)
    }
}

// MARK: - 原生牌义弹窗

struct TarotDetailSheet: View {
    let drawn: TarotDrawnCard

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        // 固定缩略图，不参与文字排版，杜绝卡片压住标题
                        TarotCardThumbnail(drawn: drawn)
                            .frame(width: 96, height: 160)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(drawn.position.label)
                                .font(.system(size: 10, weight: .semibold, design: .serif))
                                .kerning(1.4)
                                .foregroundStyle(Color(hex: 0x8A744D))

                            Text(drawn.card.name)
                                .font(.system(size: 22, weight: .semibold, design: .serif))
                                .foregroundStyle(Theme.text)

                            Text(drawn.card.en)
                                .font(.system(size: 11.5, design: .serif))
                                .foregroundStyle(Theme.textTertiary)

                            Text(drawn.reversed ? "逆位 · REVERSED" : "正位 · UPRIGHT")
                                .font(.system(size: 9, weight: .semibold, design: .serif))
                                .kerning(0.8)
                                .foregroundStyle(Color(hex: drawn.reversed ? 0x8A4A33 : 0x5A4A30))
                                .padding(.horizontal, 9)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Color(hex: 0xF3E7CB)))

                            HStack(spacing: 6) {
                                ForEach(drawn.card.keywords(reversed: drawn.reversed), id: \.self) { keyword in
                                    AccentChip(text: keyword, small: true)
                                }
                            }
                            .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Text(drawn.reversed ? "逆位解读" : "正位解读")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.text)

                    Text(drawn.card.text(reversed: drawn.reversed))
                        .font(.system(size: 14))
                        .lineSpacing(6)
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Theme.surface)
                        )
                }
                .padding(20)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg)
            .navigationTitle("塔罗牌义")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                        .foregroundStyle(Theme.text)
                }
            }
            .tint(Theme.text)
        }
    }
}

// MARK: - 弹窗内的固定缩略牌面（96 × 160）

struct TarotCardThumbnail: View {
    let drawn: TarotDrawnCard

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(hex: 0xF4ECD8))

            if let image = TarotArt.image(named: drawn.card.rwsFile) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 160)
                    .clipped()
                    .rotationEffect(.degrees(drawn.reversed ? 180 : 0))
            } else {
                VStack(spacing: 4) {
                    Text(drawn.card.roman)
                        .font(.system(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(hex: 0xC5A059))
                    Text(drawn.card.name)
                        .font(.system(size: 12, weight: .semibold, design: .serif))
                        .foregroundStyle(Color(hex: 0x4A3B26))
                }
            }
        }
        .frame(width: 96, height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color(hex: 0xC5A059), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 6, y: 3)
    }
}

// MARK: - RWS 公版图加载（RWSCards/ 文件夹引用，78 张随包内置）

enum TarotArt {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(named name: String) -> UIImage? {
        guard !name.isEmpty else { return nil }
        if let hit = cache.object(forKey: name as NSString) { return hit }

        let nsName = name as NSString
        let base = nsName.deletingPathExtension
        let ext = nsName.pathExtension.isEmpty ? "jpg" : nsName.pathExtension

        guard let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "RWSCards"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }

        cache.setObject(image, forKey: name as NSString)
        return image
    }
}

// MARK: - 素材加载（首页 OverviewView 的 CardArt 依赖，保持原行为）

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
            if loaded == nil, name.contains("-"), let first = name.split(separator: "-").first {
                // 大牌兼容：RWS 扫描图（RWSCards/）
                if let index = Int(first),
                   let url = Bundle.main.url(forResource: String(format: "maj-%02d", index), withExtension: "jpg", subdirectory: "RWSCards"),
                   let image = UIImage(contentsOfFile: url.path) {
                    loaded = image
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
