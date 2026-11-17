import SwiftUI
import SwiftData
import UIKit
import AVFoundation

private var sfx: HoloSfx? { HoloSfx.shared }

/// 塔罗 Tab · holo-reverse 原生 1:1 移植（SwiftUI 版）。
/// 源基准：holo-reverse/index.html + src/app.js + src/styles.css + src/tarot-data.js（塔罗化改编版）。
/// 全部机制与参数一一对应：撕包（96 段撕裂线/12 片撕条/方向锁/回弹阈值）、彩虹光流（35 条彩带/行波/白热根部/光尘）、
/// 开包（卡包坠落/彩带爆发/三张牌上抛→环绕→扇形）、牌面（羊皮纸牌框/香槟金铭牌/RWS 插槽/正逆位/全息三层）、
/// 触感与合成音效（撕箔噪声loop/玻璃钟琴/五声音阶）。
struct TarotView: View {
    @Environment(\.modelContext) private var context
    @StateObject private var engine = TarotEngine()
    @State private var detail: CardDetail?
    @AppStorage("tarot-muted") private var muted = false

    struct CardDetail: Identifiable {
        let id: Int
        let card: TarotCard
        let reversed: Bool
        let slot: Int
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.bg.ignoresSafeArea()
                TimelineView(.animation) { timeline in
                    let safeBottom = proxy.safeAreaInsets.bottom
                    let _ = engine.tick(until: timeline.date, size: proxy.size,
                                        safeBottom: safeBottom, context: context)
                    StageView(engine: engine, size: proxy.size, onCardTapped: { card, reversed, slot in
                        detail = CardDetail(id: card.id, card: card, reversed: reversed, slot: slot)
                    })
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .ignoresSafeArea()
                .simultaneousGesture(stageDrag)
                .onTapGesture { engine.press() }
            }
            .sheet(item: $detail) { d in
                TarotReadingSheet(card: d.card, isReversed: d.reversed)
            }
            .onAppear {
                engine.prepare(context: context)
                sfx?.muted = muted
            }
            .onChange(of: muted) { _, m in
                sfx?.muted = m
                UserDefaults.standard.set(m, forKey: "tarot-muted")
                if !m { sfx?.tick() }
            }
        }
    }

    /// 舞台拖动：驱动撕包与指针（悬停/倾斜）
    private var stageDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                sfx?.unlock()
                engine.pointerMoved(to: value.location, in: UIScreen.main.bounds.size)
                engine.dragMoved(value.translation, time: value.time)
            }
            .onEnded { value in
                engine.dragEnded(value.translation, time: value.time)
            }
    }
}

// MARK: - 弹簧（与 holo-reverse/src/app.js 的 Spring 一致，response/bounce → SwiftUI spring 参数）

final class HoloSpring {
    var x: Double
    var to: Double
    var v: Double = 0
    var k: Double = 0
    var c: Double = 0

    init(_ x: Double, _ response: Double = 0.5, _ bounce: Double = 0) {
        self.x = x
        self.to = x
        set(response, bounce)
    }

    @discardableResult
    func set(_ response: Double, _ bounce: Double = 0) -> HoloSpring {
        k = (2 * .pi / response) * (2 * .pi / response)
        c = 4 * .pi * (1 - bounce) / response
        return self
    }

    func step(_ h: Double) {
        v += (k * (to - x) - c * v) * h
        x += v * h
    }

    func reset(_ value: Double) { x = value; to = value; v = 0 }
}

// MARK: - 牌包配色（深空色系，名称印在包身，不连续重复）

let HoloSkins: [(name: String, color: Color)] = [
    ("夜幕", Color(hex: 0x1C2240)),
    ("深空", Color(hex: 0x20294F)),
    ("紫穹", Color(hex: 0x372A63)),
    ("松烟", Color(hex: 0x123F3D)),
    ("绛夜", Color(hex: 0x461F36)),
    ("雾蓝", Color(hex: 0x2A3D55))
]

let HoloBands = ["#ff3d6e", "#ff8a3d", "#ffd34d", "#4fd9a0", "#4fb2ff", "#8b6cff", "#ff5cc8"]

// MARK: - 引擎（frame loop 的完整移植）

final class TarotEngine: ObservableObject {
    // ---- 常量（与 src/app.js 一致）----
    static let tearBase: Double = 10.5
    static let jagCount = 96
    static let plyCount = 8            // handheld: 8 片
    static let yMin: Double = 8
    static let yMax: Double = 19.5
    static let orbitDur: Double = 1.25
    static let drawCount = 3

    // ---- 状态 ----
    enum Phase { case enter, idle, open, spread }
    var state: Phase = .enter
    var reduce = UIAccessibility.isReduceMotionEnabled
    var t: Double = 0
    var last: Date?
    var openedAt: Double = 0
    var nudgeAt: Double = 5
    var settleAt: Double = 0
    var PW: Double = 0
    var PH: Double = 0
    var padShift: Double = 0
    var skinIndex = -1
    var context: ModelContext?

    // ---- 撕裂 ----
    var jag: [[Double]] = []           // [x, y, line, tooth, metal, bend]
    var tearRoll: Double = 1
    var tearDir = 1
    let tearP = HoloSpring(0, 0.1)
    let tearTh = HoloSpring(0, 0.28, 0.35)
    let tearPh = HoloSpring(0, 0.3, 0.2)
    var tearLast: Double = 0
    var tearVX: Double = 0
    let squeeze = HoloSpring(0, 0.3, 0.45)
    let glow = HoloSpring(0, 0.5)
    var held = false
    var hurt = false
    var tugged = false
    var hitDisabled = false
    var drag: (x0: Double, y0: Double, p0: Double, moved: Bool, dy: Double, lx: Double, lt: Double, k: Double)?
    var wasDrag = false

    // ---- 包体姿态 ----
    let px = HoloSpring(0, 0.7, 0.28)
    let py = HoloSpring(0, 0.7, 0.28)
    let prx = HoloSpring(0, 0.7, 0.28)
    let pry = HoloSpring(0, 0.7, 0.28)
    let prz = HoloSpring(0, 0.7, 0.28)
    var fly: (x: Double, y: Double, vx: Double, vy: Double, th: Double, vth: Double, ph: Double, vph: Double)?
    var fall: (y: Double, v: Double)?
    var anchor = (y: Double(0), rz: Double(0), rx: Double(0), ry: Double(0), sq: Double(0))

    // ---- 光流 ----
    struct Ribbon {
        var mx: Double, gx: Double, r: Double
        var on = false
        var c: String
        var len: Double = 0
        let g: HoloSpring
    }
    var ribbons: [Ribbon] = []
    var ribbonLines: [(ox: Double, x: Double, ux: Double, uy: Double, ph: Double, r: Double)] = []
    var flowY0: Double = 62.5
    var flowR0: Double = 45
    var flowReach: Double = 0
    var flowDrained = false
    var flowColorShift = 0
    var motes: (u: [Double], j: [Int], v: [Double], sp: [Double], r: [Double]) = ([], [], [], [], [])

    // ---- 彩带纸屑 ----
    struct Bit {
        var kind: Int
        var fill: String
        var lx: Double = 0, ly: Double = 0, lz: Double = 0
        var inside = true
        var up: Double = 0, a: Double = 0, sp: Double = 0
        var r: Double = 0, spin: Double = 0, rot0: Double = 0
        var c: Double = 0, slip: Double = 0, glide: Double = 0, sc: Double = 1
        var ph: Double = 0
        var age: Double = 0
        var x: Double = 0, y: Double = 0, z: Double = 0
        var vx: Double = 0, vy: Double = 0, vz: Double = 0
    }
    var bits: [Bit] = []
    var bitsLoaded = false

    // ---- 卡牌 ----
    struct Card {
        var d: TarotCard
        var reversed: Bool
        var i: Int
        var slot: Int
        var phase: Phase2 = .in
        var hover = false
        var glad = false
        var hx: Double = 0.5, hy: Double = 0.5
        var from: Double = 0
        var x0: Double = 0, y0: Double = 0, vy0: Double = 0, rz0: Double = 0
        var even: Double = 0, end: Double = 0
        var landAt: Double = 0
        var f: (x: Double, y: Double, z: Double, rz: Double, s: Double) = (0, 0, 0, 0, 1)
        var p: [HoloSpring]          // x, y, z, rx, ry, rz, s
        var until: Double = 0
        var kb = false

        enum Phase2 { case `in`, shot, orbit, spread }
    }
    var deck: [(d: TarotCard, reversed: Bool)] = []
    var cards: [Card] = []
    var spreadAt: Double = 0

    // ---- 指针 ----
    var pointer = (x: Double(0), y: Double(0), inside: false, touch: false, tap: false)
    var dragMoved = false

    // ---- 尺寸 ----
    var stageW: Double = 0
    var stageH: Double = 0

    // ---- 回调（原生持久化 + 牌义弹层）----
    var onOpened: (([(card: TarotCard, reversed: Bool, slot: Int)]) -> Void)?
    var onCardTapped: ((TarotCard, Bool, Int) -> Void)?

    /// 再抽一次：清空手牌重新来（换配色/重洗牌，与原版 again 一致）
    func again() {
        cards = []
        deck = []
        enter()
    }

    // MARK: 生命周期

    func prepare(context: ModelContext) {
        self.context = context
        enter()
    }

    /// enter()：新包从右侧飞入落定（换配色、重生成撕裂线与光流）
    func enter() {
        state = .enter
        let pool = HoloSkins.indices.filter { $0 != skinIndex }
        skinIndex = pool.randomElement() ?? 0
        light()
        path()
        sprout()
        tearP.reset(0); tearTh.reset(0); tearPh.reset(0)
        squeeze.reset(0); glow.reset(0)
        px.reset(0); py.reset(0); prx.reset(0); pry.reset(0); prz.reset(0)
        held = false; hurt = false; tugged = false; hitDisabled = false
        fly = nil; fall = nil; spreadAt = 0
        tearLast = 0; tearDir = 1
        flowDrained = false
        for i in ribbons.indices { ribbons[i].on = false; ribbons[i].g.reset(0) }
        if !reduce {
            px.x = stageW * 0.62
            py.x = -50
            pry.x = -200
            prz.x = 16
        }
        settleAt = reduce ? t : t + 0.95
        sfx?.arrive()
    }

    // MARK: 输入

    func pointerMoved(to location: CGPoint, in bounds: CGSize) {
        pointer.x = location.x
        pointer.y = location.y
        pointer.inside = true
        pointer.touch = true
    }

