import SwiftUI
import UIKit

// MARK: - 表情参数（移植自 Emotion Ball 的社区许可版本）
//
// 出处：Emotion Ball — https://github.com/Aithena/emotion-ball
//      作者 sam70361（抖音/仓库公开说明：社区许可免费用于个人学习、
//      研究、技术交流、非商业分享，注明出处即可）。
// 本文件只参考其 `js/emotions.js` 的**表情参数与行为设计**（表情命名、
// 眼型池、openness、眨眼间隔、呼吸/zzz/彩带等），渲染与动画全部用
// SwiftUI 从零重写，未复制其源码或素材（该项目本身零图片资源）。

/// 眼型（对应原项目眼环池的分类，简化为 SwiftUI 可插值的形状参数）
enum BallEyeStyle {
    case calm        // 平静（0/8）
    case smile       // 笑眼（2/11/17/19）
    case wide        // 圆睁（3/21）
    case closed      // 闭合（13/22/4）
    case sleepy      // 半闭（4/22）
    case sideEye     // 斜眼（14/5/23）
    case angry       // 怒目（7/16）
    case shy         // 羞怯（24）

    /// 开合度 0...1.2
    var open: CGFloat {
        switch self {
        case .calm: return 1.0
        case .smile: return 0.16
        case .wide: return 1.25
        case .closed: return 0.06
        case .sleepy: return 0.32
        case .sideEye: return 0.9
        case .angry: return 0.55
        case .shy: return 0.5
        }
    }

    /// 弯曲：负值上弯（笑眼 ∩），正值下垂
    var bend: CGFloat {
        switch self {
        case .smile: return -1.4
        case .sleepy: return 0.35
        case .angry: return 0.6
        case .shy: return -0.3
        default: return 0
        }
    }

    /// 倾角（度）
    var slant: CGFloat {
        switch self {
        case .angry: return 14
        case .sideEye: return -8
        case .shy: return 4
        default: return 0
        }
    }

    var verticalOffset: CGFloat {
        switch self {
        case .sleepy: return 1.5
        case .shy: return 1
        default: return 0
        }
    }
}

/// 嘴型
struct BallMouthStyle {
    var curve: CGFloat   // 1 大笑 … 0 平 … -1 撇嘴
    var width: CGFloat   // 0.4...0.85（相对 16pt）
    var open: CGFloat    // 0 = 线，1 = O 型

    static let gentle = BallMouthStyle(curve: 0.45, width: 0.5, open: 0)
    static let flat = BallMouthStyle(curve: 0.05, width: 0.45, open: 0)
    static let smile = BallMouthStyle(curve: 1.0, width: 0.72, open: 0)
    static let frown = BallMouthStyle(curve: -0.85, width: 0.5, open: 0)
    static let small = BallMouthStyle(curve: -0.2, width: 0.4, open: 0)
    static let surprised = BallMouthStyle(curve: 0, width: 0.3, open: 1)
}

/// 单个表情的完整规格（字段对应原项目 emotions.js 的对应项）
struct BallEmotionSpec: Identifiable {
    let id: String                    // 原项目 emotionId（00-09 生命周期 / 10-29 情绪 / 30-49 代理状态）
    let name: String                  // 原项目中文命名
    let eyes: [BallEyeStyle]          // 眼环池（原 pool）
    let mouth: BallMouthStyle
    let blinkInterval: ClosedRange<Double>?   // 原 blinkMs（秒）
    let breathe: CGFloat              // 原 body.breathe
    let yOffset: CGFloat              // 原 body.y
    let glanceAmp: CGFloat            // 原 eyes lookX 漂移幅度
    let rotate: CGFloat               // 原 body.rotate
    let extras: Extras

    struct Extras {
        var blush: CGFloat = 0
        var tears: CGFloat = 0
        var zzz: CGFloat = 0
        var sparkle: CGFloat = 0
        var anger: CGFloat = 0
        var confetti: CGFloat = 0
    }

