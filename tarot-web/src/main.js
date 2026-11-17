import './style.css'
import { deck, POSITION_LABELS } from './deck.js'
import { Sfx } from './audio.js'

const app = document.getElementById('app')
const sfx = new Sfx()

const clamp = (v, a, b) => Math.min(b, Math.max(a, v))
const TEAR_RATIO = 0.358          // 撕口位置（占卡包高度比例），与素材撕裂线一致
const FAN_COUNT = 14              // 牌扇张数
const ARC_FROM = 110              // 弧起点（度）
const ARC_TO = 250                // 弧终点（度）

// 嵌入 WKWebView 时走原生桥接；独立预览时回退到页内详情弹层
const embedded = typeof window !== 'undefined' &&
  !!(window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tarotCardTapped)

// 原生端在 documentStart 注入启动态：{ opened, spread: [{id, reversed} × 3] }
const BOOT = typeof window !== 'undefined' ? (window.__TAROT_BOOT__ || null) : null

// ---------- 缓动 ----------
const easeOutCubic = k => 1 - Math.pow(1 - k, 3)
const easeInOutCubic = k => (k < 0.5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2)
const easeOutBack = k => { const c = 1.9; return 1 + (c + 1) * Math.pow(k - 1, 3) + c * Math.pow(k - 1, 2) }

function animate(from, to, dur, ease, onFrame, onDone) {
  const t0 = performance.now()
  function frame(now) {
    const k = clamp((now - t0) / dur, 0, 1)
    onFrame(from + (to - from) * ease(k))
    if (k < 1) requestAnimationFrame(frame)
    else if (onDone) onDone()
  }
  requestAnimationFrame(frame)
}

function shuffle(a) {
  for (let i = a.length - 1; i > 0; i--) {
    const j = (Math.random() * (i + 1)) | 0
    const t = a[i]; a[i] = a[j]; a[j] = t
  }
  return a
}

// 每次装包随机生成撕裂线：斜率 + 弓形 + 随机游走 + 锯齿（与原生端同源）
function makeJag(n = 56) {
  const a = []
  let walk = 0
  const slope = Math.random() * 5 - 2.5
  const bow = Math.random() * 3 - 1.5
  for (let i = 0; i <= n; i++) {
    const s = (i / n) * 2 - 1
    walk = clamp(walk + (Math.random() * 0.7 - 0.35) + (Math.random() < 0.5 ? 0.45 : -0.45), -1.2, 1.2)
    const tooth = Math.random() < 0.5 ? 0.4 : -0.4
    a.push((slope * s + bow * (1 - s * s) + walk + tooth) / 100)
  }
  return a
}

function el(tag, cls, html) {
  const e = document.createElement(tag)
  if (cls) e.className = cls
  if (html != null) e.innerHTML = html
  return e
}

function freshState() {
  return {
    phase: 'sealed',
    jag: makeJag(),
    progress: 0,
    tearStarted: false,
    acc: 0,
    pool: [],
    poolReversed: [],
    selected: [],
    picks: null,
    revealedCount: 0,
    flipState: {},
    bloomed: false,
    slotViews: [],
    cardEls: []
  }
}

let S = freshState()

function render() {
  window.removeEventListener('resize', onResize)
  app.innerHTML = ''
  if (S.phase === 'sealed') renderSealed()
  else if (S.phase === 'fan') {
    renderFan()
    window.addEventListener('resize', onResize)
  } else renderSpread()
}

function onResize() { if (S.phase === 'fan') renderFan() }

// ============================================================
// 阶段一/二：sealed + tearing（密封卡包 · 沿虚线右向撕开）
// ============================================================

