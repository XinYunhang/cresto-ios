import SwiftUI
import SwiftData
import UIKit

/// 每日一抽 · 塔罗抽牌模块
///
/// 四阶段状态机（防剧透时序）：
///   sealed（未拆封）→ tearing（跟手撕开中）→ fannedOut（牌堆抽出展开）→ revealed（90° 翻牌揭晓）
///
/// 物理与光影参数移植自 holo-reverse（github.com/xxbb11122/holo-reverse，_ref/app.js + _ref/styles.css）：
/// - Spring(response, bounce) → SwiftUI `.spring(response:, dampingFraction: 1 - bounce)`
///   卡包回弹 .7/.28（阻尼 0.72）、牌堆展开按需求固定 .45/0.72 错峰延迟
/// - 撕裂方向锁：|dx| ≥ 8 且 |dx| > |dy|·0.5 才开始撕；进度 = dx·dir/(包宽·0.85)，只进不退
/// - 撕条抛飞：横向 easeOut 飞出 + 纵向 easeOut 上抛（-150）转 easeIn 重力坠落（+520），带旋转与渐隐
/// - 彩带粒子：重力 2600pt/s²、隐式阻力 1/(1 + c·min(1, .06+age/.45)·v·dt)、侧滑 slip/glide、
///   翻滚透视压扁 cos((rot-rot0)·0.7°)，三类形状（圆点/彩带/星尘）、七彩+白
/// - 全息层：110° 多色循环渐变（400% 幅面随倾斜流动）+ .colorDodge + 阈值噪点闪粉 + 径向 glare
struct TarotView: View {
    @Environment(\.modelContext) private var context

    @State private var draw: DailyTarot?
    @State private var didLoad = false
    @State private var phase: Phase = .sealed
    @State private var isDetailPresented = false
    /// 重新抽流程标记：撕包动作完成后才执行随机换牌（TarotService.redraw）
    @State private var isRedraw = false

    // MARK: sealed —— 跟手撕包
    @State private var tearProgress: CGFloat = 0
    @State private var tearDirection: CGFloat = -1
    @State private var tearStarted = false
    @State private var packTilt: CGSize = .zero
    @State private var deform: CGFloat = 0
    @State private var jag: [CGFloat] = TarotView.makeJag()

    // MARK: tearing —— 撕条抛飞 + 卡包坠出
    @State private var stripFlying = false
    @State private var stripBase: CGSize = .zero
    @State private var stripBaseRotation: Double = 0
    @State private var stripFlyX: CGFloat = 0
    @State private var stripFlyY: CGFloat = 0
    @State private var stripFlyRotation: Double = 0
    @State private var stripFlyOpacity: Double = 1
    @State private var packDropped = false

    // MARK: fannedOut —— 牌堆抽出扇形展开
    @State private var fanSpread = false

    // MARK: revealed —— 90° 翻牌揭晓
    @State private var flipAngle: Double = 0
    @State private var revealShown = false
    @State private var confettiToken = 0

    // MARK: 全息倾斜（DragGesture 驱动）
    @State private var holoDrag: CGSize = .zero

    enum Phase { case sealed, tearing, fannedOut, revealed }

    private var card: TarotCard { draw?.card ?? TarotDeck.major[0] }
    private var isReversed: Bool { draw?.isReversed ?? false }

    private let packWidth: CGFloat = 236
    private let packHeight: CGFloat = 386
    /// 撕口位置（占卡包高度比例），与素材撕裂线一致
    private let tearRatio: CGFloat = 0.358
    private let cardWidth: CGFloat = 196
    private let cardHeight: CGFloat = 297

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                header

