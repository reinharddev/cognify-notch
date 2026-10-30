import SwiftUI

// Teman kecil di notch: wajah yang ekspresinya menyesuaikan keadaan. Saat notch menempel di layar
// hanya dua mata yang tampil; saat notch mengambang (Mac tanpa notch) mata itu menjadi kepala bulat
// lengkap dengan mulut. Mesin ekspresinya sama dengan mimik (github.com/reinharddev/mimik).

// MARK: - Ekspresi

enum Deco { case none, z, question, bang, sweat, heart, spiral }

/// Bentuk wajah untuk satu ekspresi. `top`/`bot`: kelopak atas/bawah menutup 0...1, `tilt`: kemiringan
/// kelopak (derajat, + = ujung dalam turun), `sx`/`sy`: ukuran mata, `skew`: mata kanan lebih besar dari
/// kiri, `gx`/`gy`: arah pandang, `mw`/`mc`/`mo`: lebar, lengkung, dan buka mulut (hanya saat mengambang).
struct Pose {
    var top = 0.0, bot = 0.0, tilt = 0.0, sx = 1.0, sy = 1.0
    var gx = 0.0, gy = 0.0, skew = 0.0
    var mw = 3.6, mc = 0.9, mo = 0.0
    var deco: Deco = .none
}

enum Emotion: String, CaseIterable, Identifiable {
    case idle, content, happy, joy, excited, love, hello
    case surprised, scared, curious, confused, dizzy
    case suspicious, smug, bored, tired, exhausted, yawn
    case worried, sad, annoyed, angry, determined
    case sleepy, sleep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .idle: return L("Biasa", "Neutral")
        case .content: return L("Tenang", "Content")
        case .happy: return L("Senang", "Happy")
        case .joy: return L("Gembira", "Joyful")
        case .excited: return L("Semangat", "Excited")
        case .love: return L("Jatuh cinta", "In love")
        case .hello: return L("Menyapa", "Greeting")
        case .surprised: return L("Kaget", "Surprised")
        case .scared: return L("Takut", "Scared")
        case .curious: return L("Penasaran", "Curious")
        case .confused: return L("Bingung", "Confused")
        case .dizzy: return L("Pusing", "Dizzy")
        case .suspicious: return L("Curiga", "Suspicious")
        case .smug: return L("Puas", "Smug")
        case .bored: return L("Bosan", "Bored")
        case .tired: return L("Lelah", "Tired")
        case .exhausted: return L("Kehabisan tenaga", "Exhausted")
        case .yawn: return L("Menguap", "Yawning")
        case .worried: return L("Cemas", "Worried")
        case .sad: return L("Sedih", "Sad")
        case .annoyed: return L("Kesal", "Annoyed")
        case .angry: return L("Marah", "Angry")
        case .determined: return L("Serius", "Determined")
        case .sleepy: return L("Mengantuk", "Sleepy")
        case .sleep: return L("Tidur", "Asleep")
        }
    }

    /// Gerakan yang menyertai ekspresi saat muncul karena kejadian.
    var motion: Face.Reaction {
        switch self {
        case .happy, .joy, .excited, .love: return .bounce
        case .surprised, .scared, .angry: return .shake
        case .hello: return .pop
        default: return .none
        }
    }

    var pose: Pose {
        switch self {
        case .idle: return Pose()
        case .content: return Pose(top: 0.35, mc: 2.2)
        case .happy: return Pose(bot: 0.45, mw: 5, mc: 3.6)
        case .joy: return Pose(top: 0.1, bot: 0.6, sy: 0.9, mw: 6, mc: 4.5, mo: 2.2)
        case .excited: return Pose(sx: 1.15, sy: 1.15, mw: 5.4, mc: 3.6, mo: 3.6)
        case .love: return Pose(mw: 4.5, mc: 3.6, deco: .heart)
        case .hello: return Pose(bot: 0.6, mw: 5.5, mc: 4, mo: 1.8)
        case .surprised: return Pose(sx: 1.2, sy: 1.25, mw: 1.8, mc: 0, mo: 4, deco: .bang)
        case .scared: return Pose(top: 0.3, tilt: -14, sx: 1.2, sy: 1.2, mw: 4, mc: -1.8, mo: 2.2, deco: .sweat)
        case .curious: return Pose(gx: 2.5, skew: 0.25, mw: 2.7, mc: 0.5)
        case .confused: return Pose(top: 0.2, tilt: -6, skew: 0.15, mw: 3.2, mc: -1, deco: .question)
        case .dizzy: return Pose(mw: 3.6, mc: 0, mo: 1.4, deco: .spiral)
        case .suspicious: return Pose(top: 0.45, bot: 0.3, gx: 3, mw: 3.2, mc: -0.5)
        case .smug: return Pose(top: 0.35, tilt: -4, mw: 4.5, mc: 1.4)
        case .bored: return Pose(top: 0.55, gy: 1.5, mw: 3.6, mc: -0.5)
        case .tired: return Pose(top: 0.6, gy: 1.5, mw: 3.6, mc: -1)
        case .exhausted: return Pose(top: 0.8, tilt: -6, gy: 2, mw: 3.2, mc: -1.5, mo: 1.5, deco: .sweat)
        case .yawn: return Pose(top: 0.85, mw: 4.5, mc: 0, mo: 5.5)
        case .worried: return Pose(top: 0.35, tilt: -14, mw: 3.6, mc: -1.8, deco: .sweat)
        case .sad: return Pose(top: 0.4, tilt: -18, mw: 4, mc: -2.7)
        case .annoyed: return Pose(top: 0.5, tilt: 10, mw: 3.6, mc: -1)
        case .angry: return Pose(top: 0.45, tilt: 22, mw: 4.5, mc: -2.7, mo: 1.4)
        case .determined: return Pose(top: 0.4, tilt: 14, mw: 4.5, mc: -0.5)
        case .sleepy: return Pose(top: 0.75, mw: 2.7, mc: 0, mo: 0.9)
        case .sleep: return Pose(top: 1, mw: 2.2, mc: 0.9, deco: .z)
        }
    }
}

