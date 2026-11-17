import SwiftUI
import SwiftData
import UIKit
import AVFoundation

/// 塔罗 Tab · 原生 SwiftUI 版（2.5D 羊皮纸物理牌框 + RWS 公版图 + 右侧弧形厚卡扇 + 上1下2三角牌阵）
///
/// 四阶段状态机：
///   sealed（未拆封）→ tearing（沿虚线右向撕包仪式）→ fanSelection（右侧 40% 弧形厚卡扇选 3 张）→ spreadRevealed（上1下2三角牌阵翻牌）
///
/// 要点：
/// - 卡包底部映射微光（#D4AF37×#2A4B8C，opacity 0.32、blur 26、下偏 16pt）+ 随触摸偏移的斜向金属高光层（.screen）
/// - 指纹引导（touchid + 呼吸微光环 + 右向粒子拖尾），开始拖动（dx>2）即 0.15s 淡出消失
/// - 仅响应虚线区横向向右拖动：TearClipMask 逐段揭开、撕条以前沿为轴局部上翘；每滑 10pt 微震 + 合成撕箔音效；
///   < 0.72 松手弹回 spring(0.3, 0.72)；≥ 0.72 撕条 0.3s 右上抛飞渐隐，卡包原地微移 40pt + 0.88 + 渐隐（PackExit），牌扇同帧弹开
/// - 牌扇：虚拟圆心 (1.12w, 0.40h)、半径 0.64w、110°~250° 等分 14 张大牌背，径向旋转（中部水平横放）；
///   PhysicalCardBackView 三层错位厚卡纸 + 0.5pt 香槟金描边；点选沿放射角外弹 30pt + 轻震 + 纸张摩擦音
/// - 三牌阵：上 1 居中（过去 · PAST / 核心）+ 下 2 并排（现在 / 未来）；羊皮纸牌框（#F4ECD8、12px 圆角、
///   1px rgba(182,160,126,.45) 描边、三层纸边厚度 0 2/4/6px + 12/24px 投影）；顶部香槟金铭牌始终正立；
///   插槽 1.5px #C5A059 双线金边，RWS 公版图 aspect-fill 裁白边，逆位仅插画 rotate(180°)；
///   全息镭射层（colorDodge 0.22）随倾斜偏移；90° 临界切换正反面，阴影绑定 abs(cos(angle))；
///   牌名/关键词在翻过 90° 后弹簧淡入；点击已翻开的牌弹出原生牌义页
/// - 重新抽牌：清空全部状态无重影切回 sealed；选满 3 张即 commitSpread 落库（首页核心牌同步）
struct TarotView: View {
    @Environment(\.modelContext) private var context
    @Query private var draws: [DailyTarot]
    @State private var detail: CardDetail?

    struct CardDetail: Identifiable {
        let id: Int
        let card: TarotCard
        let reversed: Bool
    }

    @State private var phase: Phase = .sealed
    @State private var didLoad = false
    @State private var isRedraw = false

    // MARK: sealed —— 跟手撕包
    @State private var tearProgress: CGFloat = 0
    @State private var tearStarted = false
    @State private var packTilt: CGSize = .zero
    @State private var deform: CGFloat = 0
    @State private var jag: [CGFloat] = TarotView.makeJag()
    @State private var tearTickAccumulator: CGFloat = 0

    // MARK: tearing —— 撕条抛飞 + 卡包退场
    @State private var stripFlying = false
    @State private var stripBaseRotation: Double = 0
    @State private var stripFlyX: CGFloat = 0
    @State private var stripFlyY: CGFloat = 0
    @State private var stripFlyRotation: Double = 0
    @State private var stripFlyOpacity: Double = 1
    @State private var packRecoil = false

    // MARK: fanSelection —— 右侧弧形牌扇
    @State private var pool: [Int] = []
    @State private var poolReversed: [Bool] = []
    @State private var selectedSlots: [Int] = []
    @State private var fanBloomed = false

    // MARK: spreadRevealed —— 三角牌阵
    @State private var flipAllToken = 0
    @State private var revealedCount = 0
    @State private var spreadSettled = false
    @State private var loadedOpened = false

    @State private var confettiToken = 0

    enum Phase { case sealed, tearing, fanSelection, spreadRevealed }

    private let packWidth: CGFloat = 236
    private let packHeight: CGFloat = 386
    /// 撕口位置（占卡包高度比例），与素材撕裂线一致
    private let tearRatio: CGFloat = 0.358

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()

            if !didLoad {
                // 首帧占位：onAppear 恢复状态前不渲染任何牌面/文字，杜绝重启闪屏
                Color.clear
            } else if phase == .sealed || phase == .tearing {
                sealedBranch
                    .transition(.packExit)
            } else if phase == .fanSelection {
                fanBranch
                    .transition(.opacity)
            } else {
                // 重新抽牌时移除必须瞬时（.identity），杜绝旧牌阵与新卡包的半透明双层重影
                spreadBranch
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
            }