function renderSealed() {
  const scene = el('div', 'scene sealed')
  scene.innerHTML = `
    <div class="hud"><div class="hint">👆 沿虚线向右撕开</div></div>
    <div class="pack-stage">
      <div class="pack-glow"></div>
      <div class="pack-body"><div class="metal"></div></div>
      <div class="strip"></div>
      <div class="tear-zone"></div>
      <div class="fp-guide">
        <i class="ring"></i>
        <svg viewBox="0 0 24 24" fill="none" stroke="#D4AF37" stroke-width="1.6" stroke-linecap="round">
          <path d="M12 4c4.4 0 8 3.6 8 8 0 2.4-.9 4.3-2.2 5.7"/>
          <path d="M12 7.5c2.5 0 4.5 2 4.5 4.5 0 1.8-.6 3.1-1.5 4.1"/>
          <path d="M12 11c.6 0 1 .4 1 1 0 1.5-.4 2.7-1.1 3.6"/>
          <path d="M7.6 8.2C8.4 6.8 9.6 5.8 11 5.4"/>
          <path d="M5.8 10.4c.3-1.5 1-2.8 1.9-3.8"/>
          <path d="M5.6 13.6c.1-1 .3-2 .7-2.9"/>
          <path d="M6.4 16.8c-.4-.9-.7-2-.8-3"/>
          <path d="M9 19.6c-1.1-1.1-2-2.5-2.4-4"/>
        </svg>
        <i class="dot"></i><i class="dot"></i><i class="dot"></i>
      </div>
    </div>
    <div class="caption">今日牌阵已备好，撕开后从牌扇中选取 3 张</div>`
  app.appendChild(scene)

  const zone = scene.querySelector('.tear-zone')
  const stage = scene.querySelector('.pack-stage')
  let dragging = false
  let startX = 0, startY = 0

  zone.addEventListener('pointerdown', e => {
    dragging = true
    startX = e.clientX
    startY = e.clientY
    sfx.unlock()
    zone.setPointerCapture(e.pointerId)
  })

  zone.addEventListener('pointermove', e => {
    if (!dragging || S.phase === 'tearing-done') return
    const dx = e.clientX - startX
    const dy = e.clientY - startY
    // 3D 倾斜反馈（同时驱动金属高光偏移）
    stage.style.setProperty('--ptx', `${clamp(dx * 0.07, -10, 10)}deg`)
    stage.style.setProperty('--pty', `${clamp(-dy * 0.05, -8, 8)}deg`)
    stage.style.setProperty('--mx', `${clamp(dx * 0.12, -16, 16)}px`)
    stage.style.setProperty('--my', `${clamp(dy * 0.10, -12, 12)}px`)
    // 指纹引导消失触发点：手指按上虚线并开始拖动（dx > 2）
    if (!S.tearStarted && dx > 2) {
      S.tearStarted = true
      scene.querySelector('.fp-guide').classList.add('gone')
      scene.querySelector('.hint').classList.add('gone')
    }
    // 仅响应横向向右
    if (dx <= 0) return
    const packW = stage.clientWidth
    const p = clamp(dx / (packW * 0.85), 0, 1)
    if (p > S.progress) {
      S.acc += (p - S.progress) * packW * 0.85
      while (S.acc >= 10) {
        S.acc -= 10
        sfx.tick()
        sfx.tear()
        if (navigator.vibrate) navigator.vibrate(7)
      }
      S.progress = p
      applyTear(scene)
    }
  })

  const release = () => {
    if (!dragging) return
    dragging = false
    stage.style.setProperty('--ptx', '0deg')
    stage.style.setProperty('--pty', '0deg')
    if (S.progress >= 0.72) finishTear(scene)
    else rebound(scene)
  }
  zone.addEventListener('pointerup', release)
  zone.addEventListener('pointercancel', release)

  applyTear(scene)
}

// 撕裂裁切：前沿左侧逐段揭开（动态 clip-path 多边形）
function bodyClip(p) {
  const cut = TEAR_RATIO * 100
  const amp = Math.min(1, p * 4)
  const n = S.jag.length - 1
  const pts = [[0, cut]]
  for (let i = 0; i <= n; i++) pts.push([(i / n) * p * 100, cut + S.jag[i] * 100 * amp])
  pts.push([p * 100, cut], [p * 100, 0], [100, 0], [100, 100], [0, 100])
  return `polygon(${pts.map(pt => `${pt[0].toFixed(2)}% ${pt[1].toFixed(2)}%`).join(',')})`
}

function stripClip(p) {
  const cut = TEAR_RATIO * 100
  const amp = Math.min(1, p * 4)
  const n = S.jag.length - 1
  const pts = [[0, 0], [p * 100, 0], [p * 100, cut]]
  for (let i = n; i >= 0; i--) pts.push([(i / n) * p * 100, cut + S.jag[i] * 100 * amp])
  return `polygon(${pts.map(pt => `${pt[0].toFixed(2)}% ${pt[1].toFixed(2)}%`).join(',')})`
}

