// Web Audio 合成音效：全部运行时生成，无音频素材文件，file:// 协议下可用。
// iOS/WebKit 要求 AudioContext 在用户手势后 resume —— 首次 pointerdown 时调用 ensure()。
export class Sfx {
  constructor() {
    this.ctx = null
    this._noiseCache = {}
    this._unlocked = false
  }

  ensure() {
    if (!this.ctx) {
      const AC = window.AudioContext || window.webkitAudioContext
      if (!AC) return null
      try { this.ctx = new AC({ latencyHint: 'interactive' }) } catch { return null }
    }
    if (this.ctx.state === 'suspended') this.ctx.resume().catch(() => {})
    return this.ctx
  }

  unlock() {
    this._unlocked = true
    this.ensure()
  }

  noise(duration = 1) {
    const ctx = this.ensure()
    if (!ctx) return null
    const key = Math.round(duration * 10)
    if (!this._noiseCache[key]) {
      const buf = ctx.createBuffer(1, Math.floor(ctx.sampleRate * duration), ctx.sampleRate)
      const d = buf.getChannelData(0)
      for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1
      this._noiseCache[key] = buf
    }
    return this._noiseCache[key]
  }

  // 撕箔：带通噪声扫频 + 随机"折痕断裂"脆响簇
  tear() {
    const ctx = this.ensure()
    if (!ctx) return
    const t = ctx.currentTime
    const src = ctx.createBufferSource()
    src.buffer = this.noise(0.4)
    const bp = ctx.createBiquadFilter()
    bp.type = 'bandpass'
    bp.Q.value = 0.8
    bp.frequency.setValueAtTime(1600, t)
    bp.frequency.exponentialRampToValueAtTime(3600, t + 0.25)
    const g = ctx.createGain()
    g.gain.setValueAtTime(0.0001, t)
    g.gain.exponentialRampToValueAtTime(0.42, t + 0.02)
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.3)
    src.connect(bp).connect(g).connect(ctx.destination)
    src.start(t)
    src.stop(t + 0.32)
    for (let n = 0; n < 7; n++) {
      const at = t + Math.random() * 0.24
      const s2 = ctx.createBufferSource()
      s2.buffer = this.noise(0.4)
      const hp = ctx.createBiquadFilter()
      hp.type = 'highpass'
      hp.frequency.value = 2400 + Math.random() * 2200
      const g2 = ctx.createGain()
      g2.gain.setValueAtTime(0.0001, at)
      g2.gain.exponentialRampToValueAtTime(0.22 + Math.random() * 0.28, at + 0.004)
      g2.gain.exponentialRampToValueAtTime(0.0001, at + 0.05)
      s2.connect(hp).connect(g2).connect(ctx.destination)
      s2.start(at)
      s2.stop(at + 0.06)
    }
  }

  // 锯齿微震提示音（与触感震动同步的短促 tick）
  tick() {
    const ctx = this.ensure()
    if (!ctx) return
    const t = ctx.currentTime
    const o = ctx.createOscillator()
    o.type = 'square'
    o.frequency.value = 1500 + Math.random() * 300
    const g = ctx.createGain()
    g.gain.setValueAtTime(0.0001, t)
    g.gain.exponentialRampToValueAtTime(0.05, t + 0.004)
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.035)
    o.connect(g).connect(ctx.destination)
    o.start(t)
    o.stop(t + 0.04)
  }

  // 纸张摩擦（选牌）
  rub() {
    const ctx = this.ensure()
    if (!ctx) return
    const t = ctx.currentTime
    const src = ctx.createBufferSource()
    src.buffer = this.noise(0.5)
    const lp = ctx.createBiquadFilter()
    lp.type = 'lowpass'
    lp.frequency.value = 900
    const g = ctx.createGain()
    g.gain.setValueAtTime(0.0001, t)
    g.gain.linearRampToValueAtTime(0.16, t + 0.08)
    g.gain.linearRampToValueAtTime(0.0001, t + 0.42)
    src.connect(lp).connect(g).connect(ctx.destination)
    src.start(t)
    src.stop(t + 0.44)
  }

  // 翻牌：噪声扫频上扬
  flip() {
    const ctx = this.ensure()
    if (!ctx) return
    const t = ctx.currentTime
    const src = ctx.createBufferSource()
    src.buffer = this.noise(0.4)
    const bp = ctx.createBiquadFilter()
    bp.type = 'bandpass'
    bp.Q.value = 1.1
    bp.frequency.setValueAtTime(500, t)
    bp.frequency.exponentialRampToValueAtTime(2400, t + 0.22)
    const g = ctx.createGain()
    g.gain.setValueAtTime(0.0001, t)
    g.gain.exponentialRampToValueAtTime(0.2, t + 0.03)
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.26)
    src.connect(bp).connect(g).connect(ctx.destination)
    src.start(t)
    src.stop(t + 0.28)
  }

  // 揭晓小钟琴（主牌过 90°）
  chime() {
    const ctx = this.ensure()
    if (!ctx) return
    const t = ctx.currentTime
    const partials = [[1, 0.10, 0.6], [3.9, 0.03, 0.2], [9.2, 0.012, 0.08]]
    for (const [ratio, level, dur] of partials) {
      const o = ctx.createOscillator()
      o.type = 'sine'
      o.frequency.value = 659 * ratio
      const g = ctx.createGain()
      g.gain.setValueAtTime(0.0001, t)
      g.gain.exponentialRampToValueAtTime(level, t + 0.006)
      g.gain.exponentialRampToValueAtTime(0.0001, t + dur)
      o.connect(g).connect(ctx.destination)
      o.start(t)
      o.stop(t + dur + 0.02)
    }
  }
}