            ConfettiOverlay(token: confettiToken)
                .allowsHitTesting(false)
                .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(item: $detail) { d in
            TarotReadingSheet(card: d.card, isReversed: d.reversed)
        }
        .onAppear(perform: load)
    }

    // MARK: - 页头（sealed / spreadRevealed 阶段显示）

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("每日一抽 · \(Date().formatted(.dateTime.month().day()))")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text("塔罗")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Theme.text)
                .tracking(-0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 2)
        .padding(.bottom, 18)
    }

    // MARK: - 阶段 1/2：sealed + tearing（密封卡包 · 沿虚线右向撕开）

    private var sealedBranch: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                header
                sealedScene
            }
            .padding(.bottom, 128)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 6)
    }

    private var sealedScene: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text("👆").font(.system(size: 14))
                Text("沿虚线向右撕开")
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
            .opacity(Double(max(0, 1 - tearProgress * 4)))
            .padding(.bottom, 16)

            ZStack(alignment: .top) {
                // 底层：卡包底部映射微光（悬浮台面感）
                packGlow
                // 卡包主体：撕裂裁切 + 金属高光 + 短促回弹
                packBody
                // 顶部撕条：掀起层 / 抛飞层（同一素材同一坐标系，位置连续无瞬移）
                if !stripFlying {
                    stripLayer
                } else {
                    flyingStrip
                }
                // 指纹引导（虚线左端，触摸即消失）
                FingerprintGuide(visible: phase == .sealed && !tearStarted && tearProgress < 0.01)
                    .offset(x: 16, y: packHeight * tearRatio - 44)
            }
            .frame(width: packWidth, height: packHeight)
            .contentShape(Rectangle())
            .gesture(packTiltGesture)
            .overlay(alignment: .top) {
                tearZone
            }

            Text("今日牌阵已备好，撕开后从牌扇中选取 3 张")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
                .opacity(tearProgress < 0.02 && !stripFlying ? 1 : 0)
                .animation(.easeOut(duration: 0.2), value: tearProgress)
                .padding(.top, 26)
        }
        .padding(.top, 14)
    }

    /// 卡包底部映射微光：香槟金 × 深靛蓝椭圆放射光晕
    private var packGlow: some View {
        Ellipse()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hex: 0xD4AF37).opacity(0.55),
                        Color(hex: 0x2A4B8C).opacity(0.30),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: 0,
                    endRadius: packWidth * 0.78
                )
            )
            .frame(width: packWidth * 1.52, height: 104)
            .blur(radius: 26)
            .opacity(0.32)
            .offset(y: packHeight / 2 + 16)
    }

    /// 卡包本体：3D 倾斜 + 阻力形变 + 撕裂裁切 + 斜向金属高光 + 短促回弹
    private var packBody: some View {
        AssetImage.image("pack")
            .resizable()
            .scaledToFit()
            .mask(TearClipMask(keepBody: true, progress: tearProgress, ratio: tearRatio, jitter: jag))
            .overlay(alignment: .top) {
                // 斜向金属高光层：随手指触摸轻微偏移
                LinearGradient(
                    colors: [.clear, .white.opacity(0.34), .white.opacity(0.10), .clear],
                    startPoint: UnitPoint(x: 0.05, y: 0.05),
                    endPoint: UnitPoint(x: 0.85, y: 0.95)
                )
                .blendMode(.screen)
                .offset(x: packTilt.width * 0.12, y: packTilt.height * 0.10)
                .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(0.28), radius: 18, y: 12)
            .scaleEffect(x: 1 + deform * 0.02, y: 1 - deform * 0.028)
            .scaleEffect(packRecoil ? 0.96 : 1)
            .rotation3DEffect(.degrees(packTilt.width), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
            .rotation3DEffect(.degrees(-packTilt.height), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
    }

    /// 跟手掀起的撕条：撕裂前沿左侧逐段揭开，以前沿为轴局部上翘（禁止整条僵硬平移）
    private var stripLayer: some View {
        AssetImage.image("torn-strip")
            .resizable()
            .scaledToFit()
            .mask(TearClipMask(keepBody: false, progress: tearProgress, ratio: tearRatio, jitter: jag))
            .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
            .rotationEffect(
                .degrees(-tearProgress * 14),
                anchor: UnitPoint(x: max(0.08, tearProgress), y: tearRatio)
            )
    }

    /// 抛飞中的撕条：从冻结的上翘姿态出发，0.3s 向右上抛飞渐隐
    private var flyingStrip: some View {
        AssetImage.image("torn-strip")
            .resizable()
            .scaledToFit()
            .mask(TearClipMask(keepBody: false, progress: tearProgress, ratio: tearRatio, jitter: jag))
            .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
            .rotationEffect(
                .degrees(stripBaseRotation + stripFlyRotation),
                anchor: UnitPoint(x: 1, y: tearRatio)
            )
            .offset(x: stripFlyX, y: stripFlyY)
            .opacity(stripFlyOpacity)
    }

    /// 顶部虚线撕口区：仅响应区域内横向向右拖动（取消点击开包）
    private var tearZone: some View {
        Rectangle()
            .fill(.clear)
            .frame(height: packHeight * tearRatio + 36)
            .contentShape(Rectangle())
            .gesture(tearGesture)
    }

    /// 整卡拖动：微弱 3D 倾斜反馈（同时驱动金属高光偏移）
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

    /// 撕口区拖动：仅横向向右响应；每 10pt 触发微震 + 撕箔音效；< 0.72 松手弹回
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
                // 指纹引导消失触发点：手指按上虚线并开始拖动（dx > 2）
                if !tearStarted && dx > 2 {
                    tearStarted = true
                    phase = .tearing
                }
                // 仅响应横向向右
                guard dx > 0 else { return }
                let packW = packWidth
                let progress = min(1, max(0, dx / (packW * 0.85)))
                if progress > tearProgress {
                    tearTickAccumulator += (progress - tearProgress) * packW * 0.85
                    while tearTickAccumulator >= 10 {
                        tearTickAccumulator -= 10
                        FoilSound.shared.tick()
                        FoilSound.shared.tear()
                    }
                    tearProgress = progress
                    deform = progress
                }
            }
            .onEnded { _ in
                guard !stripFlying else { return }
                if tearProgress >= 0.72 {
                    finishTear()
                } else {
                    // 未撕到底：弹回原位，绝不强行开包
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.72)) {
                        tearProgress = 0
                        tearStarted = false
                        deform = 0
                        packTilt = .zero
                        phase = .sealed
                    }
                }
            }
    }

    /// 点击快捷撕包已按规范取消：撕包仅由沿虚线右向拖动触发

    // MARK: - 撕包完成：撕条抛飞 + 卡包原地退场 + 牌扇同帧弹开

    private func finishTear() {
        guard phase == .sealed || phase == .tearing, !stripFlying else { return }
        phase = .tearing

        // 冻结上翘姿态作为抛飞起点（位置连续，杜绝“先消失再瞬移”）
        stripBaseRotation = -(tearProgress * 14)
        stripFlying = true

        // 撕裂前沿补完到整条撕线
        withAnimation(.easeOut(duration: 0.15)) {
            tearProgress = 1
        }
        // 卡包本体短促弹簧回弹
        withAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            packRecoil = true
            deform = 0
            packTilt = .zero
        }

        // 撕条 0.3s 向右上抛飞渐隐
        withAnimation(.easeOut(duration: 0.3)) {
            stripFlyX = 300
            stripFlyY = -230
            stripFlyRotation = 25
        }
        withAnimation(.linear(duration: 0.2).delay(0.1)) {
            stripFlyOpacity = 0
        }

        // 同帧交叉：卡包原地退场（PackExit：下移 40pt + 0.88 + 渐隐）与牌扇从卡包中心错峰弹开
        withAnimation(.easeOut(duration: 0.45)) {
            phase = .fanSelection
        }
        // 牌扇从 22 张大牌洗牌取 14 张（与 DailyTarot 契约对齐）
        pool = Array(TarotDeck.major.map(\.id).shuffled().prefix(14))
        poolReversed = (0..<pool.count).map { _ in Bool.random() }
        selectedSlots = []
        fanBloomed = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            fanBloomed = true
        }
    }

    // MARK: - 阶段 3：fanSelection（右侧固定 40% 弧形厚卡扇 + 顶部三段进度）

    private var fanBranch: some View {
        ZStack(alignment: .topLeading) {
            TarotFanView(
                pool: pool,
                selectedSlots: selectedSlots,
                bloomed: fanBloomed,
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
        return "请从牌扇中选取 3 张牌 (\(count)/3)"
    }

    /// 点选一张牌背：沿放射角度外弹锁定；选满 3 张后提交记录并进入三角牌阵
    private func selectSlot(_ slot: Int) {
        guard phase == .fanSelection, selectedSlots.count < 3, !selectedSlots.contains(slot) else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            selectedSlots.append(slot)
        }
        FoilSound.shared.select()
        FoilSound.shared.rub()
        guard selectedSlots.count == 3, pool.count == 14 else { return }
        let picks = selectedSlots.map { pool[$0] }
        let revs = selectedSlots.map { poolReversed[$0] }
        if let record = today ?? draws.first {
            TarotService.commitSpread(
                record, in: context,
                core: picks[0], present: picks[1], future: picks[2],
                reversedCore: revs[0], reversedPresent: revs[1], reversedFuture: revs[2]
            )
        }
        isRedraw = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
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

    // MARK: - 阶段 4：spreadRevealed（上 1 下 2 三角羊皮纸大牌阵）

    private var spreadBranch: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                header

                // 上 1 居中（过去 · PAST / 核心）
                spreadCard(index: 0, positionLabel: "过去 · PAST", card: spreadCards.core, reversed: spreadReversed.core)
                    .padding(.top, 4)

                // 下 2 并排（现在 / 未来）
                HStack(alignment: .top, spacing: 14) {
                    spreadCard(index: 1, positionLabel: "现在 · PRESENT", card: spreadCards.present, reversed: spreadReversed.present)
                    spreadCard(index: 2, positionLabel: "未来 · FUTURE", card: spreadCards.future, reversed: spreadReversed.future)
                }
                .padding(.top, 18)

                if revealedCount < 3 {
                    Button {
                        flipAllToken += 1
                    } label: {
                        Text("全部翻开")
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
                    Text("重新抽牌")
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(PressableStyle())
                .padding(.top, 10)
            }
            .padding(.bottom, 128)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 6)
    }

    /// 三角牌阵中的一张：飞入入场 + 翻牌 + 逐牌文字门控
    private func spreadCard(index: Int, positionLabel: String, card: TarotCard, reversed: Bool) -> some View {
        ParchmentCardView(
            index: index,
            positionLabel: positionLabel,
            card: card,
            reversed: reversed,
            initiallyRevealed: loadedOpened,
            flipAllTrigger: flipAllToken,
            onNinety: { confettiToken += 1 },
            onFlipped: { revealedCount += 1 },
            onOpen: { detail = CardDetail(id: card.id, card: card, reversed: reversed) }
        )
        .opacity(spreadSettled ? 1 : 0)
        .scaleEffect(spreadSettled ? 1 : 0.72)
        .offset(x: spreadSettled ? 0 : 90)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.08), value: spreadSettled)
    }

    /// 三牌阵牌面数据（cardID = 上位·过去/核心，card2ID = 下左·现在，card3ID = 下右·未来）
    private var spreadCards: (core: TarotCard, present: TarotCard, future: TarotCard) {
        (
            TarotDeck.card(id: today?.cardID ?? 0),
            TarotDeck.card(id: today?.card2ID ?? 0),
            TarotDeck.card(id: today?.card3ID ?? 0)
        )
    }

    private var spreadReversed: (core: Bool, present: Bool, future: Bool) {
        (
            today?.isReversed ?? false,
            today?.isReversed2 ?? false,
            today?.isReversed3 ?? false
        )
    }

    // MARK: - 生命周期

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        let record = TarotService.ensureToday(in: context)
        isRedraw = false
        if record.isOpened {
            // 今天已选过牌：直接进入三角牌阵且全部翻开，无彩带
            phase = .spreadRevealed
            loadedOpened = true
            revealedCount = 3
            spreadSettled = true
        } else {
            phase = .sealed
            tearProgress = 0
            tearStarted = false
        }
    }

    /// 重新抽牌：立即清空已选数组/翻牌/文字/粒子，以无重影状态切回 sealed；
    /// 只把记录标记为未拆（首页继续显示旧牌阵核心牌，不剧透），新牌池撕包时重新洗牌
    private func redraw() {
        guard phase == .spreadRevealed else { return }
        isRedraw = true
        if let record = today {
            TarotService.markUnopened(record, in: context)
        }
        selectedSlots = []
        pool = []
        poolReversed = []
        fanBloomed = false
        flipAllToken = 0
        revealedCount = 0
        spreadSettled = false
        loadedOpened = false
        tearProgress = 0
        tearStarted = false
        tearTickAccumulator = 0
        stripFlying = false
        stripBaseRotation = 0
        stripFlyX = 0
        stripFlyY = 0
        stripFlyRotation = 0
        stripFlyOpacity = 1
        packRecoil = false
        deform = 0
        packTilt = .zero
        jag = TarotView.makeJag()
        withAnimation(.easeInOut(duration: 0.25)) {
            phase = .sealed
        }
    }

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