                if !didLoad {
                    // 首帧占位：onAppear 恢复状态前不渲染任何牌面/文字，杜绝重启闪屏
                    Color.clear.frame(height: 440)
                } else if phase == .sealed || phase == .tearing {
                    sealedScene
                        .transition(.opacity)
                } else {
                    fanScene
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 128)
        }
        .overlay {
            ConfettiOverlay(token: confettiToken)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $isDetailPresented) {
            TarotReadingSheet(card: card, isReversed: isReversed)
        }
        .onAppear(perform: load)
    }

    // MARK: - 页头（全局结构，未改动）

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

    // MARK: - 阶段 1/2：sealed + tearing（卡包、撕条、跟手物理）

    private var sealedScene: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("👆").font(.system(size: 14))
                Text("拖动 / 点击撕开")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
            .opacity(Double(max(0, 1 - tearProgress * 4)))
            .padding(.bottom, 16)

            ZStack(alignment: .top) {
                // 下半截卡包：随撕裂进度裁切，重力坠出
                packBody
                // 顶部撕条：跟手层 / 抛飞层（同一素材同一坐标系，禁止先隐藏再瞬移）
                if !stripFlying {
                    stripLayer
                } else {
                    flyingStrip
                }
            }
            .frame(width: packWidth, height: packHeight)
            .contentShape(Rectangle())
            .gesture(packTiltGesture)
            .overlay(alignment: .top) {
                tearZone
            }

            Text("今日主牌已备好，拆包看看今天的运势吧")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .opacity(tearProgress < 0.02 && !stripFlying ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: tearProgress)
                .padding(.top, 26)
        }
        .padding(.top, 14)
    }

    /// 卡包下半截：3D 倾斜 + 阻力形变 + 撕裂裁切 + 坠落退场
    private var packBody: some View {
        AssetImage.image("pack")
            .resizable()
            .scaledToFit()
            .mask(TornEdge(keepBelow: true, progress: tearProgress, ratio: tearRatio, jitter: jag))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 12)
            .scaleEffect(x: 1 + deform * 0.02, y: 1 - deform * 0.028)
            .rotation3DEffect(.degrees(packTilt.width), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
            .rotation3DEffect(.degrees(-packTilt.height), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
            .offset(y: packDropped ? 1150 : 0)
            .rotationEffect(.degrees(packDropped ? Double(tearDirection * 9) : 0), anchor: .bottom)
    }

    /// 跟手中的撕条：位移/微旋与手指 1:1（不挂隐式动画）
    private var stripLayer: some View {
        AssetImage.image("torn-strip")
            .resizable()
            .scaledToFit()
            .mask(TornEdge(keepBelow: false, progress: tearProgress, ratio: tearRatio, jitter: jag))
            .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
            .rotationEffect(
                .degrees(-tearDirection * tearProgress * 7),
                anchor: tearDirection < 0 ? .topLeading : .topTrailing
            )
            .offset(x: tearDirection * tearProgress * 46, y: -tearProgress * 58)
    }

    /// 抛飞中的撕条：从冻结的跟手位置出发做抛物线 + 旋转 + 渐隐（位置连续，无瞬移）
    private var flyingStrip: some View {
        AssetImage.image("torn-strip")
            .resizable()
            .scaledToFit()
            .mask(TornEdge(keepBelow: false, progress: 1, ratio: tearRatio, jitter: jag))
            .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
            .rotationEffect(
                .degrees(stripBaseRotation + stripFlyRotation),
                anchor: tearDirection < 0 ? .topLeading : .topTrailing
            )
            .offset(x: stripBase.width + stripFlyX, y: stripBase.height + stripFlyY)
            .opacity(stripFlyOpacity)
    }

    /// 顶部虚线撕口区：撕包 DragGesture + 点击快捷触发
    private var tearZone: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: packHeight * tearRatio + 24)
            .contentShape(Rectangle())
            .gesture(tearGesture)
            .onTapGesture { beginTearTap() }
    }

    /// 整卡拖动：微弱 3D 倾斜反馈；松手按 holo-reverse 卡包弹簧（response .7, 阻尼 .72）回正
    private var packTiltGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard phase == .sealed, !stripFlying else { return }
                packTilt = CGSize(
                    width: max(-140, min(140, value.translation.width)) * 0.1,
                    height: max(-140, min(140, value.translation.height)) * 0.08
                )
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.7, dampingFraction: 0.72)) {
                    packTilt = .zero
                }
            }
    }

    /// 撕口区拖动：方向锁 → 跟手进度（只进不退）→ 超阈值抛飞
    private var tearGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !stripFlying, phase == .sealed || phase == .tearing else { return }
                let dx = value.translation.width
                let dy = value.translation.height
                // 撕包全程给卡包微弱 3D 倾斜反馈
                packTilt = CGSize(
                    width: max(-140, min(140, dx)) * 0.07,
                    height: max(-140, min(140, dy)) * 0.05
                )
                if !tearStarted {
                    // holo-reverse 方向锁：横向意图足够强才开始撕，否则只是拽动卡包
                    if abs(dx) < 8 || abs(dx) < abs(dy) * 0.5 { return }
                    tearDirection = dx < 0 ? -1 : 1
                    tearStarted = true
                    phase = .tearing
                }
                // 进度 = dx·dir/(宽·0.85)，只进不退（已撕开的部分不回退）
                let progress = max(0, min(1, dx * tearDirection / (packWidth * 0.85)))
                tearProgress = max(tearProgress, progress)
                deform = tearProgress
            }
            .onEnded { _ in
                guard !stripFlying else { return }
                if tearProgress > 0.45 {
                    finishTear()
                } else {
                    // 未到阈值：倾斜与形变弹回；几乎没撕的直接归位，半撕状态保留可续撕
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                        packTilt = .zero
                        deform = 0
                    }
                    if tearProgress < 0.12 {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                            tearProgress = 0
                        }
                        tearStarted = false
                        phase = .sealed
                    }
                }
            }
    }

    /// 点击快捷撕包：沿默认方向（左上）立即完成
    private func beginTearTap() {
        guard phase == .sealed || (phase == .tearing && !stripFlying) else { return }
        if !tearStarted {
            tearDirection = -1
            tearStarted = true
            phase = .tearing
        }
        finishTear()
    }

    // MARK: - 撕包完成：抛飞、坠出、换牌绑定、牌堆登场

    private func finishTear() {
        guard phase == .sealed || phase == .tearing, !stripFlying else { return }
        phase = .tearing

        // 冻结撕条当前跟随位置作为抛飞起点（位置连续，杜绝“先消失再瞬移”）
        stripBase = CGSize(width: tearDirection * tearProgress * 46, height: -tearProgress * 58)
        stripBaseRotation = Double(-tearDirection * tearProgress * 7)
        stripFlying = true

        // 撕口裁切补完到整条撕线
        withAnimation(.easeOut(duration: 0.18)) {
            tearProgress = 1
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
            deform = 0
            packTilt = .zero
        }

        // 撕条抛飞：横向 easeOut 飞出（沿撕开方向，默认朝左上）
        withAnimation(.easeOut(duration: 0.3)) {
            stripFlyX = tearDirection * 320
        }
        // 纵向上抛减速（easeOut），随后重力加速坠落（easeIn）——参考 ref: vy=-1900, g=2600
        withAnimation(.easeOut(duration: 0.26)) {
            stripFlyY = -150
        }
        withAnimation(.easeIn(duration: 0.55).delay(0.26)) {
            stripFlyY = 520
        }
        withAnimation(.easeOut(duration: 0.5)) {
            stripFlyRotation = Double(tearDirection * -42)
        }
        withAnimation(.linear(duration: 0.22).delay(0.52)) {
            stripFlyOpacity = 0
        }

        // 卡包下半截：重力坠出屏幕（ref: fall.v=1500, g=2800，坠落时朝撕开方向倾倒 9°）
        withAnimation(.easeIn(duration: 0.55)) {
            packDropped = true
        }

        // ★ 数据绑定时序：撕包动作完成后才执行随机换牌/开牌，绝不允许提前渲染新牌
        if let draw {
            if isRedraw {
                TarotService.redraw(draw, in: context)
            } else {
                draw.isOpened = true
                try? context.save()
            }
            AppLog.info("拆包：今天的牌是 \(draw.card.name)\(draw.isReversed ? "逆位" : "正位")")
        }

        // 牌堆在卡包坠出后登场
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                phase = .fannedOut
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                // 5 张牌背从中心叠合状态抽出，向两侧错峰弹簧展开
                withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) {
                    fanSpread = true
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                startFlip()
            }
        }
    }

    // MARK: - 阶段 3/4：fannedOut + revealed（牌阵、90° 翻牌、全息、揭晓文字）

    private var fanScene: some View {
        VStack(spacing: 0) {
            ZStack {
                fanCard(index: -2)
                fanCard(index: -1)
                fanCard(index: 1)
                fanCard(index: 2)
                heroCard
            }
            .frame(height: 376)
            .padding(.top, 8)

            // ★ 结果文字全部由 revealShown 门控：主牌翻过 90°（phase == .revealed）才伴随弹簧逐条淡入
            staged(0.05) {
                Text("✨ 恭喜获得今日主牌")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.text)
            }
            .padding(.top, 6)

            staged(0.12) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(card.name)
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(card.en)
                        .font(.system(size: 12, design: .serif))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.top, 6)

            staged(0.2) {
                HStack(spacing: 6) {
                    ForEach(card.keywords(reversed: isReversed), id: \.self) { keyword in
                        AccentChip(text: keyword)
                    }
                }
            }
            .padding(.top, 10)

            staged(0.28) {
                Text("点击牌面查看牌义")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.top, 10)

            staged(0.36) {
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
            }
            .padding(.top, 14)
        }
    }

    /// 揭晓态文字的统一出场包装：隐藏时完全不可见且不响应点击
    @ViewBuilder
    private func staged(_ delay: Double, @ViewBuilder content: () -> some View) -> some View {
        content()
            .opacity(revealShown ? 1 : 0)
            .offset(y: revealShown ? 0 : 14)
            .allowsHitTesting(revealShown)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(delay), value: revealShown)
    }

    /// 扇形两侧牌背：叠合(中心下方) → 错峰弹簧展开
    private func fanCard(index: Int) -> some View {
        let pose = fanSpread ? FanPose.fan(index) : FanPose.stacked
        let delay = Double(abs(index)) * 0.06
        return AssetImage.image("back")
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
            .rotationEffect(.degrees(pose.angle))
            .scaleEffect(pose.scale)
            .offset(x: pose.x, y: pose.y)
            .opacity(pose.opacity)
            .animation(.spring(response: 0.45, dampingFraction: 0.72).delay(delay), value: fanSpread)
    }

    /// 中心主牌：升起 → Y 轴 180° 翻转（90° 临界切换正反面）→ 全息镭射 + 倾斜手势
    private var heroCard: some View {
        ZStack {
            heroBack
                .modifier(FaceGate(angle: flipAngle, front: false))
            heroFace
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .modifier(FaceGate(angle: flipAngle, front: true))
        }
        .frame(width: cardWidth, height: cardHeight)
        .shadow(color: .black.opacity(0.35), radius: 22, y: 14)
        .rotation3DEffect(.degrees(holoTiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.68)
        .rotation3DEffect(.degrees(holoTiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.68)
        .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .offset(x: fanSpread ? 0 : FanPose.stacked.x, y: fanSpread ? 0 : FanPose.stacked.y)
        .scaleEffect(fanSpread ? 1 : FanPose.stacked.scale)
        .opacity(fanSpread ? 1 : 0)
        .animation(.spring(response: 0.45, dampingFraction: 0.72), value: fanSpread)
        .onTapGesture {
            if phase == .revealed { isDetailPresented = true }
        }
        .simultaneousGesture(holoGesture)
    }

    private var heroBack: some View {
        AssetImage.image("back")
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

    /// 正面立绘 + 全息镭射光影层（只在翻过 90° 后可见）
    private var heroFace: some View {
        ZStack {
            AssetImage.image(card.slug)
                .resizable()
                .scaledToFill()
            HoloShine(nx: holoTiltY / 24, ny: holoTiltX / 24, active: revealShown)
                .opacity(revealShown ? 1 : 0)
            glaze
        }
        .frame(width: cardWidth, height: cardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .allowsHitTesting(true)
    }

    /// 卡面清漆：边缘高光 + 顶部光泽
    private var glaze: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2))
        }
    }

    /// 揭晓后拖动主牌：卡身倾斜 + 驱动全息层反光流动
    private var holoGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard phase == .revealed else { return }
                holoDrag = value.translation
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                    holoDrag = .zero
                }
            }
    }

    private var holoTiltY: Double {
        guard phase == .revealed else { return 0 }
        return Double(max(-10, min(10, holoDrag.width * 0.07)))
    }

    private var holoTiltX: Double {
        guard phase == .revealed else { return 0 }
        return Double(max(-8, min(8, -holoDrag.height * 0.06)))
    }

    // MARK: - 翻牌：0° → 90°（临界切换）→ 180°，过 90° 瞬间触发全屏彩带 + 揭晓文字

    private func startFlip() {
        withAnimation(.easeInOut(duration: 0.32)) {
            flipAngle = 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.33) {
            // ★ 主牌翻过 90° 的瞬间：全屏彩带 + 揭晓文字 + 进入 revealed
            confettiToken += 1
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                revealShown = true
                phase = .revealed
            }
            withAnimation(.spring(response: 0.85, dampingFraction: 0.82)) {
                flipAngle = 180
            }
        }
    }

    // MARK: - 生命周期

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let today = TarotService.ensureToday(in: context)
        draw = today
        isRedraw = false
        if today.isOpened {
            // 今天已拆过：直接进入揭晓态，无彩带
            phase = .revealed
            fanSpread = true
            flipAngle = 180
            revealShown = true
        } else {
            phase = .sealed
            tearProgress = 0
            tearStarted = false
            tearDirection = -1
        }
    }

    /// 重新抽：立即清空牌面与文字并切回 sealed 展示密封卡包；
    /// 新塔罗牌的随机抽取延迟到撕包动作完成（finishTear → TarotService.redraw）
    private func redraw() {
        guard phase == .revealed else { return }
        isRedraw = true
        // 只把记录标记为未拆（牌面数据不动，首页继续显示旧牌，不剧透）
        if let draw {
            TarotService.markUnopened(draw, in: context)
        }
        // 同步清空一切揭晓态（此刻均不可见，直接赋值）
        flipAngle = 0
        revealShown = false
        fanSpread = false
        tearProgress = 0
        tearStarted = false
        stripFlying = false
        stripBase = .zero
        stripBaseRotation = 0
        stripFlyX = 0
        stripFlyY = 0
        stripFlyRotation = 0
        stripFlyOpacity = 1
        packDropped = false
        holoDrag = .zero
        deform = 0
        packTilt = .zero
        jag = TarotView.makeJag()
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = .sealed
        }
    }

    /// 每次装包生成一条新的不规则撕裂线：斜率 + 弓形 + 随机游走 + 锯齿（移植自 ref path()，96 段精简为 56 段）
    static func makeJag() -> [CGFloat] {
        let segments = 56
        let slope = CGFloat.random(in: -2.5...2.5)
        let bow = CGFloat.random(in: -1.5...1.5)
        var walk: CGFloat = 0
        var jitter: [CGFloat] = []
        jitter.reserveCapacity(segments + 1)
        for i in 0...segments {
            let s = CGFloat(i) / CGFloat(segments) * 2 - 1
            walk = max(-1.2, min(1.2, walk + CGFloat.random(in: -0.35...0.35) + (Bool.random() ? 0.45 : -0.45)))
            let tooth: CGFloat = Bool.random() ? 0.4 : -0.4
            jitter.append((slope * s + bow * (1 - s * s) + walk + tooth) / 100)
        }
        return jitter
    }
}