    func dragMoved(_ translation: CGSize, time: Date) {
        pointer.tap = false
        guard state == .idle || state == .enter else { return }
        let dx = translation.width
        let dy = translation.height
        if !dragMoved {
            if hypot(dx, dy) < 6 { return }
            dragMoved = true
            if state == .enter { settleAt = 0; state = .idle; squeeze.v -= 6; for s in [px, py, prx, pry, prz] { s.set(0.28, 0.25) } }
            tearP.set(0.1)
            tugged = true
            sfx?.grab()
        }
        guard state == .idle, let drag else { return }
        if tearP.to == 0 {
            drag.dy = dy
            if abs(dx) < 8 || abs(dx) < abs(dy) * 0.5 { return }
            tearDir = dx < 0 ? -1 : 1
            drag.y0 += dy // 重置 y0（方向锁定后只看横向）
            startTearing()
        }
        guard tearP.to < 1 else { return }
        let pw = max(1, PW)
        tearP.to = clamp(drag.p0 + (drag.p0 != 0 ? abs(dx) : dx * Double(tearDir)) / (pw * 0.85), tearP.to, 1)
        tearTh.to = 6 + tearP.to * 14 + clamp(-dy * 0.16, -6, 22)
        tearPh.to = -(8 + tearP.to * 22) - clamp(-dy * 0.2, 0, 24)
        let now = time.timeIntervalSince1970 * 1000
        tearVX = Double(dx) / max(8, now - drag.lt) * 1000
        drag.lt = now
        drag.k = (drag.k ?? 0) + (clamp(Double(dy) / max(60, abs(dx)), -0.7, 0.7) * PW / PH - (drag.k ?? 0)) * 0.3
        steer(drag.k ?? 0)
        if tearP.to > 0.985 { open() }
    }

    func dragEnded(_ translation: CGSize, time: Date) {
        pointer.tap = true
        let wasDragging = drag != nil
        drag = nil
        guard state == .idle else { return }
        if wasDragging {
            if tearP.to > 0.55 {
                finishTear(0.18)
                return
            }
            let hurtWas = hurt
            held = false; hurt = false; tugged = false
            tearTh.to = 3 + tearP.to * 10
            tearPh.to = -tearP.to * 14
            if hurtWas { sfx?.phew() } else { sfx?.boing() }
            return
        }
        // 轻点：直接开包（原版按压行为）
        if tearP.to < 1 {
            if tearP.to == 0 { tearDir = Bool.random() ? -1 : 1 }
            startTearing()
            finishTear(tearP.to == 0 ? 0.55 : 0.18)
        }
    }

    func press() {
        // 兜底按压（非拖动手势路径）
        sfx?.unlock()
    }

    private func startTearing() {
        if !hurt { sfx?.eep() }
        held = true
        hurt = true
        tugged = false
        sfx?.grab()
    }

    private func finishTear(_ response: Double) {
        tearP.set(response)
        tearP.to = 1
        tearTh.to = Double.random(in: 14...30)
        tearPh.to = -Double.random(in: 20...44)
    }

    // MARK: 开包

    private func open() {
        state = .open
        openedAt = t
        tearP.x = 1
        tearP.to = 1
        hitDisabled = true
        prx.set(0.3); pry.set(0.3)
        prx.to = 0; pry.to = 0
        if reduce {
            fly = nil
        } else {
            fly = (x: 0, y: 0, vx: Double(tearDir) * 240, vy: -1900,
                   th: tearTh.x, vth: 520, ph: tearPh.x, vph: -320)
            py.v += 320
            prz.v -= Double(tearDir) * 40
        }
        burst()
        spawn()
        sfx?.rip(0)
        sfx?.pop(!reduce)
        // ★ 原生持久化：一包三张即落库（现在位 = deck[1]，首页核心牌同步）
        if let context {
            let record = TarotService.ensureToday(in: context)
            guard deck.count == 3 else { return }
            TarotService.commitSpread(
                record, in: context,
                core: deck[1].d.id, past: deck[2].d.id, future: deck[0].d.id,
                reversedCore: deck[1].reversed, reversedPast: deck[2].reversed, reversedFuture: deck[0].reversed
            )
        }
    }

    // MARK: 帧循环（frame() 的移植）

    func tick(until date: Date, size: CGSize, safeBottom: CGFloat, context: ModelContext) {
        guard size.width > 10 else { return }
        if last == nil { last = date }
        var dt = date.timeIntervalSince(last ?? date)
        last = date
        dt = min(0.05, max(0.001, dt))
        t += dt
        stageW = size.width
        stageH = size.height
        self.context = context
        measure(size: size, safeBottom: safeBottom)

        let motion: Double = reduce ? 0 : 1
        let holding = held

        // 撕扯上下的拉伸
        var tug: Double = 0
        if motion != 0, drag != nil, dragMoved, tearP.to == 0, let d = drag {
            tug = Double(d.dy.signum()) * 170 * (1 - 1 / (1 + abs(d.dy) / 170))
        }
        squeeze.to = tug != 0 ? -abs(tug) / 90 : (holding && state == .idle ? motion : 0)

        if state == .enter || state == .idle {
            let tiltFactor: Double = (drag?.moved ?? false) ? 0.25 : 1
            let nx = pointer.inside ? clamp(pointer.x / stageW * 2 - 1, -1, 1) : 0
            let ny = pointer.inside ? clamp(pointer.y / stageH * 2 - 1, -1, 1) : 0
            py.to = sin(t * 1.4) * 7 * motion + tug
            pry.to = nx * 22 * tiltFactor * motion
            prx.to = -ny * 16 * tiltFactor * motion - squeeze.x * 6
            prz.to = sin(t * 0.9) * 1.6 * motion - (holding && tearP.x > 0 ? Double(tearDir) * tearP.x * 3 : 0)
            if state == .idle, drag == nil, tearP.to < 1, motion != 0, t > nudgeAt {
                prz.v += (Bool.random() ? -1 : 1) * 70
                if tearP.to != 0 { tearTh.v += 120 }
                nudgeAt = t + Double.random(in: 4...7)
            }
            if state == .enter, t >= settleAt { state = .idle }
        }

        // 弹簧子步进（240Hz）
        var springs: [HoloSpring] = [px, py, prx, pry, prz, tearP, tearTh, tearPh, squeeze, glow]
        springs.append(contentsOf: ribbons.map(\.g))
        for c in cards { springs.append(contentsOf: c.p) }
        let n = Int(ceil(dt * 240))
        let h = dt / Double(max(1, n))
        for _ in 0..<max(1, n) {
            for s in springs { s.step(h) }
        }

        // 撕裂进行中
        if state == .idle, tearP.x > 0 {
            let p = min(1, tearP.x)
            let dp = p - tearLast
            tearLast = p
            sfx?.rip(speed: dp > 0 ? pow(dp / max(dt, 0.004) / 4, 0.6) : 0)
            if dp > 0, motion != 0 {
                prz.v += Double.random(in: -1...1) * min(dp, 0.02) * 900
                py.v += dp * 420
                tearTh.v += dp * 300
                squeeze.v += dp * 20
                for i in ribbons.indices where ribbons[i].on { ribbons[i].g.v += dp * 6 }
            }
            if dp > 0 || abs(tearP.v) > 0.001 { clips(p) }
            if p > 0.985 && tearP.to >= 1 { open() }
        }
        glow.to = (state == .idle && tearP.x > 0) || ((state == .open || state == .spread) && !reduce && !flowDrained) ? 1 : 0

        // 撕条抛飞
        if var f = fly {
            f.vy += 2600 * dt
            f.x += f.vx * dt
            f.y += f.vy * dt
            f.th += f.vth * dt
            f.ph += f.vph * dt
            fly = f
            if t - openedAt > 1.6 { fly = nil }
        }
        // 卡包坠落
        if state == .open, fall == nil, !reduce, t - openedAt > 0.02 {
            fall = (y: 0, v: 1500 * PH / 420)
        }
        if var fl = fall, fl.y < stageH {
            fl.v += 2800 * dt
            fl.y += fl.v * dt
            fall = fl
            prz.to = Double(tearDir) * 9
        }

        // 光流
        pour(dt)

        // 卡牌状态机
        if state == .open, spreadAt == 0, cards.allSatisfy({ $0.phase == .shot }) {
            let mouth = py.x + (fall?.y ?? 0) + PH * ((jag.map { $0[1] }.max() ?? 10) / 100 - 0.5)
            let ch = PW * 0.84 * 1.4
            if cards.allSatisfy({ $0.p[1].x + ch * 0.36 < mouth }) { unwind() }
        }
        for i in cards.indices where cards[i].phase == .orbit { orbit(&cards[i]) }

        // 卡牌散开后的悬停/摇摆/全息
        let hot = pointer.inside || pointer.tap ? aimed() : nil
        for i in cards.indices {
            var c = cards[i]
            let p = c.p
            let since = t - openedAt
            if c.phase == .in, !reduce, since > Double(c.i) * 0.022 {
                c.phase = .shot
                p[6].to = 1
                p[1].k = 0
                p[1].c = 1.2
                p[1].v = -Double.random(in: 1250...1450) * PH / 420
            }
            if c.phase == .spread {
                if c == hot { c.until = t + 1.1 }
                c.hover = c == hot || t < c.until || c.kb
                let f = c.f
                let w = t * 0.8 + Double(c.i) * 1.9
                let on = c.hover
                if on != c.glad {
                    c.glad = on
                    if on { sfx?.lift(c.slot) }
                }
                p[0].to = f.x
                p[6].to = f.s
                p[1].to = f.y + (on ? -16 : sin(w * 1.2) * 5 * motion)
                p[2].to = f.z + (on ? 110 : 0)
                p[5].to = f.rz * (on ? 0.3 : 1)
                p[3].to = on ? (0.5 - c.hy) * 36 : cos(w * 0.9) * 4 * motion
                p[4].to = on ? (c.hx - 0.5) * 40 : sin(w) * 8 * motion
                // 全息高光跟随倾斜
                let nx = clamp(p[4].x / 24, -1, 1)
                let ny = clamp(p[3].x / 24, -1, 1)
                c.hx = 50 + nx * 50
                c.hy = 50 - ny * 50
            }
            cards[i] = c
        }

        // 彩带纸屑物理
        stepBits(dt: dt)

        if state == .open, spreadAt != 0, t > spreadAt + (reduce ? 0.1 : TarotEngine.orbitDur + 0.3) {
            state = .spread
        }
        pointer.tap = false
    }

    private func measure(size: CGSize, safeBottom: CGFloat) {
        stageW = size.width
        stageH = size.height
        PH = min(420, size.height * 0.58, size.width * 1.2)
        PW = PH * 0.69
        padShift = max(96, safeBottom + 84) / 2
    }

    private func clamp(_ v: Double, _ a: Double, _ b: Double) -> Double { min(b, max(a, v)) }

    // MARK: 撕裂线生成（path()）

    func path() {
        tearRoll = Double.random(in: 0.65...1.4)
        let slope = Double.random(in: -7.5...7.5)
        let bow = Double.random(in: -3...3)
        let freq = Double.random(in: 1.5...3.5)
        let ph = Double.random(in: 0...(2 * .pi))
        let wob = Double.random(in: 0.3...1.1)
        let y0 = Double.random(in: 10.5...14)
        var walk = 0.0
        jag = []
        for i in 0...Self.jagCount {
            let x = Double(i) / Double(Self.jagCount) * 100
            let s = x / 50 - 1
            walk = clamp(walk + Double.random(in: -0.25...0.25) + (Double.random(in: 0...1) < 0.05 ? Double.random(in: -1.5...1.5) : 0), -2.2, 2.2)
            let line = clamp(y0 + slope * s + bow * (1 - s * s) + wob * sin(s * freq * .pi + ph) + walk, Self.yMin, Self.yMax)
            let tooth = Double.random(in: -0.42...0.42) + (Double.random(in: 0...1) < 0.14 ? Double.random(in: -1.2...1.2) : 0)
            let metal = Double.random(in: 0...1) < 0.12 ? Double.random(in: 1.2...2.1) : Double.random(in: 0.35...1.1)
            let jitterX = (i == 0 || i == Self.jagCount) ? 0 : Double.random(in: -0.3...0.3)
            jag.append([x + jitterX, line + tooth, line, tooth, metal, 0])
        }
    }