// MARK: - 右侧固定 40% 弧形牌扇（TarotFanView）

/// 固定展开的非对称自然弧形牌扇（取消圆环拖动旋转）：
/// - 虚拟圆心在屏幕右侧外偏上 (1.12w, 0.40h)，半径 0.64w
/// - 110°~250°（约 40% 圆周）均匀排布 14 张牌背，右上向左下自然扫过
/// - 每张牌径向旋转（rotation = θ + 90°），弧线中部呈水平横放姿态，上下两端随弧线自然倾斜
/// - 卡包淡出时 14 张以错峰 spring(0.45, 0.75) 从卡包中心弹开成弧；点选沿放射角度外弹 30pt
/// - 扇面几何约束在底栏上方：最低卡缘 ≈ 0.71h，任何卡牌边缘不压底部导航栏
struct TarotFanView: View {
    let pool: [Int]
    let selectedSlots: [Int]
    let bloomed: Bool
    var onSelect: (Int) -> Void

    private let slotCount = 14
    private let fanCardWidth: CGFloat = 66
    private let fanCardHeight: CGFloat = 99

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let center = CGPoint(x: w * 1.12, y: h * 0.40)
            let radius = w * 0.64
            let packCenter = CGPoint(x: w * 0.5, y: h * 0.42)
            ZStack {
                ForEach(0..<slotCount, id: \.self) { slot in
                    if slot < pool.count {
                        fanCard(slot: slot, center: center, radius: radius, restCenter: packCenter)
                    }
                }
            }
            .frame(width: w, height: h)
        }
    }

    private func angleDeg(slot: Int) -> Double {
        110.0 + Double(slot) * (140.0 / Double(slotCount - 1))
    }

    @ViewBuilder
    private func fanCard(slot: Int, center: CGPoint, radius: CGFloat, restCenter: CGPoint) -> some View {
        let theta = angleDeg(slot: slot) * .pi / 180
        let ux = CGFloat(cos(theta))
        let uy = CGFloat(sin(theta))
        let target = CGPoint(x: center.x + radius * ux, y: center.y + radius * uy)
        let isSelected = selectedSlots.contains(slot)
        let radialOffset: CGFloat = isSelected ? 30 : 0
        let midCloseness = slotCount / 2 - abs(slot - slotCount / 2 + 1)

        PhysicalCardBackView(onSelect: { onSelect(slot) })
            .frame(width: fanCardWidth, height: fanCardHeight)
            .rotationEffect(.degrees(angleDeg(slot: slot) + 90))
            .scaleEffect(bloomed ? (isSelected ? 1.08 : 1) : 0.55)
            .offset(x: ux * radialOffset, y: uy * radialOffset)
            .opacity(bloomed ? 1 : 0)
            .position(x: bloomed ? target.x : restCenter.x, y: bloomed ? target.y : restCenter.y)
            .zIndex(Double(midCloseness) + (isSelected ? 10 : 0))
            .animation(.spring(response: 0.45, dampingFraction: 0.75).delay(Double(slot) * 0.03), value: bloomed)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: selectedSlots)
    }
}