// MARK: - 扇形牌位

private struct FanPose {
    let x: CGFloat
    let y: CGFloat
    let angle: Double
    let scale: CGFloat
    let opacity: Double

    /// 叠合状态：从卡包口（中心下方）抽出
    static let stacked = FanPose(x: 0, y: 96, angle: 0, scale: 0.86, opacity: 0)

    static func fan(_ index: Int) -> FanPose {
        switch index {
        case -2: FanPose(x: -112, y: 18, angle: -15, scale: 0.9, opacity: 0.85)
        case -1: FanPose(x: -64, y: 8, angle: -7.5, scale: 0.95, opacity: 0.95)
        case 1: FanPose(x: 64, y: 8, angle: 7.5, scale: 0.95, opacity: 0.95)
        default: FanPose(x: 112, y: 18, angle: 15, scale: 0.9, opacity: 0.85)
        }
    }
}

// MARK: - 90° 防穿帮翻转

/// AnimatableModifier 在动画的每一帧用插值后的角度重算可见性：
/// 牌背在角度 < 90° 时可见，正面立绘在角度 ≥ 90° 的那一帧才显示，
/// 配合正面预置 180° Y 轴旋转完成镜像修正，翻转中途永不透出。
private struct FaceGate: ViewModifier, Animatable {
    var angle: Double
    var front: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let faceUp = angle >= 90
        content.opacity((front == faceUp) ? 1 : 0)
    }
}

