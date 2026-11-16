import SwiftUI
import SwiftData
import UIKit
import AVFoundation

/// 每日一抽 · 塔罗抽牌模块（卡包质感 · 右侧弧形厚卡扇 · 上1下2三角牌阵版）
///
/// 四阶段状态机：
///   sealed（未拆封）→ tearing（沿虚线撕包仪式）→ fanSelection（右侧 40% 弧形牌扇选 3 张）→ spreadRevealed（上1下2三角牌阵翻牌揭晓）
///
/// 交互与动画要点：
/// - 卡包底部映射微光：香槟金 #D4AF37 × 深靛蓝 #2A4B8C 椭圆放射光晕（opacity 0.32、blur 26、下偏 16pt），
///   卡包表面叠加随手指触摸偏移的斜向金属高光层（.blendMode(.screen)）
/// - 指纹引导：虚线左端 touchid 图标 + 呼吸微光环 + 向右粒子拖尾；手指按上虚线开始拖动（dx > 2）即 0.15s 淡出缩小消失
/// - 强制沿虚线右向跟手撕开（取消点击开包）：撕裂前沿随 tearProgress 从左向右逐段揭开（动态 clipShape + 以前沿为轴的局部上翘旋转），
///   每滑 10pt 触发 UISelectionFeedbackGenerator 微震 + 合成撕箔音效；tearProgress < 0.72 松手弹回（spring 0.3/0.72），
///   ≥ 0.72 才触发撕条向右上 0.3s 抛飞渐隐，卡包原地微缩淡出（PackExit：0.88 + 渐隐，无位移）
/// - TarotFanView：虚拟圆心 (1.12w, 0.40h)、半径 0.64w，110°~250°（约 40% 圆周）均匀排布 14 张牌背，
///   径向旋转（弧线中部水平横放、两端随弧倾斜）；卡包淡出时 14 张以错峰 spring(0.45, 0.75) 从卡包中心弹开成弧；
///   PhysicalCardBackView 三层错位厚卡纸边 + 0.5pt 香槟金描边做出实体厚度；点选沿放射角度外弹 30pt + 轻震 + 纸张摩擦音（无数字角标）；
///   扇面几何约束在底栏上方（最低卡缘 ≈ 0.71h），任何卡牌边缘不压底部导航栏
/// - 上 1 下 2 三角大牌阵：选满 3 张后牌扇淡出，卡牌飞入中上部（上 1 居中·过去/核心，下 2 并排·现在/未来），
///   卡面放大至 128×192；FaceGate 在 90° 帧无缝切换正反面（正面预置 180° 镜像修正），阴影透明度绑定 abs(cos(angle))；
///   翻开后表面叠加全息镭射层（斜向多色渐变 + .colorDodge），支持按住单张拖动 3D 微倾与光影流动
/// - 「重新抽一张」：清空已选数组/翻牌/文字/粒子（clearToken），无重影切回 sealed，新牌池进扇时重新洗牌
struct TarotView: View {
    @Environment(\.modelContext) private var context

    @State private var draw: DailyTarot?
    @State private var didLoad = false
    @State private var phase: Phase = .sealed
    @State private var isRedraw = false
    @State private var isReadingPresented = false

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

    // MARK: spreadRevealed —— 三牌阵
    @State private var flipAllToken = 0
    @State private var revealedCount = 0
    @State private var spreadSettled = false
    @State private var loadedOpened = false