    /// 首页彩蛋的点击轮换序列（按原 ID，未收纳的代理状态类留待后续）
    static let cycle: [BallEmotionSpec] = [
        // 02 待机放空：左看右看、偶尔眨眼、轻微呼吸
        BallEmotionSpec(id: "02", name: "待机放空", eyes: [.calm], mouth: .gentle,
                        blinkInterval: 4.0...9.0, breathe: 0.012, yOffset: 0, glanceAmp: 2.6,
                        rotate: 0, extras: .init()),
        // 10 开心：笑眼、身体上浮、偶尔眨动
        BallEmotionSpec(id: "10", name: "开心", eyes: [.smile], mouth: .smile,
                        blinkInterval: 2.5...4.5, breathe: 0.014, yOffset: -1.5, glanceAmp: 0,
                        rotate: 0, extras: .init(sparkle: 0.7)),
        // 14 害羞：目光偏向一侧、腮红、轻微歪头
        BallEmotionSpec(id: "14", name: "害羞", eyes: [.shy], mouth: .gentle,
                        blinkInterval: 3.0...5.5, breathe: 0.012, yOffset: 0, glanceAmp: 2,
                        rotate: 6, extras: .init(blush: 1)),
        // 21 生气：怒目、撇嘴、怒气符号
        BallEmotionSpec(id: "21", name: "生气", eyes: [.angry], mouth: .frown,
                        blinkInterval: 3.5...7.0, breathe: 0.004, yOffset: 0.5, glanceAmp: 0,
                        rotate: 0, extras: .init(anger: 1)),
        // 13 惊讶：圆睁、O 型嘴、身体弹起
        BallEmotionSpec(id: "13", name: "惊讶", eyes: [.wide], mouth: .surprised,
                        blinkInterval: 1.8...3.2, breathe: 0.006, yOffset: -1.5, glanceAmp: 0,
                        rotate: 0, extras: .init()),
        // 11 疑惑：斜眼、撇嘴、歪头
        BallEmotionSpec(id: "11", name: "疑惑", eyes: [.sideEye], mouth: .small,
                        blinkInterval: 2.8...5.0, breathe: 0.008, yOffset: 0, glanceAmp: -2,
                        rotate: -8, extras: .init()),
        // 15 疲惫：半闭眼、身体下沉、不眨眼
        BallEmotionSpec(id: "15", name: "疲惫", eyes: [.sleepy], mouth: .flat,
                        blinkInterval: nil, breathe: 0.016, yOffset: 1.5, glanceAmp: 1.2,
                        rotate: -3, extras: .init()),
        // 00 睡眠：闭眼成线、zzz 飘起
        BallEmotionSpec(id: "00", name: "睡眠", eyes: [.closed], mouth: .fine,
                        blinkInterval: nil, breathe: 0.018, yOffset: 2, glanceAmp: 0,
                        rotate: -2, extras: .init(zzz: 1)),
        // 19 满意：平和眼、浅笑
        BallEmotionSpec(id: "19", name: "满意", eyes: [.calm, .smile], mouth: .gentle,
                        blinkInterval: 3.5...6.5, breathe: 0.012, yOffset: 0, glanceAmp: 1.4,
                        rotate: 0, extras: .init(sparkle: 0.3)),
        // 33 任务完成：笑眼、撒彩纸
        BallEmotionSpec(id: "33", name: "任务完成", eyes: [.smile], mouth: .smile,
                        blinkInterval: 2.2...4.2, breathe: 0.013, yOffset: -1, glanceAmp: 0,
                        rotate: 0, extras: .init(sparkle: 0.5, confetti: 1)),
    ]
}

private extension BallMouthStyle {
    /// 睡眠时的一点小嘴
    static let fine = BallMouthStyle(curve: 0.12, width: 0.32, open: 0)
}

// MARK: - 首页彩蛋球

