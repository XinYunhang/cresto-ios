import SwiftUI
import SwiftData
import UIKit

/// 每日一抽 · 塔罗抽牌模块（三牌阵 · 环形牌轮版）
///
/// 四阶段状态机：
///   sealed（未拆封）→ tearing（撕包仪式）→ wheelSelection（环形牌轮选 3 张）→ spreadRevealed（三牌阵翻牌揭晓）
///
/// 交互与动画要点：
/// - 撕条 0.35s 抛物线飞出（右上/左上、旋转 25°、渐隐），卡包本体 spring(0.25, 0.6) 短促回弹
/// - 卡包退场：原地向下微移 40pt + 缩小至 0.88 + 快速渐隐（PackExit 过渡），与环形牌轮从卡包中心
///   同帧交叉展开，画面无空白断层
/// - TarotWheelView：22 张大阿卡纳牌背按等分角度排在圆周上，圆心偏移至 (0.82w, 0.54h)、半径 0.68w，
///   左侧牌弧正好落在单手拇指热区；上下拖动带惯性旋转，点选牌背沿圆心法线外弹 28pt + scale 1.12 并锁定
/// - 三牌阵（左·过去 / 中·现在 / 右·未来）：选满 3 张后牌轮淡出、卡牌飞入屏幕中央展开，
///   支持逐张点击翻转与「一键全部翻开」；FaceGate 在 90° 帧无缝切换正反面（正面预置 180° 镜像修正），
///   阴影透明度绑定 abs(cos(angle))，90° 垂直瞬间归零，彻底消除黑色竖线
/// - 每张牌的牌名/关键词与「查看牌阵解读」入口，仅在对应卡牌翻过 90° 后伴随 .spring() 淡入
/// - 「重新抽一张」：立即清空已选数组/翻牌/文字/粒子状态（clearToken），以无重影方式切回 sealed，
///   新牌池在进入新一轮选牌时重新洗牌生成
struct TarotView: View {
    @Environment(\.modelContext) private var context

    @State private var draw: DailyTarot?
    @State private var didLoad = false
    @State private var phase: Phase = .sealed
    @State private var isRedraw = false
    @State private var isReadingPresented = false

    // MARK: sealed —— 跟手撕包
    @State private var tearProgress: CGFloat = 0
    @State private var tearDirection: CGFloat = -1
    @State private var tearStarted = false
    @State private var packTilt: CGSize = .zero
    @State private var deform: CGFloat = 0
    @State private var jag: [CGFloat] = TarotView.makeJag()

    // MARK: tearing —— 撕条抛飞 + 卡包退场
    @State private var stripFlying = false
    @State private var stripBase: CGSize = .zero
    @State private var stripBaseRotation: Double = 0
    @State private var stripFlyX: CGFloat = 0
    @State private var stripFlyY: CGFloat = 0
    @State private var stripFlyRotation: Double = 0
    @State private var stripFlyOpacity: Double = 1
    @State private var packRecoil = false

    // MARK: wheelSelection —— 环形牌轮
    @State private var pool: [Int] = []
    @State private var poolReversed: [Bool] = []
    @State private var selectedSlots: [Int] = []
    @State private var wheelAngle: Double = 0
    @State private var wheelBorn = false

    // MARK: spreadRevealed —— 三牌阵
    @State private var flipAllToken = 0
    @State private var revealedCount = 0
    @State private var spreadSettled = false
    @State private var loadedOpened = false

    @State private var confettiToken = 0
    @State private var clearToken = 0

    enum Phase { case sealed, tearing, wheelSelection, spreadRevealed }

    private var card: TarotCard { draw?.card ?? TarotDeck.major[0] }

    private let packWidth: CGFloat = 236
    private let packHeight: CGFloat = 386
    /// 撕口位置（占卡包高度比例），与素材撕裂线一致
    private let tearRatio: CGFloat = 0.358
    private let spreadCardWidth: CGFloat = 106
    private let spreadCardHeight: CGFloat = 160

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()

            if !didLoad {
                // 首帧占位：onAppear 恢复状态前不渲染任何牌面/文字，杜绝重启闪屏
                Color.clear
            } else if phase == .sealed || phase == .tearing {
                sealedBranch
                    .transition(.packExit)
            } else if phase == .wheelSelection {
                wheelBranch
                    .transition(.opacity)
            } else {
                // 重新抽时移除必须瞬时（.identity），杜绝旧牌阵与新卡包的半透明双层重影
                spreadBranch
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }

