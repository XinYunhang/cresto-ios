import SwiftUI
import QuartzCore

/// 紧急程度滑块 —— galaxy-effort-slider 的 100% 纯原生 SwiftUI 复刻。
/// 唯一视觉/运动依据：`materials/leibox/galaxy-effort-slider/复刻提示词.txt`（参数级规格）。
/// 弹簧/褶皱生长/色板/像素/射线公式逐条照抄；SwiftUI 全部自写，零 Web 代码。
/// 材料原件只存本地 Obsidian（materials/leibox/），不进公开仓库（LeiBox 未声明开源许可）。
///
/// 引擎：CADisplayLink 手动积分——主弹簧 k=420/c=32 每帧 3 子步（dt≤0.032），
/// 快速反向只换目标保留位置与速度；Galaxy 独立第二弹簧 k=190/c=25；
/// 停稳即停帧；后台/离屏暂停不补时间；reduce motion 直接吸附目标。
///
/// 渲染（Canvas 全量）：
/// · 轨道渐变：四组色板 ×5 色标随**连续 position** 逐通道插值（Low 左端恒 #312a2d 暗灰紫）
/// · 五层脑回褶皱跟随连续位置连续生长（u²(3-2u)），回拉同公式反向收回，节点身份不变
/// · Galaxy：像素轨道（49×5 hash 点阵）+ 射线粒子（26×7 黄金角 2.399963）+ 双光晕 + 震动
/// · 档位标题逐字入场（220ms/错峰 15ms/blur 4→0/y 5→0）
struct UrgencySlider: View {
    @Binding var selection: TaskUrgency
    /// 紧凑模式（新建待办快捷页）：不带标题行
    var compact = false

    @StateObject private var engine = UrgencyEngine()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dragging = false
    @State private var dragStartTarget: Double = 0
    @State private var lastHapticTier: TaskUrgency?

    private let hapticSelect = UISelectionFeedbackGenerator()
    private let hapticImpact = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !compact {
                HStack(alignment: .firstTextBaseline) {
                    Text("紧急程度").cardLabel()
                    Spacer()
                    TierTitle(tier: engine.nearestTier, reduceMotion: reduceMotion)
                }
            }