    private func yAt(_ x: Double) -> Double {
        let f = clamp(x, 0, 100) / 100 * Double(Self.jagCount)
        let i = min(Self.jagCount - 1, Int(f))
        return jag[i][1] + (jag[i + 1][1] - jag[i][1]) * (f - Double(i))
    }

    /// 未撕部分跟随手上下弯折（steer）
    private func steer(_ bendK: Double) {
        let d = tearDir
        let i0 = Int(clamp((d > 0 ? tearP.x : 1 - tearP.x) * Double(Self.jagCount), 0, Double(Self.jagCount)))
        var i = i0 + d
        while i >= 0 && i <= Self.jagCount {
            jag[i][5] = jag[i0][5] + bendK * abs(Double(i - i0)) * 100 / Double(Self.jagCount)
            jag[i][1] = clamp(jag[i][2] + jag[i][5], Self.yMin, Self.yMax) + jag[i][3]
            i += d
        }
    }

    // MARK: 裁切与撕条片（clips）

    struct PlyState {
        var hidden: Bool
        var lo: Double, hi: Double
        var piece: [(Double, Double)]
        var lip: [(Double, Double)]
        var rotateY: Double
        var rotateZ: Double
        var sliceX: Double
        var shadeO: Double
        var underO: Double
    }
    var plyStates: [PlyState] = []
    var bodyClipFront: [(Double, Double)] = [[0.0, 0.0], [100.0, 0.0], [100.0, 100.0], [0.0, 100.0]]
    var bodyClipBack: [(Double, Double)] = [[0.0, 0.0], [100.0, 0.0], [100.0, 100.0], [0.0, 100.0]]
    var lipBand: [(Double, Double)] = []
    var flapOrigin = (x: Double(50), y: Double(10.5))
    var flapTilt = (z: Double(0), x: Double(0))

    func clips(_ p: Double) {
        let d = tearDir
        let xt = d > 0 ? p * 100 : 100 - p * 100
        let yt = yAt(xt)
        let K = Self.plyCount
        let w = 100.0 / Double(K)
        let lap = 0.25
        let bend = (2.6 + 2.6 * p) * tearRoll
        let jit = min(1, abs(tearP.v) * 0.4) * 1.6
        let torn = jag.filter { d > 0 ? $0[0] < xt : $0[0] > xt }
        let tip = [xt, yt]

        // 卡包主体裁切（正/背面镜像）
        if d > 0 {
            bodyClipFront = [[xt, 0], [100, 0], [100, 100], [0, 100]] + torn.map { [$0[0], $0[1]] } + [[xt, yt]]
            bodyClipBack = [[100 - xt, 0], [100, 0], [100, 100], [0, 100]] + torn.map { [100 - $0[0], $0[1]] } + [[100 - xt, yt]]
        } else {
            bodyClipFront = [[0, 0], [xt, 0], [xt, yt]] + torn.map { [$0[0], $0[1]] } + [[100, 100], [0, 100]]
            bodyClipBack = [[0, 0], [100 - xt, 0], [100 - xt, yt]] + torn.map { [100 - $0[0], $0[1]] } + [[100, 100], [0, 100]]
        }
        // 撕裂亮边带（银色金属层，宽度 = 各点 metal）
        let spanAll = d > 0 ? torn + [jag.last!] : [jag[0]] + torn
        lipBand = band(spanAll.map { [$0[0], $0[1], 0, 0, $0[4]] }, 1)
        flapOrigin = (x: xt, y: yt)

        plyStates = []
        var sum = 0.0
        var chainX = 0.0
        let k0 = Int(clamp((d > 0 ? xt - 0.000001 : xt) / w, 0, Double(K - 1)))
        var nn = 0
        var k = k0
        while k >= 0 && k < K {
            defer { k -= d; nn += 1 }
            let lo = d > 0 ? Double(k) * w : max(Double(k) * w, xt)
            let hi = d > 0 ? min(Double(k + 1) * w, xt) : Double(k + 1) * w
            if hi <= lo { continue }
            let sliceX = Double((nn == 0 ? xt : (d > 0 ? k + 1 : k) * w))
            let a = Double(d) * (bend * (0.4 + 0.3 * Double(nn)) + sin(t * 16 + Double(nn) * 0.9) * jit)
            sum += a
            chainX = sliceX
            let L = d < 0 && lo == xt ? lo : max(0, lo - lap)
            let R = d > 0 && hi == xt ? hi : min(100, hi + lap)
            var span: [[Double]] = [[L, yAt(L), 0, 0, 0.8]]
            span.append(contentsOf: jag.filter { $0[0] > L && $0[0] < R })
            span.append([R, yAt(R), 0, 0, 0.8])
            var piece: [(Double, Double)] = [[L, 0], [R, 0]]
            piece.append(contentsOf: span.reversed().map { [$0[0], $0[1]] })
            let lip = band(span, -1)
            plyStates.append(PlyState(
                hidden: false, lo: lo, hi: hi, piece: piece, lip: lip,
                rotateY: a, rotateZ: Double(d) * 0.9 * Double(nn) / 4, sliceX: sliceX,
                shadeO: min(0.5, abs(sum) / 200), underO: max(0, 0.34 - abs(sum) / 420)
            ))
        }
        _ = chainX
    }

    /// 沿撕裂边缘的亮边带（宽度 = 各点 metal）
    private func band(_ a: [[Double]], _ sign: Double) -> [(Double, Double)] {
        var pts = a.map { (Double($0[0]), Double($0[1])) }
        pts.append(contentsOf: a.reversed().map { (Double($0[0]), Double($0[1] + sign * $0[4])) })
        return pts
    }

    // MARK: 开包后的彩带爆发（burst）

    func burst() {
        for i in bits.indices where bits[i].age != nil {}
        for i in bits.indices {
            if bits[i].age != nil { continue }
            let lx = Double.random(in: 6...94)
            let vt = 260 + 400 * pow(Double.random(in: 0...1), 1.5)
            bits[i].lx = lx
            bits[i].ly = yAt(lx) + Double.random(in: 1...16)
            bits[i].lz = Double.random(in: 4.6...7)
            bits[i].up = Double.random(in: 900...2600)
            bits[i].a = ((lx - 50) / 50 + Double.random(in: -0.5...0.5)) * clamp(stageW / 1000, 0.5, 1)
            bits[i].sp = Double.random(in: 500...2700)
            bits[i].r = Double.random(in: 0...360)
            bits[i].rot0 = bits[i].r
            bits[i].spin = Double.random(in: -700...700)
            bits[i].c = 2600 / (vt * vt)
            bits[i].slip = Double.random(in: 900...2600)
            bits[i].glide = (lx < 50 ? -1 : 1) * Double.random(in: -200...900)
            bits[i].sc = Double.random(in: 0.9...1.9)
            bits[i].ph = Double.random(in: 0...(2 * .pi))
            bits[i].age = i < 50 ? 0 : -Double.random(in: 0...0.22)
            bits[i].x = 0; bits[i].y = 0; bits[i].z = 0
        }
    }

    /// 包内坐标系 → 舞台坐标（onStage）
    private func onStage(_ lx: Double, _ ly: Double, _ lz: Double) -> (x: Double, y: Double, z: Double) {
        let r = .pi / 180
        let cx = cos(prx.x * r), sx = sin(prx.x * r)
        let cy = cos(pry.x * r), sy = sin(pry.x * r)
        let cz = cos(prz.x * r), sz = sin(prz.x * r)
        let x0 = (lx - 50) / 100 * PW
        let y0 = (ly - 50) / 100 * PH
        let x1 = x0 * cz - y0 * sz
        let y1 = x0 * sz + y0 * cz
        let x2 = x1 * cy + lz * sy
        let z2 = -x1 * sy + lz * cy
        return (x2 + px.x, y1 * cx - z2 * sx + py.x + (fall?.y ?? 0), y1 * sx + z2 * cx)
    }

    func stepBits(dt: Double) {
        let cullY = stageH / 2 + 40
        for i in bits.indices {
            bits[i].age += dt
            guard bits[i].age >= 0 else { continue }
            if bits[i].inside {
                bits[i].ly -= bits[i].up * dt / PH * 100
                bits[i].r += bits[i].spin * dt
                if bits[i].ly > yAt(bits[i].lx) { continue }   // 还在包内，未被光流送出
                let s = onStage(bits[i].lx, bits[i].ly, bits[i].lz)
                bits[i].x = s.x; bits[i].y = s.y; bits[i].z = s.z
                bits[i].inside = false
                bits[i].age = 0
                bits[i].rot0 = bits[i].r
                bits[i].vx = sin(bits[i].a) * bits[i].sp
                bits[i].vy = -cos(bits[i].a) * bits[i].sp
                bits[i].vz = Double.random(in: 0...160)
            }
            bits[i].z += bits[i].vz * dt
            bits[i].vy += 2600 * dt
            bits[i].vx += (sin(bits[i].ph) * bits[i].slip + bits[i].glide) * dt
            let v = sqrt(bits[i].vx * bits[i].vx + bits[i].vy * bits[i].vy)
            let dragK = 1 / (1 + bits[i].c * min(1, 0.06 + bits[i].age / 0.45) * v * dt)
            bits[i].vx *= dragK
            bits[i].vy *= dragK
            bits[i].x += bits[i].vx * dt
            bits[i].y += bits[i].vy * dt
            let turn = 0.35 + v / 800
            bits[i].r += bits[i].spin * turn * dt
            bits[i].ph += 7 * turn * dt
        }
        // 落出屏幕底部即回收（y 相对舞台中心 oy）
        bits.removeAll { b in
            guard !b.inside, b.age >= 0 else { return false }
            return b.y >= cullY || b.age > 4
        }
    }

    // MARK: 开包与卡牌（open/spawn/unwind/orbit/fan/aimed）

    private func spawn() {
        deck = draw()
        cards = deck.enumerated().map { i, entry in
            var c = Card(d: entry.d, reversed: entry.reversed, i: i, slot: deck.count - 1 - i)
            let maxY = jag.map { $0[1] }.max() ?? 10
            let mouthY = py.x + PH * ((maxY + 0.8 + 38.2) / 100 - 0.5)
            c.p = [
                HoloSpring(px.x, 0.55, 0.22),
                HoloSpring(mouthY, 0.55, 0.22),
                HoloSpring(3.5 - Double(i) * 1.75, 0.55, 0.22),
                HoloSpring(0, 0.55, 0.22),
                HoloSpring(0, 0.55, 0.22),
                HoloSpring(prz.x, 0.55, 0.22),
                HoloSpring(0.94, 0.55, 0.22)
            ]
            return c
        }
    }