            ConfettiOverlay(token: confettiToken, clearToken: clearToken)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $isReadingPresented) {
            TarotSpreadSheet(
                past: spreadCards.past,
                present: spreadCards.present,
                future: spreadCards.future,
                reversedPast: spreadReversed.past,
                reversedPresent: spreadReversed.present,
                reversedFuture: spreadReversed.future
            )
        }
        .onAppear(perform: load)
    }

    // MARK: - 页头（仅 sealed / spreadRevealed 阶段显示；牌义按钮在完成选牌前禁用）

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
                isReadingPresented = true
            } label: {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.text)
                    .frame(width: 38, height: 38)
                    .glassCircle()
                    .opacity(draw?.isOpened == true ? 1 : 0.4)
            }
            .buttonStyle(PressableStyle())
            .disabled(draw?.isOpened != true)
            .accessibilityLabel("牌阵解读")
        }
        .padding(.top, 2)
        .padding(.bottom, 18)
    }

    // MARK: - 阶段 1/2：sealed + tearing

    private var sealedBranch: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                header
                sealedScene
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 128)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 14)
    }

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
                // 下半截卡包：随撕裂进度裁切，原地微移退场
                packBody
                // 顶部撕条：跟手层 / 抛飞层（同一素材同一坐标系，位置连续无瞬移）
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

            Text("今日牌阵已备好，拆包后从牌轮中抽取 3 张")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .opacity(tearProgress < 0.02 && !stripFlying ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: tearProgress)
                .padding(.top, 26)
        }
    }

    /// 卡包本体：3D 倾斜 + 阻力形变 + 撕裂裁切 + 撕包瞬间的短促弹簧回弹
    private var packBody: some View {
        AssetImage.image("pack")
            .resizable()
            .scaledToFit()
            .mask(TornEdge(keepBelow: true, progress: tearProgress, ratio: tearRatio, jitter: jag))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 12)
            .scaleEffect(x: 1 + deform * 0.02, y: 1 - deform * 0.028)
            .scaleEffect(packRecoil ? 0.96 : 1)
            .rotation3DEffect(.degrees(packTilt.width), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
            .rotation3DEffect(.degrees(-packTilt.height), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
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

    /// 抛飞中的撕条：0.35s 内沿抛物线向右上/左上旋转 25° 并渐隐，绝不在卡包上方悬停平移
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

    /// 整卡拖动：微弱 3D 倾斜反馈；松手按弹簧回正
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
                withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) {
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
                packTilt = CGSize(
                    width: max(-140, min(140, dx)) * 0.07,
                    height: max(-140, min(140, dy)) * 0.05
                )
                if !tearStarted {
                    // 方向锁：横向意图足够强才开始撕，否则只是拽动卡包
                    if abs(dx) < 8 || abs(dx) < abs(dy) * 0.5 { return }
                    tearDirection = dx < 0 ? -1 : 1
                    tearStarted = true
                    phase = .tearing
                }
                let progress = max(0, min(1, dx * tearDirection / (packWidth * 0.85)))
                tearProgress = max(tearProgress, progress)
                deform = tearProgress
            }
            .onEnded { _ in
                guard !stripFlying else { return }
                if tearProgress > 0.45 {
                    finishTear()
                } else {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
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

    // MARK: - 撕包完成：撕条抛飞 + 卡包退场 + 牌轮同帧展开

    private func finishTear() {
        guard phase == .sealed || phase == .tearing, !stripFlying else { return }
        phase = .tearing

        // 冻结撕条当前跟随位置作为抛飞起点（位置连续，杜绝“先消失再瞬移”）
        stripBase = CGSize(width: tearDirection * tearProgress * 46, height: -tearProgress * 58)
        stripBaseRotation = Double(-tearDirection * tearProgress * 7)
        stripFlying = true

        // 撕口裁切补完到整条撕线
        withAnimation(.easeOut(duration: 0.15)) {
            tearProgress = 1
        }
        // 卡包本体短促弹簧回弹（被撕开瞬间的 recoil）
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            packRecoil = true
            deform = 0
            packTilt = .zero
        }

        // 撕条 0.35s 抛物线飞出：横向 easeOut + 纵向上抛 easeOut，旋转 25°，尾段渐隐
        withAnimation(.easeOut(duration: 0.35)) {
            stripFlyX = tearDirection * 280
            stripFlyY = -230
            stripFlyRotation = Double(tearDirection * -25)
        }
        withAnimation(.linear(duration: 0.22).delay(0.13)) {
            stripFlyOpacity = 0
        }

        // 同帧交叉：卡包原地退场（PackExit：下移 40pt + 0.88 + 渐隐）与环形牌轮从卡包中心展开
        // 新牌池在进入新一轮选牌时重新洗牌生成
        withAnimation(.easeOut(duration: 0.45)) {
            phase = .wheelSelection
        }
        pool = TarotDeck.major.map(\.id).shuffled()
        poolReversed = (0..<TarotDeck.major.count).map { _ in Bool.random() }
        selectedSlots = []
        wheelBorn = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                wheelBorn = true
            }
        }
    }

    // MARK: - 阶段 3：wheelSelection（环形牌轮 + 顶部三段进度）

    private var wheelBranch: some View {
        ZStack(alignment: .topLeading) {
            TarotWheelView(
                pool: pool,
                poolReversed: poolReversed,
                selectedSlots: selectedSlots,
                wheelAngle: $wheelAngle,
                onSelect: selectSlot
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                progressCapsules
                Text(guideText)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .animation(.easeOut(duration: 0.2), value: selectedSlots.count)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .scaleEffect(wheelBorn ? 1 : 0.22)
        .opacity(wheelBorn ? 1 : 0)
    }

    /// 极简三段式进度条：每选定 1 张点亮 1 段
    private var progressCapsules: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(index < selectedSlots.count ? Theme.text : Theme.text.opacity(0.14))
                    .frame(width: 34, height: 5)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selectedSlots.count)
    }

    private var guideText: String {
        let count = selectedSlots.count
        if count >= 3 { return "牌阵已集齐，正在展开…" }
        return "请从牌轮中选择 3 张牌 (\(count)/3)"
    }

    /// 点选一张牌背：径向外弹锁定；选满 3 张后提交记录并进入三牌阵
    private func selectSlot(_ slot: Int) {
        guard phase == .wheelSelection, selectedSlots.count < 3, !selectedSlots.contains(slot) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            selectedSlots.append(slot)
        }
        guard selectedSlots.count == 3, pool.count == TarotDeck.major.count else { return }
        let slots = selectedSlots
        let past = pool[slots[0]]
        let present = pool[slots[1]]
        let future = pool[slots[2]]
        if let draw {
            TarotService.commitSpread(
                draw, in: context,
                past: past, present: present, future: future,
                reversedPast: poolReversed[slots[0]],
                reversedPresent: poolReversed[slots[1]],
                reversedFuture: poolReversed[slots[2]]
            )
        }
        isRedraw = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 0.4)) {
                phase = .spreadRevealed
            }
            spreadSettled = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    spreadSettled = true
                }
            }
        }
    }

    // MARK: - 阶段 4：spreadRevealed（三牌阵 + 防穿帮翻牌）

    private var spreadBranch: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                header

                HStack(alignment: .top, spacing: 12) {
                    spreadCard(index: 0, positionLabel: "过去", card: spreadCards.past, reversed: spreadReversed.past)
                    spreadCard(index: 1, positionLabel: "现在", card: spreadCards.present, reversed: spreadReversed.present)
                    spreadCard(index: 2, positionLabel: "未来", card: spreadCards.future, reversed: spreadReversed.future)
                }
                .padding(.top, 4)

                if revealedCount < 3 {
                    Button {
                        flipAllToken += 1
                    } label: {
                        Text("一键全部翻开")
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
                    .transition(.opacity)
                    .padding(.top, 20)
                }

                if revealedCount >= 3 {
                    Button {
                        isReadingPresented = true
                    } label: {
                        Text("查看牌阵解读")
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
                    .transition(.opacity)
                    .padding(.top, 20)
                }

                Button {
                    redraw()
                } label: {
                    Text("重新抽一张")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 10)
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.bottom, 128)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 14)
    }

    /// 三牌阵中的一张：飞入入场 + 翻牌 + 逐牌文字门控
    private func spreadCard(index: Int, positionLabel: String, card: TarotCard, reversed: Bool) -> some View {
        RevealCard(
            index: index,
            positionLabel: positionLabel,
            card: card,
            reversed: reversed,
            initiallyRevealed: loadedOpened,
            flipAllTrigger: flipAllToken,
            onNinety: { confettiToken += 1 },
            onFlipped: { revealedCount += 1 },
            onOpen: { isReadingPresented = true }
        )
        .opacity(spreadSettled ? 1 : 0)
        .scaleEffect(spreadSettled ? 1 : 0.72)
        .offset(x: spreadSettled ? 0 : 90)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.08), value: spreadSettled)
    }

    /// 三牌阵牌面数据（cardID = 中央·现在，card2ID = 左·过去，card3ID = 右·未来）
    private var spreadCards: (past: TarotCard, present: TarotCard, future: TarotCard) {
        (
            TarotDeck.card(id: draw?.card2ID ?? 0),
            TarotDeck.card(id: draw?.cardID ?? 0),
            TarotDeck.card(id: draw?.card3ID ?? 0)
        )
    }

    private var spreadReversed: (past: Bool, present: Bool, future: Bool) {
        (
            draw?.isReversed2 ?? false,
            draw?.isReversed ?? false,
            draw?.isReversed3 ?? false
        )
    }

    // MARK: - 生命周期

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let today = TarotService.ensureToday(in: context)
        draw = today
        isRedraw = false
        if today.isOpened {
            // 今天已选过牌：直接进入三牌阵且全部翻开，无彩带
            phase = .spreadRevealed
            loadedOpened = true
            revealedCount = 3
            spreadSettled = true
        } else {
            phase = .sealed
            tearProgress = 0
            tearStarted = false
            tearDirection = -1
        }
    }

    /// 重新抽：立即清空已选数组/翻牌/文字/粒子，以无重影状态切回 sealed；
    /// 只把记录标记为未拆（首页继续显示旧牌阵的中央牌，不剧透），
    /// 新牌池在撕包后进入牌轮时重新洗牌，选满 3 张时由 commitSpread 落库
    private func redraw() {
        guard phase == .spreadRevealed else { return }
        isRedraw = true
        if let draw {
            TarotService.markUnopened(draw, in: context)
        }
        clearToken += 1          // 清空粒子状态（不触发新的发射）
        selectedSlots = []
        pool = []
        poolReversed = []
        wheelAngle = 0
        wheelBorn = false
        flipAllToken = 0
        revealedCount = 0
        spreadSettled = false
        loadedOpened = false
        tearProgress = 0
        tearStarted = false
        stripFlying = false
        stripBase = .zero
        stripBaseRotation = 0
        stripFlyX = 0
        stripFlyY = 0
        stripFlyRotation = 0
        stripFlyOpacity = 1
        packRecoil = false
        holoReset()
        deform = 0
        packTilt = .zero
        jag = TarotView.makeJag()
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = .sealed
        }
    }

    private func holoReset() { /* RevealCard 内部状态随分支卸载自动重置，此处保留语义占位 */ }

    /// 每次装包生成一条新的不规则撕裂线：斜率 + 弓形 + 随机游走 + 锯齿
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