/// 首页右下角表情球（与课表/待办 FAB 同锚点：52pt、右 20、底 80）。
/// 点击循环切换表情（原项目 emotionId 顺序），轻震反馈；6 秒后自动回到待机。
/// 待机态带随机眨眼（带回弹过冲）、目光漂移与呼吸；睡眠带 zzz；完成态撒彩纸。
struct EmotionBallView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    @State private var index = 0
    @State private var eyePoolIndex = 0
    @State private var blinkScale: CGFloat = 1
    @State private var glanceX: CGFloat = 0
    @State private var breathScale: CGFloat = 1
    @State private var zzzPhase: CGFloat = 0
    @State private var sparklePhase: CGFloat = 0
    @State private var confettiToken = UUID()
    @State private var returnTask: Task<Void, Never>?

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    private var emotion: BallEmotionSpec { BallEmotionSpec.cycle[index] }
    private var eyeStyle: BallEyeStyle {
        let pool = emotion.eyes
        return pool[min(eyePoolIndex, pool.count - 1)]
    }

    var body: some View {
        Button {
            next()
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.text)

                BallFace(
                    style: eyeStyle,
                    blinkScale: blinkScale,
                    glanceX: glanceX,
                    mouth: emotion.mouth
                )

                extrasLayer
            }
            .frame(width: 52, height: 52)
            .rotationEffect(.degrees(emotion.rotate))
            .offset(y: emotion.yOffset)
            .scaleEffect(breathScale)
            .shadow(color: .black.opacity(0.22), radius: 10, y: 4)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("表情球：\(emotion.name)，点按换表情")
        .task(id: emotion.id) {
            await runEmotionLoops()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                blinkScale = 1
            }
        }
        .onDisappear {
            returnTask?.cancel()
            returnTask = nil
        }
    }

    // MARK: 点击切换

    private func next() {
        haptic.impactOccurred()
        let nextIndex = (index + 1) % BallEmotionSpec.cycle.count
        withAnimation(.spring(response: 0.34, dampingFraction: 0.74)) {
            index = nextIndex
        }
        // 进入「任务完成」时撒彩纸
        if BallEmotionSpec.cycle[nextIndex].extras.confetti > 0 {
            confettiToken = UUID()
        }
        // 6 秒后自动回到待机（再次点击会取消上一次计时）
        returnTask?.cancel()
        returnTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                index = 0
            }
        }
    }

    // MARK: 每个表情的循环动效

    private func runEmotionLoops() async {
        eyePoolIndex = 0
        glanceX = 0
        blinkScale = 1

        guard !reduceMotion else { return }

        async let poolLoop: Void = runEyePoolLoop()
        async let blinkLoop: Void = runBlinkLoop()
        async let glanceLoop: Void = runGlanceLoop()
        _ = await (poolLoop, blinkLoop, glanceLoop)
    }

    /// 眼型池轮换（原 poolMs：眼睛形状每隔几秒缓缓换一次）
    private func runEyePoolLoop() async {
        guard emotion.eyes.count > 1 else { return }
        let intervals: [Double] = [4.5, 6.5, 5.5, 8.0]
        var step = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(intervals[step % intervals.count] * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.6)) {
                eyePoolIndex = (eyePoolIndex + 1) % emotion.eyes.count
            }
            step += 1
        }
    }

    /// 眨眼：快速闭合，回弹带轻微过冲（原 blinkMs 区间）
    private func runBlinkLoop() async {
        guard let interval = emotion.blinkInterval else { return }
        let durations: [Double] = [interval.lowerBound, (interval.lowerBound + interval.upperBound) / 2, interval.upperBound, interval.lowerBound * 1.3]
        var step = 0
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: UInt64(durations[step % durations.count] * 1_000_000_000))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.07)) { blinkScale = 0.08 }
            try? await Task.sleep(nanoseconds: 95_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.16, dampingFraction: 0.5)) { blinkScale = 1 }
            step += 1
        }
    }

    /// 目光漂移（原 lookX 正弦/左右看）
    private func runGlanceLoop() async {
        guard emotion.glanceAmp != 0 else { return }
        var direction: CGFloat = 1
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.9)) {
                glanceX = emotion.glanceAmp * direction
            }
            direction *= -1
        }
    }

    // MARK: 气泡外的小元素

    @ViewBuilder
    private var extrasLayer: some View {
        let extras = emotion.extras
        ZStack {
            // 呼吸
            Color.clear
                .onAppear {
                    guard !reduceMotion else { return }
                    breathScale = 1 - emotion.breathe
                    withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) {
                        breathScale = 1 + emotion.breathe
                    }
                }

            // 腮红
            if extras.blush > 0 {
                HStack(spacing: 15) {
                    blushDot; blushDot
                }
                .offset(y: 6)
                .opacity(extras.blush)
            }

            // 怒气符号（左上）
            if extras.anger > 0 {
                AngerMark()
                    .frame(width: 10, height: 10)
                    .foregroundStyle(Color(hex: 0xE4574A))
                    .offset(x: -16, y: -16)
                    .opacity(extras.anger)
            }

            // 困倦 zzz（右上漂浮）
            if extras.zzz > 0 {
                ZzzMark()
                    .offset(x: 20, y: -14)
                    .opacity(extras.zzz)
            }

            // 星光（右上小金星）
            if extras.sparkle > 0 {
                SparkleMark()
                    .offset(x: 17, y: -17)
                    .opacity(extras.sparkle)
            }

            // 任务完成彩纸
            if extras.confetti > 0 {
                ConfettiBurst(token: confettiToken, reduceMotion: reduceMotion)
            }
        }
        .allowsHitTesting(false)
    }

    private var blushDot: some View {
        Circle()
            .fill(Color(hex: 0xF4A8A0).opacity(0.85))
            .frame(width: 7, height: 4)
            .blur(radius: 0.5)
    }
}

