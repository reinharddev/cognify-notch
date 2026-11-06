// mimik — a small animated SVG face. No dependencies. MIT.
const NS = 'http://www.w3.org/2000/svg'
let uid = 0

// top/bot: upper / lower lid closure 0..1, tilt: lid angle (+ inner end down),
// sx/sy: eye scale, sp: eye spacing, ey: eye y, gx/gy: gaze offset,
// m: [half width, curve (+ smile), open], ms: mouth skew, l/r: per-eye overrides
export const expressions = {
  idle: { m: [8, 2, 0] },
  content: { top: 0.35, m: [9, 5, 0] },
  relieved: { top: 0.5, tilt: -6, ey: 5, m: [9, 4, 0] },
  happy: { bot: 0.45, m: [11, 8, 0] },
  joy: { bot: 0.6, top: 0.1, sy: 0.9, m: [13, 10, 5] },
  excited: { sx: 1.15, sy: 1.15, sp: 20, ey: 3, m: [12, 8, 8] },
  love: { deco: 'heart', m: [10, 8, 0] },
  pleading: { sx: 1.2, sy: 1.25, top: 0.3, tilt: -10, ey: 3, m: [6, -3, 0] },
  shy: { top: 0.25, gx: -4, gy: 5, ey: 5, m: [5, 2, 0] },
  surprised: { sx: 1.2, sy: 1.2, ey: 2, m: [4, 0, 9] },
  scared: { sx: 1.2, sy: 1.2, top: 0.3, tilt: -14, sp: 21, trem: 1, m: [9, -4, 5] },
  curious: { l: { sy: 0.85 }, r: { sy: 1.25, top: 0.25, tilt: -8, ey: 2 }, gx: 3, m: [6, 1, 0], ms: 1.5 },
  confused: { l: { top: 0.3, tilt: -10 }, r: { tilt: 6, sy: 1.15 }, deco: 'q', m: [7, -2, 0], ms: 2 },
  dizzy: { deco: 'spiral', m: [8, 0, 3] },
  thinking: { gx: 8, gy: -8, top: 0.2, r: { top: 0.35, tilt: -8, sy: 1.1 }, m: [5, 0, 0], ms: 1 },
  focus: { top: 0.3, bot: 0.15, tilt: 8, m: [6, 0, 0] },
  suspicious: { top: 0.45, bot: 0.3, gx: 6, m: [7, -1, 0] },
  unimpressed: { top: 0.5, m: [9, -1, 0] },
  smug: { top: 0.35, tilt: -4, m: [10, 3, 0], ms: 2.5 },
  sly: { top: 0.3, bot: 0.2, tilt: 10, m: [10, 5, 0], ms: 1.5 },
  bored: { top: 0.55, gy: 3, m: [8, -1, 0] },
  exasperated: { top: 0.85, m: [9, -3, 3] },
  worried: { top: 0.35, tilt: -14, ey: 5, m: [8, -4, 0] },
  guilty: { top: 0.4, tilt: -10, gx: -4, gy: 5, m: [7, -3, 0] },
  sad: { top: 0.4, tilt: -18, ey: 6, m: [9, -6, 0] },
  disgusted: { l: { top: 0.45, tilt: 12 }, r: { top: 0.45, tilt: -4, sy: 0.8 }, m: [10, -5, 2], ms: -2 },
  annoyed: { top: 0.5, tilt: 10, m: [8, -2, 0] },
  angry: { top: 0.45, tilt: 22, m: [10, -6, 3] },
  sleepy: { top: 0.75, m: [6, 0, 2] },
  sleep: { top: 1, deco: 'z', m: [5, 2, 0] },
  laugh: { bot: 0.65, top: 0.05, sy: 0.85, m: [14, 9, 9] },
  cry: { top: 0.3, tilt: -14, ey: 5, deco: 'tears', m: [9, -6, 4] },
  sob: { top: 0.55, tilt: -20, ey: 6, trem: 1, deco: 'tears', m: [10, -7, 6] },
  starstruck: { deco: 'star', m: [12, 9, 6] },
  dead: { deco: 'x', m: [9, -1, 0] },
  cool: { deco: 'shades', m: [9, 4, 0], ms: 1.5 },
  nervous: { top: 0.2, tilt: -8, trem: 0.6, deco: 'sweat', m: [9, -2, 3] },
  embarrassed: { top: 0.3, gx: -5, gy: 4, deco: 'blush', m: [6, 1, 3] },
  blush: { bot: 0.35, deco: 'blush', m: [8, 5, 0] },
  proud: { top: 0.3, gy: -3, tilt: -4, ey: 3, m: [11, 6, 0] },
  hopeful: { sx: 1.15, sy: 1.2, gy: -5, top: 0.2, tilt: -8, m: [7, 3, 0] },
  determined: { top: 0.4, tilt: 14, m: [10, -1, 0] },
  mischievous: { top: 0.3, bot: 0.25, tilt: 16, m: [13, 8, 3], ms: 1.5 },
  skeptical: { l: { top: 0.5, tilt: 6 }, r: { sy: 1.2, tilt: -6, ey: 2 }, m: [7, -1, 0], ms: 2 },
  tired: { top: 0.65, gy: 2, ey: 6, m: [8, -2, 2] },
  hurt: { top: 0.4, tilt: -16, sy: 0.8, trem: 0.4, m: [7, -5, 3] },
  grumpy: { top: 0.5, tilt: 16, ey: 5, m: [12, -7, 0] },
  dazed: { top: 0.25, l: { gx: -3, sy: 0.9 }, r: { gx: 3, sy: 1.1 }, m: [7, 0, 3] },
  mindblown: { sx: 1.3, sy: 1.3, ey: 2, sp: 22, trem: 0.5, m: [5, 0, 11] },
  lonely: { top: 0.35, tilt: -12, gx: -3, gy: 5, ey: 6, m: [6, -3, 0] },
}