// MARK: - 卡包退场过渡（原地下移 40pt + 缩小 0.88 + 快速渐隐）

struct PackExitModifier: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - 0.12 * progress)
            .offset(y: 40 * progress)
            .opacity(Double(1 - progress))
    }
}

extension AnyTransition {
    static var packExit: AnyTransition {
        .modifier(active: PackExitModifier(progress: 1), identity: PackExitModifier(progress: 0))
    }
}

// MARK: - 环形牌轮（TarotWheelView）

/// 偏移式极坐标环形牌轮：
/// - 圆心 (0.82w, 0.54h)，半径 0.68w，22 个牌位按 360°/22 ≈ 16.36° 等分，slot 0 初始位于正左（180°）拇指热区
/// - 每张牌背 64×96，沿径向旋转（ Roulette 造型），点选后沿圆心法线外弹 28pt + scale 1.12 并锁定
/// - 单手上下拖动旋转牌轮（dy→角度线性映射），松手带惯性（easeOut 衰减滑行）
struct TarotWheelView: View {
    let pool: [Int]
    let poolReversed: [Bool]
    let selectedSlots: [Int]
    @Binding var wheelAngle: Double
    var onSelect: (Int) -> Void

    @State private var prevDragY: CGFloat?
    @State private var lastMoveTime: Date?
    @State private var angularVelocity: Double = 0