function applyTear(scene) {
  const p = clamp(S.progress, 0, 1)
  const body = scene.querySelector('.pack-body')
  const strip = scene.querySelector('.strip')
  if (!body || !strip) return
  body.style.clipPath = bodyClip(p)
  strip.style.clipPath = stripClip(p)
  // 撕条以前沿为轴局部上翘（禁止整条僵硬平移）
  strip.style.transformOrigin = `${(p * 100).toFixed(2)}% ${(TEAR_RATIO * 100).toFixed(2)}%`
  strip.style.transform = `rotate(${(-p * 14).toFixed(2)}deg)`
  const hint = scene.querySelector('.hint')
  if (hint) hint.style.opacity = String(clamp(1 - p * 4, 0, 1))
}

// 未撕到底：弹簧弹回原位，绝不强行开包
function rebound(scene) {
  animate(S.progress, 0, 340, easeOutBack, v => {
    S.progress = clamp(v, 0, 1)
    applyTear(scene)
  }, () => {
    S.progress = 0
    S.tearStarted = false
    S.phase = 'sealed'
    applyTear(scene)
  })
}

// 撕到底：撕条 0.3s 向右上抛飞渐隐，卡包原地微缩淡出，牌扇同帧弹开
function finishTear(scene) {
  S.phase = 'tearing'
  scene.querySelector('.fp-guide').classList.add('gone')
  scene.querySelector('.caption').classList.add('gone')
  animate(S.progress, 1, 150, easeOutCubic, v => {
    S.progress = v
    applyTear(scene)
  }, () => {
    const strip = scene.querySelector('.strip')
    strip.classList.add('fly')
    strip.style.transform = 'translate(300px, -230px) rotate(11deg)'
    strip.style.opacity = '0'
    scene.querySelector('.pack-body').classList.add('exit')
    sfx.flip()
    setTimeout(() => {
      S.phase = 'fan'
      // 牌扇从 22 张大牌中洗牌取 14 张（与原生 DailyTarot 契约对齐，首页小卡可映射）
      S.pool = shuffle(deck.filter(c => c.suit === 'major').map(c => c.id)).slice(0, FAN_COUNT)
      S.poolReversed = S.pool.map(() => Math.random() < 0.5)
      S.selected = []
      S.bloomed = false
      render()
    }, 470)
  })
}

// ============================================================
// 阶段三：fanSelection（右侧固定 40% 弧形厚卡扇）
// ============================================================

function renderFan() {
  const scene = el('div', 'scene fan')
  scene.innerHTML = `
    <div class="hud">
      <div class="segs">${'<i></i>'.repeat(3)}</div>
      <div class="guide">请从牌扇中选取 3 张牌 (0/3)</div>
    </div>
    <div class="fan-stage"></div>`
  app.appendChild(scene)
  layoutFan(scene)

  // 从卡包中心错峰弹开成弧
  clearTimeout(S.bloomTimer)
  S.bloomTimer = setTimeout(() => {
    S.bloomed = true
    S.slotViews.forEach(v => {
      setArcTransform(v.card, v.x, v.y, v.deg, false)
      v.card.style.opacity = '1'
    })
    setTimeout(() => {
      S.slotViews.forEach(v => { v.card.style.transitionDelay = '0s' })
    }, 1100)
  }, 80)
}