// MARK: - 实体塔罗牌背（PhysicalCardBackView）

/// 三层错位厚卡纸边 + 香槟金描边 + 柔和投影，做出实体卡牌的 2.5D 厚度感；
/// 内置点选手势：按住产生微弱 3D 倾斜，松手弹簧回弹；轻点（位移 < 10pt）即选中。
struct PhysicalCardBackView: View {
    var onSelect: () -> Void = {}

    @State private var tilt: CGSize = .zero
    @State private var pressing = false

    private var tiltXDegrees: Double {
        max(-7.0, min(7.0, Double(-tilt.height) * 0.14))
    }

    private var tiltYDegrees: Double {
        max(-7.0, min(7.0, Double(tilt.width) * 0.14))
    }

    var body: some View {
        ZStack {
            cardstock(color: Color(hex: 0x8C6D2F), dx: 3.5, dy: 4.5)
            cardstock(color: Color(hex: 0xC9A24B), dx: 2.5, dy: 3.2)
            cardstock(color: Color(hex: 0xEDE6D6), dx: 1.5, dy: 2.0)
            AssetImage.image("back")
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color(hex: 0xD4AF37).opacity(0.85), lineWidth: 0.5)
                )
        }
        .shadow(color: .black.opacity(0.30), radius: 7, y: 5)
        .rotation3DEffect(.degrees(tiltXDegrees), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
        .rotation3DEffect(.degrees(tiltYDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
        .scaleEffect(pressing ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: pressing)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    pressing = true
                    tilt = CGSize(
                        width: max(-80, min(80, value.translation.width)),
                        height: max(-80, min(80, value.translation.height))
                    )
                }
                .onEnded { value in
                    pressing = false
                    let distance = sqrt(value.translation.width * value.translation.width + value.translation.height * value.translation.height)
                    if distance < 10 {
                        onSelect()
                    }
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                        tilt = .zero
                    }
                }
        )
    }

    private func cardstock(color: Color, dx: CGFloat, dy: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(color)
            .offset(x: dx, y: dy)
    }
}