// MARK: - 脸部（眼 + 嘴）

private struct BallFace: View {
    let style: BallEyeStyle
    let blinkScale: CGFloat
    let glanceX: CGFloat
    let mouth: BallMouthStyle

    var body: some View {
        GeometryReader { geo in
            let s = geo.size.width / 52
            let eyeOpen = max(0.04, style.open * blinkScale)

            ZStack {
                // 左眼
                BallEye(open: eyeOpen, bend: style.bend, slant: -style.slant)
                    .fill(Theme.bg)
                    .frame(width: 9 * s, height: 8 * s)
                    .position(x: 17.5 * s + glanceX * s, y: (24.5 + style.verticalOffset) * s)

                // 右眼
                BallEye(open: eyeOpen, bend: style.bend, slant: style.slant)
                    .fill(Theme.bg)
                    .frame(width: 9 * s, height: 8 * s)
                    .position(x: 34.5 * s + glanceX * s, y: (24.5 + style.verticalOffset) * s)

                // 嘴（曲线 + O 型）
                BallMouthCurve(curve: mouth.curve, width: mouth.width)
                    .stroke(Theme.bg, style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round))
                    .frame(width: 16 * s, height: 8 * s)
                    .position(x: 26 * s, y: 35 * s)
                    .opacity(1 - mouth.open)

                Ellipse()
                    .fill(Theme.bg)
                    .frame(width: (3.4 + mouth.open * 1.6) * s,
                           height: (1.2 + mouth.open * 4.6) * s)
                    .position(x: 26 * s, y: 35 * s)
                    .opacity(mouth.open)
            }
        }
    }
}

/// 眼睛：透镜形状，可插值开合 / 弯曲 / 斜角
private struct BallEye: Shape {
    var open: CGFloat
    var bend: CGFloat
    var slant: CGFloat

    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(open, AnimatablePair(bend, slant)) }
        set {
            open = newValue.first
            bend = newValue.second.first
            slant = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = max(1.1, rect.height * min(1.3, open))
        let cx = rect.midX
        let cy = rect.midY
        let bendOffset = bend * rect.height * 0.28

        var path = Path()
        path.move(to: CGPoint(x: cx - w / 2, y: cy))
        path.addQuadCurve(
            to: CGPoint(x: cx + w / 2, y: cy),
            control: CGPoint(x: cx, y: cy - h / 2 + bendOffset)
        )
        path.addQuadCurve(
            to: CGPoint(x: cx - w / 2, y: cy),
            control: CGPoint(x: cx, y: cy + h / 2 + bendOffset)
        )
        path.closeSubpath()

        guard slant != 0 else { return path }
        let radians = slant * .pi / 180
        let transform = CGAffineTransform(translationX: cx, y: cy)
            .rotated(by: radians)
            .translatedBy(x: -cx, y: -cy)
        return path.applying(transform)
    }
}