const st = (c) => `style="fill:var(--face-${c},#fff)"`
const sk = (c, w) => `fill="none" stroke-width="${w}" stroke-linecap="round" style="stroke:var(--face-${c},#fff)"`
function blob(t) {
  const N = 8, p = []
  for (let i = 0; i < N; i++) {
    const a = (i / N) * Math.PI * 2, r = 42 + 3 * Math.sin(t * 1.1 + i * 1.9) + 2 * Math.sin(t * 0.7 + i * 3.1)
    p.push([Math.cos(a) * r, Math.sin(a) * r * 0.95])
  }
  const f = (q) => q[0].toFixed(1) + ' ' + q[1].toFixed(1), mid = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2]
  let d = 'M' + f(mid(p[0], p[1]))
  for (let i = 1; i <= N; i++) d += 'Q' + f(p[i % N]) + ' ' + f(mid(p[i % N], p[(i + 1) % N]))
  return d + 'Z'
}

// eye: [half width, half height, corner], sp/ey: eye spacing / y, my: mouth y, mS: mouth scale, rot: eye slant
export const types = {
  round: { shape: 'M-46 0a46 46 0 1 0 92 0a46 46 0 1 0-92 0Z', eye: [12, 12, 12], sp: 19, ey: 4, my: 24, mS: 1, rot: 0 },
  robot: {
    shape: 'M-28 -38H28Q42 -38 42 -24V26Q42 40 28 40H-28Q-42 40 -42 26V-24Q-42 -38 -28 -38Z',
    eye: [11, 9, 3.5], sp: 19, ey: 2, my: 26, mS: 0.9, rot: 0,
    back: `<rect x="-48" y="-8" width="7" height="18" rx="2.5" ${st('ring')}/><rect x="41" y="-8" width="7" height="18" rx="2.5" ${st('ring')}/><path d="M0 -38V-44" ${sk('ring', 2.5)}/><circle cy="-46" r="3.6" ${st('ink')}/>`,
  },
  cat: {
    shape: 'M-40 -8L-38 -42L-14 -32Q0 -35 14 -32L38 -42L40 -8Q42 40 0 42Q-42 40 -40 -8Z',
    eye: [8, 11, 8], sp: 18, ey: 6, my: 25, mS: 0.8, rot: 0,
    inner: `<path d="M-3 16h6l-3 4z" ${st('ink')}/>`,
    front: `<path d="M-35 -36L-23 -30L-34 -20ZM35 -36L23 -30L34 -20Z" style="fill:var(--face-ring,#34363a)"/><path d="M-31 20L-47 17M-31 26L-47 28M31 20L47 17M31 26L47 28" ${sk('ink', 1.5)} opacity=".5"/>`,
  },
  ghost: {
    shape: 'M-40 40V0Q-40 -44 0 -44Q40 -44 40 0V40Q33 48 26.7 40T13.3 40T0 40T-13.3 40T-26.7 40Q-33 48 -40 40Z',
    eye: [8, 11, 8], sp: 17, ey: -4, my: 19, mS: 0.8, rot: 0,
  },
  blob: { shape: blob, eye: [11, 11, 11], sp: 18, ey: 2, my: 23, mS: 1, rot: 0 },
  alien: {
    shape: 'M0 -46C30 -46 42 -20 40 4C38 30 18 46 0 46C-18 46 -38 30 -40 4C-42 -20 -30 -46 0 -46Z',
    eye: [13, 8, 8], sp: 19, ey: 6, my: 31, mS: 0.6, rot: 24,
  },
  bear: {
    shape: 'M-42 0a42 42 0 1 0 84 0a42 42 0 1 0-84 0Z',
    eye: [8, 8, 8], sp: 17, ey: 4, my: 25, mS: 0.85, rot: 0,
    back: `<circle cx="-30" cy="-32" r="13" stroke-width="2.5" style="fill:var(--face-skin,#000);stroke:var(--face-ring,#34363a)"/><circle cx="30" cy="-32" r="13" stroke-width="2.5" style="fill:var(--face-skin,#000);stroke:var(--face-ring,#34363a)"/><circle cx="-30" cy="-32" r="6" style="fill:var(--face-ring,#34363a)"/><circle cx="30" cy="-32" r="6" style="fill:var(--face-ring,#34363a)"/>`,
    inner: `<ellipse cy="19" rx="15" ry="11" ${st('ink')} opacity=".13"/><ellipse cy="13" rx="4.5" ry="3.2" ${st('ink')}/>`,
  },
}