// MARK: - 指纹引导（触摸即消失）

/// 虚线左端的指纹引导：呼吸微光环 + 向右滑动粒子拖尾；
/// 手指按上虚线开始拖动后 0.15s 淡出缩小消失，不遮挡撕裂过程。
struct FingerprintGuide: View {
    var visible: Bool

    private let gold = Color(hex: 0xD4AF37)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !visible)) { timeline in
            fingerprintBody(t: timeline.date.timeIntervalSinceReferenceDate)
        }
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.55)
        .animation(.easeOut(duration: 0.15), value: visible)
        .allowsHitTesting(false)
    }

    private func fingerprintBody(t: Double) -> some View {
        let breatheRaw = 0.5 + 0.5 * sin(t * 2.4)
        let ringScale = 1.0 + breatheRaw * 0.10
        let ringOpacity = 0.35 + breatheRaw * 0.40
        let dotX1 = 22.0 + sin(t * 2.2) * 3.5
        let dotX2 = 31.0 + sin(t * 2.2 + 1.3) * 3.5
        let dotX3 = 40.0 + sin(t * 2.2 + 2.6) * 3.5
        return ZStack(alignment: .leading) {
            Circle()
                .stroke(gold.opacity(0.55), lineWidth: 1.2)
                .frame(width: 34, height: 34)
                .scaleEffect(CGFloat(ringScale))
                .opacity(ringOpacity)
            Image(systemName: "touchid")
                .font(.system(size: 19))
                .foregroundStyle(gold.opacity(0.92))
            trailDot(x: dotX1, size: 3.5, alpha: 0.50)
            trailDot(x: dotX2, size: 2.7, alpha: 0.37)
            trailDot(x: dotX3, size: 1.9, alpha: 0.24)
        }
    }

    private func trailDot(x: Double, size: Double, alpha: Double) -> some View {
        Circle()
            .fill(gold.opacity(alpha))
            .frame(width: size, height: size)
            .offset(x: x)
    }
}