function layoutFan(scene) {
  const stage = scene.querySelector('.fan-stage')
  S.stage = stage
  const w = stage.clientWidth
  const h = stage.clientHeight
  // 虚拟圆心：屏幕右侧外偏上；半径 0.64w；110°~250° 约 40% 圆周等分 14 张
  const cx = w * 1.12
  const cy = h * 0.40
  const R = w * 0.64
  const restX = w * 0.5
  const restY = h * 0.42

  stage.innerHTML = ''
  S.slotViews = S.pool.map((cardIdx, slot) => {
    const deg = ARC_FROM + slot * ((ARC_TO - ARC_FROM) / (FAN_COUNT - 1))
    const rad = deg * Math.PI / 180
    const ux = Math.cos(rad)
    const uy = Math.sin(rad)
    const x = cx + R * ux
    const y = cy + R * uy

    const card = el('div', 'fan-card')
    card.innerHTML = '<i class="edge e3"></i><i class="edge e2"></i><i class="edge e1"></i><i class="back"></i>'
    if (!S.bloomed) {
      // 叠合在卡包中心
      card.style.transform = `perspective(600px) translate(${restX - 33}px, ${restY - 49.5}px) rotate(0deg) scale(0.55)`
      card.style.opacity = '0'
    } else {
      setArcTransform(card, x, y, deg, true)
      card.style.opacity = '1'
    }
    // 弧线中部 zIndex 最高，扇面重叠自然；选中牌置顶
    const midCloseness = 14 - Math.abs(slot - 7) - Math.abs(slot - 6)
    card.style.zIndex = String(midCloseness + (S.selected.includes(slot) ? 30 : 0))
    card.style.transitionDelay = `${slot * 0.03}s`

    // 微物理反馈：按住微弱 3D 倾斜，松手弹簧回弹；轻点选中
    let sx = 0, sy = 0, moved = false
    card.addEventListener('pointerdown', e => {
      sx = e.clientX
      sy = e.clientY
      moved = false
      sfx.unlock()
      card.setPointerCapture(e.pointerId)
    })
    card.addEventListener('pointermove', e => {
      const dx = e.clientX - sx
      const dy = e.clientY - sy
      if (Math.abs(dx) + Math.abs(dy) > 6) moved = true
      card.style.setProperty('--frx', `${clamp(-dy * 0.14, -7, 7)}deg`)
      card.style.setProperty('--fry', `${clamp(dx * 0.14, -7, 7)}deg`)
    })
    card.addEventListener('pointerup', () => {
      card.style.setProperty('--frx', '0deg')
      card.style.setProperty('--fry', '0deg')
      if (!moved) selectSlot(slot, card)
    })
    card.addEventListener('pointercancel', () => {
      card.style.setProperty('--frx', '0deg')
      card.style.setProperty('--fry', '0deg')
    })

    stage.appendChild(card)
    return { slot, card, x, y, ux, uy, deg }
  })
  updateHUD()
}

// 卡片定位：translate 到弧上坐标（中心对齐）+ 径向旋转（rotation = θ + 90°，中部水平横放）
function setArcTransform(card, x, y, deg, withTilt = true) {
  const tilt = withTilt ? ' rotateX(var(--frx, 0deg)) rotateY(var(--fry, 0deg))' : ''
  card.style.transform = `perspective(600px) translate(${(x - 33).toFixed(1)}px, ${(y - 49.5).toFixed(1)}px) rotate(${(deg + 90).toFixed(1)}deg)${tilt}`
}

function selectSlot(slot, card) {
  if (S.phase !== 'fan' || S.selected.length >= 3 || S.selected.includes(slot)) return
  S.selected.push(slot)
  sfx.select()
  sfx.rub()
  if (navigator.vibrate) navigator.vibrate(10)
  const v = S.slotViews[slot]
  // 沿自身放射角度向外弹出 30pt
  setArcTransform(v.card, v.x + v.ux * 30, v.y + v.uy * 30, v.deg, false)
  v.card.classList.add('sel')
  v.card.style.zIndex = '40'
  updateHUD()
  if (S.selected.length === 3) {
    S.phase = 'spreading'
    // 第 1 张 → 过去·PAST（上位核心），第 2 张 → 现在·PRESENT，第 3 张 → 未来·FUTURE
    S.picks = S.selected.map((s, i) => {
      const c = deck.find(d => d.id === S.pool[s])
      const reversed = S.poolReversed[s]
      return {
        card: c,
        reversed,
        positionLabel: POSITION_LABELS[i],
        keywords: reversed ? c.keywordsRev : c.keywordsUp,
        meaning: reversed ? c.meaningRev : c.meaningUp
      }
    })
    // ★ 选满 3 张即提交原生持久化（选牌即落库，翻牌动画不影响数据）
    const bridge = window.webkit && window.webkit.messageHandlers
    if (bridge && bridge.tarotSpreadCommitted) {
      bridge.tarotSpreadCommitted.postMessage({
        core: S.picks[0].card.id,
        present: S.picks[1].card.id,
        future: S.picks[2].card.id,
        reversedCore: S.picks[0].reversed,
        reversedPresent: S.picks[1].reversed,
        reversedFuture: S.picks[2].reversed
      })
    }
    setTimeout(() => render(), 620)
  }
}