export const reactions = ['blink', 'wink', 'nod', 'shake', 'bounce', 'pop', 'boing', 'spin', 'jitter']
const RX_DUR = { blink: 0.26, wink: 0.42, nod: 0.72, shake: 0.72, bounce: 0.85, pop: 0.5, boing: 0.95, spin: 0.95, jitter: 0.5 }
// Spring per parameter (stiffness, damping). Damping ratio d/(2*sqrt(k)) < 1 gives a slight overshoot.
const SPRING = { k: 190, d: 24 }
const GAZE = { k: 150, d: 19 }
const ease = (p) => (p < 0.5 ? 2 * p * p : 1 - 2 * (1 - p) * (1 - p))

const BASE = { top: 0, bot: 0, tilt: 0, sx: 1, sy: 1, sp: 19, ey: 4, gx: 0, gy: 0, m: [8, 2, 0], my: 24, ms: 0, deco: null, trem: 0 }

function resolve(name, T) {
  const e = { ...BASE, ...(expressions[name] || expressions.idle) }
  const s = {}
  for (const k of ['L', 'R']) {
    const o = { ...e, ...(e[k.toLowerCase()] || {}) }
    s[k + 'top'] = o.top; s[k + 'bot'] = o.bot; s[k + 'tilt'] = o.tilt
    s[k + 'sx'] = o.sx; s[k + 'sy'] = o.sy
    s[k + 'x'] = (k === 'L' ? -1 : 1) * (o.sp - 19 + T.sp); s[k + 'y'] = o.ey - 4 + T.ey
    s[k + 'gx'] = o.gx; s[k + 'gy'] = o.gy
  }
  s.mw = e.m[0] * T.mS; s.mc = e.m[1] * T.mS; s.mo = e.m[2] * T.mS; s.my = T.my + (e.my - 24); s.ms = e.ms * T.mS
  s.dH = e.deco === 'heart' ? 1 : 0
  s.dS = e.deco === 'spiral' ? 1 : 0
  s.dZ = e.deco === 'z' ? 1 : 0
  s.dQ = e.deco === 'q' ? 1 : 0
  s.dX = e.deco === 'x' ? 1 : 0
  s.dT = e.deco === 'star' ? 1 : 0
  s.dB = e.deco === 'blush' ? 1 : 0
  s.dW = e.deco === 'sweat' ? 1 : 0
  s.dC = e.deco === 'tears' ? 1 : 0
  s.dG = e.deco === 'shades' ? 1 : 0
  s.trem = e.trem
  return s
}