    @State private var confettiToken = 0
    @State private var clearToken = 0

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
                core: spreadCards.core,
                present: spreadCards.present,
                future: spreadCards.future,
                reversedCore: spreadReversed.core,
                reversedPresent: spreadReversed.present,
                reversedFuture: spreadReversed.future
            )
        }
        .onAppear(perform: load)
    }

    // MARK: - 页头（仅 sealed / spreadRevealed 阶段显示；牌阵解读在完成选牌前禁用）

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
            .overlay(
                // 斜向金属高光层：随手指触摸轻微偏移
                LinearGradient(
                    colors: [.clear, .white.opacity(0.34), .white.opacity(0.10), .clear],
                    startPoint: UnitPoint(x: 0.05, y: 0.05),
                    endPoint: UnitPoint(x: 0.85, y: 0.95)
                )
                .blendMode(.screen)
                .offset(x: packTilt.width * 0.12, y: packTilt.height * 0.10)
                .allowsHitTesting(false)
            )
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
                // 指纹引导消失触发点：手指按上虚线并开始拖动（translation.width > 2）
                if !tearStarted && dx > 2 {
                    tearStarted = true
                    phase = .tearing
                }
                // 仅响应横向向右
                guard dx > 0 else { return }
                let progress = min(1, max(0, dx / (packWidth * 0.85)))
                if progress > tearProgress {
                    tearTickAccumulator += (progress - tearProgress) * packWidth * 0.85
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

        // 同帧交叉：卡包原地微缩淡出（PackExit）与右侧牌扇从卡包中心错峰弹开
        // 新牌池在进入新一轮选牌时重新洗牌（22 张洗牌取前 14 张上扇）
        withAnimation(.easeOut(duration: 0.45)) {
            phase = .fanSelection
        }
        pool = Array(TarotDeck.major.map(\.id).shuffled().prefix(14))
        poolReversed = (0..<pool.count).map { _ in Bool.random() }
        selectedSlots = []
        fanBloomed = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            fanBloomed = true
        }
    }

    // MARK: - 阶段 3：fanSelection（右侧 40% 弧形厚卡扇 + 顶部三段进度）

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
        if let draw {
            TarotService.commitSpread(
                draw, in: context,
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

    // MARK: - 阶段 4：spreadRevealed（上 1 下 2 三角大牌阵）

    private var spreadBranch: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                header

                // 上 1 居中（过去 / 核心）
                spreadCard(index: 0, positionLabel: "过去 · 核心", card: spreadCards.core, reversed: spreadReversed.core)
                    .padding(.top, 4)

                // 下 2 并排（现在 / 未来）
                HStack(alignment: .top, spacing: 14) {
                    spreadCard(index: 1, positionLabel: "现在", card: spreadCards.present, reversed: spreadReversed.present)
                    spreadCard(index: 2, positionLabel: "未来", card: spreadCards.future, reversed: spreadReversed.future)
                }
                .padding(.top, 16)

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

    /// 三角牌阵中的一张：飞入入场 + 翻牌 + 逐牌文字门控
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

    /// 三牌阵牌面数据（cardID = 上位·核心，card2ID = 下左·现在，card3ID = 下右·未来）
    private var spreadCards: (core: TarotCard, present: TarotCard, future: TarotCard) {
        (
            TarotDeck.card(id: draw?.cardID ?? 0),
            TarotDeck.card(id: draw?.card2ID ?? 0),
            TarotDeck.card(id: draw?.card3ID ?? 0)
        )
    }

    private var spreadReversed: (core: Bool, present: Bool, future: Bool) {
        (
            draw?.isReversed ?? false,
            draw?.isReversed2 ?? false,
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

    /// 重新抽：立即清空已选数组/翻牌/文字/粒子，以无重影状态切回 sealed；
    /// 只把记录标记为未拆（首页继续显示旧牌阵的核心牌，不剧透），
    /// 新牌池在撕包后进入牌扇时重新洗牌，选满 3 张时由 commitSpread 落库
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

// MARK: - 卡包退场过渡（原地微缩淡出：0.88 + 渐隐，无位移）

struct PackExitModifier: ViewModifier, Animatable {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(1 - 0.12 * progress)
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
                        fanCard(
                            slot: slot,
                            center: center,
                            radius: radius,
                            restCenter: packCenter
                        )
                    }
                }
            }
            .frame(width: w, height: h)
        }
    }

    /// 弧上角度：110° → 250°，等分 14 段
    private func angleDeg(slot: Int) -> Double {
        110.0 + Double(slot) * (140.0 / Double(slotCount - 1))
    }

    @ViewBuilder
    private func fanCard(slot: Int, center: CGPoint, radius: CGFloat, restCenter: CGPoint) -> some View {
        let theta = angleDeg(slot: slot) * .pi / 180
        let ux = CGFloat(cos(theta))
        let uy = CGFloat(sin(theta))
        let target = CGPoint(x: center.x + radius * ux, y: center.y + radius * uy)
        let order = selectedSlots.firstIndex(of: slot)
        let isSelected = order != nil
        let radialOffset: CGFloat = isSelected ? 30 : 0
        // 弧线中部（接近 180°）的牌 zIndex 最高，扇面重叠自然
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
/// 内置点选手势：手指滑过/按住产生微弱 3D 倾斜，松手弹簧回弹；轻点（位移 < 10pt）即选中。
struct PhysicalCardBackView: View {
    var onSelect: () -> Void = {}

    @State private var tilt: CGSize = .zero
    @State private var pressing = false

    var body: some View {
        ZStack {
            // 三层微错位厚卡纸边（深金 / 卡纸 / 象牙）
            cardstock(color: Color(hex: 0x8C6D2F), dx: 3.5, dy: 4.5)
            cardstock(color: Color(hex: 0xC9A24B), dx: 2.5, dy: 3.2)
            cardstock(color: Color(hex: 0xEDE6D6), dx: 1.5, dy: 2.0)
            // 牌背 + 0.5pt 香槟金描边
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
        .rotation3DEffect(
            .degrees(max(-7, min(7, -tilt.height * 0.14))),
            axis: (x: 1, y: 0, z: 0), perspective: 0.7
        )
        .rotation3DEffect(
            .degrees(max(-7, min(7, tilt.width * 0.14))),
            axis: (x: 0, y: 1, z: 0), perspective: 0.7
        )
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

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !visible)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let breathe = 0.5 + 0.5 * sin(t * 2.4)
            ZStack(alignment: .leading) {
                // 呼吸微光环
                Circle()
                    .stroke(Color(hex: 0xD4AF37).opacity(0.55), lineWidth: 1.2)
                    .frame(width: 34, height: 34)
                    .scaleEffect(1 + breathe * 0.10)
                    .opacity(0.35 + breathe * 0.40)
                // 指纹图标
                Image(systemName: "touchid")
                    .font(.system(size: 19))
                    .foregroundStyle(Color(hex: 0xD4AF37).opacity(0.92))
                // 向右滑动粒子拖尾
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Color(hex: 0xD4AF37).opacity(0.50 - Double(i) * 0.13))
                        .frame(width: CGFloat(3.5 - Double(i) * 0.8), height: CGFloat(3.5 - Double(i) * 0.8))
                        .offset(x: 22 + CGFloat(i) * 9 + sin(t * 2.2 + Double(i) * 1.3) * 3.5)
                }
            }
        }
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.55)
        .animation(.easeOut(duration: 0.15), value: visible)
        .allowsHitTesting(false)
    }
}