// MARK: - 全息镭射光影层（Holo Shader）

/// 全息素材：阈值化闪粉噪点（对应 ref --glitter：feTurbulence + feColorMatrix 阈值切白点）
enum HoloAssets {
    static let glitter: UIImage = {
        let side = 420
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
        return renderer.image { context in
            let cg = context.cgContext
            cg.clear(CGRect(x: 0, y: 0, width: side, height: side))
            for _ in 0..<7000 {
                let v = Double.random(in: 0...1)
                guard v > 0.88 else { continue }
                let alpha = (v - 0.88) / 0.12 * 0.85
                let size = CGFloat.random(in: 0.7...2.4)
                cg.setFillColor(UIColor(white: 1, alpha: alpha).cgColor)
                cg.fill(CGRect(x: CGFloat.random(in: 0..<side), y: CGFloat.random(in: 0..<side), width: size, height: size))
            }
        }
    }()

    /// 多色斜向循环渐变（对应 ref --rainbow：repeating-linear-gradient(110deg, ...)，
    /// 16 个循环保证主牌视窗内始终有 4 条以上色带可供流动）
    static let rainbow: Gradient = {
        let palette: [Color] = [
            Color(hex: 0xFF7AA8), Color(hex: 0xFFCF6B), Color(hex: 0xA8FF8A),
            Color(hex: 0x6BE2FF), Color(hex: 0x9B8CFF)
        ]
        var stops: [Gradient.Stop] = []
        let cycles = 16
        for c in 0...cycles {
            for (i, color) in palette.enumerated() {
                stops.append(.init(color: color, location: CGFloat(c) / CGFloat(cycles) + CGFloat(i) / (5 * CGFloat(cycles))))
            }
        }
        return Gradient(stops: stops)
    }()
}