    private let slotCount = 22
    private let wheelCardWidth: CGFloat = 64
    private let wheelCardHeight: CGFloat = 96

    var body: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width * 0.82, y: geo.size.height * 0.54)
            let radius = geo.size.width * 0.68
            ZStack {
                ForEach(0..<slotCount, id: \.self) { slot in
                    if slot < pool.count {
                        wheelCard(slot: slot, center: center, radius: radius)
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(spinGesture)
        }
    }

    private func angleDeg(slot: Int) -> Double {
        180.0 + Double(slot) * (360.0 / Double(slotCount)) + wheelAngle
    }

    @ViewBuilder
    private func wheelCard(slot: Int, center: CGPoint, radius: CGFloat) -> some View {
        let theta = angleDeg(slot: slot) * .pi / 180
        let ux = CGFloat(cos(theta))
        let uy = CGFloat(sin(theta))
        let order = selectedSlots.firstIndex(of: slot)
        let isSelected = order != nil
        let radialOffset: CGFloat = isSelected ? 28 : 0

        AssetImage.image("back")
            .resizable()
            .scaledToFill()
            .frame(width: wheelCardWidth, height: wheelCardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(Color.white.opacity(isSelected ? 0.9 : 0.22), lineWidth: isSelected ? 1.5 : 0.8)
            )
            .overlay(alignment: .topTrailing) {
                if let order {
                    Text("\(order + 1)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.black)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white))
                        .offset(x: 7, y: -7)
                }
            }
            .shadow(color: .black.opacity(0.25), radius: 6, y: 4)
            .rotationEffect(.degrees(angleDeg(slot: slot)))
            .scaleEffect(isSelected ? 1.12 : 1)
            .offset(x: ux * radialOffset, y: uy * radialOffset)
            .position(x: center.x + radius * ux, y: center.y + radius * uy)
            .zIndex(isSelected ? 2 : 1)
            .onTapGesture { onSelect(slot) }
    }

    /// 单手上下拖动：dy 线性映射角度；松手按角速度惯性滑行（easeOut 衰减）
    private var spinGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let now = Date()
                if let prevY = prevDragY, let lastTime = lastMoveTime {
                    let dy = value.translation.height - prevY
                    let dAngle = Double(dy) * 0.33
                    wheelAngle += dAngle
                    let dt = max(0.008, now.timeIntervalSince(lastTime))
                    let instant = dAngle / dt
                    angularVelocity = angularVelocity * 0.72 + instant * 0.28
                }
                prevDragY = value.translation.height
                lastMoveTime = now
            }
            .onEnded { _ in
                let fling = max(-700, min(700, angularVelocity)) * 0.32
                withAnimation(.easeOut(duration: 0.9)) {
                    wheelAngle += fling
                }
                prevDragY = nil
                lastMoveTime = nil
                angularVelocity = 0
            }
    }
}

