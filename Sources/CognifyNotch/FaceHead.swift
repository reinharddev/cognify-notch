import AppKit
import SwiftUI

// Kepala bulat untuk notch mengambang, bergaya Mimik/bbot: kepala bulat sempurna dengan cincin tipis, mata bulat besar,
// dan mulut. Mata dan mulut menempel pada permukaan kepala yang berbentuk bola; bola itu diputar mengikuti arah pandang
// (kursor), jadi mata di tepi bergeser jauh dan menyempit sehingga wajah terasa menoleh. Rumusnya sama dengan
// Skins/mimik/face.js (`project()`), yang berasal dari bbot. Ekspresi tetap dari `Pose` (Companion.swift).

/// Semua angka yang menggerakkan wajah, dalam satu nilai yang bisa dianimasikan SwiftUI (pegas/ease antar ekspresi).
struct HeadParams: VectorArithmetic, Equatable {
    static let count = 20
    var v = [Double](repeating: 0, count: HeadParams.count)

    var top: Double { get { v[0] } set { v[0] = newValue } }
    var bot: Double { get { v[1] } set { v[1] = newValue } }
    var tilt: Double { get { v[2] } set { v[2] = newValue } }
    var sx: Double { get { v[3] } set { v[3] = newValue } }
    var sy: Double { get { v[4] } set { v[4] = newValue } }
    var skew: Double { get { v[5] } set { v[5] = newValue } }
    /// Arah pandang bawaan ekspresi (satuan kepala 100).
    var gx: Double { get { v[6] } set { v[6] = newValue } }
    var gy: Double { get { v[7] } set { v[7] = newValue } }
    var mw: Double { get { v[8] } set { v[8] = newValue } }
    var mc: Double { get { v[9] } set { v[9] = newValue } }
    var mo: Double { get { v[10] } set { v[10] = newValue } }
    var mr: Double { get { v[11] } set { v[11] = newValue } }
    var blink: Double { get { v[12] } set { v[12] = newValue } }
    var wink: Double { get { v[13] } set { v[13] = newValue } }
    /// Arah kursor -1.15...1.15 (menoleh).
    var lookX: Double { get { v[14] } set { v[14] = newValue } }
    var lookY: Double { get { v[15] } set { v[15] = newValue } }
    /// 1 = mata disembunyikan (diganti hati atau pusaran).
    var hide: Double { get { v[16] } set { v[16] = newValue } }
    /// Mengangguk mengikuti lagu: wajah turun (satuan kepala 100), miring (derajat), dan mulut bersenandung (0...1).
    var nodY: Double { get { v[17] } set { v[17] = newValue } }
    var rot: Double { get { v[18] } set { v[18] = newValue } }
    var hum: Double { get { v[19] } set { v[19] = newValue } }

    static var zero: HeadParams { HeadParams() }
    static func + (a: HeadParams, b: HeadParams) -> HeadParams { HeadParams(v: zip(a.v, b.v).map(+)) }
    static func - (a: HeadParams, b: HeadParams) -> HeadParams { HeadParams(v: zip(a.v, b.v).map(-)) }
    static func += (a: inout HeadParams, b: HeadParams) { a = a + b }
    static func -= (a: inout HeadParams, b: HeadParams) { a = a - b }
    mutating func scale(by rhs: Double) { v = v.map { $0 * rhs } }
    var magnitudeSquared: Double { v.reduce(0) { $0 + $1 * $1 } }

    /// Dari pose ekspresi (satuan lama) ke satuan kepala 100.
    init(pose p: Pose, blink: Double, wink: Double, look: CGSize) {
        self.init()
        top = p.top; bot = p.bot; tilt = p.tilt; sx = p.sx; sy = p.sy; skew = p.skew
        gx = p.gx * 2; gy = p.gy * 2
        mw = p.mw * 2.2; mc = p.mc * 2.2; mo = p.mo * 1.7; mr = p.mr
        self.blink = blink; self.wink = wink
        lookX = look.width; lookY = look.height
        hide = (p.deco == .heart || p.deco == .spiral) ? 1 : 0
    }
    init() {}
    private init(v: [Double]) { self.v = v }
}