/// 全息反光层：随倾斜 nx/ny（-1...1）流动。公式对应 ref：
/// --px = 50 + nx·50，--py = 50 - ny·50，hyp = min(1, hypot(nx, ny))
struct HoloShine: View {
    var nx: CGFloat
    var ny: CGFloat
    /// 静置流光只在揭晓后运行，避免空转
    var active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let idleX = sin(t * 0.55) * 0.14
            let idleY = cos(t * 0.42) * 0.1
            shine(
                nx: max(-1, min(1, nx + idleX)),
                ny: max(-1, min(1, ny + idleY))
            )
        }
        .allowsHitTesting(false)
    }

    private func shine(nx: CGFloat, ny: CGFloat) -> some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let px = 0.5 + nx * 0.5
            let py = 0.5 - ny * 0.5
            let hyp = min(1, sqrt(nx * nx + ny * ny))
            ZStack {
                // 彩虹层：400% 幅面的斜向循环渐变，位置随倾斜流动（110° 方向：CSS y-up → SwiftUI y-down）
                LinearGradient(
                    gradient: HoloAssets.rainbow,
                    startPoint: UnitPoint(x: 0.03, y: 0.33),
                    endPoint: UnitPoint(x: 0.97, y: 0.67)
                )
                    .frame(width: w * 4, height: h * 4)
                    .offset(x: (px - 0.5) * w * 3, y: (py - 0.5) * h * 3)
                    .saturation(1.4)
                    .brightness(-0.22)
                    .blendMode(.colorDodge)
                    .opacity(0.26 + hyp * 0.5)
                // 闪粉噪点层（ref: --glitter 遮罩 + brightness(1.8)）
                Image(uiImage: HoloAssets.glitter)
                    .resizable()
                    .blendMode(.plusLighter)
                    .opacity(0.16 + hyp * 0.3)
                // 镜面炫光（ref: --glare 径向高光 + overlay）
                RadialGradient(
                    colors: [.white.opacity(0.85), .white.opacity(0.14), .black.opacity(0.22)],
                    center: UnitPoint(x: px, y: py),
                    startRadius: 0,
                    endRadius: max(w, h) * 0.95
                )
                .blendMode(.overlay)
                .opacity(0.3 + hyp * 0.55)
            }
        }
    }
}