const CSS = `
.mm{width:100%;height:100%;display:block;overflow:visible}
.mm .mm-fx{opacity:0;transition:opacity .3s}
.mm.mm-gloss .mm-gloss-l,.mm.mm-rim .mm-rim-l,.mm.mm-scan .mm-scan-l{opacity:1}
.mm.mm-glow{filter:drop-shadow(0 0 5px var(--face-ink,#fff))}
.mm.mm-hue{animation:mm-hue 8s linear infinite}
.mm.mm-hue.mm-glow{animation-name:mm-hue-glow}
@keyframes mm-hue{to{filter:hue-rotate(360deg)}}
@keyframes mm-hue-glow{from{filter:drop-shadow(0 0 5px var(--face-ink,#fff)) hue-rotate(0)}to{filter:drop-shadow(0 0 5px var(--face-ink,#fff)) hue-rotate(360deg)}}
`

function el(tag, attrs, parent) {
  const n = document.createElementNS(NS, tag)
  for (const k in attrs) n.setAttribute(k, attrs[k])
  if (parent) parent.appendChild(n)
  return n
}

const reduceMotion = typeof matchMedia === 'function' ? matchMedia('(prefers-reduced-motion: reduce)') : { matches: false }
const faces = new Set()
const ptr = { x: 0, y: 0, t: -1e9 }
const CURSOR_HOLD = 2.2 // seconds after the last pointer event before the face goes back to wandering
const LEAN = 0.45 // head shift per unit of gaze: the body follows the eyes
// How strongly each mood follows the cursor (default 1). Dreamy moods barely turn, alert ones lock on.
const TRACK = { thinking: 0.15, bored: 0.2, exasperated: 0.15, tired: 0.3, sleepy: 0.45, sleep: 0, dead: 0, dizzy: 0.2, shy: 0.4, sad: 0.7, scared: 1.3, focus: 1.25, excited: 1.2, angry: 1.15 }
let raf = 0, last = 0, listening = false

function ensureLoop() {
  if (!listening) {
    const seen = (e) => { ptr.x = e.clientX; ptr.y = e.clientY; ptr.t = performance.now() / 1000 }
    addEventListener('pointermove', seen, { passive: true })
    addEventListener('pointerdown', seen, { passive: true })
    addEventListener('blur', () => { ptr.t = -1e9 })
    listening = true
  }
  if (!raf) { last = performance.now(); raf = requestAnimationFrame(tick) }
}

function tick(now) {
  const dt = Math.min(0.05, (now - last) / 1000)
  last = now
  for (const f of faces) if (f.vis) f.step(now / 1000, dt)
  raf = faces.size ? requestAnimationFrame(tick) : 0
}

const clamp = (v, a, b) => Math.max(a, Math.min(b, v))
const STAR = (() => {
  let d = ''
  for (let i = 0; i < 10; i++) { const a = -Math.PI / 2 + (i * Math.PI) / 5, r = i % 2 ? 5.5 : 13; d += (i ? 'L' : 'M') + (Math.cos(a) * r).toFixed(2) + ' ' + (Math.sin(a) * r).toFixed(2) }
  return d + 'Z'
})()
const spiral = (() => {
  let d = 'M0 0'
  for (let a = 0.3; a < Math.PI * 4; a += 0.3) d += `L${(Math.cos(a) * a * 0.9).toFixed(2)} ${(Math.sin(a) * a * 0.9).toFixed(2)}`
  return d
})()

class Face {
  constructor(host, opts) {
    this.host = host
    this.o = { expression: 'idle', type: 'round', mouth: false, pupils: false, follow: true, blink: true, wander: true, ...opts }
    this.id = ++uid
    this.T = types[this.o.type]
    this.vis = true
    this.talkE = 0
    this.rx = null
    this.g = { x: 0, y: 0 }
    this.tw = { x: 0, y: 0 }
    this.nextBlink = 1 + Math.random() * 2
    this.nextWander = 0
    this.blinkStart = -9
    this.mop = 0
    this.build()
    this.update({})
    this.tgt = resolve(this.o.expression, this.T)
    this.cur = { ...this.tgt }
    this.vel = {}
    this.gv = { x: 0, y: 0 }
    this.rect = null
    this.rectT = -9
    faces.add(this)
    if (typeof IntersectionObserver === 'function') {
      this.io = new IntersectionObserver((en) => { this.vis = en[en.length - 1].isIntersecting })
      this.io.observe(host)
    }
    ensureLoop()
    this.step(performance.now() / 1000, 0)
  }