enum HeadGeo {
    static let radius = 46.0
    static let turn = 0.36
    static let eyeX = 19.0, eyeY = 4.0, eyeR = 12.0, mouthY = 24.0

    struct Spot { var x: Double, y: Double, squash: Double, phi: Double }

    /// Titik (x, y) di wajah datar → posisi di kepala yang diputar `look` (yaw ke kiri-kanan, pitch ke atas-bawah).
    static func project(_ x: Double, _ y: Double, look: (Double, Double)) -> Spot {
        let yaw = look.0 * turn, pitch = -look.1 * turn
        let cy = cos(yaw), sy = sin(yaw), cp = cos(pitch), sp = sin(pitch)
        let z = sqrt(max(radius * radius - x * x - y * y, 1))
        let rx = x * cy + z * sy, rz = z * cy - x * sy
        let py = y * cp - rz * sp
        let depth = y * sp + rz * cp
        return Spot(x: rx, y: py, squash: min(1, max(0.25, depth / z)), phi: atan2(py, rx) * 180 / .pi)
    }

    static func eye(_ p: HeadParams, side: Double) -> Spot {
        project(side * eyeX + p.gx, eyeY + p.gy, look: (p.lookX, p.lookY))
    }
}

/// Kepala digambar langsung (Canvas) dan dianimasikan lewat `animatableData`.
struct HeadCanvas: View, Animatable {
    var params: HeadParams
    let diameter: CGFloat

    var animatableData: HeadParams {
        get { params }
        set { params = newValue }
    }

    private static let ink = Color(red: 0.914, green: 0.922, blue: 0.925)
    private static let ring = Color(red: 0.204, green: 0.212, blue: 0.227)

    var body: some View {
        Canvas { ctx, size in
            let s = Double(min(size.width, size.height)) / 100
            var g = ctx
            g.translateBy(x: size.width / 2, y: size.height / 2)
            g.scaleBy(x: s, y: s)
            let p = params
            // Kepala dan cincin diam (bentuk notch tidak bergerak); hanya mata dan mulut yang menoleh.
            g.fill(Path(ellipseIn: CGRect(x: -46, y: -46, width: 92, height: 92)), with: .color(.black))
            var face = g
            face.clip(to: Path(ellipseIn: CGRect(x: -46, y: -46, width: 92, height: 92)))
            // Mengangguk: seluruh wajah turun sedikit dan miring bergantian (cincin dan bentuk notch tetap diam).
            face.translateBy(x: 0, y: p.nodY)
            face.rotate(by: .degrees(p.rot))
            let look = (p.lookX, p.lookY)

            for side in [-1.0, 1.0] {
                let right = side > 0
                var e = face
                let spot = HeadGeo.eye(p, side: side)
                e.translateBy(x: spot.x, y: spot.y)
                e.rotate(by: .degrees(spot.phi)); e.scaleBy(x: spot.squash, y: 1); e.rotate(by: .degrees(-spot.phi))
                let size = p.skew == 0 ? 1.0 : (right ? 1 + p.skew : 1 - p.skew * 0.5)
                e.scaleBy(x: p.sx, y: p.sy * size)
                let top = min(1, max(p.top, p.blink, right ? p.wink : 0))
                let bot = min(1, max(0, p.bot))
                let tilt = (right ? -1 : 1) * p.tilt
                let r = HeadGeo.eyeR
                let alpha = 1 - p.hide
                if alpha > 0.01 {
                    e.opacity = alpha
                    e.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)), with: .color(Self.ink))
                    var lid = e
                    lid.clip(to: Path(ellipseIn: CGRect(x: -r - 0.6, y: -r - 0.6, width: 2 * r + 1.2, height: 2 * r + 1.2)))
                    var upper = lid
                    upper.rotate(by: .degrees(tilt))
                    upper.translateBy(x: 0, y: -r + (2 * r + 1) * top)
                    upper.fill(Path(CGRect(x: -22, y: -44, width: 44, height: 44)), with: .color(.black))
                    if bot > 0.001 {
                        var lower = lid
                        lower.rotate(by: .degrees(tilt))
                        lower.translateBy(x: 0, y: r + 16 - 2 * r * bot)
                        lower.fill(Path(ellipseIn: CGRect(x: -16, y: -16, width: 32, height: 32)), with: .color(.black))
                    }
                }
            }

            // Mulut: garis lengkung, atau bulat bila terbuka.
            let m = HeadGeo.project(0, HeadGeo.mouthY, look: look)
            var mouth = face
            mouth.translateBy(x: m.x, y: m.y)
            mouth.rotate(by: .degrees(m.phi)); mouth.scaleBy(x: m.squash, y: 1); mouth.rotate(by: .degrees(-m.phi))
            // Satu bentuk mulut: garis lengkung; saat terbuka, sisi bawahnya melengkung ke bawah dan bidangnya terisi
            // (bukan dua lapis yang saling menimpa).
            let w = max(1, p.mw), corner = -p.mc * 0.3, control = p.mc * 0.7
            var line = Path()
            line.move(to: CGPoint(x: -w, y: corner))
            line.addQuadCurve(to: CGPoint(x: w, y: corner), control: CGPoint(x: 0, y: control))
            if p.mo > 0.05 {
                var body = line
                body.addQuadCurve(to: CGPoint(x: -w, y: corner), control: CGPoint(x: 0, y: control + p.mo * 2))
                body.closeSubpath()
                var fill = mouth
                fill.opacity = min(1, p.mo / 2)
                fill.fill(body, with: .color(Self.ink))
            }
            mouth.stroke(line, with: .color(Self.ink), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))

            g.stroke(Path(ellipseIn: CGRect(x: -45, y: -45, width: 90, height: 90)), with: .color(Self.ring), lineWidth: 2.4)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// Hiasan ekspresi di atas kepala (hati, pusaran, tanda tanya, dan lainnya), dalam satuan kepala 100.