// MARK: - 撕裂形状

/// 不规则锯齿撕口：progress 驱动撕口位置（可动画），jitter 是每次装包随机生成的撕裂线
struct TornEdge: Shape {
    var keepBelow: Bool
    var progress: CGFloat
    var ratio: CGFloat
    var jitter: [CGFloat]

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let cut = rect.height * ratio * progress
        let segments = max(1, jitter.count - 1)
        // 未撕开时锯齿幅度归零，保证与素材撕裂线完全重合
        let amp = max(0, min(1, progress * 4))
        var path = Path()
        var first = true
        for i in 0...segments {
            let x = rect.minX + rect.width * CGFloat(i) / CGFloat(segments)
            let j = jitter[min(i, jitter.count - 1)]
            let y = cut + j * rect.height * amp + (i % 2 == 0 ? -2 : 2) * progress
            if first {
                path.move(to: CGPoint(x: x, y: y))
                first = false
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        if keepBelow {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - 全屏彩带粒子（Canvas + TimelineView）

/// 粒子物理存储：Canvas 逐帧积分，不走 SwiftUI 状态，避免每帧视图重建。
/// 物理直接移植自 holo-reverse 的 bits：重力 2600、隐式阻力、侧滑、翻滚压扁。
final class ConfettiStore {
    struct Bit {
        let kind: Int          // 0 圆点 / 1 彩带 / 2 星尘
        let color: Color
        let rx: CGFloat        // 全屏横向出生点 0...1
        let ry: CGFloat        // 纵向出生点 0...1
        let angle: CGFloat     // 抛射角
        let speed: CGFloat
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        let c: CGFloat         // 阻力系数 = 2600 / vt²
        let slip: CGFloat
        let glide: CGFloat
        var ph: CGFloat
        let spin: CGFloat
        var rot: CGFloat
        var rot0: CGFloat = 0
        let sc: CGFloat
        let delay: Double
        var age: Double = 0
    }

    var bits: [Bit] = []
    var last: Date?

    /// 全屏爆发：横向 6%~94% 均匀散布，七彩+白，三层延迟错峰
    func launch() {
        let colors: [Color] = [
            Color(hex: 0xFF3D6E), Color(hex: 0xFF8A3D), Color(hex: 0xFFD34D),
            Color(hex: 0x4FD9A0), Color(hex: 0x4FB2FF), Color(hex: 0x8B6CFF),
            Color(hex: 0xFF5CC8), .white
        ]
        bits = (0..<130).map { i in
            let rx = CGFloat.random(in: 0.06...0.94)
            let vt = 260 + 400 * pow(CGFloat.random(in: 0...1), 1.5)
            return Bit(
                kind: i % 3,
                color: colors[i % colors.count],
                rx: rx,
                ry: CGFloat.random(in: 0.24...0.4),
                angle: ((rx - 0.5) * 2 + CGFloat.random(in: -0.5...0.5)) * 0.85,
                speed: CGFloat.random(in: 500...2400),
                c: 2600 / (vt * vt),
                slip: CGFloat.random(in: 900...2600),
                glide: (rx < 0.5 ? -1 : 1) * CGFloat.random(in: -200...900),
                ph: CGFloat.random(in: 0...(2 * .pi)),
                spin: CGFloat.random(in: -700...700),
                rot: CGFloat.random(in: 0...360),
                sc: CGFloat.random(in: 0.9...1.9),
                delay: i < 60 ? 0 : Double.random(in: 0...0.28)
            )
        }
        last = nil
    }

    func step(dt: Double, height: CGFloat) {
        var alive: [Bit] = []
        alive.reserveCapacity(bits.count)
        for index in bits.indices {
            bits[index].age += dt
            guard bits[index].age >= bits[index].delay else {
                alive.append(bits[index])
                continue
            }
            let t = bits[index].age - bits[index].delay
            var b = bits[index]
            if b.vx == 0, b.vy == 0 {
                b.vx = sin(b.angle) * b.speed
                b.vy = -cos(b.angle) * b.speed
            }
            // 重力 + 翻滚侧滑（ref: vy += 2600·dt; vx += (sin(ph)·slip + glide)·dt）
            b.vy += 2600 * dt
            b.vx += (sin(b.ph) * b.slip + b.glide) * dt
            // 隐式阻力（一簇纸片先整体冲出，再各自进入终端速度，保证不反向过冲）
            let v = sqrt(b.vx * b.vx + b.vy * b.vy)
            let dragK = 1 / (1 + b.c * min(1, 0.06 + t / 0.45) * v * dt)
            b.vx *= dragK
            b.vy *= dragK
            b.x += b.vx * dt
            b.y += b.vy * dt
            let turn = 0.35 + v / 800
            b.rot += b.spin * turn * dt
            b.ph += 7 * turn * dt
            // 落出屏幕底部或寿命到期后回收
            if height * b.ry + b.y < height + 80, t < 3.2 {
                alive.append(b)
            }
        }
        bits = alive
    }

    static let sparklePath: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -6))
        p.addLine(to: CGPoint(x: 1.3, y: -1.3))
        p.addLine(to: CGPoint(x: 6, y: 0))
        p.addLine(to: CGPoint(x: 1.3, y: 1.3))
        p.addLine(to: CGPoint(x: 0, y: 6))
        p.addLine(to: CGPoint(x: -1.3, y: 1.3))
        p.addLine(to: CGPoint(x: -6, y: 0))
        p.addLine(to: CGPoint(x: -1.3, y: -1.3))
        p.closeSubpath()
        return p
    }()
}

struct ConfettiOverlay: View {
    let token: Int