// MARK: - Bentuk

/// Satu mata digambar langsung (Canvas): persegi panjang bulat yang dipotong kelopak atas (miring) dan kelopak
/// bawah (naik). Dibuat sebagai View beranimasi supaya kedipan mengecil mulus sampai jadi garis tipis.
struct EyeCanvas: View, Animatable {
    var top: Double, bot: Double, tilt: Double // radian
    var sx: Double, sy: Double
    let scale: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<Double, Double>, AnimatablePair<Double, AnimatablePair<Double, Double>>> {
        get { AnimatablePair(AnimatablePair(top, bot), AnimatablePair(tilt, AnimatablePair(sx, sy))) }
        set {
            top = newValue.first.first; bot = newValue.first.second
            tilt = newValue.second.first; sx = newValue.second.second.first; sy = newValue.second.second.second
        }
    }

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2, cy = size.height / 2
            let w = 8 * scale * sx, h = 12 * scale * sy, ry = h / 2
            let eye = Path(roundedRect: CGRect(x: cx - w / 2, y: cy - ry, width: w, height: h), cornerRadius: 3.5 * scale, style: .continuous)
            let turn = CGAffineTransform(translationX: cx, y: cy).rotated(by: tilt)
            let closed = min(1, max(0, (top - 0.78) / 0.22)) // 0 terbuka ... 1 garis tipis
            var lit = ctx
            lit.clip(to: Path(CGRect(x: -60, y: -ry + (h + 1) * top, width: 120, height: 120)).applying(turn))
            if bot > 0.001 {
                let radius = h * 0.7, mid = ry + radius - h * bot
                lit.clip(to: Path(ellipseIn: CGRect(x: -radius, y: mid - radius, width: radius * 2, height: radius * 2)).applying(turn), options: .inverse)
            }
            lit.fill(eye, with: .color(.white.opacity(1 - closed)))
            if closed > 0 {
                ctx.fill(Path(roundedRect: CGRect(x: cx - 4.5 * scale, y: cy + 1, width: 9 * scale, height: 2), cornerRadius: 1),
                         with: .color(.white.opacity(0.75 * closed)))
            }
        }
        .frame(width: 14 * scale, height: 16 * scale)
    }
}

/// Mulut: garis lengkung, terisi bila terbuka.
struct MouthShape: Shape {
    var w: Double, c: Double, o: Double