    private func draw() -> [(d: TarotCard, reversed: Bool)] {
        shuffle(Array(TarotDeck.major)).prefix(Self.drawCount).map { ($0, Bool.random()) }
    }

    private func unwind() {
        spreadAt = t
        for i in cards.indices {
            var c = cards[i]
            let f = fan(c)
            c.f = f
            c.phase = .orbit
            c.from = t + Double(c.i) * 0.03
            c.x0 = c.p[0].x
            c.y0 = c.p[1].x
            c.vy0 = c.p[1].v
            c.rz0 = c.p[5].x
            c.even = -Double(c.slot) * 2 * .pi / Double(cards.count)
            c.end = .pi / 2 - (Double(c.slot) - (Double(cards.count) - 1) / 2) * 0.55
            c.landAt = c.from + TarotEngine.orbitDur
            c.p[6].to = f.s
            for k in 0..<6 { c.p[k].k = 0; c.p[k].c = 0; c.p[k].v = 0 }
            cards[i] = c
        }
        sfx?.swirl(TarotEngine.orbitDur)
    }

    private func ease(_ a: Double, _ b: Double, _ x: Double) -> Double {
        let k = clamp((x - a) / (b - a), 0, 1)
        return k * k * (3 - 2 * k)
    }

    private func orbit(_ c: inout Card) {
        let p = c.p
        let u = clamp((t - c.from) / TarotEngine.orbitDur, 0, 1)
        let turn = 1 - (1 - u) * (1 - u)
        let out = ease(0.52, 1, u)
        let ring = sin(min(1, u / 0.42) * .pi / 2) * (1 - out)
        let a = c.end + (1 - turn) * (c.even - c.end + .pi * 2.5)
        let sinA = sin(a), cosA = cos(a)
        let W = min(stageW * 0.33, 430)
        let mid = c.y0 + c.vy0 / 9 * (1 - exp(-9 * max(0, t - c.from)))
        let cy = mid + (-stageH * 0.03 - mid) * ease(0, 0.42, u)
        p[0].x = c.x0 * (1 - out) + c.f.x * out + cosA * W * ring
        p[1].x = cy * (1 - out) + c.f.y * out + sinA * W * 0.2 * ring
        p[2].x = c.f.z * out + sinA * 300 * ring
        p[5].x = c.rz0 * (1 - out) + c.f.rz * out - cosA * 8 * ring
        p[4].x = -cosA * 26 * ring
        p[3].x = 7 * ring
        if u == 1 {
            c.phase = .spread
            for k in 0..<7 { p[k].set(0.5, 0.22) }
            sfx?.land(c.d.arcana == "major" ? "major" : "minor", c.slot)
        }
    }

    private func fan(_ c: Card) -> (x: Double, y: Double, z: Double, rz: Double, s: Double) {
        let n = cards.count
        let m = Double(c.slot) - (Double(n) - 1) / 2
        let cw = PW * 0.84
        let vw = stageW
        if stageH > vw * 1.15 {
            let w = min((vw - 34) / 2, (stageH - 150) / 2.72 / 1.4, cw)
            let layout: [[Double]] = [[-1, -1, -4], [1, -1, 4], [0, 1, -2]]
            let l = layout[c.slot]
            return (x: l[0] * (w / 2 + 5), y: -15 + l[1] * w * 1.4 * 0.86, z: (l[0] != 0 || l[1] != 0) ? 0 : 40, rz: l[2], s: w / cw)
        }
        let s = clamp((vw - 48) / (cw * (1 + (Double(n) - 1) * 1.08)), 0.6, 1)
        let w = cw * s
        let side = min(w * 1.08, (vw - 40 - w) / (Double(n) - 1))
        let tight = side < w
        let ends = (Double(n) - 1) / 2
        let lean = ends * 7 * .pi / 180
        let near = 1400 / (1400 - ends * 40)
        let gap = tight ? max(6, min(side, (vw / 2 - 8 - (w / 2 * cos(lean) + w * 0.7 * sin(lean)) * near) / (ends * near))) : side
        return (x: m * gap, y: -stageH * 0.03 + m * m * (tight ? 9 : 5) * s, z: tight ? m * 40 : 0, rz: m * (tight ? 7 : 2), s: s)
    }

    /// 指针命中的展开态卡牌（aimed）
    private func aimed() -> Card? {
        var best: Card?
        for i in cards.indices {
            var c = cards[i]
            guard c.phase == .spread else { continue }
            let f = c.f
            let near = 1400 / (1400 - f.z)
            let a = f.rz * .pi / 180
            let cosA = cos(a), sinA = sin(a)
            let w = PW * 0.84 * f.s * near
            let h = w * 1.4
            let dx = pointer.x - (stageW / 2 + f.x * near)
            let dy = pointer.y + padShift - (stageH * 0.4 + (stageH * 0.1 + f.y) * near)
            let hx = (dx * cosA + dy * sinA) / w + 0.5
            let hy = (dy * cosA - dx * sinA) / h + 0.5
            if hx >= 0, hx <= 1, hy >= 0, hy <= 1, best == nil || f.z >= (best?.f.z ?? 0) {
                c.hx = hx
                c.hy = hy
                best = c
                cards[i] = c
            }
        }
        return best
    }

    func tapCard(at index: Int) {
        guard state == .spread, cards.indices.contains(index) else { return }
        let c = cards[index]
        onCardTapped?(c.d, c.reversed, c.slot)
    }

    // MARK: 包面光影（light）——每包随机的高光条纹与皱褶阴影

    struct Streak { let x: Double, w: Double, h: Double, o: Double }
    var shineStreaks: [Streak] = []
    var crumplePeaks: [Double] = [91.6]

    func light() {
        shineStreaks = []
        var x = 0.0
        while x < 100 {
            let w = Double.random(in: 0.5...2.6)
            shineStreaks.append(Streak(x: x, w: w, h: Double.random(in: 3.2...8.5), o: Double.random(in: 0.08...0.42)))
            x += w + Double.random(in: 0...1.4)
        }
        crumplePeaks = [91.6]
        var cx = 0.0
        while cx < 100 {
            let w = Double.random(in: 2.5...7)
            cx = min(100, cx + w)
            crumplePeaks.append(Double.random(in: 86.6...90))
        }
    }

    // MARK: 彩虹光流（sprout/fit/pour）

    func sprout() {
        let u = max(1, PW / 100)
        flowY0 = 62.5 + (Self.yMax - Self.tearBase) / 100 * PH / u
        flowR0 = 107.5 - flowY0
        let k0 = Int.random(in: 0...6)
        flowColorShift = k0
        ribbonLines = (0...35).map { j in
            let ox = 3 + 94 * Double(j) / 35
            let x = 50 + (ox - 50) * flowR0 / 45
            let a = atan2(x - 50, flowR0) + Double.random(in: -0.012...0.012)
            return (ox: ox, x: x, ux: sin(a), uy: -cos(a), ph: Double(j) * 0.35 + Double.random(in: -0.1...0.1), r: sqrt((x - 50) * (x - 50) + flowR0 * flowR0))
        }
        ribbons = (0..<35).map { j in
            let r = (ribbonLines[j].r + ribbonLines[j + 1].r) / 2
            return Ribbon(mx: (ribbonLines[j].ox + ribbonLines[j + 1].ox) / 2, gx: (ribbonLines[j].x + ribbonLines[j + 1].x) / 2, r: r, c: HoloBands[(j + k0) % 7], g: HoloSpring(0, 0.4, reduce ? 0 : 0.3))
        }
        motes = (u: (0..<10).map { _ in Double.random(in: 0...1) },
                 j: (0..<10).map { _ in -1 },
                 v: (0..<10).map { _ in Double.random(in: 0.2...0.8) },
                 sp: (0..<10).map { _ in Double.random(in: 0.3...0.5) },
                 r: (0..<10).map { _ in Double.random(in: 1.6...3) })
        fit()
    }

    func fit() {
        let u = max(1, PW / 100)
        let room = 2.5 + (stageH / 2 - PH * (0.5 - Self.tearBase / 100)) / u
        flowReach = reduce ? 45 + room * 0.6 : (45 + room) * sqrt(pow(47.0 / 45.0, 2) + 1) + 36 + 20
        for i in ribbons.indices { ribbons[i].len = flowReach - ribbons[i].r }
    }

    var flowPts: [[(Double, Double)]] = []
    var flowMotes: [(x: Double, y: Double, r: Double, o: Double)] = []
    var flowOpacity: Double = 0

    /// 光流几何（pour）：撕裂后彩虹彩带从撕口向头顶铺满，行波、白热根部、尾部上抛
    func pour(dt: Double) {
        guard !ribbons.isEmpty else { return }
        let u = max(1, PW / 100)
        let ft = reduce ? 0 : t
        let xt = tearDir > 0 ? tearP.x * 100 : 100 - tearP.x * 100
        let sway = sin(ft * 0.9) * 1.5
        let go = !reduce && (state == .open || state == .spread)
        let s = t - openedAt
        let a = atan(anchor.rz * .pi / 180)
        let roof = 60 + ((-stageH / 2 - anchor.y) / cos(a) + PH * (0.5 - Self.tearBase / 100)) / u
        let soft = 36.0
        let full = (flowY0 + flowR0 - roof) * ribbons[0].r / flowR0 + soft + 20
        let far = go ? flowReach + (full - flowReach) * (1 - pow(1 - min(1, s / 0.5), 2)) : flowReach
        let tail = flowR0 - 5 + (go ? (full + 21 - flowR0) * pow(clamp((s - 0.35) / 0.55, 0, 1), 2) : 0)
        let carry = go ? 45 * s * s / (s + 0.25) : 0
        for i in ribbons.indices {
            if state == .idle, tearP.x > 0, (tearDir > 0 ? ribbons[i].mx < xt : ribbons[i].mx > xt) { ribbons[i].on = true }
            ribbons[i].g.to = ribbons[i].on ? 1 : 0
            ribbons[i].len = (flowReach - ribbons[i].r) * max(0, ribbons[i].g.x) + far - flowReach
        }
        let side = stageW / 2 / u + 14
        var edges: [[(Double, Double)]] = []
        for j in 0...35 {
            let e = ribbonLines[j]
            let stop = min((flowY0 - roof) / -e.uy, (side - abs(e.x - 50)) / abs(e.ux)) + 24
            let len = min(max(j > 0 ? ribbons[j - 1].len : 0, j < 35 ? ribbons[j].len : 0), stop)
            var pts: [(Double, Double)] = []
            let step = 2.5
            let i0 = max(0, Int(floor((tail - e.r) / step)))
            if len > Double(i0) * step {
                var i = i0
                var guardCounter = 0
                while guardCounter < 900 {
                    let d = min(Double(i) * step, len)
                    pts.append(flowPoint(j, d, sway: sway, carry: carry, ft: ft))
                    if d >= len { break }
                    i += 1
                    guardCounter += 1
                }
            }
            edges.append(pts)
        }
        flowPts = (0..<35).map { j in
            let len = ribbons[j].len
            let a = cutPts(edges[j], len)
            let b = cutPts(edges[j + 1], len)
            return a + b.reversed()
        }
        // 光尘
        let out = ribbons.indices.filter { ribbons[$0].on }
        for m in 0..<10 {
            if !reduce { motes.u[m] += dt * motes.sp[m] }
            if motes.u[m] > 1 || motes.j[m] == -1 || !out.contains(motes.j[m]) {
                if motes.u[m] > 1 { motes.u[m] -= 1 }
                if out.isEmpty { continue }
                motes.j[m] = out.randomElement() ?? 0
            }
            let j = motes.j[m]
            let len = ribbons[j].len
            let d0 = max(0, tail - ribbonLines[j].r)
            let d = d0 + motes.u[m] * (len - d0)
            let p1 = flowPoint(j, d, sway: sway, carry: carry, ft: ft)
            let p2 = flowPoint(j + 1, d, sway: sway, carry: carry, ft: ft)
            let x = p1.0 + (p2.0 - p1.0) * motes.v[m]
            let y = p1.1 + (p2.1 - p1.1) * motes.v[m]
            flowMotes[m] = (x: x, y: y, r: motes.r[m] * (0.6 + motes.u[m] * 0.7), o: sin(.pi * motes.u[m]) * min(1, len / 20))
        }
        flowOpacity = glow.x
        flowDrained = go && s > 0.9
    }