    @State private var store = ConfettiStore()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, size in
                guard !store.bits.isEmpty else { return }
                let now = timeline.date
                let dt = store.last.map { min(0.05, max(0.001, now.timeIntervalSince($0))) } ?? (1.0 / 60.0)
                store.last = now
                store.step(dt: dt, height: size.height)
                for bit in store.bits where bit.age >= bit.delay {
                    draw(bit, into: &ctx, size: size)
                }
            }
        }
        .onChange(of: token) { _, _ in
            store.launch()
        }
    }

    private func draw(_ bit: ConfettiStore.Bit, into ctx: inout GraphicsContext, size: CGSize) {
        let t = bit.age - bit.delay
        guard t > 0 else { return }
        var alpha = min(1, t / 0.08)
        if t > 2.1 { alpha *= max(0, 1 - (t - 2.1) / 0.5) }
        guard alpha > 0.02 else { return }
        var c = ctx
        c.translateBy(x: size.width * bit.rx + bit.x, y: size.height * bit.ry + bit.y)
        c.rotate(by: .degrees(bit.rot))
        // 翻滚透视压扁（ref: cq = cos((rot - rot0)·0.7°)）
        let cq = abs(cos((bit.rot - bit.rot0) * 0.7 * .pi / 180))
        c.scaleBy(x: bit.sc, y: bit.sc * max(0.18, cq))
        c.opacity = alpha
        switch bit.kind {
        case 0:
            c.fill(Path(ellipseIn: CGRect(x: -4.5, y: -4.5, width: 9, height: 9)), with: .color(bit.color))
        case 1:
            c.fill(Path(roundedRect: CGRect(x: -3.5, y: -6, width: 7, height: 12), cornerRadius: 2), with: .color(bit.color))
        default:
            c.fill(ConfettiStore.sparklePath, with: .color(bit.color))
        }
    }
}

// MARK: - 素材加载

/// SwiftUI 的 Image("name") 找不到直接扔进 bundle 的松散文件（webp/png），
/// 这里走 Bundle.url + UIImage(contentsOfFile:) 显式加载。
enum AssetImage {
    static func ui(_ name: String) -> UIImage? {
        if let image = UIImage(named: name) { return image }
        for ext in ["png", "webp", "jpg", "jpeg"] {
            if let url = Bundle.main.url(forResource: name, withExtension: ext),
               let image = UIImage(contentsOfFile: url.path) {
                return image
            }
        }
        AppLog.warn("素材缺失：\(name)")
        return nil
    }

    static func image(_ name: String) -> Image {
        if let ui = ui(name) { return Image(uiImage: ui) }
        return Image(systemName: "rectangle.dashed")
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