// MARK: - 三牌阵单卡（RevealCard）

/// 单张揭晓卡：位置标签 + 翻牌卡面 + 逐牌文字门控。
/// 翻牌两段式：0→90°（easeInOut 确定过临界），90° 帧切换正反面/触发回调，90→180° 弹簧落定；
/// 阴影透明度绑定 abs(cos(angle))，90° 垂直瞬间为 0；翻开后支持拖拽倾斜驱动全息层。
struct RevealCard: View {
    let index: Int
    let positionLabel: String
    let card: TarotCard
    let reversed: Bool
    let initiallyRevealed: Bool
    let flipAllTrigger: Int
    var onNinety: () -> Void = {}
    var onFlipped: () -> Void = {}
    var onOpen: () -> Void = {}

    @State private var angle: Double
    @State private var revealed: Bool
    @State private var handledTrigger: Int
    @State private var holoDrag: CGSize = .zero

    init(
        index: Int, positionLabel: String, card: TarotCard, reversed: Bool,
        initiallyRevealed: Bool, flipAllTrigger: Int,
        onNinety: @escaping () -> Void = {}, onFlipped: @escaping () -> Void = {}, onOpen: @escaping () -> Void = {}
    ) {
        self.index = index
        self.positionLabel = positionLabel
        self.card = card
        self.reversed = reversed
        self.initiallyRevealed = initiallyRevealed
        self.flipAllTrigger = flipAllTrigger
        self.onNinety = onNinety
        self.onFlipped = onFlipped
        self.onOpen = onOpen
        _angle = State(initialValue: initiallyRevealed ? 180 : 0)
        _revealed = State(initialValue: initiallyRevealed)
        _handledTrigger = State(initialValue: flipAllTrigger)
    }