private struct HeadDecos: View {
    let deco: Deco
    let params: HeadParams
    let s: CGFloat
    private let drop = Color(red: 0.49, green: 0.83, blue: 0.99)

    var body: some View {
        ZStack {
            switch deco {
            case .heart:
                ForEach([-1.0, 1.0], id: \.self) { side in
                    let e = HeadGeo.eye(params, side: side)
                    Image(systemName: "heart.fill").font(.system(size: 28 * s, weight: .bold)).foregroundStyle(Color(red: 1, green: 0.42, blue: 0.55))
                        .offset(x: e.x * s, y: e.y * s)
                }
            case .spiral:
                ForEach([-1.0, 1.0], id: \.self) { side in
                    let e = HeadGeo.eye(params, side: side)
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { t in
                        Text("@").font(.system(size: 26 * s, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            .rotationEffect(.degrees(t.date.timeIntervalSinceReferenceDate * 300))
                    }
                    .offset(x: e.x * s, y: e.y * s)
                }
            case .z:
                Text("z").font(.system(size: 16 * s, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.65)).offset(x: 30 * s, y: -24 * s)
            case .question:
                Text("?").font(.system(size: 22 * s, weight: .heavy, design: .rounded)).foregroundStyle(.white).offset(x: 30 * s, y: -26 * s)
            case .bang:
                Text("!").font(.system(size: 22 * s, weight: .heavy, design: .rounded)).foregroundStyle(.white).offset(x: 30 * s, y: -26 * s)
            case .sweat:
                Image(systemName: "drop.fill").font(.system(size: 13 * s)).foregroundStyle(drop).offset(x: 33 * s, y: -24 * s)
            case .note:
                FloatingNote().scaleEffect(s * 2.2).offset(x: 32 * s, y: -22 * s)
            case .sparkle:
                Twinkle().scaleEffect(s * 2.4).offset(x: -36 * s, y: -30 * s)
                Twinkle().scaleEffect(s * 2.4).offset(x: 36 * s, y: -30 * s)
            case .tear:
                let e = HeadGeo.eye(params, side: -1)
                Image(systemName: "drop.fill").font(.system(size: 13 * s)).foregroundStyle(drop).offset(x: e.x * s, y: (e.y + 20) * s)
            case .blush:
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Ellipse().fill(Color(red: 1, green: 0.48, blue: 0.64).opacity(0.55)).frame(width: 17 * s, height: 9 * s).offset(x: side * 29 * s, y: 18 * s)
                }
            case .none:
                EmptyView()
            }
        }
    }
}

/// Nada musik yang melayang di dalam kepala (dibuat di ketukan genap), tanpa state SwiftUI: daftar disimpan di objek biasa
/// yang diperbarui tiap bingkai.
final class NoteBank {
    struct Note { let t0: Double; let glyph: String; let side: Double; let x0: Double }
    static let life = 2.6
    private(set) var notes: [Note] = []
    private var lastBeats = 0

