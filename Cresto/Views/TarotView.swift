import SwiftUI
import SwiftData
import UIKit

/// 每日一抽：封口袋 → 拖动撕开 → 五张牌扇形飞出 → 揭晓今日主牌。
/// 卡包/牌背/撕条用真实素材（透明 PNG），全息层用渐变叠加做流动感。
struct TarotView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DailyTarot.drawnAt, order: .reverse) private var history: [DailyTarot]

    @State private var draw: DailyTarot?
    @State private var phase: Phase = .sealed
    @State private var tear: CGFloat = 0
    @State private var isFlipped = false
    @State private var confettiToken = 0
    @State private var isDetailPresented = false
    @State private var didLoad = false

    enum Phase { case sealed, revealed }

    private var card: TarotCard { draw?.card ?? TarotDeck.major[0] }
    private var isReversed: Bool { draw?.isReversed ?? false }

    private let packWidth: CGFloat = 236
    private let packHeight: CGFloat = 386
    /// 撕口位置（占卡包高度的比例），与素材里的撕裂线一致
    private let tearRatio: CGFloat = 0.358

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                header

                if phase == .sealed {
                    sealedView
                        .transition(.opacity)
                } else {
                    revealedView
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 128)
        }
        .overlay {
            ConfettiOverlay(token: confettiToken)
                .allowsHitTesting(false)
        }
        .sheet(isPresented: $isDetailPresented) {
            TarotReadingSheet(card: card, isReversed: isReversed)
        }
        .onAppear(perform: load)
    }

    // MARK: 页头

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 5) {
                Text("每日一抽 · \(Date().formatted(.dateTime.month().day()))")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text("塔罗")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .tracking(-0.5)
            }
            Spacer()
            Button {
                isDetailPresented = true
            } label: {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .frame(width: 38, height: 38)
                    .glassCircle()
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("牌义")
        }
        .padding(.top, 2)
        .padding(.bottom, 18)
    }

    // MARK: 待拆包

    private var sealedView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("👆").font(.system(size: 14))
                Text("拖动 / 点击撕开")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
            .opacity(Double(max(0, 1 - tear * 4)))
            .padding(.bottom, 16)

            ZStack(alignment: .top) {
                Image("pack")
                    .resizable()
                    .scaledToFit()
                    .mask(TornRemainder(progress: tear, ratio: tearRatio))
                    .shadow(color: .black.opacity(0.28), radius: 18, y: 12)

                if tear > 0.01 {
                    Image("torn-strip")
                        .resizable()
                        .scaledToFit()
                        .offset(x: -tear * 44, y: -tear * 58)
                        .rotationEffect(.degrees(Double(-tear * 7)), anchor: .topLeading)
                        .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
                }
            }
            .frame(width: packWidth, height: packHeight)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        let next = min(1, max(0, value.translation.width / 110))
                        tear = next
                        if next > 0.45 { finishTear() }
                    }
                    .onEnded { _ in
                        if tear > 0.18 { finishTear() }
                        else {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tear = 0 }
                        }
                    }
            )
            .onTapGesture { finishTear() }

            Text("今日主牌已备好，拆包看看今天的运势吧")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 26)
        }
        .padding(.top, 14)
    }

    // MARK: 揭晓

    private var revealedView: some View {
        VStack(spacing: 0) {
            CardFan(
                backName: "back",
                faceName: card.slug,
                isFlipped: isFlipped,
                onTapFace: { isDetailPresented = true }
            )
            .frame(height: 376)
            .padding(.top, 8)

            Text("✨ 恭喜获得今日主牌")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.text)
                .padding(.top, 6)

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(card.name)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(card.en)
                    .font(.system(size: 12, design: .serif))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.top, 6)

            HStack(spacing: 6) {
                ForEach(card.keywords(reversed: isReversed), id: \.self) { keyword in
                    AccentChip(text: keyword)
                }
            }
            .padding(.top, 10)

            Text("点击牌面查看牌义")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 10)

            Button {
                redraw()
            } label: {
                Text("重新抽一张")
                    .font(.system(size: 14.5, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(Theme.surface)
                    )
            }
            .buttonStyle(PressableStyle())
            .padding(.top, 14)
        }
    }

    // MARK: 动作

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let today = TarotService.ensureToday(in: context)
        draw = today
        phase = today.isOpened ? .revealed : .sealed
        isFlipped = today.isOpened
        if today.isOpened { confettiToken = 0 }
    }

    private func finishTear() {
        guard phase == .sealed else { return }
        withAnimation(.easeOut(duration: 0.18)) { tear = 1 }
        draw?.isOpened = true
        try? context.save()
        AppLog.info("拆包：今天的牌是 \(card.name)\(isReversed ? "逆位" : "正位")")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                phase = .revealed
            }
            confettiToken += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.42) {
                withAnimation(.spring(response: 0.85, dampingFraction: 0.82)) {
                    isFlipped = true
                }
            }
        }
    }

    private func redraw() {
        guard let draw else { return }
        withAnimation(.easeIn(duration: 0.25)) { isFlipped = false }
        TarotService.redraw(draw, in: context)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            confettiToken += 1
            withAnimation(.spring(response: 0.85, dampingFraction: 0.82)) {
                isFlipped = true
            }
        }
        draw.isOpened = true
        try? context.save()
    }
}

// MARK: - 撕裂形状