// MARK: - 上1下2三角牌阵单卡（ParchmentCardView）

/// 2.5D 羊皮纸物理牌框：三层纸边厚度（下 2/4/6px）+ 顶部香槟金铭牌（始终正立）+
/// 双线金边插槽（RWS 公版图 aspect-fill 裁白边，逆位仅插画 rotate(180°)）+
/// 全息镭射层（colorDodge，随倾斜偏移）+ 两段式翻牌（90° 临界切换、阴影绑定 abs(cos)）。
struct ParchmentCardView: View {
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
    @State private var tilt: CGSize = .zero

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

    private let frameWidth: CGFloat = 128
    private let frameHeight: CGFloat = 236
    private let slotRadius: CGFloat = 6

    private var titleText: String {
        revealed ? "\(card.number) · \(card.nameEn)" : "· · ·"
    }

    private var tiltXDegrees: Double {
        max(-8.0, min(8.0, Double(-tilt.height) * 0.08))
    }

    private var tiltYDegrees: Double {
        max(-8.0, min(8.0, Double(tilt.width) * 0.08))
    }

    var body: some View {
        VStack(spacing: 8) {
            cardFrame
            cardCaption
        }
        .frame(width: frameWidth)
        .onChange(of: flipAllTrigger) { _, newValue in
            guard newValue != handledTrigger else { return }
            handledTrigger = newValue
            guard angle < 90 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.18) {
                startFlip()
            }
        }
    }

    private var cardFrame: some View {
        ZStack {
            bodyGroup
            plaque
                .offset(y: -frameHeight / 2 + 1)
        }
        .frame(width: frameWidth, height: frameHeight)
        .shadow(color: .black.opacity(0.45), radius: 12, y: 24)
        .rotation3DEffect(.degrees(tiltXDegrees), axis: (x: 1, y: 0, z: 0), perspective: 0.7)
        .rotation3DEffect(.degrees(tiltYDegrees), axis: (x: 0, y: 1, z: 0), perspective: 0.7)
        .onTapGesture {
            if angle >= 180 {
                onOpen()
            } else if angle < 90 {
                startFlip()
            }
        }
        .gesture(tiltGesture)
    }

    private var bodyGroup: some View {
        ZStack(alignment: .top) {
            paperEdge(color: Color(hex: 0xB5A17B), dy: 6)
            paperEdge(color: Color(hex: 0xCBB994), dy: 4)
            paperEdge(color: Color(hex: 0xDFD1B4), dy: 2)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0xF4ECD8))
            VStack(spacing: 6) {
                Text(titleText)
                    .font(.system(size: 10, weight: .bold, design: .serif))
                    .kerning(0.5)
                    .foregroundStyle(revealed ? Color(hex: 0x7A623A) : Color(hex: 0x7A623A).opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: 13)
                    .padding(.horizontal, 4)
                artSlot
            }
            .padding(.top, 16)
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
            holoLayer
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func paperEdge(color: Color, dy: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(color)
            .offset(y: dy)
    }

    private var plaque: some View {
        Text(positionLabel)
            .font(.system(size: 10, weight: .bold))
            .kerning(0.6)
            .foregroundStyle(Color(hex: 0x4A3A1E))
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xE9DBB9), Color(hex: 0xDECBA4), Color(hex: 0xC7B183)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(Color(hex: 0x78624C).opacity(0.55), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 1.5, y: 1)
            )
    }

    /// 双线细金边插槽：RWS 公版图 aspect-fill 裁白边，逆位仅插画旋转
    private var artSlot: some View {
        ZStack {
            slotFaces
            RoundedRectangle(cornerRadius: slotRadius - 1.5, style: .continuous)
                .strokeBorder(Color(hex: 0xC5A059).opacity(0.55), lineWidth: 1)
                .padding(2.5)
        }
        .overlay(
            RoundedRectangle(cornerRadius: slotRadius, style: .continuous)
                .strokeBorder(Color(hex: 0xC5A059), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: slotRadius, style: .continuous))
    }

    private var slotFaces: some View {
        ZStack {
            AssetImage.image("back")
                .resizable()
                .scaledToFill()
                .modifier(FaceGate(angle: angle, front: false, shadowOpacity: 0.0))
            Group {
                if let rws = RWSArt.major(card.id) {
                    Image(uiImage: rws)
                        .resizable()
                        .scaledToFill()
                        .rotationEffect(.degrees(reversed ? 180 : 0))
                } else {
                    CardArt(name: card.slug)
                        .rotationEffect(.degrees(reversed ? 180 : 0))
                }
            }
            .modifier(FaceGate(angle: angle, front: true, shadowOpacity: 0.0))
        }
        .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
    }

    /// 全息镭射层：多色斜向渐变 + colorDodge，随倾斜偏移
    private var holoLayer: some View {
        LinearGradient(
            gradient: HoloAssets.rainbow,
            startPoint: UnitPoint(x: 0.03, y: 0.33),
            endPoint: UnitPoint(x: 0.97, y: 0.67)
        )
        .frame(width: frameWidth * 4, height: frameHeight * 4)
        .offset(
            x: (0.5 - tiltYDegrees / 16) * frameWidth - frameWidth * 2,
            y: (0.5 + tiltXDegrees / 16) * frameHeight - frameHeight * 2
        )
        .blendMode(.colorDodge)
        .opacity(0.22)
        .allowsHitTesting(false)
    }

    private var cardCaption: some View {
        VStack(spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(card.nameZh)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(reversed ? "逆位" : "正位")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(card.keywords(reversed: reversed).joined(separator: " · "))
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .opacity(revealed ? 1 : 0)
        .offset(y: revealed ? 0 : 8)
        .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.05), value: revealed)
    }

    private var tiltGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                tilt = CGSize(
                    width: max(-80, min(80, value.translation.width)),
                    height: max(-80, min(80, value.translation.height))
                )
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                    tilt = .zero
                }
            }
    }

    private func startFlip() {
        guard angle < 90 else { return }
        FoilSound.shared.flip()
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
/// - 牌背在角度 < 90° 可见，正面在角度 ≥ 90° 的那一帧才显示（正面已预置 180° 镜像）
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
            .shadow(color: .black.opacity(shadowOpacity * lift), radius: 10, y: 6)
            .opacity((front == faceUp) ? 1 : 0)
    }
}