            stage
        }
        .onAppear {
            engine.snap(to: Double(selection.rawValue))
            if scenePhase == .active { engine.resume() }
        }
        .onChange(of: scenePhase) { _, phase in
            // 后台/离屏暂停不补时间；恢复从原状态继续
            if phase == .active { engine.resume() } else { engine.pause() }
        }
        .onDisappear { engine.pause() }
        .onChange(of: reduceMotion) { _, reduced in
            if reduced { engine.snapToTargets() }
        }
    }

    // MARK: 手势（iOS 适配：纵向让给滚动；纵向接管 = 取消，回退按下时档位）

    private func dragGesture(trackWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else {
                    if dragging {
                        dragging = false
                        engine.setTarget(dragStartTarget)
                        selection = TaskUrgency(rawValue: Int(dragStartTarget.rounded())) ?? selection
                    }
                    return
                }
                if !dragging {
                    dragging = true
                    dragStartTarget = Double(selection.rawValue)
                }
                engine.setTarget(SliderGeometry.value(atX: value.location.x, trackWidth: trackWidth))
                updateVisualTier()
            }
            .onEnded { _ in
                dragging = false
                let snapped = max(0, min(5, engine.target.rounded()))
                engine.setTarget(snapped)
                commit(tier: TaskUrgency(rawValue: Int(snapped)) ?? .low)
            }
    }

    /// 拖动中按最近档更新视觉标签与轻震（不写绑定——中间值只更新视觉，松手提交）
    private func updateVisualTier() {
        let tier = engine.nearestTier
        guard tier != lastHapticTier else { return }
        lastHapticTier = tier
        hapticSelect.selectionChanged()
        if tier.isGalaxy { hapticImpact.impactOccurred() }
    }

    /// 提交档位（松手吸附/轻点/无障碍调节）
    private func commit(tier: TaskUrgency) {
        lastHapticTier = tier
        if tier != selection { selection = tier }
        if tier.isGalaxy { hapticImpact.impactOccurred() }
    }

    // MARK: 舞台

    private var stage: some View {
        GeometryReader { geo in
            let s = min(geo.size.width / 392, 0.889)   // 等比换算：规格轨道宽 392，上限防大屏拉伸
            let trackH = 40 * s
            let padV = 16 * s
            let fieldH = 72 * s
            let trackRect = CGRect(x: 0, y: padV, width: geo.size.width, height: trackH)
            let brainX = SliderGeometry.brainX(position: engine.position, scale: s)
            let shakeX = reduceMotion ? 0 : Shake.x(g: engine.galaxy, age: engine.age, clock: engine.clock)
            let shakeY = reduceMotion ? 0 : Shake.y(g: engine.galaxy, age: engine.age, clock: engine.clock)

            ZStack {
                // 场底（规格卡片底 #191919、描边 #292929）
                RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                    .fill(Color(hex: 0x191919))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.item, style: .continuous)
                            .strokeBorder(Color(hex: 0x292929), lineWidth: 1)
                    )

                // 主 Canvas：轨道底色/渐变填充/刻度/像素层(裁切)/脑形+褶皱+光晕
                MainSliderCanvas(engine: engine, scale: s, trackRect: trackRect, reduceMotion: reduceMotion)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.item - 2, style: .continuous))

                // 射线粒子（不裁切在轨道内，随脑形中心；溢出由外层卡片裁切）
                RayParticlesCanvas(engine: engine, scale: s, reduceMotion: reduceMotion)
                    .frame(width: geo.size.width + 240 * s, height: fieldH + 240 * s)
                    .position(x: brainX, y: fieldH / 2)
                    .allowsHitTesting(false)
            }
            .frame(width: geo.size.width, height: fieldH, alignment: .center)
            .frame(maxHeight: .infinity, alignment: .center)
            .offset(x: shakeX, y: shakeY)
            .contentShape(Rectangle())
            .onTapGesture { location in
                let value = SliderGeometry.value(atX: location.x, trackWidth: geo.size.width)
                engine.setTarget(value)
                commit(tier: TaskUrgency(rawValue: Int(value.rounded())) ?? .low)
            }
            .gesture(dragGesture(trackWidth: geo.size.width))
            .accessibilityElement()
            .accessibilityLabel("紧急程度")
            .accessibilityValue(engine.nearestTier.title)
            .accessibilityAdjustableAction { direction in
                let next = max(0, min(5, engine.nearestTier.rawValue + (direction == .increment ? 1 : -1)))
                engine.setTarget(Double(next))
                commit(tier: TaskUrgency(rawValue: next) ?? .low)
            }
        }
        .frame(height: 64)
    }
}

// MARK: - 主 Canvas（轨道 / 渐变 / 刻度 / 像素层 / 脑形）

private struct MainSliderCanvas: View {
    @ObservedObject var engine: UrgencyEngine
    let scale: CGFloat
    let trackRect: CGRect
    let reduceMotion: Bool