    var animatableData: AnimatablePair<Double, AnimatablePair<Double, Double>> {
        get { AnimatablePair(w, AnimatablePair(c, o)) }
        set { w = newValue.first; c = newValue.second.first; o = newValue.second.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        let y = r.midY, corner = y - c * 0.3, control = y + c * 0.7
        p.move(to: CGPoint(x: r.midX - w, y: corner))
        p.addQuadCurve(to: CGPoint(x: r.midX + w, y: corner), control: CGPoint(x: r.midX, y: control))
        if o > 0.3 {
            p.addQuadCurve(to: CGPoint(x: r.midX - w, y: corner), control: CGPoint(x: r.midX, y: control + o * 2))
            p.closeSubpath()
        }
        return p
    }
}

/// Gerakan sesaat untuk seluruh wajah: geser (kaget), loncat (senang), membesar sekejap (menyapa).
struct Wobble: GeometryEffect {
    var kind: Face.Reaction
    var amp: CGFloat
    var t: Double

    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        var dx = 0.0, dy = 0.0, s = 1.0
        let fade = 1 - t
        switch kind {
        case .none: break
        case .shake: dx = Double(amp) * sin(t * .pi * 6) * fade
        case .bounce: dy = -Double(amp) * abs(sin(t * .pi * 2)) * fade
        case .pop: s = 1 + 0.25 * sin(t * .pi)
        }
        let t = CGAffineTransform(translationX: dx + size.width / 2 * (1 - s), y: dy + size.height / 2 * (1 - s)).scaledBy(x: s, y: s)
        return ProjectionTransform(t)
    }
}

// MARK: - Otak

/// Keadaan dan kejadian yang bisa diberi ekspresi sendiri di mode "Per kejadian".
enum Situation: String, CaseIterable, Identifiable {
    // Keadaan (berlangsung selama kondisinya ada)
    case normal, music, focus, rest, offline, batteryLow, batteryCritical, lateNight, morning, uptimeLong, uptimeVeryLong, sleeping, waking
    // Kejadian (muncul sebentar)
    case charging, chargerFull, unplugged, lowBatteryNotice, audioConnected, audioDisconnected
    case downloadDone, downloadFailed, downloadCanceled, capsLock, inputSource, networkUp, networkDown
    case taskDone, taskFailed, alert

    var id: String { rawValue }

    var isEvent: Bool {
        switch self {
        case .charging, .chargerFull, .unplugged, .lowBatteryNotice, .audioConnected, .audioDisconnected,
             .downloadDone, .downloadFailed, .downloadCanceled, .capsLock, .inputSource, .networkUp, .networkDown,
             .taskDone, .taskFailed, .alert: return true
        default: return false
        }
    }

    static var states: [Situation] { allCases.filter { !$0.isEvent } }
    static var events: [Situation] { allCases.filter(\.isEvent) }

    var label: String {
        switch self {
        case .normal: return L("Keadaan biasa", "Nothing special")
        case .music: return L("Musik diputar", "Music playing")
        case .focus: return L("Timer fokus berjalan", "Focus timer running")
        case .rest: return L("Timer istirahat berjalan", "Break timer running")
        case .offline: return L("Internet putus", "Offline")
        case .batteryLow: return L("Baterai 20% ke bawah", "Battery 20% or less")
        case .batteryCritical: return L("Baterai 10% ke bawah", "Battery 10% or less")
        case .lateNight: return L("Larut malam (00.00 sampai 05.00)", "Late night (12 am to 5 am)")
        case .morning: return L("Pagi (05.00 sampai 09.00)", "Morning (5 am to 9 am)")
        case .uptimeLong: return L("Mac menyala 5 hari atau lebih", "Mac on for 5 days or more")
        case .uptimeVeryLong: return L("Mac menyala 10 hari atau lebih", "Mac on for 10 days or more")
        case .sleeping: return L("Mouse lama tidak digerakkan", "Mouse idle for a while")
        case .waking: return L("Mouse bergerak lagi", "Mouse moves again")
        case .charging: return L("Charger dicolok", "Charger plugged in")
        case .chargerFull: return L("Baterai penuh", "Fully charged")
        case .unplugged: return L("Charger dicabut", "Charger unplugged")
        case .lowBatteryNotice: return L("Peringatan baterai lemah", "Low battery warning")
        case .audioConnected: return L("AirPods atau headphone tersambung", "AirPods or headphones connected")
        case .audioDisconnected: return L("AirPods atau headphone terputus", "AirPods or headphones disconnected")
        case .downloadDone: return L("Unduhan selesai", "Download finished")
        case .downloadFailed: return L("Unduhan gagal", "Download failed")
        case .downloadCanceled: return L("Unduhan dibatalkan", "Download canceled")
        case .capsLock: return L("Caps Lock menyala", "Caps Lock turned on")
        case .inputSource: return L("Bahasa keyboard berganti", "Keyboard language changed")
        case .networkUp: return L("Internet kembali", "Back online")
        case .networkDown: return L("Internet terputus (kabar)", "Connection lost (notice)")
        case .taskDone: return L("Tersimpan atau selesai", "Saved or done")
        case .taskFailed: return L("Gagal menyimpan", "Failed to save")
        case .alert: return L("Pengingat (timer, minum, tugas)", "Reminder (timer, water, task)")
        }
    }