    private func flowPoint(_ j: Int, _ d: Double, sway: Double, carry: Double, ft: Double) -> (Double, Double) {
        let e = ribbonLines[j]
        let k = min(1, d / 90)
        let wave = (0.4 + 2 * k) * sin(((d - carry) / 22 - ft * 1.4) * 2 * .pi + e.ph) + sway * k
        return (e.x + e.ux * d - e.uy * wave, flowY0 + e.uy * d + e.ux * wave)
    }

    private func cutPts(_ pts: [(Double, Double)], _ len: Double) -> [(Double, Double)] {
        guard pts.count > 1 else { return [] }
        var out: [(Double, Double)] = []
        for (i, pt) in pts.enumerated() {
            let d = Double(i) * 2.5
            if d <= len { out.append(pt) } else { break }
        }
        return out
    }

    // === CHUNK3 ===
}

// MARK: - 舞台视图（stage/scene/ground/flow/pack/cards/fx 的 DOM 对应）

struct StageView: View {
    let engine: TarotEngine
    let size: CGSize
    var onCardTapped: (TarotCard, Bool, Int) -> Void

    var body: some View {
        let w = size.width
        let h = size.height
        let center = CGPoint(x: w / 2, y: h / 2 - engine.padShift)
        ZStack {
            // 地面阴影
            Ellipse()
                .fill(RadialGradient(colors: [Color(hex: 0x1E190F).opacity(0.3), .clear], center: .center, startRadius: 0, endRadius: engine.PW * 0.475))
                .frame(width: engine.PW * 0.95, height: engine.PW * 0.16)
                .position(x: center.x + engine.px.x, y: center.y + engine.PH / 2 + 26)
                .scaleEffect(1 - engine.py.x / 300)
                .opacity(groundOpacity)

            // 场景（flow 在包后，卡牌在包前）
            ZStack {
                FlowCanvas(engine: engine, packCenter: center)
                PackView(engine: engine, center: center)
                ForEach(engine.cards.indices, id: \.self) { i in
                    CardView(engine: engine, index: i, onTapped: onCardTapped)
                }
            }
            .offset(y: -engine.padShift)

            ConfettiCanvas(engine: engine, size: CGSize(width: w, height: h))
        }
        .overlay(alignment: .bottom) {
            if engine.state == .spread {
                Button {
                    engine.again()
                } label: {
                    Text("再抽一次 · Draw again")
                        .font(.system(size: 15))
                        .foregroundStyle(Color(hex: 0x141414))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(.white).shadow(color: .black.opacity(0.18), radius: 10, y: 6))
                }
                .buttonStyle(PressableStyle())
                .padding(.bottom, max(96, engine.padShift * 2 - 12))
                .transition(.opacity)
            }
        }
        .overlay(alignment: .topTrailing) {
            MuteButton()
                .padding(.top, 12)
                .padding(.trailing, 14)
        }
    }

    private var groundOpacity: Double {
        if engine.state == .enter || engine.state == .idle {
            return clampD(1 - abs(engine.px.x) / 300, 0, 1)
        }
        if let fall = engine.fall { return clampD(1 - fall.y / 160, 0, 1) }
        return 0
    }

    private func clampD(_ v: Double, _ a: Double, _ b: Double) -> Double { min(b, max(a, v)) }
}

// MARK: - 卡包（skins + plies + lips + orb 星章）

struct PackView: View {
    let engine: TarotEngine
    let center: CGPoint

    var body: some View {
        let pw = engine.PW
        let ph = engine.PH
        let squeeze = engine.squeeze.x
        ZStack {
            // 背面皮肤（fly-in 旋转经过 90° 时可见）
            BackSkinView(engine: engine)
                .scaleEffect(1400 / (1400 + 8), anchor: .center)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0), perspective: 1400)
            // 正面皮肤（撕裂裁切）
            FrontSkinView(engine: engine)
                .clipShape(PolyShape(points: engine.bodyClipFront))
            // 撕条片 + 撕裂亮边（flap：th/ph 弹簧以前沿为轴）
            ZStack {
                ForEach(engine.plyStates.indices, id: \.self) { k in
                    let ply = engine.plyStates[k]
                    if !ply.hidden {
                        PlyView(engine: engine, ply: ply)
                    }
                }
                LipBandView(points: engine.lipBand)
            }
            .rotation3DEffect(.degrees(engine.flapTilt.z * Double(engine.tearDir)), axis: (x: 0, y: 1, z: 0), anchor: UnitPoint(x: engine.flapOrigin.x / 100, y: engine.flapOrigin.y / 100), perspective: 1400)
            .rotation3DEffect(.degrees(engine.flapTilt.x), axis: (x: 1, y: 0, z: 0), anchor: UnitPoint(x: engine.flapOrigin.x / 100, y: engine.flapOrigin.y / 100), perspective: 1400)
        }
        .frame(width: pw, height: ph)
        .scaleEffect(x: 1 + 0.03 * squeeze, y: 1 - 0.06 * squeeze)
        .rotation3DEffect(.degrees(engine.prz.x), axis: (x: 0, y: 0, z: 1), perspective: 1400)
        .rotation3DEffect(.degrees(engine.prx.x), axis: (x: 1, y: 0, z: 0), perspective: 1400)
        .rotation3DEffect(.degrees(engine.pry.x), axis: (x: 0, y: 1, z: 0), perspective: 1400)
        .scaleEffect(1400 / max(600, 1400 - engine.py.x * 0.35), anchor: .center)
        .position(x: center.x + engine.px.x, y: center.y + engine.py.x + (engine.fall?.y ?? 0))
    }
}

/// 包面印刷：深空色 + 星轨点阵 + 撕口提示 + Tarot 系列 + 八芒星星章 + 脚注
struct FrontSkinView: View {
    let engine: TarotEngine