    var body: some View {
        Canvas { ctx, size in
            let clock = reduceMotion ? 0 : engine.clock
            let position = engine.position
            let g = min(1, max(0, engine.galaxy))
            let age = engine.age
            let s = scale

            // 1. 轨道底色 #272727（圆角 10）
            let trackPath = Path(roundedRect: trackRect, cornerRadius: 10 * s)
            ctx.fill(trackPath, with: .color(Color(hex: 0x272727)))

            // 2. 普通渐变填充：宽 16+position/5×358，色板随连续位置插值，透明度 1-g
            let fillWidth = (16 + SliderGeometry.positionFraction(position) * 358) * s
            let fillRect = CGRect(x: 0, y: trackRect.minY, width: min(trackRect.width, fillWidth), height: trackRect.height)
            var fillCtx = ctx
            fillCtx.opacity = 1 - g
            fillCtx.fill(
                Path(roundedRect: fillRect, cornerRadius: 10 * s),
                with: .linearGradient(
                    Gradient(stops: SliderPalette.gradientStops(position: position)),
                    startPoint: CGPoint(x: fillRect.minX, y: 0),
                    endPoint: CGPoint(x: fillRect.maxX, y: 0)
                )
            )

            // 3. 六个刻度（第二档为长刻度），像素层下方绘制
            for i in 0..<6 {
                let x = SliderGeometry.tickX(index: i, scale: s)
                let isLong = i == 1
                let tickColor = Color.white.opacity(isLong ? 0.27 : 0.20)
                let tickRect = isLong
                    ? CGRect(x: x - 3 * s, y: trackRect.midY - 10 * s, width: 6 * s, height: 20 * s)
                    : CGRect(x: x - 3 * s, y: trackRect.midY - 3 * s, width: 6 * s, height: 6 * s)
                ctx.fill(Path(roundedRect: tickRect, cornerRadius: 3 * s), with: .color(tickColor))
            }

            // 4. Galaxy 像素层（裁切在轨道内，透明度随 g 淡入淡出）
            if g > 0.004 {
                var pixelCtx = ctx
                pixelCtx.clip(to: trackPath)
                pixelCtx.opacity = g
                PixelTrack.draw(into: &pixelCtx, trackRect: trackRect, scale: s, clock: clock)
            }

            // 5. 脑形：缩放 1+.25g+.2burst、双光晕、主沟 + 五层褶皱连续生长
            let brainCenter = CGPoint(
                x: SliderGeometry.brainX(position: position, scale: s),
                y: trackRect.midY
            )
            Brain.draw(
                into: &ctx,
                center: brainCenter,
                size: 48 * s,
                position: position,
                g: g,
                burst: GalaxyMath.burst(g: g, age: age),
                reduceMotion: reduceMotion
            )
        }
    }
}

// MARK: - 射线粒子 Canvas（溢出场外，由外层卡片裁切）

private struct RayParticlesCanvas: View {
    @ObservedObject var engine: UrgencyEngine
    let scale: CGFloat
    let reduceMotion: Bool

