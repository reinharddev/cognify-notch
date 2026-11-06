import SwiftUI
import WidgetKit

// Wajah Mimik (https://github.com/reinharddev/mimik) dalam SwiftUI, tipe "round". Widget tidak bisa
// beranimasi terus-menerus, jadi yang dibawa hanya bentuk diamnya: kelopak, kemiringan, ukuran mata,
// dan mulut. Angkanya disalin dari face.js (tabel `expressions`); satuannya sama (kotak -50...50).

struct MimikExpression {
    var top = 0.0, bot = 0.0, tilt = 0.0, sx = 1.0, sy = 1.0
    var sp = 19.0, ey = 4.0, gx = 0.0, gy = 0.0
    var m: (w: Double, c: Double, o: Double) = (8, 2, 0)
    var ms = 0.0
    var z = false
    /// Penimpa per mata (kiri/kanan), seperti `l` dan `r` di face.js.
    var l: Eye? = nil, r: Eye? = nil
    struct Eye { var top: Double? = nil, tilt: Double? = nil, sy: Double? = nil, ey: Double? = nil, gx: Double? = nil }

    static let table: [String: MimikExpression] = [
        "idle": .init(),
        "content": .init(top: 0.35, m: (9, 5, 0)),
        "relieved": .init(top: 0.5, tilt: -6, ey: 5, m: (9, 4, 0)),
        "happy": .init(bot: 0.45, m: (11, 8, 0)),
        "joy": .init(top: 0.1, bot: 0.6, sy: 0.9, m: (13, 10, 5)),
        "excited": .init(sx: 1.15, sy: 1.15, sp: 20, ey: 3, m: (12, 8, 8)),
        "pleading": .init(top: 0.3, tilt: -10, sx: 1.2, sy: 1.25, ey: 3, m: (6, -3, 0)),
        "surprised": .init(sx: 1.2, sy: 1.2, ey: 2, m: (4, 0, 9)),
        "scared": .init(top: 0.3, tilt: -14, sx: 1.2, sy: 1.2, sp: 21, m: (9, -4, 5)),
        "curious": .init(gx: 3, m: (6, 1, 0), ms: 1.5, l: .init(sy: 0.85), r: .init(top: 0.25, tilt: -8, sy: 1.25, ey: 2)),
        "thinking": .init(top: 0.2, gx: 8, gy: -8, m: (5, 0, 0), ms: 1, r: .init(top: 0.35, tilt: -8, sy: 1.1)),
        "focus": .init(top: 0.3, bot: 0.15, tilt: 8, m: (6, 0, 0)),
        "worried": .init(top: 0.35, tilt: -14, ey: 5, m: (8, -4, 0)),
        "sad": .init(top: 0.4, tilt: -18, ey: 6, m: (9, -6, 0)),
        "sleepy": .init(top: 0.75, m: (6, 0, 2)),
        "sleep": .init(top: 1, m: (5, 2, 0), z: true),
        "tired": .init(top: 0.65, ey: 6, gy: 2, m: (8, -2, 2)),
        "bored": .init(top: 0.55, gy: 3, m: (8, -1, 0)),
        "proud": .init(top: 0.3, tilt: -4, ey: 3, gy: -3, m: (11, 6, 0)),
        "angry": .init(top: 0.45, tilt: 22, m: (10, -6, 3)),
    ]
}

struct MimikFace: View {
    var expression: String = "idle"
    var skin = Color.black
    var ink = Color(red: 0.914, green: 0.922, blue: 0.925)
    var ring = Color(red: 0.204, green: 0.212, blue: 0.227)
    /// Arah pandang tambahan (satuan kotak -50...50), mis. dari `Mood.wander`.
    var look: CGSize = .zero
    /// Di desktop macOS widget yang tidak sedang disorot dirender satu warna (vibrant/accented): isi kepala
    /// dilewati dan kelopak memotong mata lewat klip, bukan lewat warna kulit, supaya mata tetap terbaca.
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let e = MimikExpression.table[expression] ?? MimikExpression()
        Canvas { ctx, size in
            let s = min(size.width, size.height) / 100
            var c = ctx
            c.translateBy(x: size.width / 2, y: size.height / 2)
            c.scaleBy(x: s, y: s)

            let head = Path(ellipseIn: CGRect(x: -46, y: -46, width: 92, height: 92))
            if renderingMode == .fullColor { c.fill(head, with: .color(skin)) }
            c.stroke(head, with: .color(ring), lineWidth: 2.5)
            var inner = c
            inner.clip(to: head)

            for k in 0..<2 {
                let ov = k == 0 ? e.l : e.r
                let top = ov?.top ?? e.top, tilt = ov?.tilt ?? e.tilt
                let sy = ov?.sy ?? e.sy, ey = ov?.ey ?? e.ey, gx = ov?.gx ?? e.gx
                let x = (k == 0 ? -1.0 : 1.0) * e.sp + gx + look.width
                let y = ey + e.gy + look.height
                let a = k == 0 ? tilt : -tilt
                var g = inner
                g.translateBy(x: x, y: y)
                g.scaleBy(x: e.sx, y: sy)
                g.clip(to: Path(roundedRect: CGRect(x: -12.6, y: -12.6, width: 25.2, height: 25.2), cornerRadius: 12.6))
                // Kelopak = bentuk yang dibuang dari mata (klip terbalik), urutan SVG: rotate(a) lalu translate(0 y).
                let rot = CGAffineTransform(rotationAngle: a * .pi / 180)
                let topLid = Path(CGRect(x: -22, y: -44, width: 44, height: 44))
                    .applying(CGAffineTransform(translationX: 0, y: -12 + 25 * top).concatenating(rot))
                let botLid = Path(ellipseIn: CGRect(x: -16, y: -16, width: 32, height: 32))
                    .applying(CGAffineTransform(translationX: 0, y: 12 + 16 - 24 * e.bot).concatenating(rot))
                g.clip(to: topLid, options: .inverse)
                g.clip(to: botLid, options: .inverse)
                g.fill(Path(roundedRect: CGRect(x: -12, y: -12, width: 24, height: 24), cornerRadius: 12), with: .color(ink))
            }

            // Mulut: kurva (kiri ke kanan), tertutup dan terisi bila terbuka.
            let cy = 24.0, mw = e.m.w, mc = e.m.c, mo = e.m.o
            let lY = cy - mc * 0.3 + e.ms, rY = cy - mc * 0.3 - e.ms, ctl = cy + mc * 0.7
            var mouth = Path()
            mouth.move(to: CGPoint(x: -mw, y: lY))
            mouth.addQuadCurve(to: CGPoint(x: mw, y: rY), control: CGPoint(x: 0, y: ctl))
            if mo > 0.4 {
                mouth.addQuadCurve(to: CGPoint(x: -mw, y: lY), control: CGPoint(x: 0, y: ctl + mo * 2))
                mouth.closeSubpath()
                inner.fill(mouth, with: .color(ink.opacity(min(1, mo / 2))))
            }
            inner.stroke(mouth, with: .color(ink), style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round))

