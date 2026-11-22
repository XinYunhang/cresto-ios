import SwiftUI

/// 紧急程度滑块 —— galaxy-effort-slider 的 100% 纯原生 SwiftUI 复刻。
/// 参考文档（leibox.pantoria.cn）公开的行为规格：
/// · 六档 Low→Galaxy，档位越高「脑形」旋钮越用力（图标字重递增）；
/// · 拖拽带阻尼、松手弹簧吸附到档位；点击轨道同样可选档；
/// · 档位切换用 UISelectionFeedbackGenerator 线性马达轻震；
/// · 只有进入最高档 Galaxy 才点亮「闪动点阵 + 放射粒子 + 光晕」，并伴随短促震动。
/// 文档未公开具体阻尼数值，弹簧参数为原生等价实现（response 0.35 / damping 0.62）。
/// 全程无 WebView、无第三方依赖；圆角走 AppRadius / Capsule。
struct UrgencySlider: View {
    @Binding var selection: TaskUrgency
    /// 紧凑模式（新建待办快捷页）：不带标题行、整体更矮
    var compact = false

    @State private var position: CGFloat?   // 旋钮当前 x（绝对坐标）；nil = 吸附在当前档位锚点
    @State private var dragging = false
    @State private var galaxyBurst = UUID() // 每次进入 Galaxy 重新触发一次星尘爆发

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var tiers: [TaskUrgency] { TaskUrgency.allCases }
    private let hapticSelect = UISelectionFeedbackGenerator()
    private let hapticImpact = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !compact {
                HStack(alignment: .firstTextBaseline) {
                    Text("紧急程度").cardLabel()
                    Spacer()
                    tierTitle
                }
            }

            trackField
        }
        .onChange(of: selection) { _, newValue in
            if newValue.isGalaxy { galaxyBurst = UUID() }
        }
    }

    // MARK: 档位标题

    private var tierTitle: some View {
        HStack(spacing: 5) {
            if selection.isGalaxy {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.text)
            }
            Text(selection.title)
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
        }
        .animation(.snappy(duration: 0.2), value: selection)
    }

    // MARK: 轨道

    private var trackField: some View {
        let trackHeight: CGFloat = compact ? 32 : 36

        return GeometryReader { geo in
            let width = geo.size.width
            let knobSize: CGFloat = compact ? 28 : 32
            let inset = knobSize / 2 + 5
            let span = max(1, width - inset * 2)
            let anchors = (0..<tiers.count).map { inset + span * CGFloat($0) / CGFloat(tiers.count - 1) }
            let knobX = position ?? anchors[selection.rawValue]

            ZStack(alignment: .leading) {
                // 轨道槽
                Capsule()
                    .fill(Theme.surfaceRaised)
                    .frame(height: trackHeight)

                // 进度线（轨道中央细线，左段点亮）
                Capsule()
                    .fill(Theme.text.opacity(0.85))
                    .frame(width: max(8, knobX - 14), height: 3.5)
                    .offset(x: 14)

                // 六个档位刻度点
                ForEach(anchors.indices, id: \.self) { index in
                    Circle()
                        .fill(index <= selection.rawValue ? Theme.text.opacity(0.5) : Theme.text.opacity(0.16))
                        .frame(width: 4, height: 4)
                        .position(x: anchors[index], y: trackHeight / 2)
                }

                // Galaxy 光晕（脉动，减少动态效果时静止）
                if selection.isGalaxy {
                    Circle()
                        .fill(Theme.text.opacity(0.14))
                        .frame(width: knobSize * 2.1, height: knobSize * 2.1)
                        .blur(radius: 12)
                        .position(x: knobX, y: trackHeight / 2)
                        .modifier(PulseMotion(reduceMotion: reduceMotion))
                }

                // 旋钮（脑形；档位越高字重越重 = 用力越大）
                knob(size: knobSize)
                    .position(x: knobX, y: trackHeight / 2)

                // Galaxy 星尘：点阵 + 放射粒子
                if selection.isGalaxy {
                    SparkleBurst(burstID: galaxyBurst, reduceMotion: reduceMotion)
                        .position(x: knobX, y: trackHeight / 2)
                    staticTwinkles(size: knobSize)
                        .position(x: knobX, y: trackHeight / 2)
                }
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onTapGesture { location in
                select(nearestTier(x: location.x, width: width, inset: inset, span: span), width: width, inset: inset, span: span)
            }
            .gesture(dragGesture(width: width, inset: inset, span: span))
        }
        .frame(height: compact ? 44 : 52)
    }

    private func knob(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(Theme.text)
            Image(systemName: "brain.head.profile")
                .font(.system(size: size * 0.48, weight: knobWeight))
                .foregroundStyle(Theme.bg)
            if selection.isGalaxy {
                Image(systemName: "sparkle")
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(Theme.text)
                    .offset(x: size * 0.34, y: -size * 0.38)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        .scaleEffect(dragging ? 1.06 : 1)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: dragging)
    }

    /// 旋钮字重随档位递增（脑回褶皱逐层增加的等价表达）
    private var knobWeight: Font.Weight {
        switch selection {
        case .low: return .ultraLight
        case .medium: return .light
        case .high: return .regular
        case .extra: return .medium
        case .max: return .semibold
        case .galaxy: return .bold
        }
    }

    private func staticTwinkles(size: CGFloat) -> some View {
        ForEach(0..<3, id: \.self) { index in
            Image(systemName: "sparkle")
                .font(.system(size: 7 + CGFloat(index)))
                .foregroundStyle(Theme.text.opacity(0.8))
                .offset(
                    x: size * 0.55 + CGFloat(index) * 9,
                    y: -size * 0.42 - CGFloat(index) * 5
                )
                .opacity(reduceMotion ? 0.8 : 0.35)
                .modifier(TwinkleMotion(delay: Double(index) * 0.35, reduceMotion: reduceMotion))
        }
    }

    // MARK: 手势

    private func dragGesture(width: CGFloat, inset: CGFloat, span: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // 纵向主导：放弃，让给滚动（编辑页在 ScrollView 里）
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    if dragging {
                        dragging = false
                        position = nil
                    }
                    return
                }
                dragging = true
                position = min(width - inset, max(inset, value.location.x))
                select(nearestTier(x: value.location.x, width: width, inset: inset, span: span), width: width, inset: inset, span: span)
            }
            .onEnded { _ in
                dragging = false
                // 松手：阻尼弹簧吸附到当前档位
                withAnimation(.spring(response: 0.35, dampingFraction: 0.62)) {
                    position = nil   // 回到锚点坐标
                }
            }
    }

    private func nearestTier(x: CGFloat, width: CGFloat, inset: CGFloat, span: CGFloat) -> TaskUrgency {
        let clamped = min(width - inset, max(inset, x))
        let index = Int(round((clamped - inset) / span * CGFloat(tiers.count - 1)))
        return tiers[min(tiers.count - 1, max(0, index))]
    }

    private func select(_ tier: TaskUrgency, width: CGFloat, inset: CGFloat, span: CGFloat) {
        guard tier != selection else { return }
        selection = tier
        hapticSelect.selectionChanged()          // 线性马达轻震（每过一档一次）
        if tier.isGalaxy {
            hapticImpact.impactOccurred()        // 进入 Galaxy：短促震动
        }
    }
}