    var body: some View {
        let pw = engine.PW
        let ph = engine.PH
        let crimp = ph * 0.068
        ZStack(alignment: .topLeading) {
            // 底色
            Rectangle().fill(HoloSkins[engine.skinIndex].color)
            // 星轨点阵（两层错位）
            StarPrint(tint: 0.4).frame(width: pw, height: ph * 0.9)
            StarPrint(tint: 0.22).frame(width: pw, height: ph * 0.9).offset(x: pw * 0.13, y: ph * 0.11)
            // 皱褶阴影（底部波浪）
            CrumpleShade(peaks: engine.crumplePeaks)
            // 右缘背光
            HStack { Spacer()
                Rectangle().fill(LinearGradient(colors: [.clear, .black.opacity(0.14)], startPoint: .leading, endPoint: .trailing)).frame(width: pw * 0.07)
            }
            // 高光条纹（封口下方的褶皱反光）
            ShineStreaks(streaks: engine.shineStreaks)
            // 印刷：TEAR HERE / Tarot / 脚注
            Text("TEAR HERE →")
                .font(.system(size: pw * 0.029, weight: .bold))
                .kerning(pw * 0.0035)
                .foregroundStyle(.white.opacity(0.74))
                .position(x: pw * 0.09 + pw * 0.08, y: crimp + ph * 0.022)
            Text("Tarot")
                .font(.system(size: pw * 0.036, weight: .semibold))
                .kerning(pw * 0.004)
                .foregroundStyle(.white.opacity(0.7))
                .position(x: pw * 0.91 - pw * 0.05, y: ph * 0.175)
            Text("塔罗牌 · Tarot")
                .font(.system(size: pw * 0.042, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .position(x: pw * 0.09 + pw * 0.06, y: ph - crimp - ph * 0.034)
            Text("3 cards")
                .font(.system(size: pw * 0.042, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .position(x: pw * 0.91 - pw * 0.05, y: ph - crimp - ph * 0.034)
            // 八芒星星章
            StarMedallion(engine: engine)
                .frame(width: pw * 0.84, height: pw * 0.84)
                .position(x: pw / 2, y: ph * 0.265 + pw * 0.42)
        }
        // 封口压纹（上下热封条）
        .overlay(alignment: .top) { CrimpStrip(width: pw, height: crimp).offset(y: -crimp / 2) }
        .overlay(alignment: .bottom) { CrimpStrip(width: pw, height: crimp).offset(y: crimp / 2) }
    }
}

// MARK: - 卡包背面

struct BackSkinView: View {
    let engine: TarotEngine

    var body: some View {
        let pw = engine.PW
        let ph = engine.PH
        let crimp = ph * 0.068
        ZStack {
            Rectangle().fill(HoloSkins[engine.skinIndex].color)
            // 竖向细纹（fin）
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { _ in
                    Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                    Rectangle().fill(Color.black.opacity(0.10)).frame(height: 3)
                }
            }
            .frame(width: pw * 0.1).position(x: pw / 2, y: ph / 2)
            Text("✶")
                .font(.system(size: pw * 0.1, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .position(x: pw / 2, y: ph * 0.2)
            Text("78 张韦特塔罗 · 1909 公版\n每包 3 张 · 正逆随机")
                .font(.system(size: pw * 0.044, weight: .medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.85))
                .position(x: pw / 2, y: ph * 0.42)
            // 条码
            Canvas { ctx, size in
                var x: Double = 0
                while x < size.width {
                    let w = Double.random(in: 1...3)
                    ctx.fill(Path(CGRect(x: x, y: 0, width: w, height: size.height)), with: .color(.black.opacity(0.55)))
                    x += w + Double.random(in: 1...3)
                }
            }
            .frame(width: pw * 0.38, height: ph * 0.1)
            .position(x: pw / 2, y: ph * 0.62)
        }
    }
}

// MARK: - 撕条片（每片独立 rotateY 卷曲）

struct PlyView: View {
    let engine: TarotEngine
    let ply: TarotEngine.PlyState

    var body: some View {
        let pw = engine.PW
        let ph = engine.PH
        let crimp = ph * 0.068
        // 片内内容：该 x 段的包面顶部
        ZStack(alignment: .topLeading) {
            // 银色箔内面（卷曲时可见）
            Rectangle()
                .fill(LinearGradient(colors: [Color(hex: 0xE3E8F2), .white, Color(hex: 0xCFD7E6), .white, Color(hex: 0xDBE1EE)], startPoint: .leading, endPoint: .trailing))
                .opacity(ply.underO)
            // 包面片段
            ZStack(alignment: .topLeading) {
                Rectangle().fill(HoloSkins[engine.skinIndex].color)
                Text("TEAR HERE →")
                    .font(.system(size: pw * 0.029, weight: .bold))
                    .kerning(pw * 0.0035)
                    .foregroundStyle(.white.opacity(0.74))
                    .position(x: pw * 0.17, y: crimp + ph * 0.022)
                ShineStreaks(streaks: engine.shineStreaks)
                Text("Tarot")
                    .font(.system(size: pw * 0.036, weight: .semibold))
                    .kerning(pw * 0.004)
                    .foregroundStyle(.white.opacity(0.7))
                    .position(x: pw * 0.86, y: ph * 0.175)
            }
            .opacity(1 - ply.underO * 1.6)
        }
        .frame(width: pw, height: ph)
        .mask(PolyShape(points: ply.piece.map { CGPoint(x: $0.0 / 100 * pw, y: $0.1 / 100 * ph) }))
        .rotation3DEffect(.degrees(ply.rotateY), axis: (x: 0, y: 1, z: 0), anchor: .leading, perspective: 700)
        .rotationEffect(.degrees(ply.rotateZ), anchor: .leading)
        .offset(x: 0, y: 0)
    }
}

// MARK: - 撕裂亮边（银色金属带）

struct LipBandView: View {
    let points: [(Double, Double)]

    var body: some View {
        if points.count > 2 {
            PolyShape(points: points.map { CGPoint(x: $0.0, y: $0.1) })
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0xF4F6FB), .white, Color(hex: 0xBFC8DA), .white, Color(hex: 0xC9D1E1), Color(hex: 0xB9C2D4)],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .shadow(color: .black.opacity(0.42), radius: 1.5, y: 1.5)
        }
    }
}

// MARK: - 包面部件

struct StarPrint: View {
    let tint: Double
    var body: some View {
        Canvas { ctx, size in
            let cols = Int(size.width / 104) + 2
            let rows = Int(size.height / 92) + 2
            for r in 0..<rows {
                for c in 0..<cols {
                    let x = Double(c) * 104
                    let y = Double(r) * 92
                    ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(.white.opacity(tint)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

struct CrumpleShade: View {
    let peaks: [Double]
    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            path.move(to: CGPoint(x: 0, y: size.height * 0.932))
            path.addLine(to: CGPoint(x: 0, y: size.height * 0.916))
            for (i, peak) in peaks.enumerated() {
                if i == 0 { continue }
                let x = size.width * Double(i) / Double(peaks.count - 1)
                path.addQuadCurve(to: CGPoint(x: x, y: size.height * peak / 100), control: CGPoint(x: x - size.width * 0.01, y: size.height * peak / 100))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height * 0.932))
            path.closeSubpath()
            ctx.fill(path, with: .color(.black.opacity(0.1)))
        }
        .allowsHitTesting(false)
    }
}

struct ShineStreaks: View {
    let streaks: [TarotEngine.Streak]
    var body: some View {
        Canvas { ctx, size in
            for s in streaks {
                let rect = CGRect(x: size.width * s.x / 100, y: size.height * 0.068, width: size.width * s.w / 100, height: size.height * s.h / 100)
                ctx.fill(Path(rect), with: .linearGradient(
                    Gradient(colors: [.white.opacity(s.o), .white.opacity(0)]),
                    startPoint: CGPoint(x: rect.midX, y: rect.minY),
                    endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                ))
            }
        }
        .allowsHitTesting(false)
    }
}

struct CrimpStrip: View {
    let width: Double
    let height: Double
    var body: some View {
        Canvas { ctx, size in
            let tooth = width / 26
            var x: Double = 0
            while x < size.width {
                let w = min(tooth, size.width - x)
                var tri = Path()
                tri.move(to: CGPoint(x: x, y: size.height))
                tri.addLine(to: CGPoint(x: x + w / 2, y: 0))
                tri.addLine(to: CGPoint(x: x + w, y: size.height))
                ctx.fill(tri, with: .color(.black.opacity(0.18)))
                var tri2 = Path()
                tri2.move(to: CGPoint(x: x, y: 0))
                tri2.addLine(to: CGPoint(x: x + w / 2, y: 0))
                tri2.addLine(to: CGPoint(x: x + w / 2, y: size.height))
                ctx.fill(tri2, with: .color(.white.opacity(0.08)))
                x += w
            }
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }
}

/// 八芒星全息星章（替换原吉祥物）
struct StarMedallion: View {
    let engine: TarotEngine

    var body: some View {
        let squeeze = engine.squeeze.x
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let tremble = engine.held ? 1.2 : 0
            ZStack {
                // 星轨（两圈虚线椭圆）
                Ellipse()
                    .strokeBorder(.white.opacity(0.26), style: StrokeStyle(lineWidth: 0.6, dash: [2, 4]))
                    .frame(width: 0.9, height: 0.9)
                    .scaleEffect(x: 1, y: 0.64)
                Ellipse()
                    .strokeBorder(.white.opacity(0.15), style: StrokeStyle(lineWidth: 0.5, dash: [1, 3.4]))
                    .frame(width: 0.74, height: 0.58)
                    .scaleEffect(x: 1, y: 1).rotationEffect(.degrees(8))
                // 八芒星主体（全息渐变）
                StarPath()
                    .fill(
                        LinearGradient(
                            colors: [Color(hex: 0xFFF7D6), Color(hex: 0xFFD9F2), Color(hex: 0xC9E8FF), Color(hex: 0xD6FFE8), Color(hex: 0xFFE9B8)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                    .aspectRatio(contentMode: .fit)
                StarPath()
                    .fill(.white.opacity(0.9))
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(0.52)
                    .rotationEffect(.degrees(45))
                    .opacity(0.9)
                // 小星点
                Circle().fill(.white.opacity(0.85)).frame(width: 3.5).offset(x: 0.68, y: -0.64)
                Circle().fill(.white.opacity(0.7)).frame(width: 2.8).offset(x: -0.66, y: 0.44)
                Circle().fill(.white.opacity(0.6)).frame(width: 2.4).offset(x: 0.48, y: 0.7)
            }
            .frame(width: 100, height: 100)
            .scaleEffect(x: 1 + 0.06 * squeeze, y: 1 - 0.08 * squeeze)
            .offset(x: engine.held ? tremble : 0, y: engine.held ? -tremble * 0.6 : 0)
            .shadow(color: .black.opacity(0.38), radius: engine.PW * 0.03, y: engine.PW * 0.018)
            _ = timeline.date.timeIntervalSinceReferenceDate
        }
        .allowsHitTesting(false)
    }
}

struct StarPath: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width, h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: h * 0.08))
        p.addLine(to: CGPoint(x: w * 0.57, y: h * 0.43))
        p.addLine(to: CGPoint(x: w * 0.92, y: h * 0.5))
        p.addLine(to: CGPoint(x: w * 0.57, y: h * 0.57))
        p.addLine(to: CGPoint(x: w * 0.5, y: h * 0.92))
        p.addLine(to: CGPoint(x: w * 0.43, y: h * 0.57))
        p.addLine(to: CGPoint(x: w * 0.08, y: h * 0.5))
        p.addLine(to: CGPoint(x: w * 0.43, y: h * 0.43))
        p.closeSubpath()
        return p
    }
}

// MARK: - 通用形状/按钮

struct PolyShape: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard let first = points.first else { return p }
        p.move(to: first)
        for pt in points.dropFirst() { p.addLine(to: pt) }
        p.closeSubpath()
        return p
    }
}

struct MuteButton: View {
    @AppStorage("tarot-muted") private var muted = false

    var body: some View {
        Button {
            muted.toggle()
        } label: {
            Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.system(size: 15))
                .foregroundStyle(Color(hex: 0x141414))
                .frame(width: 40, height: 40)
                .background(Circle().fill(.white.opacity(0.9)).shadow(color: .black.opacity(0.12), radius: 6, y: 3))
        }
        .buttonStyle(PressableStyle())
    }
}

// MARK: - 卡牌视图（tarot-card-frame 逐层对应）

struct CardView: View {
    let engine: TarotEngine
    let index: Int
    var onTapped: (TarotCard, Bool, Int) -> Void

    var body: some View {
        let c = engine.cards[index]
        let p = c.p
        let cw = engine.PW * 0.84
        let ch = cw * 1.4
        let depth = p[2].x
        let persp = 1400 / max(300, 1400 - depth)
        let z = c.hover ? 90.0 : Double(3 - c.i)

        ZStack {
            // 三层纸边厚度（translateZ -1.5/-3/-4.5 的模拟）
            ForEach(0..<3, id: \.self) { k in
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(hex: 0xCDBB94))
                    .offset(y: [1.5, 3.0, 4.5][k])
            }
            .offset(y: 4.5)
            // 牌面
            cardFace(c)
            // 铭牌（跨在顶边，始终正立）
            plaque
                .position(x: cw / 2, y: -1)
        }
        .frame(width: cw, height: ch)
        .offset(x: p[0].x, y: p[1].x)
        .rotation3DEffect(.degrees(p[5].x), axis: (x: 0, y: 0, z: 1), perspective: 1400)
        .rotation3DEffect(.degrees(p[3].x), axis: (x: 1, y: 0, z: 0), perspective: 1400)
        .rotation3DEffect(.degrees(p[4].x), axis: (x: 0, y: 1, z: 0), perspective: 1400)
        .scaleEffect(p[6].x * persp)
        .position(x: engine.stageW / 2 + p[0].x, y: engine.stageH / 2 - engine.padShift + p[1].x)
        .zIndex(Int(z))
        .onTapGesture {
            if engine.state == .spread {
                onTapped(c.d, c.reversed, c.slot)
            }
        }
    }

    /// 牌面：羊皮纸物理框 + 香槟金铭牌 + 双线金边插槽（RWS 图裁白边，逆位仅插画旋转）
    private func cardFace(_ c: TarotEngine.Card) -> some View {
        let cw = engine.PW * 0.84
        let ch = cw * 1.4
        let nx = (c.hx - 50) / 50
        let ny = (50 - c.hy) / 50
        let hyp = min(1, sqrt(nx * nx + ny * ny))
        let reversed = c.reversed

        return ZStack {
            // 做旧羊皮纸：四层径向光影 + 底色
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    Color(hex: 0xF4ECD8)
                        .overlay(
                            RadialGradient(colors: [Color(hex: 0xFFFCF1).opacity(0.55), .clear], center: UnitPoint(x: 0.28, y: 0.16), startRadius: 0, endRadius: ch * 0.9)
                        )
                )
            // 内部：金色内框上方牌名 + 双线金边插槽 + 方位行
            VStack(spacing: 0) {
                Text("\(c.d.roman) · \(c.d.en.uppercased())")
                    .font(.system(size: cw * 0.047, weight: .bold, design: .serif))
                    .kerning(cw * 0.013)
                    .foregroundStyle(Color(hex: 0x4A3B26))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, cw * 0.06)
                    .padding(.top, ch * 0.05)
                ZStack {
                    // RWS 插槽（1909 扫描图裁白边）
                    GeometryReader { geo in
                        let img = RWSArt.image(for: c.d)
                        Group {
                            if let img {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .rotationEffect(.degrees(reversed ? 180 : 0))
                            } else {
                                CardArt(name: c.d.slug)
                            }
                        }
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                    }
                    // 内圈第二道细金线
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color(hex: 0xC5A059).opacity(0.55), lineWidth: 1)
                        .padding(2.5)
                }
                .frame(height: ch * 0.754)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color(hex: 0xC5A059), lineWidth: 1.5)
                )
                .shadow(color: Color(hex: 0x403018).opacity(0.2), radius: 3, y: 1)
                .padding(.top, ch * 0.018)
                Spacer(minLength: 0)
                Text(reversed ? "逆位 · REVERSED" : "正位 · UPRIGHT")
                    .font(.system(size: cw * 0.039, weight: .semibold, design: .serif))
                    .kerning(cw * 0.022)
                    .foregroundStyle(Color(reversed ? 0x8A4A33 : 0x5A4A30))
                    .padding(.bottom, ch * 0.038)
            }
            // 位置铭牌：香槟金梯形，跨在顶边
            Text(c.positionLabel)
                .font(.system(size: cw * 0.046, weight: .semibold, design: .serif))
                .kerning(cw * 0.012)
                .foregroundStyle(Color(hex: 0x33291A))
                .padding(.horizontal, cw * 0.046)
                .padding(.vertical, ch * 0.017)
                .background(
                    Trapezoid()
                        .fill(
                            LinearGradient(colors: [Color(hex: 0xF2E5C5), Color(hex: 0xDECBA4), Color(hex: 0xC8B083)], startPoint: .top, endPoint: .bottom)
                        )
                )
                .overlay(alignment: .leading) { Circle().fill(Color(hex: 0x8A744D)).frame(width: 2.2).offset(x: cw * 0.035) }
                .overlay(alignment: .trailing) { Circle().fill(Color(hex: 0x8A744D)).frame(width: 2.2).offset(x: -cw * 0.035) }
                .offset(y: -ch * 0.008)
            // 全息镭射层（colorDodge，随倾斜偏移）
            HoloRainbowLayer(px: 50 + nx * 50, py: 50 - ny * 50, hyp: hyp)
            // 眩光 + 清漆
            glareLayer(nx: nx, ny: ny, hyp: hyp, cw: cw, ch: ch)
            glazeLayer(hyp: hyp)
        }
        // 三层纸边厚度 + 投影
        .background(alignment: .bottom) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xB5A17B)).offset(y: 6)
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xCBB994)).offset(y: 4)
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: 0xDFD1B4)).offset(y: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 24)
    }

    private func glareLayer(nx: Double, ny: Double, hyp: Double, cw: Double, ch: Double) -> some View {
        ZStack {
            RadialGradient(
                colors: [.white.opacity(0.8), .white.opacity(0.12), .black.opacity(0.3)],
                center: UnitPoint(x: 50 + nx * 50, y: 50 - ny * 50),
                startRadius: 0,
                endRadius: max(cw, ch) * 0.9
            )
            .blendMode(.overlay)
            .opacity(0.25 + hyp * 0.55)
            LinearGradient(
                colors: [.clear, .clear, .white.opacity(0.4), .white.opacity(0.13), .clear, .clear, .white.opacity(0.22), .white.opacity(0.05), .clear],
                startPoint: .leading, endPoint: .trailing
            )
            .frame(width: cw * 2.2)
            .offset(x: (50 - nx * 50) / 100 * cw * 2.2 - cw * 1.1)
            .blendMode(.plusLighter)
            .opacity(0.5 + hyp * 0.3)
        }
        .allowsHitTesting(false)
    }

    private func glazeLayer(hyp: Double) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.28), lineWidth: 1)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.8), lineWidth: 1.5)
                .blendMode(.plusLighter)
                .mask(RoundedRectangle(cornerRadius: 12, style: .continuous).offset(y: 1))
            LinearGradient(colors: [.white.opacity(0.24), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.16))
        }
        .allowsHitTesting(false)
    }
}