// MARK: - 三角牌阵单卡（RevealCard）

/// 单张揭晓大牌：位置标签 + 翻牌卡面 + 逐牌文字门控。
/// 翻牌两段式：0→90°（easeInOut 确定过临界），90° 帧切换正反面/触发回调，90→180° 弹簧落定；
/// 阴影透明度绑定 abs(cos(angle))，90° 垂直瞬间为 0；翻开后叠加全息镭射层并支持拖动 3D 微倾。
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

    private let cardWidth: CGFloat = 128
    private let cardHeight: CGFloat = 192

    var body: some View {
        VStack(spacing: 8) {
            Text(positionLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .tracking(1)

            cardFace

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(card.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text(reversed ? "逆位" : "正位")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(card.keywords(reversed: reversed).joined(separator: " · "))
                    .font(.system(size: 10.5))
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
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
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
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
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
            RoundedRectangle(cornerRadius: 11, style: .continuous)
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

// MARK: - 牌阵解读

/// 三牌阵解读弹窗：上·过去/核心，下左·现在，下右·未来
struct TarotSpreadSheet: View {
    @Environment(\.dismiss) private var dismiss
    let core: TarotCard
    let present: TarotCard
    let future: TarotCard
    let reversedCore: Bool
    let reversedPresent: Bool
    let reversedFuture: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 10) {
                        spreadMini(title: "核心", card: core, reversed: reversedCore)
                        spreadMini(title: "现在", card: present, reversed: reversedPresent)
                        spreadMini(title: "未来", card: future, reversed: reversedFuture)
                    }

                    spreadSection(title: "核心 · 过去 · \(core.name)", en: core.en, reversed: reversedCore, card: core)
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

/// 全息素材：阈值化闪粉噪点
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

    /// 多色斜向循环渐变（110° 循环色带）
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

// MARK: - 全屏彩带粒子（Canvas + TimelineView）

/// 粒子物理存储：Canvas 逐帧积分，不走 SwiftUI 状态，避免每帧视图重建。
final class ConfettiStore {
    struct Bit {
        let kind: Int          // 0 圆点 / 1 彩带 / 2 星尘
        let color: Color
        let rx: CGFloat
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

/// Bundle 松散素材显式加载 + 进程内缓存（牌扇 14 张牌背同帧重排，必须复用解码结果）。
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