    /// Ekspresi bawaan.
    var emotion: Emotion {
        switch self {
        case .normal: return .idle
        case .music: return .happy
        case .focus: return .determined
        case .rest: return .content
        case .offline: return .sad
        case .batteryLow: return .tired
        case .batteryCritical: return .worried
        case .lateNight: return .sleepy
        case .morning: return .content
        case .uptimeLong: return .tired
        case .uptimeVeryLong: return .exhausted
        case .sleeping: return .sleep
        case .waking: return .hello
        case .charging: return .happy
        case .chargerFull: return .joy
        case .unplugged: return .worried
        case .lowBatteryNotice: return .scared
        case .audioConnected: return .excited
        case .audioDisconnected: return .sad
        case .downloadDone: return .joy
        case .downloadFailed: return .sad
        case .downloadCanceled: return .confused
        case .capsLock: return .surprised
        case .inputSource: return .curious
        case .networkUp: return .happy
        case .networkDown: return .sad
        case .taskDone: return .joy
        case .taskFailed: return .sad
        case .alert: return .excited
        }
    }
}

/// Cara wajah memilih ekspresi.
enum CompanionMode: String, CaseIterable, Identifiable {
    case dynamic // mengikuti keadaan dan acak (bawaan)
    case custom // ekspresi tiap keadaan dan kejadian diatur sendiri, tanpa acak
    case fixed // satu ekspresi saja

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dynamic: return L("Dinamis (acak)", "Dynamic (random)")
        case .custom: return L("Per kejadian", "Per event")
        case .fixed: return L("Statis", "Static")
        }
    }

    var hint: String {
        switch self {
        case .dynamic: return L("Mengikuti keadaan, kadang kaget atau iseng sendiri.", "Follows what is going on, sometimes startled or playful on its own.")
        case .custom: return L("Kamu menentukan ekspresi tiap keadaan dan kejadian. Tidak ada yang acak.", "You choose the expression for each situation and event. Nothing is random.")
        case .fixed: return L("Satu ekspresi saja, tidak berubah.", "One expression that never changes.")
        }
    }
}

/// Pilihan user untuk wajah, dibaca dari Preferences.
struct CompanionConfig {
    var mode: CompanionMode = .dynamic
    var fixed: Emotion = .happy
    var blink = true
    /// Situation.rawValue → "none" (tidak bereaksi) atau Emotion.rawValue. Tidak ada = bawaan.
    var map: [String: String] = [:]

    /// Ekspresi untuk satu keadaan atau kejadian; nil = tidak bereaksi (hanya kejadian).
    func emotion(for s: Situation) -> Emotion? {
        switch mode {
        case .fixed: return fixed
        case .dynamic: return s.emotion
        case .custom:
            switch map[s.rawValue] {
            case nil: return s.emotion
            case "none": return s.isEvent ? nil : .idle
            case let raw?: return Emotion(rawValue: raw) ?? s.emotion
            }
        }
    }
}

// MARK: - Otak