/// 保留卡包下方主体，顶部按比例切掉，切口是锯齿状。
struct TornRemainder: Shape {
    var progress: CGFloat
    var ratio: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cut = rect.height * ratio * progress
        path.move(to: CGPoint(x: rect.minX, y: cut))

        var x = rect.minX
        var up = true
        while x < rect.maxX {
            let next = min(x + 7, rect.maxX)
            path.addLine(to: CGPoint(x: next, y: cut + (up ? -2 : 2)))
            x = next
            up.toggle()
        }

        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 牌阵

struct CardFan: View {
    let backName: String
    let faceName: String
    let isFlipped: Bool
    var onTapFace: () -> Void

    private let cardWidth: CGFloat = 196
    private let cardHeight: CGFloat = 297

    var body: some View {
        ZStack {
            mini(index: 0, x: -112, y: 18, angle: -15, scale: 0.9, opacity: 0.8)
            mini(index: 1, x: -64, y: 8, angle: -7.5, scale: 0.95, opacity: 0.95)
            mini(index: 2, x: 64, y: 8, angle: 7.5, scale: 0.95, opacity: 0.95)
            hero
            mini(index: 3, x: 112, y: 18, angle: 15, scale: 0.9, opacity: 0.8)
        }
    }

    private func mini(index: Int, x: CGFloat, y: CGFloat, angle: Double, scale: CGFloat, opacity: Double) -> some View {
        Image(backName)
            .resizable()
            .scaledToFill()
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color(hex: 0x9BD7FF).opacity(0.18), Color(hex: 0xFF9BE0).opacity(0.14), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            )
            .shadow(color: .black.opacity(0.28), radius: 16, y: 10)
            .rotationEffect(.degrees(angle))
            .scaleEffect(scale)
            .offset(x: x, y: y)
            .opacity(opacity)
    }

    private var hero: some View {
        ZStack {
            heroBack
                .opacity(isFlipped ? 0 : 1)

            Image(faceName)
                .resizable()
                .scaledToFill()
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(isFlipped ? 1 : 0)
        }
        .frame(width: cardWidth, height: cardHeight)
        .shadow(color: .black.opacity(0.35), radius: 22, y: 14)
        .rotation3DEffect(.degrees(isFlipped ? 180 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .onTapGesture { if isFlipped { onTapFace() } }
    }

    private var heroBack: some View {
        Image(backName)
            .resizable()
            .scaledToFill()
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [.clear, Color(hex: 0x9BD7FF).opacity(0.22), Color(hex: 0xFF9BE0).opacity(0.18), .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .blendMode(.screen)
                    .allowsHitTesting(false)
            )
    }
}

// MARK: - 纸屑

struct ConfettiOverlay: View {
    let token: Int

    @State private var particles: [Particle] = []
    @State private var start = Date()

    struct Particle: Identifiable {
        let id = UUID()
        let color: Color
        let dx: CGFloat
        let dy: CGFloat
        let rotation: Double
        let delay: Double
        let size: CGSize
        let x: CGFloat
        let y: CGFloat
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                let elapsed = timeline.date.timeIntervalSince(start)
                for p in particles {
                    let t = elapsed - p.delay
                    guard t > 0, t < 2.2 else { continue }
                    let progress = min(1, t / 2.0)
                    let ease = 1 - pow(1 - progress, 2)
                    let center = CGPoint(
                        x: size.width * p.x + p.dx * CGFloat(ease),
                        y: size.height * p.y + p.dy * CGFloat(ease * ease)
                    )
                    let alpha = progress < 0.08 ? progress / 0.08 : max(0, 1 - (progress - 0.55) / 0.45)
                    guard alpha > 0.02 else { continue }

                    var context = ctx
                    context.translateBy(x: center.x, y: center.y)
                    context.rotate(by: .degrees(p.rotation * progress))
                    context.opacity = alpha

                    let rect = CGRect(
                        x: -p.size.width / 2,
                        y: -p.size.height / 2,
                        width: p.size.width,
                        height: p.size.height
                    )
                    context.fill(Path(roundedRect: rect, cornerRadius: 1.5), with: .color(p.color))
                }
            }
        }
        .onChange(of: token) { _, _ in spawn() }
        .onAppear { if token > 0 { spawn() } }
    }

    private func spawn() {
        let colors: [Color] = [
            Color(hex: 0xFF7AB6), Color(hex: 0x7AD1FF), Color(hex: 0xFFD77A),
            Color(hex: 0xA58BFF), Color(hex: 0x7BE0A8), Color(hex: 0xFF9F7A)
        ]
        particles = (0..<56).map { index in
            let angle = Double.random(in: 0...(2 * .pi))
            let distance = CGFloat.random(in: 70...250)
            return Particle(
                color: colors[index % colors.count],
                dx: CGFloat(cos(angle)) * distance,
                dy: CGFloat(sin(angle)) * distance * 0.6 + 220,
                rotation: Double.random(in: -360...360),
                delay: Double.random(in: 0...0.12),
                size: CGSize(width: CGFloat.random(in: 5...10), height: CGFloat.random(in: 8...16)),
                x: CGFloat.random(in: 0.44...0.56),
                y: CGFloat.random(in: 0.24...0.32)
            )
        }
        start = Date()
    }
}

// MARK: - 牌义

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
        if let image = UIImage(named: name) { return image }
        for ext in ["webp", "png", "jpg"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        return nil
    }
}