    private let cardWidth: CGFloat = 106
    private let cardHeight: CGFloat = 160

    var body: some View {
        VStack(spacing: 8) {
            Text(positionLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .tracking(1)

            cardFace

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(card.name)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(reversed ? "逆位" : "正位")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(card.keywords(reversed: reversed).joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : 10)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: revealed)
        }
        .frame(width: cardWidth)
        .onChange(of: flipAllTrigger) { _, newValue in
            guard newValue != handledTrigger else { return }
            handledTrigger = newValue
            guard angle < 90 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.18) {
                startFlip()
            }
        }
    }

    private var cardFace: some View {
        ZStack {
            AssetImage.image("back")
                .resizable()
                .scaledToFill()
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .modifier(FaceGate(angle: angle, front: false, shadowOpacity: 0.32))

            ZStack {
                AssetImage.image(card.slug)
                    .resizable()
                    .scaledToFill()
                HoloShine(nx: holoTiltY / 24, ny: holoTiltX / 24, active: revealed)
                    .opacity(revealed ? 1 : 0)
                glaze
            }
            .frame(width: cardWidth, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            .modifier(FaceGate(angle: angle, front: true, shadowOpacity: 0.32))
        }
        .frame(width: cardWidth, height: cardHeight)
        .rotation3DEffect(.degrees(holoTiltX), axis: (x: 1, y: 0, z: 0), perspective: 0.68)
        .rotation3DEffect(.degrees(holoTiltY), axis: (x: 0, y: 1, z: 0), perspective: 0.68)
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .onTapGesture {
            if angle >= 180 {
                onOpen()
            } else if angle < 90 {
                startFlip()
            }
        }
        .simultaneousGesture(holoGesture)
    }

    /// 卡面清漆：边缘高光 + 顶部光泽
    private var glaze: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
            LinearGradient(colors: [.white.opacity(0.2), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.2))
        }
    }

    private var holoGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard revealed else { return }
                holoDrag = value.translation
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.55, dampingFraction: 0.75)) {
                    holoDrag = .zero
                }
            }
    }

    private var holoTiltY: Double {
        guard revealed else { return 0 }
        return Double(max(-10, min(10, holoDrag.width * 0.07)))
    }

    private var holoTiltX: Double {
        guard revealed else { return 0 }
        return Double(max(-8, min(8, -holoDrag.height * 0.06)))
    }

    private func startFlip() {
        guard angle < 90 else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            angle = 90
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.31) {
            // ★ 翻过 90° 的瞬间：全屏彩带 + 该牌文字弹簧淡入
            onNinety()
            onFlipped()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                revealed = true
            }
            withAnimation(.spring(response: 0.85, dampingFraction: 0.82)) {
                angle = 180
            }
        }
    }
}

// MARK: - 90° 防穿帮翻转

/// Animatable 修饰器在动画每一帧用插值后的角度重算可见性与阴影：
/// - 牌背在角度 < 90° 可见，正面立绘在角度 ≥ 90° 的那一帧才显示（正面已预置 180° 镜像修正）
/// - 阴影透明度 = shadowOpacity · abs(cos(angle))，90° 垂直瞬间降为 0，消除黑色竖线
private struct FaceGate: ViewModifier, Animatable {
    var angle: Double
    var front: Bool
    var shadowOpacity: Double

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func body(content: Content) -> some View {
        let faceUp = angle >= 90
        let lift = abs(cos(angle * .pi / 180))
        content
            .shadow(color: .black.opacity(shadowOpacity * lift), radius: 12, y: 7)
            .opacity((front == faceUp) ? 1 : 0)
    }
}