function updateHUD() {
  const scene = app.querySelector('.fan')
  if (!scene) return
  scene.querySelectorAll('.segs i').forEach((seg, i) => {
    seg.classList.toggle('on', i < S.selected.length)
  })
  const n = S.selected.length
  scene.querySelector('.guide').textContent =
    n >= 3 ? '牌阵已集齐，正在展开…' : `请从牌扇中选取 3 张牌 (${n}/3)`
}

// ============================================================
// 阶段四：spreadRevealed（上排三联 · 2.5D 羊皮纸物理牌框）
// ============================================================

function renderSpread() {
  const scene = el('div', 'scene spread')
  scene.innerHTML = `
    <div class="spread-head">
      <div>
        <div class="title">塔罗</div>
        <div class="sub">每日三牌阵 · ${new Date().toLocaleDateString('zh-CN', { month: 'long', day: 'numeric' })}</div>
      </div>
    </div>
    <div class="spread-row"></div>
    <div class="spread-actions">
      <button class="btn" id="flip-all">全部翻开</button>
      <button class="btn ghost" id="redraw">重新抽牌</button>
    </div>`
  app.appendChild(scene)

  const row = scene.querySelector('.spread-row')
  const preRevealed = S.revealedCount >= 3
  S.cardEls = S.picks.map((pick, i) => {
    const frame = el('div', 'card-frame')
    frame.innerHTML = `
      <div class="plaque">${pick.positionLabel}</div>
      <div class="card-title pending">· · ·</div>
      <div class="slot"><div class="slot-inner">
        <div class="slot-face back-face"></div>
        <div class="slot-face front-face"><img ${pick.reversed ? 'class="reversed" ' : ''}src="${pick.card.image}" alt="${pick.card.nameEn}"></div>
      </div></div>
      <div class="holo"></div>
      <div class="card-caption">
        <span class="zh-name">${pick.card.nameZh}</span><span class="rev-tag">${pick.reversed ? '逆位' : '正位'}</span>
        <div class="kw">${pick.keywords.join(' · ')}</div>
      </div>`
    // 从牌扇侧飞入
    frame.style.setProperty('--tx', '90px')
    frame.style.setProperty('--fs', '0.72')
    frame.style.opacity = '0'
    row.appendChild(frame)
    setTimeout(() => {
      frame.style.setProperty('--tx', '0px')
      frame.style.setProperty('--fs', '1')
      frame.style.opacity = '1'
    }, 90 + i * 80)

    // 启动态（当日已抽）：直接呈现翻开的牌面
    if (preRevealed) {
      frame.classList.add('revealed')
      fillTitle(frame, pick)
      frame.querySelector('.slot-inner').style.transform = 'rotateY(180deg)'
      frame.style.setProperty('--lift', '1')
    }

    bindFrame(frame, pick, i)
    return frame
  })

  scene.querySelector('#flip-all').addEventListener('click', () => {
    scene.querySelector('#flip-all').classList.add('hidden')
    S.cardEls.forEach((f, i) => setTimeout(() => startFlip(i), i * 200))
  })
  scene.querySelector('#redraw').addEventListener('click', redraw)
}

function bindFrame(frame, pick, i) {
  // 手势倾斜 → 驱动全息镭射层偏移（--hx/--hy）与卡框 3D 微倾
  frame.addEventListener('pointermove', e => {
    const r = frame.getBoundingClientRect()
    const nx = (e.clientX - r.left) / r.width - 0.5
    const ny = (e.clientY - r.top) / r.height - 0.5
    frame.style.setProperty('--fry', `${clamp(nx * 16, -8, 8)}deg`)
    frame.style.setProperty('--frx', `${clamp(-ny * 14, -8, 8)}deg`)
    frame.style.setProperty('--hx', `${50 + nx * 90}%`)
    frame.style.setProperty('--hy', `${50 - ny * 90}%`)
  })
  frame.addEventListener('pointerleave', () => {
    frame.style.setProperty('--frx', '0deg')
    frame.style.setProperty('--fry', '0deg')
  })
  frame.addEventListener('click', () => {
    const st = S.flipState[i] || {}
    if (!st.started) startFlip(i)
    else if (st.done) tapped(pick)
  })
}