struct Trapezoid: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + rect.width * 0.045, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.045, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// 全息镭射层：斜向彩虹 400% + colorDodge + 闪粉亮点
struct HoloRainbowLayer: View {
    var px: Double
    var py: Double
    var hyp: Double

    var body: some View {
        ZStack {
            LinearGradient(gradient: HoloAssets.rainbow, startPoint: UnitPoint(x: 0.03, y: 0.33), endPoint: UnitPoint(x: 0.97, y: 0.67))
                .frame(width: 800, height: 800)
                .offset(x: (px - 50) / 100 * 600, y: (py - 50) / 100 * 600)
                .blendMode(.colorDodge)
                .saturation(1.4)
                .brightness(-0.22)
                .opacity(0.2 + hyp * 0.05)
            GlitterLayer().opacity(hyp * 0.4)
        }
        .allowsHitTesting(false)
    }
}

struct GlitterLayer: View {
    var body: some View {
        Canvas { ctx, size in
            for _ in 0..<140 {
                let x = Double.random(in: 0..<size.width), y = Double.random(in: 0..<size.height)
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(.white))
            }
        }
        .blendMode(.plusLighter)
        .id("glitter-seed")
    }
}

// MARK: - 光流画布（35 条彩带从撕口铺向头顶）

struct FlowCanvas: View {
    let engine: TarotEngine
    let packCenter: CGPoint

    var body: some View {
        let pw = engine.PW
        let ph = engine.PH
        let rectW = pw
        let rectH = pw * 0.76
        let origin = CGPoint(x: packCenter.x - pw / 2, y: packCenter.y - ph / 2 + ph * 0.105 - pw * 0.6)
        Canvas { ctx, size in
            guard engine.flowOpacity > 0.01 else { return }
            let sx = size.width / 100
            let sy = size.height / 76
            // 每条彩带：白热根部 → 花色，沿径向渐变
            for (j, pts) in engine.flowPts.enumerated() {
                guard pts.count > 2 else { continue }
                let color = holoColor(HoloBands[(j + engine.flowColorShift) % 7])
                var path = Path()
                path.move(to: CGPoint(x: pts[0].0 * sx, y: pts[0].1 * sy))
                for pt in pts.dropFirst() { path.addLine(to: CGPoint(x: pt.0 * sx, y: pt.1 * sy)) }
                path.closeSubpath()
                let base = CGPoint(x: (engine.ribbonLines[j].gx) * sx, y: engine.flowY0 * sy)
                let tipPt = pts[pts.count / 2]
                ctx.fill(path, with: .linearGradient(
                    Gradient(colors: [Color(hex: 0xFFF7E3).opacity(0.95), color.opacity(0.92)]),
                    startPoint: base,
                    endPoint: CGPoint(x: tipPt.0 * sx, y: tipPt.1 * sy)
                ))
                ctx.stroke(path, with: .color(.white.opacity(0.28)), lineWidth: 0.6)
            }
            // 光尘
            for m in engine.flowMotes {
                let rect = CGRect(x: m.x * sx - m.r, y: m.y * sy - m.r, width: m.r * 2, height: m.r * 2)
                ctx.fill(Path(ellipseIn: rect), with: .color(.white.opacity(m.o * 0.8)))
            }
        }
        .frame(width: rectW, height: rectH)
        .position(x: origin.x + rectW / 2, y: origin.y + rectH / 2)
        .opacity(engine.flowOpacity)
        .allowsHitTesting(false)
    }