// MARK: - 动效小件

/// 光晕脉动
private struct PulseMotion: ViewModifier {
    let reduceMotion: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .scaleEffect(on ? 1.12 : 0.92)
                .opacity(on ? 0.9 : 0.55)
                .onAppear {
                    withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                        on = true
                    }
                }
        }
    }
}

/// 旋钮旁持续闪烁的星点
private struct TwinkleMotion: ViewModifier {
    let delay: Double
    let reduceMotion: Bool
    @State private var bright = false

    func body(content: Content) -> some View {
        if reduceMotion {
            content
        } else {
            content
                .opacity(bright ? 1 : 0.3)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true).delay(delay)) {
                        bright = true
                    }
                }
        }
    }
}

/// 进入 Galaxy 的一次性放射粒子（点阵星尘）。burstID 变化时重挂载重放。
private struct SparkleBurst: View {
    let burstID: UUID
    let reduceMotion: Bool

    @State private var fired = false

    /// 预生成的 12 粒：角度（弧度）、距离系数、尺寸
    private static let seeds: [(angle: Double, distance: Double, size: CGFloat)] = (0..<12).map { i in
        let angle = Double(i) / 12 * .pi * 2 + Double(i % 3) * 0.22
        let distance = i % 2 == 0 ? 1.0 : 0.62
        return (angle, distance, CGFloat(3 + i % 3))
    }

    var body: some View {
        ZStack {
            ForEach(Self.seeds.indices, id: \.self) { index in
                let seed = Self.seeds[index]
                Circle()
                    .fill(Theme.text)
                    .frame(width: seed.size, height: seed.size)
                    .scaleEffect(fired ? 1.25 : 0.2)
                    .opacity(fired ? 0 : 0.9)
                    .offset(
                        x: fired ? cos(seed.angle) * 34 * seed.distance : 0,
                        y: fired ? sin(seed.angle) * 30 * seed.distance : 0
                    )
            }
        }
        .allowsHitTesting(false)
        .id(burstID)
        .onAppear {
            guard !reduceMotion else {
                fired = true
                return
            }
            withAnimation(.easeOut(duration: 0.65)) {
                fired = true
            }
        }
    }
}