// MARK: - 牌阵解读

/// 三牌阵解读弹窗：左·过去 / 中·现在 / 右·未来
struct TarotSpreadSheet: View {
    @Environment(\.dismiss) private var dismiss
    let past: TarotCard
    let present: TarotCard
    let future: TarotCard
    let reversedPast: Bool
    let reversedPresent: Bool
    let reversedFuture: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 10) {
                        spreadMini(title: "过去", card: past, reversed: reversedPast)
                        spreadMini(title: "现在", card: present, reversed: reversedPresent)
                        spreadMini(title: "未来", card: future, reversed: reversedFuture)
                    }

                    spreadSection(title: "过去 · \(past.name)", en: past.en, reversed: reversedPast, card: past)
                    spreadSection(title: "现在 · \(present.name)", en: present.en, reversed: reversedPresent, card: present)
                    spreadSection(title: "未来 · \(future.name)", en: future.en, reversed: reversedFuture, card: future)
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.vertical, 16)
            }
            .background(Theme.bg)
            .navigationTitle("牌阵解读")
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

    private func spreadMini(title: String, card: TarotCard, reversed: Bool) -> some View {
        VStack(spacing: 6) {
            CardArt(name: card.slug)
                .frame(width: 92, height: 136)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text("\(card.name) · \(reversed ? "逆位" : "正位")")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
    }

    private func spreadSection(title: String, en: String, reversed: Bool, card: TarotCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(en)
                    .font(.system(size: 11, design: .serif))
                    .foregroundStyle(Theme.textTertiary)
            }
            HStack(spacing: 6) {
                ForEach(card.keywords(reversed: reversed), id: \.self) { keyword in
                    AccentChip(text: keyword)
                }
            }
            Text(card.text(reversed: reversed))
                .font(.system(size: 13))
                .lineSpacing(5)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                .cardSurface()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 全息镭射光影层（Holo Shader）

/// 全息素材：阈值化闪粉噪点（对应 holo-reverse --glitter 的遮罩思路）
enum HoloAssets {
    static let glitter: UIImage = {
        let side: CGFloat = 420
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

    /// 多色斜向循环渐变（对应 --rainbow：110° 循环色带）
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

/// 全息反光层：随倾斜 nx/ny（-1...1）流动。
/// px = 0.5 + nx·0.5，py = 0.5 - ny·0.5，hyp = min(1, hypot(nx, ny))
struct HoloShine: View {
    var nx: CGFloat
    var ny: CGFloat
    var active: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let idleX = sin(t * 0.55) * 0.14
            let idleY = cos(t * 0.42) * 0.1
            shine(
                nx: max(-1, min(1, nx + CGFloat(idleX))),
                ny: max(-1, min(1, ny + CGFloat(idleY)))
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
                // 彩虹层：400% 幅面的斜向循环渐变，位置随倾斜流动
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
                // 闪粉噪点层
                Image(uiImage: HoloAssets.glitter)
                    .resizable()
                    .blendMode(.plusLighter)
                    .opacity(0.16 + hyp * 0.3)
                // 镜面炫光
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
/// 物理：重力 2600pt/s²、隐式阻力、翻滚侧滑、翻滚透视压扁。
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

    /// 全屏爆发：横向 6%~94% 均匀散布，七彩+白，错峰延迟
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

    /// 清空粒子（重新抽时调用，不触发新的发射）
    func clear() {
        bits = []
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
            b.vy += 2600 * dt
            b.vx += (sin(b.ph) * b.slip + b.glide) * dt
            let v = sqrt(b.vx * b.vx + b.vy * b.vy)
            let dragK = 1 / (1 + b.c * min(1, 0.06 + t / 0.45) * v * dt)
            b.vx *= dragK
            b.vy *= dragK
            b.x += b.vx * dt
            b.y += b.vy * dt
            let turn = 0.35 + v / 800
            b.rot += b.spin * turn * dt
            b.ph += 7 * turn * dt
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
    var clearToken: Int = 0

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
        .onChange(of: clearToken) { _, _ in
            store.clear()
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
/// 这里走 Bundle.url + UIImage(contentsOfFile:) 显式加载，并做进程内缓存
/// （环形牌轮 22 张牌背同帧重排，必须复用解码结果）。
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