    private func holoColor(_ hex: String) -> Color {
        var v: UInt64 = 0
        let s = hex.dropFirst()
        Scanner(string: String(s)).scanHexInt64(&v)
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - 彩带纸屑画布（burst 物理 + 翻滚透视）

struct ConfettiCanvas: View {
    let engine: TarotEngine
    let size: CGSize

    var body: some View {
        Canvas { ctx, size in
            let oy = size.height * 0.4 - engine.padShift
            for b in engine.bits {
                guard !b.inside, b.age >= 0 else { continue }
                let p = 1400 / max(300, 1400 - b.z)
                let k = p * b.sc
                let cr = cos(b.r * .pi / 180)
                let sr = sin(b.r * .pi / 180)
                let cq = cos((b.r - b.rot0) * 0.7 * .pi / 180)
                let cx = size.width / 2 + b.x * p
                let cy = oy + (size.height * 0.1 + b.y) * p
                var c = ctx
                c.translateBy(x: cx, y: cy)
                c.rotate(by: .radians(b.r * .pi / 180))
                c.scaleBy(x: k, y: k * max(0.18, abs(cq)))
                switch b.kind {
                case 0:
                    c.fill(Path(ellipseIn: CGRect(x: -4.5, y: -4.5, width: 9, height: 9)), with: .color(holoColor(b.fill)))
                case 1:
                    c.fill(Path(roundedRect: CGRect(x: -3.5, y: -6, width: 7, height: 12), cornerRadius: 2), with: .color(holoColor(b.fill)))
                default:
                    c.fill(starBit, with: .color(holoColor(b.fill)))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var starBit: Path {
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
    }

    private func holoColor(_ hex: String) -> Color {
        var v: UInt64 = 0
        Scanner(string: String(hex.dropFirst())).scanHexInt64(&v)
        return Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

// MARK: - 合成音效（AVAudioEngine 移植 voices()）

final class HoloSfx {
    static let shared = HoloSfx()

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var noiseBuffer: AVAudioPCMBuffer?
    private var foilBuffer: AVAudioPCMBuffer?
    private var ripPlayer: AVAudioPlayerNode?
    private var ripGainNode: AVAudioMixerNode?
    private var started = false
    var muted: Bool = false { didSet { mixer.outputVolume = muted ? 0 : 0.8 } }

    private init() {
        noiseBuffer = Self.noiseBuffer(2.0)
        foilBuffer = Self.foilBuffer()
    }

    func unlock() {
        guard !started else {
            if !engine.isRunning { try? engine.start() }
            return
        }
        started = true
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        // 撕箔 loop：纹理 buffer → 增益（音量随撕速调制）
        let player = AVAudioPlayerNode()
        let gain = AVAudioMixerNode()
        engine.attach(player)
        engine.attach(gain)
        if let foilBuffer, let fmt = foilBuffer.format as AVAudioFormat? {
            engine.connect(player, to: gain, format: fmt)
            engine.connect(gain, to: mixer, format: fmt)
            player.scheduleBuffer(foilBuffer, at: nil, options: .loops)
            player.play()
        }
        ripPlayer = player
        ripGainNode = gain
        gain.volume = 0
        mixer.outputVolume = muted ? 0 : 0.8
        if !engine.isRunning { try? engine.start() }
    }

    private func play(_ buffer: AVAudioPCMBuffer, pan: Float = 0) {
        unlock()
        guard engine.isRunning else { return }
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: mixer, format: buffer.format)
        player.pan = pan
        player.scheduleBuffer(buffer, at: nil)
        player.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + buffer.duration + 0.1) {
            player.stop()
            engine.detach(player)
        }
    }

    // MARK: 各提示音（离线渲染 PCM）

    func grab() { play(Self.renderAir(from: 3000, to: 2200, q: 0.7, gain: 0.3, attack: 0.003, dur: 0.09, send: 0)) }
    func eep() { play(Self.renderCoo(freq: 1250, shape: [(0, 0.82), (0.05, 1.25), (0.13, 1.02)], gain: 0.05, wobble: 0.04, dur: 0.2)) }
    func phew() {
        play(Self.renderCoo(freq: 900, shape: [(0, 1.1), (0.24, 0.6)], gain: 0.05, dur: 0.32))
        play(Self.renderAir(from: 1500, to: 700, q: 0.6, gain: 0.03, attack: 0.02, dur: 0.26, send: 0))
    }
    func boing() { play(Self.renderCoo(freq: 340, shape: [(0, 0.8), (0.05, 1.6), (0.12, 0.85), (0.2, 1.25), (0.3, 1)], gain: 0.12, dur: 0.4)) }
    func pop(_ withSparkle: Bool) {
        play(Self.renderAir(from: 5000, to: 1800, q: 0.9, gain: 0.14, attack: 0.002, dur: 0.1, send: 0))
        play(Self.renderCoo(freq: 300, shape: [(0, 0.8), (0.05, 3.4)], gain: 0.3, dur: 0.3))
        guard withSparkle else { return }
        for i in 0..<3 {
            let note = Self.note(8 + Int.random(in: 0...4))
            let buf = Self.renderChime(freq: note, gain: 0.018 * Double.random(in: 0.6...1.4), dur: 0.35)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12 + Double(i) * 0.07) { [weak self] in
                self?.play(buf, pan: Float.random(in: -0.7...0.7))
            }
        }
    }
    func swirl(_ dur: Double) { play(Self.renderAir(from: 700, to: 1800, q: 0.9, gain: 0.12, attack: dur * 0.4, dur: dur, send: 0, panSweep: true)) }
    func land(_ kind: String, slot: Int) {
        play(Self.renderAir(from: 2600, to: 1300, q: 0.6, gain: 0.07, attack: 0.002, dur: 0.05, send: 0))
        if kind == "major" {
            play(Self.renderCoo(freq: 659, shape: [(0, 0.94), (0.035, 1)], gain: 0.04, dur: 0.15, pan: Float(slot - 1) * 0.18))
        }
    }
    func lift(_ slot: Int) {
        let pan = Float(slot - 1) * 0.18
        play(Self.renderAirLow(from: 760, to: 480, q: 0.3, gain: 0.045, dur: 0.22, pan: pan))
    }
    func tick() { play(Self.renderCoo(freq: 880, shape: [(0, 0.9), (0.05, 1.12)], gain: 0.04, dur: 0.12, send: 0)) }
    func arrive() {
        play(Self.renderAir(from: 900, to: 2600, q: 1, gain: 0.06, attack: 0.3, dur: 0.75, send: 0, pan: [0.7, 0]))
        play(Self.renderAir(from: 3000, to: 2200, q: 0.7, gain: 0.16, attack: 0.003, dur: 0.09, send: 0))
    }

    /// 撕箔 loop 音量随撕速变化（rip(level)）
    func rip(speed: Double) {
        let v = Float(clamp2(speed, 0, 1))
        ripGainNode?.volume = pow(v, 0.8) * 0.15
    }

    private func clamp2(_ v: Double, _ a: Double, _ b: Double) -> Double { min(b, max(a, v)) }

    // MARK: 离线渲染（噪声 + 状态变量滤波 + 包络）

    private static func pcmBuffer(_ left: [Float], _ right: [Float]) -> AVAudioPCMBuffer? {
        guard !left.isEmpty else { return nil }
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(left.count)) else { return nil }
        buf.frameLength = AVAudioFrameCount(left.count)
        for i in 0..<left.count {
            buf.floatChannelData![0][i] = left[i]
            buf.floatChannelData![1][i] = right[i]
        }
        return buf
    }

    private static func noiseBuffer(_ dur: Double) -> AVAudioPCMBuffer? {
        let n = Int(44100 * dur)
        var l = [Float](repeating: 0, count: n), r = l
        for i in 0..<n { l[i] = Float.random(in: -1...1); r[i] = l[i] }
        return pcmBuffer(l, r)
    }

    /// 撕箔纹理：900 个随机衰减咔哒（近原版 foil buffer）
    private static func foilBuffer() -> AVAudioPCMBuffer? {
        let n = 44100 * 2
        var l = [Float](repeating: 0, count: n)
        for _ in 0..<900 {
            let start = Int.random(in: 0..<(n - 400))
            let amp = Float(pow(Double.random(in: 0...1), 3)) * (Bool.random() ? 1 : -1)
            let len = 30 + Int.random(in: 0...260)
            for i in 0..<len where start + i < n {
                l[start + i] += amp * Float.random(in: -1...1) * Float(exp(-Double(i) / Double(len) * 5))
            }
        }
        return pcmBuffer(l, l)
    }

    /// air：噪声 → SVF 带通扫频 → 包络（bell 可选）
    private static func renderAir(from: Double, to: Double, q: Double, gain: Double, attack: Double, dur: Double, send: Double, panSweep: Bool = false, pan: [Double]? = nil) -> AVAudioPCMBuffer? {
        let n = Int(44100 * dur) + 64
        var l = [Float](repeating: 0, count: n), r = l
        var low = 0.0, band = 0.0, high = 0.0
        let f0 = min(from, to), f1 = max(from, to)
        for i in 0..<n {
            let t = Double(i) / 44100
            let k = min(1, t / max(0.001, dur))
            let cutoff = from + (to - from) * k
            let white = Double.random(in: -1...1)
            let fClamp = min(8000, max(80, cutoff))
            let fsin = 2 * sin(.pi * fClamp / 44100)
            band += fsin * (white - low - q * band)
            low += fsin * band
            high = white - low - q * band
            let env = attack > 0
                ? (t < attack ? t / attack : exp(-(t - attack) * 5 / max(0.05, dur - attack)))
                : exp(-t * 8)
            let bellEnv = sin(.pi * min(1, t / dur))
            let v = band * env * gain
            let panV = panSweep ? cos((1 - k) * .pi) : (pan?.first ?? 0)
            let panR = panSweep ? sin((1 - k) * .pi) : ((pan?.count ?? 0) > 1 ? pan![1] : (pan?.first ?? 0))
            l[i] = Float(v * (1 - max(0, panV)))
            r[i] = Float(v * (1 - max(0, -panR)))
            _ = bellEnv
        }
        return pcmBuffer(l, r)
    }

    private static func renderAirLow(from: Double, to: Double, q: Double, gain: Double, dur: Double, pan: Float) -> AVAudioPCMBuffer? {
        let n = Int(44100 * dur) + 64
        var l = [Float](repeating: 0, count: n), r = l
        var low = 0.0, band = 0.0
        for i in 0..<n {
            let t = Double(i) / 44100
            let cutoff = from + (to - from) * (t / dur)
            let white = Double.random(in: -1...1)
            let fsin = 2 * sin(.pi * min(8000, max(80, cutoff)) / 44100)
            band += fsin * (white - low - q * band)
            low += fsin * band
            let env = sin(.pi * min(1, t / dur))
            let v = low * env * gain
            l[i] = Float(v * (1 - Double(pan) * 0.5 + 0.5 * 0))
            r[i] = Float(v * (1 + Double(pan) * 0.5))
        }
        return pcmBuffer(l, r)
    }

    /// chime：玻璃钟琴（基音 + 两个泛音）
    private static func renderChime(freq: Double, gain: Double, dur: Double) -> AVAudioPCMBuffer? {
        let n = Int(44100 * dur) + 64
        var l = [Float](repeating: 0, count: n), r = l
        for i in 0..<n {
            let t = Double(i) / 44100
            var v = 0.0
            for (ratio, level, life) in [(1.0, 1.0, 1.0), (3.9, 0.18, 0.22), (9.2, 0.05, 0.08)] {
                let d = max(0.03, dur * life)
                v += sin(2 * .pi * freq * ratio * t) * level * exp(-t / d * 4)
            }
            l[i] = Float(v * gain)
            r[i] = l[i]
        }
        return pcmBuffer(l, r)
    }

    /// coo：小音符（频率曲线 + 颤音）
    private static func renderCoo(freq: Double, shape: [(Double, Double)], gain: Double, dur: Double, wobble: Double = 0, pan: Float = 0, send: Double = 0) -> AVAudioPCMBuffer? {
        let n = Int(44100 * dur) + 64
        var l = [Float](repeating: 0, count: n), r = l
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / 44100
            var mult = shape.first?.1 ?? 1
            for (s, m) in shape where s > 0 && t >= s { mult = m }
            let wob = wobble > 0 ? sin(2 * .pi * 24 * t) * wobble : 0
            phase += 2 * .pi * freq * (mult + wob) / 44100
            let env = min(1, t / 0.008) * exp(-max(0, t - 0.01) * 3 / max(0.1, dur))
            let v = sin(phase) * env * gain
            l[i] = Float(v * (1 - Double(pan) * 0.5))
            r[i] = Float(v * (1 + Double(pan) * 0.5))
        }
        return pcmBuffer(l, r)
    }

    private static func note(_ i: Int) -> Double {
        440 * pow(2, (72 + 12 * (i / 5) + [0, 2, 4, 7, 9][i % 5] - 69) / 12)
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
                    RWSArtView(card: card)
                        .frame(width: 210, height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(card.name).font(.system(size: 21, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text(card.en).font(.system(size: 12, design: .serif))
                            .foregroundStyle(Theme.textTertiary)
                    }

                    Text("\(card.positionText(reversed: isReversed)) · \(card.roman)")
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

/// RWS 公版图视图（RWSCards/ 内置扫描图）
struct RWSArtView: View {
    let card: TarotCard

    var body: some View {
        Group {
            if let img = RWSArt.file(card.rwsFile) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                CardArt(name: card.slug)
            }
        }
    }
}

// MARK: - RWS 公版图加载（RWSCards/ 文件夹引用，78 张全套随包内置）

enum RWSArt {
    private static var cache: [Int: UIImage] = [:]

    static func major(_ index: Int) -> UIImage? {
        let clamped = max(0, min(21, index))
        if let hit = cache[clamped] { return hit }
        let name = String(format: "major-%02d", clamped)
        guard let img = file(name + ".jpg") else {
            AppLog.warn("RWS 图缺失：\(name)")
            return nil
        }
        cache[clamped] = img
        return img
    }

    static func file(_ name: String) -> UIImage? {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.main.url(forResource: base, withExtension: ext, subdirectory: "RWSCards"),
              let img = UIImage(contentsOfFile: url.path) else { return nil }
        return img
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
            if loaded == nil, name.contains("-"), let first = name.split(separator: "-").first {
                // 大牌兼容：RWS 扫描图（RWSCards/）
                if let idx = Int(first), let url = Bundle.main.url(forResource: String(format: "maj-%02d", idx), withExtension: "jpg", subdirectory: "RWSCards"),
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