    private var nextNote = 0.0
    private var count = 0

    func update(beats: Int, on: Bool, now: Double) {
        // Berdasarkan waktu, bukan ketukan, supaya pasti muncul: satu nada tiap ~1 sampai 2 detik selama lagu terdengar.
        if on, now >= nextNote, notes.count < 3 {
            count += 1
            let side: Double = count % 2 == 0 ? 1 : -1
            notes.append(Note(t0: now, glyph: ["♪", "♫", "♬"][count % 3], side: side, x0: side * Double.random(in: 22...30)))
            nextNote = now + 1.0 + Double.random(in: 0...1.0)
        }
        lastBeats = beats
        notes.removeAll { now - $0.t0 > Self.life }
    }
}

/// Kepala bulat untuk notch mengambang (dan pratinjau di Pengaturan).
struct FaceHead: View {
    @ObservedObject var face: Face
    var diameter: CGFloat = 42
    @State private var bank = NoteBank()

    var body: some View {
        // Saat musik diputar kepala digambar ulang ±30× per detik (mengangguk di ketukan); selain itu hanya saat berubah.
        if face.groove, face.vibeProvider != nil {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in head(now: ctx.date.timeIntervalSinceReferenceDate) }
        } else {
            head(now: nil)
        }
    }

    private func head(now: Double?) -> some View {
        let p = face.pose
        var params = HeadParams(pose: p, blink: face.blink, wink: face.wink,
                                look: CGSize(width: face.gaze.width + face.glance.width * 0.25, height: face.gaze.height + face.glance.height * 0.25))
        let s = diameter / 100
        if let now, let v = face.vibe(), v.isAudible {
            // Santai: anggukan lambat (satu siklus beberapa ketukan, minimal ~1,3 detik) dan kecil; mulut tetap senyum tertutup.
            let amp = 0.5 + 0.35 * min(1, v.energy * 1.4)
            params.nodY = amp * 2.4 * v.slowDepth(at: now)
            params.rot = amp * 1.8 * v.slowSway(at: now)
            bank.update(beats: v.beats, on: true, now: now)
        } else if let now {
            bank.update(beats: 0, on: false, now: now)
        }
        return ZStack {
            HeadCanvas(params: params, diameter: diameter)
            HeadDecos(deco: p.deco, params: params, s: s)
                .animation(.easeInOut(duration: 0.2), value: p.deco)
            if let now {
                ForEach(Array(bank.notes.enumerated()), id: \.offset) { _, n in
                    let age = (now - n.t0) / NoteBank.life
                    Text(n.glyph)
                        .font(.system(size: 17 * s, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white.opacity(sin(.pi * min(1, age * 1.05)) * 0.95))
                        .offset(x: (n.x0 + sin(age * 5) * 3 + n.side * age * 6) * s, y: (-6 - age * 24) * s)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .modifier(Wobble(kind: face.rx, amp: 4, t: face.rxT))
    }
}