  build() {
    if (!document.getElementById('mm-css')) {
      const s = document.createElement('style'); s.id = 'mm-css'; s.textContent = CSS; document.head.appendChild(s)
    }
    const p = 'mm' + this.id, T = this.T
    const [rx, ry, cr] = T.eye
    this.ry = ry
    const svg = this.svg = el('svg', { class: 'mm', viewBox: '-50 -50 100 100', 'aria-hidden': 'true' })
    const defs = el('defs', {}, svg)
    el('rect', { x: -rx - 0.6, y: -ry - 0.6, width: 2 * rx + 1.2, height: 2 * ry + 1.2, rx: cr + 0.6 }, el('clipPath', { id: p + 'e' }, defs))
    this.clipH = el('path', {}, el('clipPath', { id: p + 'h' }, defs))
    const pat = el('pattern', { id: p + 's', width: 4, height: 4, patternUnits: 'userSpaceOnUse' }, defs)
    el('rect', { width: 4, height: 1.6, fill: '#000', opacity: 0.35 }, pat)

    const head = this.head = el('g', {}, svg)
    if (T.back) el('g', {}, head).innerHTML = T.back
    this.headP = el('path', { style: 'fill:var(--face-skin,#000)' }, head)
    const fx = el('g', { 'clip-path': `url(#${p}h)` }, head)
    if (T.inner) el('g', {}, fx).innerHTML = T.inner
    const shape = () => ({ x: -rx, y: -ry, width: 2 * rx, height: 2 * ry, rx: cr })
    this.eyes = ['L', 'R'].map((k) => {
      const g = el('g', {}, fx)
      const sc = el('g', { 'clip-path': `url(#${p}e)` }, g)
      const eye = el('rect', { ...shape(), style: 'fill:var(--face-ink,#fff)' }, sc)
      const pupil = el('circle', { r: Math.min(rx, ry) * 0.36, style: 'fill:var(--face-skin,#000)' }, sc)
      const top = el('rect', { x: -22, y: -44, width: 44, height: 44, style: 'fill:var(--face-skin,#000)' }, sc)
      const bot = el('circle', { r: 16, style: 'fill:var(--face-skin,#000)' }, sc)
      const ov = el('g', {}, g)
      const spinBg = el('rect', { ...shape(), style: 'fill:var(--face-ink,#fff)' }, ov)
      const heart = el('path', { d: 'M0 8C-16 -2 -12 -13 0 -6C12 -13 16 -2 0 8Z', style: 'fill:var(--face-ink,#fff)' }, ov)
      const star = el('path', { d: STAR, style: 'fill:var(--face-ink,#fff)' }, ov)
      const spin = el('path', { d: spiral, fill: 'none', 'stroke-width': 1.8, 'stroke-linecap': 'round', style: 'stroke:var(--face-skin,#000)' }, ov)
      const xx = el('path', { d: 'M-6 -6L6 6M6 -6L-6 6', fill: 'none', 'stroke-width': 3, 'stroke-linecap': 'round', style: 'stroke:var(--face-skin,#000)' }, ov)
      return { k, g, sc, eye, pupil, top, bot, ov, heart, star, spin, xx, spinBg }
    })
    this.mouth = el('path', { fill: 'none', 'stroke-width': 3.2, 'stroke-linecap': 'round', 'stroke-linejoin': 'round', style: 'stroke:var(--face-ink,#fff);fill:var(--face-ink,#fff)' }, fx)
    this.lens = ['L', 'R'].map(() => el('rect', { x: -rx - 3, y: -ry - 3, width: 2 * rx + 6, height: 2 * ry + 6, rx: 5, 'stroke-width': 1.6, fill: '#05070a', style: 'stroke:var(--face-ink,#fff)' }, fx))
    this.tears = ['L', 'R'].map(() => el('path', { d: 'M0 -4C3 0 4 3 0 5C-4 3 -3 0 0 -4Z', fill: '#7dd3fc' }, fx))
    this.sweat = el('path', { d: 'M0 -8C5 -1 6 4 0 7C-6 4 -5 -1 0 -8Z', fill: '#7dd3fc' }, fx)
    this.blush = [-1, 1].map((sgn) => el('ellipse', { cx: sgn * (T.sp + 9), cy: T.ey + ry + 7, rx: 8, ry: 4.5, fill: '#ff7a9a' }, fx))
    this.zs = [0, 1, 2].map((i) => {
      const t = el('text', { 'font-size': 9 + i * 3, 'font-weight': 700, 'font-family': 'ui-sans-serif,system-ui,sans-serif', style: 'fill:var(--face-ink,#fff)' }, head)
      t.textContent = 'z'
      return t
    })
    this.q = el('text', { x: 26, y: -22, 'font-size': 20, 'font-weight': 700, 'font-family': 'ui-sans-serif,system-ui,sans-serif', style: 'fill:var(--face-ink,#fff)' }, head)
    this.q.textContent = '?'
    // effect layers
    const gl = el('g', { class: 'mm-fx mm-gloss-l' }, fx)
    el('ellipse', { cx: -14, cy: -27, rx: 24, ry: 10, transform: 'rotate(-28 -14 -27)', fill: '#fff', opacity: 0.16 }, gl)
    const rm = el('g', { class: 'mm-fx mm-rim-l', transform: 'scale(.95)' }, fx)
    this.rimP = el('path', { fill: 'none', 'stroke-width': 1.3, opacity: 0.45, style: 'stroke:var(--face-ink,#fff)' }, rm)
    const sl = el('g', { class: 'mm-fx mm-scan-l' }, fx)
    el('rect', { x: -50, y: -50, width: 100, height: 100, fill: `url(#${p}s)` }, sl)
    this.ringP = el('path', { fill: 'none', 'stroke-width': 2.5, style: 'stroke:var(--face-ring,#34363a)' }, head)
    if (T.front) el('g', {}, head).innerHTML = T.front
    this.setShape(typeof T.shape === 'function' ? T.shape(0) : T.shape)
    this.host.appendChild(svg)
  }