// 两段式翻牌：0→90°（easeInOut 确定过临界）→ 90° 帧 JS 切换内容 → 90→180° 弹簧落定；
// 阴影透明度绑定 abs(cos(angle))，90° 垂直瞬间归零消除黑色竖线
function startFlip(i) {
  const st = S.flipState[i]
  if (st && st.started) return
  S.flipState[i] = { started: true, done: false }
  const frame = S.cardEls[i]
  const inner = frame.querySelector('.slot-inner')
  sfx.flip()
  animate(0, 90, 300, easeInOutCubic, a => setFlip(frame, inner, a), () => {
    // ★ 翻过 90° 的瞬间：标题/文字弹簧淡入 + 揭晓小钟琴
    frame.classList.add('revealed')
    fillTitle(frame, S.picks[i])
    sfx.chime()
    S.revealedCount++
    const btn = document.getElementById('flip-all')
    if (S.revealedCount >= 3 && btn) btn.classList.add('hidden')
    animate(90, 180, 560, easeOutBack, a => setFlip(frame, inner, a), () => {
      S.flipState[i].done = true
    })
  })
}

function setFlip(frame, inner, a) {
  inner.style.transform = `rotateY(${a.toFixed(2)}deg)`
  frame.style.setProperty('--lift', Math.abs(Math.cos(a * Math.PI / 180)).toFixed(3))
}

function fillTitle(frame, pick) {
  const t = frame.querySelector('.card-title')
  t.classList.remove('pending')
  t.textContent = `${pick.card.number} · ${pick.card.nameEn}`
}

// ============================================================
// iOS WebKit 通信桥接
// ============================================================

function tapped(pick) {
  const payload = {
    id: pick.card.id,               // 如 "major-09"（原生映射 TarotDeck.major 用）
    position: pick.positionLabel,   // "过去 · PAST" / "现在 · PRESENT" / "未来 · FUTURE"
    number: pick.card.number,       // 如 "IX"
    nameEn: pick.card.nameEn,       // 如 "THE HERMIT"
    nameZh: pick.card.nameZh,       // 如 "隐者"
    isReversed: pick.reversed,      // Boolean
    keywords: pick.keywords,        // 字符串数组
    meaning: pick.meaning           // 对应正位或逆位的详细牌义文本
  }
  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tarotCardTapped
  if (handler) {
    handler.postMessage(payload)
    return
  }
  showDetail(payload) // 独立浏览器预览时的兜底弹层
}

function showDetail(p) {
  const mask = el('div', 'detail-mask')
  mask.innerHTML = `
    <div class="detail-card">
      <h3>${p.number} · ${p.nameEn}（${p.nameZh}）</h3>
      <div class="d-pos">${p.positionLabel} · ${p.isReversed ? '逆位' : '正位'}</div>
      <div class="d-kw">${p.keywords.map(k => `<span>${k}</span>`).join('')}</div>
      <div class="d-meaning">${p.meaning}</div>
      <button class="d-close">收起</button>
    </div>`
  document.body.appendChild(mask)
  mask.addEventListener('click', e => {
    if (e.target === mask || e.target.classList.contains('d-close')) mask.remove()
  })
}

// ============================================================
// 重新抽牌：清空已选数组/翻牌/文字/粒子状态，无重影切回 sealed
// ============================================================

function redraw() {
  clearTimeout(S.bloomTimer)
  // 通知原生把记录标记为未拆（首页继续显示旧牌阵核心牌，不剧透）
  const bridge = window.webkit && window.webkit.messageHandlers
  if (bridge && bridge.tarotRedraw) bridge.tarotRedraw.postMessage({})
  S = freshState()
  render()
}

// ---------- 启动 ----------
function start() {
  S = freshState()
  // 原生注入启动态：当日已抽过 → 直接呈现三牌阵（全部翻开）
  if (BOOT && BOOT.opened && Array.isArray(BOOT.spread) && BOOT.spread.length === 3) {
    const picks = BOOT.spread.map((entry, i) => {
      const c = deck.find(d => d.id === entry.id)
      const reversed = !!entry.reversed
      return {
        card: c,
        reversed,
        positionLabel: POSITION_LABELS[i],
        keywords: reversed ? c.keywordsRev : c.keywordsUp,
        meaning: reversed ? c.meaningRev : c.meaningUp
      }
    })
    if (picks.every(p => p.card)) {
      S.phase = 'spread'
      S.picks = picks
      S.revealedCount = 3
      S.flipState = { 0: { started: true, done: true }, 1: { started: true, done: true }, 2: { started: true, done: true } }
      render()
      return
    }
  }
  render()
}

start()