/// Keadaan yang memengaruhi suasana hati, dikumpulkan NotchModel tiap beberapa detik.
struct CompanionContext {
    var idle: TimeInterval // detik sejak gerakan mouse terakhir
    var uptimeDays: Double // lama Mac menyala sejak dihidupkan
    var hour: Int
    var battery: NotchModel.Battery?
    var playing: Bool
    var focus: Bool
    var rest: Bool
    var offline: Bool
}

@MainActor
final class Face: ObservableObject {
    enum Reaction { case none, shake, bounce, pop }

    @Published private(set) var emotion: Emotion = .idle
    @Published private(set) var blink = 0.0
    @Published private(set) var wink = 0.0
    @Published private(set) var glance = CGSize.zero
    @Published private(set) var rx: Reaction = .none
    @Published private(set) var rxT = 0.0

    /// Pilihan user; diisi NotchModel dari Preferences.
    var config: () -> CompanionConfig = { CompanionConfig() }

    private(set) var base: Emotion = .idle
    private var sleeping = false
    private var holding = false
    private var sequence: Task<Void, Never>?
    private var neutral: Emotion = .idle
    private var neutralUntil = Date.distantPast

    var pose: Pose { emotion.pose }

    // MARK: Perintah

    func set(_ next: Emotion, _ animation: Animation = .spring(response: 0.35, dampingFraction: 0.65)) {
        withAnimation(animation) { emotion = next }
    }

    func reset() {
        sequence?.cancel()
        holding = false
        sleeping = false
        base = .idle
        set(.idle, .easeInOut(duration: 0.2))
    }

    /// Untuk snapshot.
    func preview(_ next: Emotion) {
        base = next
        emotion = next
    }

    /// Pilihan user berubah: mulai dari awal supaya hasilnya langsung terlihat.
    func configChanged() {
        sequence?.cancel()
        holding = false
        sleeping = false
    }

    func sleep() {
        guard !sleeping else { return }
        sequence?.cancel()
        holding = false
        sleeping = true
        base = config().emotion(for: .sleeping) ?? .sleep
        set(base, .easeInOut(duration: 0.6))
    }

    /// Mouse bergerak lagi: kalau tertidur, bangun dan menyapa.
    func wake() {
        guard sleeping else { return }
        sleeping = false
        base = .idle
        if let hello = config().emotion(for: .waking) { play([(hello, 1.6, hello.motion)]) } else { set(base, .easeInOut(duration: 0.3)) }
    }