  setShape(d) { for (const n of [this.headP, this.clipH, this.rimP, this.ringP]) n.setAttribute('d', d) }

  update(opts) {
    const typeChanged = opts.type && opts.type !== this.o.type
    Object.assign(this.o, opts)
    const o = this.o
    if (typeChanged) { this.T = types[o.type]; this.svg.remove(); this.build() }
    for (const [k, v] of [['skin', 'skin'], ['ink', 'ink'], ['ring', 'ring']]) {
      if (o[k]) this.host.style.setProperty('--face-' + v, o[k])
    }
    const c = this.svg.classList
    for (const k of ['gloss', 'rim', 'glow', 'scan', 'hue']) c.toggle('mm-' + k, !!o[k])
    if (opts.expression || typeChanged) this.tgt = resolve(o.expression, this.T)
  }

  set(name) { this.update({ expression: name }) }
  react(name) {
    if (!(name in RX_DUR)) throw new Error(`Unknown reaction "${name}". Try: ${reactions.join(', ')}`)
    this.rx = { name, t0: performance.now() / 1000, d: RX_DUR[name] }
  }
  talk(e) { this.talkE = clamp(e, 0, 1) }
  look(x, y, ms = 900) { this.lk = { x: clamp(x, -1, 1), y: clamp(y, -1, 1), until: performance.now() / 1000 + ms / 1000 } }