// MARK: - 全息镭射渐变

/// 多色斜向循环渐变（对应羊皮纸牌框的全息层，110° 循环色带）
enum HoloAssets {
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

// MARK: - 触感反馈 + 合成音效（无音频素材，运行时生成 PCM）

/// 撕包锯齿微震（UISelectionFeedbackGenerator）+ 选牌轻震（UIImpactFeedbackGenerator.light）
/// 以及代码合成的撕箔脆响与纸张摩擦音（WAV 头 + 16bit PCM 在内存中生成，AVAudioPlayer 变速播放）。
final class FoilSound {
    static let shared = FoilSound()

    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private var tearPlayer: AVAudioPlayer?
    private var rubPlayer: AVAudioPlayer?

    private init() {
        tearPlayer = Self.player(sample: Self.renderTear())
        rubPlayer = Self.player(sample: Self.renderRub())
    }

    /// 撕裂每滑 10pt 的锯齿微震
    func tick() {
        selectionGenerator.selectionChanged()
    }

    /// 点选牌背的轻震
    func select() {
        impactGenerator.impactOccurred()
    }

    /// 合成撕箔音效（每次随机变速，听感不重复）
    func tear() {
        guard let p = tearPlayer else { return }
        p.currentTime = 0
        p.rate = Float.random(in: 0.9...1.5)
        p.volume = Float.random(in: 0.22...0.40)
        p.play()
    }

    /// 纸张摩擦音
    func rub() {
        guard let p = rubPlayer else { return }
        p.currentTime = 0
        p.rate = Float.random(in: 0.85...1.1)
        p.volume = 0.22
        p.play()
    }

    /// 翻牌：噪声扫频上扬
    func flip() {
        guard let p = tearPlayer else { return }
        p.currentTime = 0
        p.rate = Float.random(in: 1.2...1.6)
        p.volume = 0.18
        p.play()
    }

    private static func player(sample: Data?) -> AVAudioPlayer? {
        guard let sample, let p = try? AVAudioPlayer(data: sample) else { return nil }
        p.enableRate = true
        p.prepareToPlay()
        return p
    }

    // 16bit 单声道 WAV 封装
    private static func wav(from samples: [Int16]) -> Data? {
        let sampleRate = 44100
        var data = Data()
        func appendU32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func appendU16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        func appendS16(_ v: Int16) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        data.append("RIFF".data(using: .ascii)!)
        appendU32(UInt32(36 + samples.count * 2))
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        appendU32(16)
        appendU16(1)
        appendU16(1)
        appendU32(UInt32(sampleRate))
        appendU32(UInt32(sampleRate * 2))
        appendU16(2)
        appendU16(16)
        data.append("data".data(using: .ascii)!)
        appendU32(UInt32(samples.count * 2))
        for s in samples { appendS16(s) }
        return data
    }