/// 嘴：一条二次曲线
private struct BallMouthCurve: Shape {
    var curve: CGFloat
    var width: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(curve, width) }
        set {
            curve = newValue.first
            width = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width * width
        let cx = rect.midX
        let cy = rect.midY
        let offset = curve * rect.height * 0.62

        var path = Path()
        path.move(to: CGPoint(x: cx - w / 2, y: cy))
        path.addQuadCurve(
            to: CGPoint(x: cx + w / 2, y: cy),
            control: CGPoint(x: cx, y: cy + offset)
        )
        return path
    }
}

// MARK: - 小元素

private struct AngerMark: View {
    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .frame(width: 1.6, height: 4)
                    .offset(y: -3.2)
                    .rotationEffect(.degrees(Double(i) * 90 + 45))
            }
        }
    }
}

/// 睡眠 zzz：两个 z 交错上浮
private struct ZzzMark: View {
    @State private var lift: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Text("z")
                .font(.system(size: 8, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .offset(x: 0, y: lift)
                .opacity(max(0.15, 0.9 + Double(lift) * 0.1))
            Text("z")
                .font(.system(size: 6, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textTertiary.opacity(0.7))
                .offset(x: 5, y: lift * 0.7 + 4)
                .opacity(max(0.1, 0.7 + Double(lift) * 0.08))
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) {
                lift = -6
            }
        }
    }
}

/// 星光：一颗四角星 + 两点小星
private struct SparkleMark: View {
    @State private var phase: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            ReiconIcon(icon: .star, size: 7)
                .foregroundStyle(Color(hex: 0xF5C542))
                .scaleEffect(0.85 + phase * 0.3)
            Circle()
                .fill(Color(hex: 0xF5C542).opacity(0.8))
                .frame(width: 2.2, height: 2.2)
                .offset(x: 7, y: 3)
            Circle()
                .fill(Color(hex: 0xF5C542).opacity(0.55))
                .frame(width: 1.6, height: 1.6)
                .offset(x: -5, y: 5)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                phase = 1
            }
        }
    }
}

/// 任务完成时的一次性彩纸
private struct ConfettiBurst: View {
    let token: UUID
    let reduceMotion: Bool

    @State private var fired = false

    private static let seeds: [(angle: Double, distance: Double, size: CGFloat, color: UInt32)] = [
        (-1.2, 30, 3, 0xF5C542), (-0.7, 34, 2.4, 0x34C759),
        (-0.25, 28, 3.2, 0x60A5FA), (0.2, 34, 2.2, 0xF43F5E),
        (0.7, 30, 2.8, 0xF5C542), (1.2, 26, 2.2, 0x34C759),
        (1.7, 32, 2.6, 0x60A5FA), (2.3, 28, 2.0, 0xF43F5E),
        (-1.7, 27, 2.0, 0x34C759), (2.8, 30, 2.4, 0xF5C542),
    ]

    var body: some View {
        ZStack {
            ForEach(Self.seeds.indices, id: \.self) { i in
                let seed = Self.seeds[i]
                Circle()
                    .fill(Color(hex: seed.color))
                    .frame(width: seed.size, height: seed.size)
                    .scaleEffect(fired ? 1 : 0.2)
                    .opacity(fired ? 0 : 0.95)
                    .offset(
                        x: fired ? cos(seed.angle) * seed.distance : 0,
                        y: fired ? sin(seed.angle) * seed.distance * 0.8 : 0
                    )
            }
        }
        .id(token)
        .onAppear {
            guard !reduceMotion else {
                fired = true
                return
            }
            withAnimation(.easeOut(duration: 0.75)) {
                fired = true
            }
        }
    }
}