  step(t, dt) {
    const o = this.o, c = this.cur, tg = this.tgt
    const still = reduceMotion.matches
    if (!dt) Object.assign(c, tg)
    else {
      // Semi-implicit Euler spring, sub-stepped so a slow frame cannot blow it up.
      const n = Math.ceil(dt / (1 / 60)), h = dt / n, v = this.vel
      const kf = 1 - Math.exp(-dt * 10)
      for (const key in tg) {
        if (key[0] === 'd' || key === 'trem') { c[key] += (tg[key] - c[key]) * kf; continue } // opacities: no overshoot
        let x = c[key], vv = v[key] || 0
        for (let i = 0; i < n; i++) { vv += ((tg[key] - x) * SPRING.k - vv * SPRING.d) * h; x += vv * h }
        c[key] = x; v[key] = vv
      }
    }

    let blink = 0, rBlink = 0, wink = 0
    if (o.blink && !still && t >= this.nextBlink) { this.blinkStart = t; this.nextBlink = t + 2 + Math.random() * 3.5 }
    const bp = (t - this.blinkStart) / 0.16
    if (bp >= 0 && bp <= 1) blink = Math.sin(bp * Math.PI) ** 0.55

    let tx = this.g.x * LEAN, ty = Math.sin(t * 1.3) * (still ? 0 : 0.5) + this.g.y * LEAN, rot = 0, hx = 1, hy = 1
    if (this.rx) {
      const p = (t - this.rx.t0) / this.rx.d
      if (p >= 1) this.rx = null
      else if (p >= 0) {
        const tri = Math.sin(p * Math.PI) ** 0.55, fade = 1 - p
        switch (this.rx.name) {
          case 'blink': rBlink = tri; break
          case 'wink': wink = tri; break
          case 'nod': if (!still) ty += 6 * Math.sin(p * Math.PI * 4) * fade; break
          case 'shake': if (!still) tx += 5 * Math.sin(p * Math.PI * 6) * fade; break
          case 'bounce': if (!still) { const i = Math.sin(p * Math.PI * 2) * fade; ty -= 14 * Math.abs(i); hy += i * 0.13; hx -= i * 0.13 } break
          case 'pop': { const i = Math.sin(p * Math.PI) * (1 - p * 0.4); hx = hy = 1 + 0.17 * i; break }
          case 'boing': { const i = Math.sin(p * Math.PI * 2 * 2.2) * Math.exp(-4 * p); hy += i * 0.24; hx -= i * 0.24; break }
          case 'spin': if (!still) rot = ease(p) * 360; break
          case 'jitter': if (!still) { tx += (Math.random() - 0.5) * 4; ty += (Math.random() - 0.5) * 4 } break
        }
      }
    }
    if (c.trem > 0.01 && !still) { tx += Math.sin(t * 70) * 0.5 * c.trem; ty += Math.cos(t * 83) * 0.4 * c.trem }
    this.head.setAttribute('transform', `translate(${tx.toFixed(2)} ${ty.toFixed(2)}) rotate(${rot.toFixed(1)}) scale(${hx.toFixed(3)} ${hy.toFixed(3)})`)

    // gaze: pointer if it moved recently, otherwise wander
    let gx = 0, gy = 0
    if (this.lk && t < this.lk.until && !still) {
      gx = this.lk.x * 5; gy = this.lk.y * 5
    } else if (o.follow && ptr.t > 0 && t - ptr.t < CURSOR_HOLD && !still) {
      if (!this.rect || t - this.rectT > 0.4) { this.rect = this.host.getBoundingClientRect(); this.rectT = t }
      const r = this.rect
      const dx = ptr.x - (r.left + r.width / 2), dy = ptr.y - (r.top + r.height / 2)
      const d = Math.hypot(dx, dy) || 1, g0 = Math.min(1, d / Math.max(r.width, r.height, 1) / 2.2), f = Math.min(1, g0 * (2 - g0) * 4.4)
      const tk = TRACK[o.expression] ?? 1
      gx = (dx / d) * f * 5 * tk; gy = (dy / d) * f * 5 * tk
    } else if (o.wander && !still) {
      if (t >= this.nextWander) { this.tw = { x: (Math.random() - 0.5) * 8, y: (Math.random() - 0.5) * 6 }; this.nextWander = t + 1.2 + Math.random() * 2.5 }
      gx = this.tw.x; gy = this.tw.y
    }
    if (!dt) { this.g.x = gx; this.g.y = gy } else {
      const n = Math.ceil(dt / (1 / 60)), h = dt / n, G = this.gv
      for (let i = 0; i < n; i++) {
        G.x += ((gx - this.g.x) * GAZE.k - G.x * GAZE.d) * h; this.g.x += G.x * h
        G.y += ((gy - this.g.y) * GAZE.k - G.y * GAZE.d) * h; this.g.y += G.y * h
      }
    }

    const T = this.T, ry = this.ry
    if (typeof T.shape === 'function') this.setShape(T.shape(t))
    const pos = {}
    for (const e of this.eyes) {
      const K = e.k, a = K === 'L' ? c.Ltilt : -c.Rtilt
      const top = clamp(Math.max(c[K + 'top'], blink, rBlink, K === 'R' ? wink : 0), 0, 1)
      const bot = clamp(c[K + 'bot'], 0, 1)
      const x = c[K + 'x'] + c[K + 'gx'] + this.g.x, y = c[K + 'y'] + c[K + 'gy'] + this.g.y
      const rt = (K === 'L' ? -T.rot : T.rot), sc = `rotate(${rt}) scale(${c[K + 'sx'].toFixed(3)} ${c[K + 'sy'].toFixed(3)})`
      pos[K] = [x, y]
      e.g.setAttribute('transform', `translate(${x.toFixed(2)} ${y.toFixed(2)})`)
      e.sc.setAttribute('transform', sc)
      e.ov.setAttribute('transform', sc)
      e.top.setAttribute('transform', `rotate(${a.toFixed(1)}) translate(0 ${(-ry + (2 * ry + 1) * top).toFixed(2)})`)
      e.bot.setAttribute('transform', `rotate(${a.toFixed(1)}) translate(0 ${(ry + 16 - 2 * ry * bot).toFixed(2)})`)
      e.pupil.setAttribute('transform', `translate(${(this.g.x * 0.6).toFixed(2)} ${(this.g.y * 0.6).toFixed(2)})`)
      e.pupil.style.opacity = o.pupils ? 1 : 0
      const hide = Math.max(c.dH, c.dT)
      e.heart.style.opacity = c.dH
      e.star.style.opacity = c.dT
      e.spin.style.opacity = c.dS
      e.xx.style.opacity = c.dX
      e.spinBg.style.opacity = Math.max(c.dS, c.dX)
      e.spin.setAttribute('transform', `rotate(${(t * 220) % 360})`)
      e.sc.style.opacity = 1 - hide
    }

    this.lens.forEach((n, i) => {
      const [x, y] = pos[i ? 'R' : 'L']
      n.setAttribute('transform', `translate(${x.toFixed(2)} ${y.toFixed(2)})`); n.style.opacity = c.dG
    })
    this.tears.forEach((n, i) => {
      const [x, y] = pos[i ? 'R' : 'L'], ph = still ? 0.3 : (t * 0.9 + i * 0.5) % 1
      n.setAttribute('transform', `translate(${x.toFixed(2)} ${(y + ry + 2 + ph * 22).toFixed(2)})`)
      n.style.opacity = c.dC * Math.sin(ph * Math.PI)
    })
    const sp = still ? 0 : Math.sin(t * 3) * 1.2
    this.sweat.setAttribute('transform', `translate(${(T.sp + 12).toFixed(1)} ${(-24 + sp).toFixed(2)})`)
    this.sweat.style.opacity = c.dW
    this.blush.forEach((n) => (n.style.opacity = c.dB * 0.55))
    const tk = this.talkE
    const want = o.mouth || tk > 0.02 ? 1 : 0
    this.mop += (want - this.mop) * (dt ? 1 - Math.exp(-dt * 12) : 1)
    const mo = Math.max(c.mo, tk * 9), mw = tk > 0.02 ? c.mw + (9 - c.mw) * Math.min(1, tk * 3) : c.mw
    const cy = c.my, mc = c.mc, ms = c.ms
    const lY = cy - mc * 0.3 + ms, rY = cy - mc * 0.3 - ms, ctl = cy + mc * 0.7
    const d = `M${-mw.toFixed(2)} ${lY.toFixed(2)}Q0 ${ctl.toFixed(2)} ${mw.toFixed(2)} ${rY.toFixed(2)}` +
      (mo > 0.4 ? `Q0 ${(ctl + mo * 2).toFixed(2)} ${-mw.toFixed(2)} ${lY.toFixed(2)}Z` : '')
    this.mouth.setAttribute('d', d)
    this.mouth.style.opacity = this.mop
    this.mouth.style.fillOpacity = clamp(mo / 2, 0, 1)

    const z = still ? 0 : t
    this.zs.forEach((n, i) => {
      const ph = ((z * 0.5 + i * 0.33) % 1)
      n.setAttribute('x', 22 + i * 7 + ph * 4)
      n.setAttribute('y', -18 - i * 9 - ph * 8)
      n.style.opacity = c.dZ * Math.sin(ph * Math.PI)
    })
    this.q.style.opacity = c.dQ
  }

  destroy() {
    faces.delete(this)
    if (this.io) this.io.disconnect()
    this.svg.remove()
  }
}

export function createFace(host, opts = {}) {
  if (opts.expression && !expressions[opts.expression]) {
    throw new Error(`Unknown expression "${opts.expression}". Try: ${Object.keys(expressions).join(', ')}`)
  }
  if (opts.type && !types[opts.type]) throw new Error(`Unknown type "${opts.type}". Try: ${Object.keys(types).join(', ')}`)
  const f = new Face(host, opts)
  return {
    el: f.svg,
    set: (n) => {
      if (!expressions[n]) throw new Error(`Unknown expression "${n}". Try: ${Object.keys(expressions).join(', ')}`)
      f.set(n)
    },
    update: (o) => f.update(o),
    react: (n) => f.react(n),
    talk: (e) => f.talk(e),
    look: (x, y, ms) => f.look(x, y, ms),
    destroy: () => f.destroy(),
  }
}