    /// 撕箔：底噪 + 每 ~24ms 一次随机幅度的“折痕断裂”脆响簇，整体快速衰减
    private static func renderTear() -> Data? {
        let sr = 44100.0
        let duration = 0.30
        let count = Int(sr * duration)
        var samples = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / sr
            let env = min(1, t / 0.01) * exp(-t * 6)
            let hiss = Double.random(in: -1...1) * 0.35
            let burstIndex = Int(t / 0.024)
            let burstSeed = Double((burstIndex * 9781 + 37) % 1000) / 1000
            let burstStart = Double(burstIndex) * 0.024 + burstSeed * 0.01
            let bt = t - burstStart
            var crackle = 0.0
            if bt >= 0, bt < 0.02 {
                let amp = 0.4 + burstSeed * 0.6
                crackle = Double.random(in: -1...1) * amp * exp(-bt * 180)
            }
            let v = (hiss + crackle) * env * 0.8
            samples[i] = Int16(max(-1, min(1, v)) * 32000)
        }
        return wav(from: samples)
    }

    /// 纸张摩擦：泄漏积分棕噪 + 去直流 + 两端淡入淡出
    private static func renderRub() -> Data? {
        let sr = 44100.0
        let duration = 0.5
        let count = Int(sr * duration)
        var samples = [Int16](repeating: 0, count: count)
        var brown = 0.0
        var last = 0.0
        for i in 0..<count {
            let t = Double(i) / sr
            let env = sin(.pi * min(1, t / duration))
            let white = Double.random(in: -1...1)
            brown = (brown + 0.02 * white) / 1.02
            let hp = brown - last
            last = brown
            let v = hp * 8 * env
            samples[i] = Int16(max(-1, min(1, v)) * 26000)
        }
        return wav(from: samples)
    }
}

// MARK: - 撕裂裁切遮罩

/// 撕裂前沿从左向右逐段揭开的动态裁切：
/// - keepBody = true：卡包主体（前沿左侧裁到撕口以下，前沿右侧保持完整）
/// - keepBody = false：掀起撕条区（前沿左侧、撕口以上）
/// 锯齿边缘随 progress 逐渐展开，保证与素材撕裂线在未撕时完全重合。
struct TearClipMask: Shape {
    var keepBody: Bool
    var progress: CGFloat
    var ratio: CGFloat
    var jitter: [CGFloat]

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let cut = rect.height * ratio
        let frontX = rect.width * max(0, min(1, progress))
        let segments = max(1, jitter.count - 1)
        let amp = min(1, progress * 4)
        var path = Path()
        var first = true
        func line(_ p: CGPoint) {
            if first {
                path.move(to: p)
                first = false
            } else {
                path.addLine(to: p)
            }
        }
        func jaggedPoint(_ i: Int) -> CGPoint {
            let x = rect.width * CGFloat(i) / CGFloat(segments) * progress
            let j = jitter[min(i, segments)]
            return CGPoint(x: x, y: cut + j * rect.height * amp)
        }
        if keepBody {
            line(CGPoint(x: 0, y: cut))
            if progress > 0 {
                for i in 0...segments { line(jaggedPoint(i)) }
            }
            line(CGPoint(x: frontX, y: cut))
            line(CGPoint(x: frontX, y: 0))
            line(CGPoint(x: rect.maxX, y: 0))
            line(CGPoint(x: rect.maxX, y: rect.maxY))
            line(CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        } else {
            line(CGPoint(x: 0, y: 0))
            line(CGPoint(x: frontX, y: 0))
            if progress > 0 {
                line(CGPoint(x: frontX, y: cut))
                for i in stride(from: segments, through: 0, by: -1) { line(jaggedPoint(i)) }
            }
            path.closeSubpath()
        }
        return path
    }
}

// MARK: - 全屏彩带粒子（Canvas + TimelineView）

/// 粒子物理存储：Canvas 逐帧积分，不走 SwiftUI 状态，避免每帧视图重建。
final class ConfettiStore {
    struct Bit {
        let kind: Int          // 0 圆点 / 1 彩带 / 2 星尘
        let color: Color
        let rx: CGFloat        // 全屏横向出生点 0...1
        let ry: CGFloat
        let angle: CGFloat
        let speed: CGFloat
        var vx: CGFloat = 0
        var vy: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        let c: CGFloat
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

// MARK: - RWS 公版图加载

/// 1909 公版韦特塔罗（RWSCards/ 文件夹引用，78 张全套随包内置）。
/// 大牌绘制用：major 索引（0...21）→ major-XX.jpg；带进程内缓存。
enum RWSArt {
    private static var cache: [Int: UIImage] = [:]

    static func major(_ index: Int) -> UIImage? {
        let clamped = max(0, min(21, index))
        if let hit = cache[clamped] { return hit }
        let name = String(format: "major-%02d", clamped)
        var loaded: UIImage?
        if let url = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "RWSCards"),
           let img = UIImage(contentsOfFile: url.path) {
            loaded = img
        }
        if let loaded {
            cache[clamped] = loaded
        } else {
            AppLog.warn("RWS 图缺失：\(name)")
        }
        return loaded
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

// MARK: - 牌义弹层

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