    func react(_ kind: Reaction) {
        rx = kind
        rxT = 0
        withAnimation(.linear(duration: 0.6)) { rxT = 1 }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            self?.rx = .none
            self?.rxT = 0
        }
    }

    /// Menampilkan beberapa ekspresi berurutan, lalu kembali ke suasana dasar.
    func play(_ steps: [(Emotion, Double, Reaction)]) {
        sequence?.cancel()
        holding = true
        sequence = Task { [weak self] in
            for (emotion, seconds, kind) in steps {
                guard let self, !Task.isCancelled else { return }
                self.set(emotion)
                if kind != .none { self.react(kind) }
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            guard let self, !Task.isCancelled else { return }
            self.holding = false
            self.set(self.base, .easeInOut(duration: 0.3))
        }
    }

    func blinkOnce() {
        guard !holding, !sleeping, config().blink, emotion != .sleep else { return }
        withAnimation(.easeIn(duration: 0.11)) { blink = 1 }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 170_000_000) // menutup 110 ms, tertahan sebentar
            withAnimation(.easeOut(duration: 0.26)) { self?.blink = 0 }
        }
    }

    func winkOnce() {
        guard !holding, !sleeping, emotion != .sleep else { return }
        withAnimation(.easeIn(duration: 0.14)) { wink = 1 }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 420_000_000)
            withAnimation(.easeOut(duration: 0.28)) { self?.wink = 0 }
        }
    }

    func lookAround() {
        guard !holding, !sleeping, emotion != .sleep else { return }
        withAnimation(.easeInOut(duration: 0.25)) { glance = CGSize(width: Double.random(in: -2.5...2.5), height: Double.random(in: -1.5...1.5)) }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(Double.random(in: 1.2...2.4) * 1_000_000_000))
            withAnimation(.easeInOut(duration: 0.3)) { self?.glance = .zero }
        }
    }

    // MARK: Suasana hati

    /// Keadaan yang paling mendesak sekarang.
    private func state(for c: CompanionContext) -> Situation {
        if let b = c.battery, !b.charging {
            if b.percent <= 10 { return .batteryCritical }
            if b.percent <= 20 { return .batteryLow }
        }
        if c.focus { return .focus }
        if c.rest { return .rest }
        if c.offline { return .offline }
        if c.playing { return .music }
        if (0..<5).contains(c.hour) { return .lateNight }
        if c.uptimeDays >= 10 { return .uptimeVeryLong }
        if c.uptimeDays >= 5 { return .uptimeLong }
        if (5..<9).contains(c.hour) { return .morning }
        return .normal
    }

    /// Dipanggil tiap 5 sampai 10 detik. `flavor: false` hanya menyegarkan suasana (tanpa iseng).
    func tick(_ c: CompanionContext, flavor: Bool = true) {
        let cfg = config()
        if cfg.mode == .fixed {
            if base != cfg.fixed || emotion != cfg.fixed { base = cfg.fixed; set(cfg.fixed, .easeInOut(duration: 0.35)) }
            if flavor { blinkOnce() }
            return
        }
        if c.idle > 150 { sleep(); return }
        if holding { return }
        let s = state(for: c)
        var next = cfg.emotion(for: s) ?? .idle
        if s == .normal, cfg.mode == .dynamic {
            // Tidak ada yang istimewa: ganti-ganti santai tiap satu-dua menit.
            if Date() > neutralUntil {
                neutral = [Emotion.idle, .idle, .content, .curious, .smug].randomElement() ?? .idle
                if c.idle > 60, Bool.random() { neutral = .bored }
                neutralUntil = Date().addingTimeInterval(Double.random(in: 45...100))
            }
            next = neutral
        }
        if next != base || emotion != next {
            base = next
            set(next, .easeInOut(duration: 0.5))
        }
        guard flavor else { return }
        guard cfg.mode == .dynamic else { blinkOnce(); return }
        let r = Double.random(in: 0...1)
        switch r {
        case ..<0.12: lookAround()
        case ..<0.19: if base != .exhausted { winkOnce() }
        case ..<0.23: play([(.surprised, 1.0, .shake)]) // kaget tanpa sebab
        case ..<0.27 where c.uptimeDays >= 3 || (0..<5).contains(c.hour): play([(.yawn, 2.4, .none)])
        case ..<0.31 where c.playing: play([(.love, 2.5, .bounce)])
        case ..<0.34: play([(.smug, 2.0, .none)])
        case ..<0.355: play([(.dizzy, 2.0, .none)])
        default: blinkOnce()
        }
    }

    // MARK: Reaksi pada kabar

    private func situation(of notice: DeviceNotice) -> Situation {
        switch notice {
        case .charging(_, let full): return full ? .chargerFull : .charging
        case .unplugged: return .unplugged
        case .lowBattery: return .lowBatteryNotice
        case .audioConnected: return .audioConnected
        case .audioDisconnected: return .audioDisconnected
        case .downloadDone: return .downloadDone
        case .downloadFailed: return .downloadFailed
        case .downloadCanceled: return .downloadCanceled
        case .capsLock: return .capsLock
        case .inputSource: return .inputSource
        case .network(let online): return online ? .networkUp : .networkDown
        }
    }

    /// Kabar muncul. Dinamis: kadang kaget dulu, kadang biasa saja. Per kejadian: persis ekspresi pilihan user.
    func react(to notice: DeviceNotice) {
        let cfg = config()
        guard cfg.mode != .fixed else { return }
        let s = situation(of: notice)
        if case .capsLock(let on) = notice, !on { return }
        guard let chosen = cfg.emotion(for: s) else { return }
        var steps: [(Emotion, Double, Reaction)] = []
        if cfg.mode == .dynamic {
            if Double.random(in: 0...1) < 0.5 { steps.append((.surprised, 0.7, .shake)) }
            // Sebagian kabar punya dua kemungkinan ekspresi.
            var e = chosen
            switch s {
            case .audioConnected: e = [Emotion.excited, .love].randomElement() ?? chosen
            case .downloadFailed: e = [Emotion.angry, .sad].randomElement() ?? chosen
            default: break
            }
            steps.append((e, s == .lowBatteryNotice ? 4.5 : 2.6, e.motion))
        } else {
            steps.append((chosen, s == .lowBatteryNotice ? 4.5 : 2.6, chosen.motion))
        }
        play(steps)
    }

    func react(to toast: NotchModel.Toast) {
        let cfg = config()
        guard cfg.mode != .fixed else { return }
        let s: Situation
        switch toast {
        case .working: return
        case .done: s = .taskDone
        case .failed: s = .taskFailed
        case .alert: s = .alert
        }
        guard let chosen = cfg.emotion(for: s) else { return }
        if cfg.mode == .dynamic {
            switch s {
            case .taskFailed:
                let e = [Emotion.sad, .angry].randomElement() ?? chosen
                play([(e, 2.8, .none)])
            case .alert:
                if Bool.random() { play([(.surprised, 0.9, .shake), (chosen, 1.6, chosen.motion)]) } else { play([(chosen, 2.0, chosen.motion)]) }
            default: play([(chosen, 2.4, chosen.motion)])
            }
        } else {
            play([(chosen, 2.4, chosen.motion)])
        }
    }
}