            if e.z {
                for (i, size) in [9.0, 12.0, 15.0].enumerated() {
                    let text = Text("z").font(.system(size: size, weight: .bold)).foregroundColor(ink.opacity(1 - Double(i) * 0.25))
                    c.draw(text, at: CGPoint(x: 24 + Double(i) * 8, y: -16 - Double(i) * 10))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

extension Mood {
    /// Arah pandang yang berganti tiap 10 menit (seperti melirik acak di Mimik). Widget tidak bisa mengikuti kursor,
    /// jadi ini hanya variasi per penyegaran; nilainya tetap untuk satu waktu supaya tampilan stabil.
    static func wander(_ date: Date) -> CGSize {
        let n = Double(Int(date.timeIntervalSince1970 / 600))
        let a = sin(n * 12.9898) * 43758.5453, b = sin(n * 78.233) * 12345.6789, c = sin(n * 39.346) * 9876.5432
        func unit(_ v: Double) -> Double { v - v.rounded(.down) }
        if unit(c) < 0.3 { return .zero }
        return CGSize(width: (unit(a) - 0.5) * 9, height: (unit(b) - 0.5) * 6)
    }
}

/// Suasana (nama ekspresi) dari keadaan pengguna. Dipakai widget Mimik dan wajah kecil di widget lain.
enum Mood {
    static func overall(_ snap: WidgetSnapshot, now: Date) -> (expression: String, line: String) {
        let t = now.timeIntervalSince1970
        let hour = Calendar.current.component(.hour, from: now)
        let todos = snap.todos
        let open = todos.filter { !$0.done }
        if snap.timers?.contains(where: { $0.end > t }) == true { return ("focus", tr("Lagi fokus", "Focus time")) }
        if hour < 5 { return ("sleep", tr("Sudah malam, istirahat ya", "It's late, get some rest")) }
        if let soon = snap.events.first(where: { $0.isTask && $0.start > t && $0.start - t < 6 * 3600 }) {
            return ("worried", tr("Segera: ", "Due soon: ") + soon.title)
        }
        if let late = snap.events.first(where: { $0.isTask && $0.start < t && $0.start > t - 86_400 }) {
            return ("scared", tr("Lewat tenggat: ", "Overdue: ") + late.title)
        }
        if let next = snap.events.first(where: { !$0.isTask && !$0.allDay && $0.start > t && $0.start - t < 30 * 60 }) {
            return ("excited", next.title)
        }
        if let w = snap.water, w.goalMl > 0, w.todayMl >= w.goalMl, hour >= 12 { return ("joy", tr("Target minum tercapai", "Water goal reached")) }
        if !todos.isEmpty, open.isEmpty { return ("joy", tr("Semua tugas selesai", "All tasks done")) }
        if let w = snap.water, w.goalMl > 0, hour >= 15, Double(w.todayMl) < Double(w.goalMl) * 0.3 { return ("pleading", tr("Minum dulu, yuk", "Time for some water")) }
        if hour >= 22 { return ("sleepy", tr("Mulai ngantuk", "Getting sleepy")) }
        if let w = snap.weather, (51...67).contains(w.code) || (80...82).contains(w.code) { return ("content", tr("Di luar hujan", "Raining outside")) }
        if !open.isEmpty { return ("curious", tr("\(open.count) tugas menunggu", "\(open.count) tasks waiting")) }
        return (hour < 11 ? "happy" : "idle", hour < 11 ? tr("Selamat pagi", "Good morning") : tr("Santai dulu", "All calm"))
    }
}
