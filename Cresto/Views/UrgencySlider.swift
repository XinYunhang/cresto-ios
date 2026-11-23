import SwiftUI
import QuartzCore

/// 三档紧急程度滑块（对齐 UI 设计图：轻微 / 重要 / 紧急）。
/// 保留 galaxy-effort-slider 的像素点阵星光质感与弹簧手感，按 v7 规格精简：
/// · 胶囊轨道固定高 42pt；圆形发光滑块 34pt×34pt，四周 4pt 内边距，水平中心锁在 [21, trackWidth−21]
/// · 像素点阵颜色随连续 position 在 冰蓝 #60A5FA / 琥珀 #F59E0B / 珊瑚红 #F43F5E 间插值
/// · CADisplayLink 手动积分弹簧（k=420/c=32，每帧 3 子步，快速反向保留位置速度；停稳即停帧）
/// · 切档 UISelectionFeedbackGenerator 轻震；reduce motion 立即吸附
struct UrgencySlider: View {
    @Binding var selection: TaskUrgency

    @StateObject private var engine = UrgencyEngine()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragging = false
    @State private var dragStartTarget: Double = 0
    @State private var lastHapticTier: TaskUrgency?

    private let hapticSelect = UISelectionFeedbackGenerator()

    /// 34pt 滑块 + 四周 4pt 内边距 = 21pt 锁边
    private static let inset: CGFloat = 21
    private static let trackHeight: CGFloat = 42
    private static let knobSize: CGFloat = 34

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let span = max(1, width - Self.inset * 2)
            let knobX = Self.inset + span * CGFloat(min(2, max(0, engine.position)) / 2)
            let tint = SliderTint.blend(engine.position)

            ZStack {
                // 胶囊轨道
                Capsule()
                    .fill(Color.black.opacity(0.35))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.06), lineWidth: 1))

                // 像素点阵星光
                DotFieldCanvas(
                    position: engine.position,
                    clock: reduceMotion ? 0 : engine.clock,
                    inset: Self.inset
                )
                .allowsHitTesting(false)

                // 34pt 发光滑块（图标 15pt，四周 4pt 内距，绝不裁切）
                ZStack {
                    Circle().fill(tint)
                    ReiconIcon(icon: engine.nearestTier.reicon, size: 16)
                        .foregroundStyle(Color.white)
                }
                .frame(width: Self.knobSize, height: Self.knobSize)
                .shadow(color: tint.opacity(0.55), radius: 10)
                .shadow(color: tint.opacity(0.25), radius: 18)
                .scaleEffect(dragging ? 1.06 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.62), value: dragging)
                .position(x: knobX, y: Self.trackHeight / 2)
            }
            .frame(width: width, height: Self.trackHeight)
            .contentShape(Rectangle())
            .onTapGesture { location in
                engine.setTarget(sliderValue(x: location.x, width: width))
                commit()
            }
            .gesture(sliderDrag(width: width))
            .accessibilityElement()
            .accessibilityLabel("紧急程度")
            .accessibilityValue(engine.nearestTier.title)
            .accessibilityAdjustableAction { direction in
                let next = max(0, min(2, engine.nearestTier.rawValue + (direction == .increment ? 1 : -1)))
                engine.setTarget(Double(next))
                commit()
            }
        }
        .frame(height: 54)
        .onAppear {
            engine.snap(to: Double(selection.rawValue))
            if scenePhase == .active { engine.resume() }
        }
        .onChange(of: scenePhase) { _, phase in
            // 后台/离屏暂停不补时间
            if phase == .active { engine.resume() } else { engine.pause() }
        }
        .onDisappear { engine.pause() }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { engine.snapToTargets() }
        }
    }

    // MARK: 手势（纵向主导让给滚动，视为取消并回退按下时档位）

    private func sliderDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard abs(value.translation.width) >= abs(value.translation.height) else {
                    if dragging {
                        dragging = false
                        engine.setTarget(dragStartTarget)
                    }
                    return
                }
                if !dragging {
                    dragging = true
                    dragStartTarget = Double(selection.rawValue)
                }
                engine.setTarget(sliderValue(x: value.location.x, width: width))
                updateHaptic()
            }
            .onEnded { _ in
                dragging = false
                let snapped = max(0, min(2, engine.target.rounded()))
                engine.setTarget(snapped)
                commit()
            }
    }

    /// value = clamp((x−21)/(w−42)×2, 0, 2)
    private func sliderValue(x: CGFloat, width: CGFloat) -> Double {
        let span = max(1, width - Self.inset * 2)
        let clamped = min(width - Self.inset, max(Self.inset, x))
        return Double((clamped - Self.inset) / span) * 2
    }

    private func updateHaptic() {
        let tier = engine.nearestTier
        guard tier != lastHapticTier else { return }
        lastHapticTier = tier
        hapticSelect.selectionChanged()
    }

    private func commit() {
        let tier = engine.nearestTier
        lastHapticTier = tier
        if tier != selection { selection = tier }
    }
}