// MARK: - Tampilan

/// Satu mata dengan hiasannya (z, tanda tanya, tanda seru, keringat, hati, pusaran).
struct Eye: View {
    @ObservedObject var face: Face
    let right: Bool
    var scale: CGFloat = 1

    var body: some View {
        let p = face.pose
        let top = min(1, max(p.top, face.blink, right ? face.wink : 0))
        let size = p.skew == 0 ? 1.0 : (right ? 1 + p.skew : 1 - p.skew * 0.5)
        let hidden = p.deco == .heart || p.deco == .spiral
        let tilt = (right ? -1 : 1) * p.tilt * .pi / 180
        ZStack {
            EyeCanvas(top: top, bot: p.bot, tilt: tilt, sx: p.sx, sy: p.sy * size, scale: scale)
                .opacity(hidden ? 0 : 1)
            switch p.deco {
            case .heart:
                Image(systemName: "heart.fill").font(.system(size: 11 * scale, weight: .bold)).foregroundStyle(Color(red: 1, green: 0.42, blue: 0.55))
            case .spiral:
                TimelineView(.animation) { t in
                    Text("@").font(.system(size: 12 * scale, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .rotationEffect(.degrees(t.date.timeIntervalSinceReferenceDate * 300))
                }
            case .z where right:
                Text("z").font(.system(size: 8, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.6)).offset(x: 9, y: -6)
            case .question where right:
                Text("?").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(.white).offset(x: 8, y: -8)
            case .bang where right:
                Text("!").font(.system(size: 10, weight: .heavy, design: .rounded)).foregroundStyle(.white).offset(x: 8, y: -8)
            case .sweat where right:
                Image(systemName: "drop.fill").font(.system(size: 6)).foregroundStyle(Color(red: 0.49, green: 0.83, blue: 0.99)).offset(x: 8, y: -6)
            default: EmptyView()
            }
        }
        .offset(x: p.gx * 0.5 + face.glance.width, y: p.gy * 0.5 + face.glance.height)
        .frame(width: 14 * scale, height: 16 * scale)
        .padding(.horizontal, 4)
    }
}

/// Kepala bulat untuk notch mengambang: dua mata dan mulut.
struct FaceHead: View {
    @ObservedObject var face: Face
    var diameter: CGFloat = 42

    var body: some View {
        let p = face.pose
        ZStack {
            HStack(spacing: -2) {
                Eye(face: face, right: false, scale: 0.85)
                Eye(face: face, right: true, scale: 0.85)
            }
            .offset(y: -4)
            MouthShape(w: p.mw, c: p.mc, o: p.mo)
                .fill(Color.white.opacity(min(1, p.mo / 2)))
                .overlay(MouthShape(w: p.mw, c: p.mc, o: p.mo).stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)))
                .frame(width: 20, height: 14)
                .offset(y: 10)
        }
        .frame(width: diameter, height: diameter)
        .modifier(Wobble(kind: face.rx, amp: 4, t: face.rxT))
    }
}