    var body: some View {
        Canvas { ctx, size in
            let g = min(1, max(0, engine.galaxy))
            guard g > 0.004 else { return }
            let clock = reduceMotion ? 0 : engine.clock
            let age = engine.age
            let center = CGPoint(x: size.width / 2, y: size.height / 2)

            for ray in 0..<26 {
                let angle = Double(ray) * 2.399963               // 黄金角
                let seed = GalaxyMath.hash(Double(ray) + 94)
                let speed = 15 + 24 * seed
                for dot in 0..<7 {
                    let base = (Double(dot) * 13 + clock * speed + seed * 40)
                        .truncatingRemainder(dividingBy: 87)
                    let radius = (27 + base) * scale + exp(-age * 5) * Double(dot) * 3 * scale
                    let fade = pow(1 - min(1, max(0, (radius / scale - 27) / 110)), 1.6)
                    let pulse = reduceMotion ? 0.6 : 0.45 + 0.55 * pow(sin(clock * 4 + Double(ray) + Double(dot)), 2)
                    let alpha = g * fade * pulse * (0.4 + 0.35 * exp(-age * 5))
                    guard alpha > 0.01 else { continue }
                    let side = (seed > 0.65 ? 3 : 2) * scale
                    let point = CGPoint(
                        x: center.x + cos(angle) * radius,
                        y: center.y + sin(angle) * radius
                    )
                    let rect = CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(SliderPalette.dotColor((ray + dot) % 6).opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 几何 / 数学（提示词公式照抄）

enum SliderGeometry {
    /// 轨道内坐标：刻度 x = 16 + i×71.6（358/5），脑形中心同公式
    static func tickX(index: Int, scale: CGFloat) -> CGFloat {
        (16 + Double(index) * 71.6) * scale
    }

    static func positionFraction(_ position: Double) -> Double {
        min(5, max(0, position)) / 5
    }

    static func brainX(position: Double, scale: CGFloat) -> CGFloat {
        (16 + positionFraction(position) * 358) * scale
    }

    /// 拖动换算：value = clamp((指针在轨道内的 x−16)/358×5, 0, 5)
    static func value(atX x: CGFloat, trackWidth: CGFloat) -> Double {
        guard trackWidth > 0 else { return 0 }
        let s = trackWidth / 392
        let local = Double(x) / s
        return min(5, max(0, (local - 16) / 358 * 5))
    }
}

enum GalaxyMath {
    /// 确定性 hash：fract(sin(n×127.1+311.7)×43758.5453)
    static func hash(_ n: Double) -> Double {
        let value = sin(n * 127.1 + 311.7) * 43758.5453
        return value - value.rounded(.down)
    }

    /// 进入 Galaxy 的爆发量：burst = exp(-age×6)×g
    static func burst(g: Double, age: Double) -> Double {
        exp(-age * 6) * g
    }
}

enum Shake {
    static func amplitude(g: Double, age: Double) -> Double {
        g * (0.28 + exp(-age * 7) * 2.1)
    }

    static func x(g: Double, age: Double, clock: Double) -> CGFloat {
        sin(clock * 93) * amplitude(g: g, age: age)
    }

    static func y(g: Double, age: Double, clock: Double) -> CGFloat {
        cos(clock * 117) * amplitude(g: g, age: age) * 0.65
    }
}

// MARK: - 色板（四组 ×5 色标，随连续位置逐通道插值）

enum SliderPalette {
    /// 依次对应 Medium、High、Extra、Max；色标位置 0%/30%/60%/90%/100%
    private static let palettes: [[[Double]]] = [
        [[49, 42, 45], [86, 57, 76], [125, 73, 112], [161, 89, 146], [175, 94, 157]],
        [[49, 42, 45], [81, 55, 76], [112, 69, 107], [143, 83, 139], [153, 87, 150]],
        [[49, 42, 45], [78, 56, 74], [108, 69, 110], [129, 84, 149], [136, 90, 163]],
        [[49, 42, 45], [77, 56, 74], [102, 67, 111], [118, 84, 153], [124, 90, 167]],
    ]
    private static let stopLocations: [Double] = [0, 0.30, 0.60, 0.90, 1.0]
    /// Galaxy 像素/粒子色板
    private static let dotPalette: [Color] = [
        Color(hex: 0x80D5D8), Color(hex: 0xDC8CD5), Color(hex: 0xB3A3E8),
        Color(hex: 0x7061B5), Color(hex: 0xF4C1EB), Color(hex: 0x6656A0),
    ]

    static func dotColor(_ index: Int) -> Color {
        dotPalette[index % dotPalette.count]
    }

    /// t=clamp(position-1,0,3)；index=min(2,floor(t))；blend=t-index；逐通道 round 插值
    static func gradientStops(position: Double) -> [Gradient.Stop] {
        let t = min(3, max(0, position - 1))
        let index = min(2, Int(t.rounded(.down)))
        let blend = t - Double(index)
        let low = palettes[index]
        let high = palettes[index + 1]

        var stops: [Gradient.Stop] = []
        for (i, location) in stopLocations.enumerated() {
            var rgb: [Double] = []
            for channel in 0..<3 {
                let value = low[i][channel] + (high[i][channel] - low[i][channel]) * blend
                rgb.append(value.rounded())
            }
            stops.append(.init(
                color: Color(red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255),
                location: location
            ))
        }
        return stops
    }
}

// MARK: - Galaxy 像素轨道（49 列 ×5 行 hash 点阵）

enum PixelTrack {
    static func draw(into ctx: inout GraphicsContext, trackRect: CGRect, scale: CGFloat, clock: Double) {
        // 底色 linear-gradient(90deg,#10091d,#25123f)
        ctx.fill(
            Path(roundedRect: trackRect, cornerRadius: 10 * scale),
            with: .linearGradient(
                Gradient(colors: [Color(hex: 0x10091D), Color(hex: 0x25123F)]),
                startPoint: CGPoint(x: trackRect.minX, y: 0),
                endPoint: CGPoint(x: trackRect.maxX, y: 0)
            )
        )

        let cell = 8 * scale
        let cols = 49
        for col in 0..<cols {
            for row in 0..<5 {
                let n = Double(row * cols + col)
                let seed = GalaxyMath.hash(n + 7)
                let wave = 0.5 + 0.5 * sin(clock * (2 + 3 * seed) + n * 1.618)
                let density = 0.14 + 0.78 * pow(Double(col) / 48, 1.6)
                if seed > density + 0.16 * sin(clock * 1.8 + Double(col) * 0.2) { continue }
                let alpha = (0.18 + 0.72 * wave) * (0.22 + 0.78 * Double(col) / 48)
                let color = SliderPalette.dotColor(Int(GalaxyMath.hash(n + 211) * 6))
                let side = (seed > 0.74 ? 5.7 : 5.1) * scale
                let rect = CGRect(
                    x: trackRect.minX + CGFloat(col) * cell + 1 * scale,
                    y: trackRect.minY + CGFloat(row) * cell + 0.5 * scale,
                    width: side,
                    height: side
                )
                ctx.fill(Path(roundedRect: rect, cornerRadius: 1.3 * scale), with: .color(color.opacity(alpha)))
            }
        }
    }
}

// MARK: - 脑形（轮廓 + 主沟 + 五层褶皱，左右半球镜像）

enum Brain {
    /// 规格给出的左半球轮廓（viewBox 64）
    static let outlinePath = "M30 14C30 5 20 4 16 12C9 11 5 20 9 26C2 30 3 39 10 43C6 50 11 59 19 57C24 63 30 58 30 52Z"
    /// 主沟（宽 4.2，常显）
    static let mainFoldPath = "M30 27Q28 35 22 35M10 43Q15 44 17 48M16 12Q13 17 16 20"
    /// 五层递增褶皱：线宽 2.8→1.9，左右半球各实例化一次
    static let foldLayers: [(level: Int, width: Double, paths: [String])] = [
        (1, 2.8, ["M29 25Q28 21 24 21C20 21 18 17 21 14"]),
        (2, 2.6, ["M28 42C23 39 19 41 20 45Q21 48 25 47"]),
        (3, 2.5, ["M12 28C15 25 19 26 20 29Q21 33 17 34"]),
        (4, 2.2, ["M21 21Q18 19 15 22", "M20 53Q24 55 27 51"]),
        (5, 1.9, ["M10 36Q13 34 16 37", "M24 35Q27 37 25 40"]),
    ]

    /// 五层褶皱的采样折线（每条 path 一个子路径；预解析缓存，渲染热路径不再解析）
    static let foldPolylines: [[[CGPoint]]] = foldLayers.map { layer in
        layer.paths.map { BrainPathParser.sampledPolyline($0) }
    }

    /// 褶皱生长：u=clamp((p-tier+.85)/.7,0,1)，reveal=u²(3-2u)，跟随连续位置
    static func reveal(position: Double, tier: Int) -> Double {
        let p = min(5, max(0, position))
        let u = min(1, max(0, (p - Double(tier) + 0.85) / 0.7))
        return u * u * (3 - 2 * u)
    }

    /// Galaxy 变形：填充 rgb(255-85g,146+4g,206+39g)，轮廓 rgb(101-45g,14+2g,60+77g)
    static func fill(g: Double) -> Color {
        Color(red: (255 - 85 * g) / 255, green: (146 + 4 * g) / 255, blue: (206 + 39 * g) / 255)
    }

    static func stroke(g: Double) -> Color {
        Color(red: (101 - 45 * g) / 255, green: (14 + 2 * g) / 255, blue: (60 + 77 * g) / 255)
    }

    static func draw(
        into ctx: inout GraphicsContext,
        center: CGPoint,
        size: CGFloat,
        position: Double,
        g: Double,
        burst: Double,
        reduceMotion: Bool
    ) {
        let scale = size / 64
        let grow = 1 + 0.25 * g + 0.2 * burst

        let outline = PathSVG.path(outlinePath)
        let mainFold = PathSVG.path(mainFoldPath)

        // 双光晕（规格：两层 drop-shadow 半径 4+10burst / 9+15burst，#8351ff / #7543fc70）
        if g > 0.004 && !reduceMotion {
            for shadow in [(4.0 + 10 * burst, Color(hex: 0x8351FF)), (9.0 + 15 * burst, Color(hex: 0x7543FC).opacity(0.44))] {
                var glowCtx = ctx
                glowCtx.addFilter(.blur(radius: shadow.0 * scale))
                glowCtx.opacity = g
                drawMirrored(into: &glowCtx, center: center, scale: scale, grow: grow) { half in
                    half.fill(outline, with: .color(shadow.1))
                }
            }
        }

        drawMirrored(into: &ctx, center: center, scale: scale, grow: grow) { half in
            // 轮廓：填充 + 深酒红描边（宽 5）
            half.fill(outline, with: .color(fill(g: g)))
            half.stroke(outline, with: .color(stroke(g: g)), lineWidth: 5 * scale)

            // 主沟（常显，宽 4.2）
            half.stroke(
                mainFold,
                with: .color(stroke(g: g)),
                style: StrokeStyle(lineWidth: 4.2 * scale, lineCap: .round, lineJoin: .round)
            )

            // 五层褶皱：沿路径连续生长（采样折线按弧长截取，等价于规格的 dashoffset 揭示）+ 渐显
            for (index, layer) in foldLayers.enumerated() {
                let reveal = reduceMotion
                    ? (position >= Double(layer.level) - 0.15 ? 1 : 0)
                    : reveal(position: position, tier: layer.level)
                guard reveal > 0.01 else { continue }
                for points in foldPolylines[index] {
                    let trimmed = partialPolyline(points, fraction: reveal)
                    half.opacity = reveal
                    half.stroke(
                        trimmed,
                        with: .color(stroke(g: g)),
                        style: StrokeStyle(lineWidth: layer.width * scale, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
    }

    /// 折线按弧长截取前 fraction 段（等价 SVG dashoffset 沿路径揭示）
    static func partialPolyline(_ points: [CGPoint], fraction: Double) -> Path {
        guard let first = points.first else { return Path() }
        guard fraction < 0.999, points.count > 1 else {
            var full = Path()
            full.move(to: first)
            for point in points.dropFirst() { full.addLine(to: point) }
            return full
        }
        var lengths: [Double] = [0]
        var total: Double = 0
        for i in 1..<points.count {
            let dx = Double(points[i].x - points[i - 1].x)
            let dy = Double(points[i].y - points[i - 1].y)
            total += (dx * dx + dy * dy).squareRoot()
            lengths.append(total)
        }
        let targetLength = total * min(1, max(0, fraction))
        var path = Path()
        path.move(to: first)
        for i in 1..<points.count {
            if lengths[i] <= targetLength {
                path.addLine(to: points[i])
            } else {
                let segLen = lengths[i] - lengths[i - 1]
                let t = segLen > 0 ? (targetLength - lengths[i - 1]) / segLen : 0
                let p0 = points[i - 1], p1 = points[i]
                path.addLine(to: CGPoint(x: p0.x + (p1.x - p0.x) * t, y: p0.y + (p1.y - p0.y) * t))
                break
            }
        }
        return path
    }

    /// 左右半球：右半球 = translate(64,0) scale(-1,1)
    private static func drawMirrored(
        into ctx: inout GraphicsContext,
        center: CGPoint,
        scale: CGFloat,
        grow: Double,
        renderer: (inout GraphicsContext) -> Void
    ) {
        for mirror in [false, true] {
            var half = ctx
            half.translateBy(x: center.x, y: center.y)
            half.scaleBy(x: grow, y: grow)
            if mirror { half.scaleBy(x: -1, y: 1) }
            half.translateBy(x: -32 * scale, y: -32 * scale)
            renderer(&half)
        }
    }
}

/// 迷你 SVG path 采样器（规格用到的绝对指令 M/C/Q/L）→ 采样折线点列
enum BrainPathParser {
    /// 单子路径 path 字符串 → 均匀采样折线
    static func sampledPolyline(_ d: String) -> [CGPoint] {
        let chars = Array(d)
        var i = 0
        var points: [CGPoint] = []
        var current = CGPoint.zero

        func isSkip(_ c: Character) -> Bool { c == " " || c == "," }
        func number() -> Double? {
            while i < chars.count, isSkip(chars[i]) { i += 1 }
            guard i < chars.count, chars[i].isNumber || chars[i] == "-" || chars[i] == "." else { return nil }
            var token = ""
            while i < chars.count, chars[i].isNumber || chars[i] == "-" || chars[i] == "." {
                token.append(chars[i])
                i += 1
            }
            return Double(token)
        }
        func sampleQuad(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint) {
            for step in 1...24 {
                let t = Double(step) / 24
                let mt = 1 - t
                points.append(CGPoint(
                    x: mt * mt * p0.x + 2 * mt * t * c.x + t * t * p1.x,
                    y: mt * mt * p0.y + 2 * mt * t * c.y + t * t * p1.y
                ))
            }
        }
        func sampleCubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p1: CGPoint) {
            for step in 1...24 {
                let t = Double(step) / 24
                let mt = 1 - t
                points.append(CGPoint(
                    x: mt * mt * mt * p0.x + 3 * mt * mt * t * c1.x + 3 * mt * t * t * c2.x + t * t * t * p1.x,
                    y: mt * mt * mt * p0.y + 3 * mt * mt * t * c1.y + 3 * mt * t * t * c2.y + t * t * t * p1.y
                ))
            }
        }

        while i < chars.count {
            let raw = chars[i]
            i += 1
            switch raw {
            case "M":
                guard let x = number(), let y = number() else { continue }
                current = CGPoint(x: x, y: y)
                points.append(current)
            case "L":
                guard let x = number(), let y = number() else { continue }
                current = CGPoint(x: x, y: y)
                points.append(current)
            case "Q":
                guard let cx = number(), let cy = number(), let x = number(), let y = number() else { continue }
                let from = current
                current = CGPoint(x: x, y: y)
                sampleQuad(from, CGPoint(x: cx, y: cy), current)
            case "C":
                guard let c1x = number(), let c1y = number(), let c2x = number(), let c2y = number(),
                      let x = number(), let y = number() else { continue }
                let from = current
                current = CGPoint(x: x, y: y)
                sampleCubic(from, CGPoint(x: c1x, y: c1y), CGPoint(x: c2x, y: c2y), current)
            case "Z":
                continue
            default:
                continue
            }
        }
        return points
    }
}

// MARK: - 迷你 SVG path 解析（仅规格用到的绝对指令 M/C/Q/L/Z）

enum PathSVG {
    static func path(_ d: String) -> Path {
        var path = Path()
        var current = CGPoint.zero
        let chars = Array(d)
        var i = 0

        func isSkip(_ c: Character) -> Bool { c == " " || c == "," }

        func number() -> Double? {
            while i < chars.count, isSkip(chars[i]) { i += 1 }
            guard i < chars.count, chars[i].isNumber || chars[i] == "-" || chars[i] == "." else { return nil }
            var token = ""
            while i < chars.count, chars[i].isNumber || chars[i] == "-" || chars[i] == "." {
                token.append(chars[i])
                i += 1
            }
            return Double(token)
        }

        while i < chars.count {
            let raw = chars[i]
            i += 1
            switch raw {
            case "M":
                guard let x = number(), let y = number() else { continue }
                current = CGPoint(x: x, y: y)
                path.move(to: current)
            case "L":
                guard let x = number(), let y = number() else { continue }
                current = CGPoint(x: x, y: y)
                path.addLine(to: current)
            case "Q":
                guard let cx = number(), let cy = number(), let x = number(), let y = number() else { continue }
                path.addQuadCurve(to: CGPoint(x: x, y: y), control: CGPoint(x: cx, y: cy))
                current = CGPoint(x: x, y: y)
            case "C":
                guard let c1x = number(), let c1y = number(), let c2x = number(), let c2y = number(),
                      let x = number(), let y = number() else { continue }
                path.addCurve(to: CGPoint(x: x, y: y), control1: CGPoint(x: c1x, y: c1y), control2: CGPoint(x: c2x, y: c2y))
                current = CGPoint(x: x, y: y)
            case "Z":
                path.closeSubpath()
            default:
                continue
            }
        }
        return path
    }
}

// MARK: - 引擎（CADisplayLink 手动积分；k420/c32 三子步 + Galaxy k190/c25）

@MainActor
final class UrgencyEngine: ObservableObject {
    @Published private(set) var position: Double = 0
    @Published private(set) var galaxy: Double = 0
    @Published private(set) var clock: Double = 0
    @Published private(set) var enteredClock: Double = 0
    @Published private(set) var target: Double = 0
    @Published private(set) var galaxyTarget: Double = 0

    private var velocity: Double = 0
    private var galaxyVelocity: Double = 0
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0

    /// 档位标签按最近档切换
    var nearestTier: TaskUrgency {
        TaskUrgency(rawValue: Int(target.rounded())) ?? .low
    }

    var age: Double {
        max(0, clock - enteredClock)
    }

    func setTarget(_ value: Double) {
        let clamped = max(0, min(5, value))
        target = clamped
        let next: Double = Int(clamped.rounded()) == 5 ? 1 : 0
        if next == 1 && galaxyTarget == 0 {
            enteredClock = clock
        }
        galaxyTarget = next
        resume()
    }

    /// reduce motion：立即吸附目标，保留静态像素与全部交互
    func snapToTargets() {
        position = target
        velocity = 0
        galaxy = galaxyTarget
        galaxyVelocity = 0
        pause()
    }

    /// 按给定档位立即吸附（进入页面时对齐绑定初值；不触发 Galaxy 时钟）
    func snap(to value: Double) {
        target = max(0, min(5, value))
        galaxyTarget = Int(target.rounded()) == 5 ? 1 : 0
        position = target
        velocity = 0
        galaxy = galaxyTarget
        galaxyVelocity = 0
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

        // 每帧拆 3 子步：v += ((target-position)×k − v×c)×dt/3；position += v×dt/3
        let sub = dt / 3
        for _ in 0..<3 {
            velocity += ((target - position) * 420 - velocity * 32) * sub
            position += velocity * sub
            galaxyVelocity += ((galaxyTarget - galaxy) * 190 - galaxyVelocity * 25) * sub
            galaxy += galaxyVelocity * sub
        }

        // 误差 <.0002 且速度 <.002 时吸附
        if abs(target - position) < 0.0002 && abs(velocity) < 0.002 {
            position = target
            velocity = 0
        }
        if abs(galaxyTarget - galaxy) < 0.0002 && abs(galaxyVelocity) < 0.002 {
            galaxy = galaxyTarget
            galaxyVelocity = 0
        }

        // 非 Galaxy 停稳后无帧循环（功耗）；Galaxy 需要持续绘制
        if galaxyTarget == 0 &&
            abs(target - position) < 0.0002 && abs(velocity) < 0.002 &&
            abs(galaxy) < 0.0002 && abs(galaxyVelocity) < 0.002 {
            position = target
            galaxy = galaxyTarget
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

// MARK: - 档位标题（逐字入场：220ms、错峰 15ms、blur 4→0、y 5→0）

private struct TierTitle: View {
    let tier: TaskUrgency
    let reduceMotion: Bool

    var body: some View {
        HStack(spacing: 1) {
            ForEach(Array(tier.title.enumerated()), id: \.offset) { index, char in
                Text(String(char))
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(tier.isGalaxy ? Color(hex: 0x9DCEF3) : Theme.text)
                    .modifier(CharEnter(delay: Double(index) * 0.015, reduceMotion: reduceMotion))
            }
        }
        .id(tier) // 档位变化重挂载，快速改档取消旧文字动画
    }
}

private struct CharEnter: ViewModifier {
    let delay: Double
    let reduceMotion: Bool
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown ? 0 : 4)
            .offset(y: shown ? 0 : 5)
            .onAppear {
                guard !reduceMotion else {
                    shown = true
                    return
                }
                withAnimation(.timingCurve(0.2, 0.7, 0.2, 1, duration: 0.22).delay(delay)) {
                    shown = true
                }
            }
    }
}