// MARK: - 色板插值（相邻档位色逐通道混合）

enum SliderTint {
    static func blend(_ position: Double) -> Color {
        let t = min(2, max(0, position))
        let index = min(1, Int(t.rounded(.down)))
        let fraction = t - Double(index)
        let low: TaskUrgency = index == 0 ? .mild : .important
        let high: TaskUrgency = index == 0 ? .important : .urgent
        let a = low.tintComponents
        let b = high.tintComponents
        return Color(
            red: a.red + (b.red - a.red) * fraction,
            green: a.green + (b.green - a.green) * fraction,
            blue: a.blue + (b.blue - a.blue) * fraction
        )
    }
}

// MARK: - 像素点阵星光（确定性 hash，颜色随连续 position 插值，靠近滑块更亮）

private struct DotFieldCanvas: View {
    let position: Double
    let clock: Double
    let inset: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let span = max(1, size.width - inset * 2)
            let knobX = inset + span * CGFloat(min(2, max(0, position)) / 2)
            let tint = SliderTint.blend(position)

            for index in 0..<48 {
                let seedX = SliderSeed.hash(Double(index) + 3)
                let seedY = SliderSeed.hash(Double(index) + 157)
                let x = 10 + seedX * (size.width - 20)
                let y = 7 + seedY * (size.height - 14)

                // 靠近滑块更亮；远离处只留极淡星尘
                let distance = abs(x - knobX) / max(1, size.width)
                let proximity = 1 - min(1, distance * 1.45)
                let twinkle = 0.72 + 0.28 * sin(clock * 2.2 + Double(index) * 1.7)
                let alpha = (0.08 + 0.52 * proximity) * twinkle

                let radius = 0.9 + SliderSeed.hash(Double(index) + 91) * 1.3
                let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(tint.opacity(alpha)))
            }
        }
    }
}

enum SliderSeed {
    /// 确定性 hash：fract(sin(n×127.1+311.7)×43758.5453)
    static func hash(_ n: Double) -> Double {
        let value = sin(n * 127.1 + 311.7) * 43758.5453
        return value - value.rounded(.down)
    }
}

// MARK: - 引擎（CADisplayLink 手动积分；k=420/c=32 每帧 3 子步）

@MainActor
final class UrgencyEngine: ObservableObject {
    @Published private(set) var position: Double = 0
    @Published private(set) var clock: Double = 0
    @Published private(set) var target: Double = 0

    private var velocity: Double = 0
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    var nearestTier: TaskUrgency {
        TaskUrgency(legacyRaw: Int(target.rounded()))
    }

    func setTarget(_ value: Double) {
        target = max(0, min(2, value))
        resume()
    }

    /// 进入页面时对齐绑定初值
    func snap(to value: Double) {
        target = max(0, min(2, value))
        position = target
        velocity = 0
        pause()
    }

    /// reduce motion：立即吸附目标
    func snapToTargets() {
        position = target
        velocity = 0
        pause()
    }

    func resume() {
        guard link == nil else { return }
        let link = CADisplayLink(target: DisplayLinkProxy(engine: self), selector: #selector(DisplayLinkProxy.step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        lastTimestamp = 0
    }

    func pause() {
        link?.invalidate()
        link = nil
        lastTimestamp = 0
    }

    func step(timestamp: CFTimeInterval) {
        let dt = lastTimestamp == 0 ? (1.0 / 120.0) : min(0.032, timestamp - lastTimestamp)
        lastTimestamp = timestamp
        clock += dt

        // v += ((target-position)×k − v×c)×dt/3；position += v×dt/3（每帧 3 子步）
        let sub = dt / 3
        for _ in 0..<3 {
            velocity += ((target - position) * 420 - velocity * 32) * sub
            position += velocity * sub
        }

        // 误差 <.0002 且速度 <.002 时吸附；停稳即停帧（功耗）
        if abs(target - position) < 0.0002 && abs(velocity) < 0.002 {
            position = target
            velocity = 0
            pause()
        }
    }

    deinit {
        link?.invalidate()
        link = nil
    }
}

private final class DisplayLinkProxy: NSObject {
    private weak var engine: UrgencyEngine?

    init(engine: UrgencyEngine) {
        self.engine = engine
    }

    @objc func step(_ link: CADisplayLink) {
        // CADisplayLink 在主 runloop 触发；显式声明隔离（iOS 17+ assumeIsolated）
        MainActor.assumeIsolated {
            engine?.step(timestamp: link.timestamp)
        }
    }
}