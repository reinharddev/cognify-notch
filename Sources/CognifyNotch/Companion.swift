import NotchDock
import SwiftUI

// Teman kecil di notch: wajah yang ekspresinya menyesuaikan keadaan. Saat notch menempel di layar
// hanya dua mata yang tampil; saat notch mengambang (Mac tanpa notch) mata itu menjadi kepala bulat
// lengkap dengan mulut. Mesin ekspresinya sama dengan mimik (github.com/reinharddev/mimik).

// MARK: - Ekspresi

enum Deco { case none, z, question, bang, sweat, heart, spiral, note, sparkle, tear, blush }

/// Bentuk wajah untuk satu ekspresi. `top`/`bot`: kelopak atas/bawah menutup 0...1, `tilt`: kemiringan
/// kelopak (derajat, + = ujung dalam turun), `sx`/`sy`: ukuran mata, `skew`: mata kanan lebih besar dari
/// kiri, `gx`/`gy`: arah pandang, `mw`/`mc`/`mo`: lebar, lengkung, dan buka mulut (hanya saat mengambang).
struct Pose {
    var top = 0.0, bot = 0.0, tilt = 0.0, sx = 1.0, sy = 1.0
    var gx = 0.0, gy = 0.0, skew = 0.0
    var mw = 3.6, mc = 0.9, mo = 0.0, mr = 0.0
    var deco: Deco = .none
}

enum Emotion: String, CaseIterable, Identifiable {
    case idle, content, happy, joy, excited, love, hello
    case surprised, scared, curious, confused, dizzy
    case suspicious, smug, bored, tired, exhausted, yawn
    case worried, sad, annoyed, angry, determined
    case sleepy, sleep
    case sing, proud, shy, cry, hot, wow, bliss

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
        case .sing: return L("Bernyanyi", "Singing")
        case .proud: return L("Bangga", "Proud")
        case .shy: return L("Malu", "Shy")
        case .cry: return L("Menangis", "Crying")
        case .hot: return L("Kepanasan", "Hot")
        case .wow: return L("Takjub", "Amazed")
        case .bliss: return L("Menikmati", "Enjoying")
        }
    }

    /// Gerakan yang menyertai ekspresi saat muncul karena kejadian.
    var motion: Face.Reaction {
        switch self {
        case .happy, .joy, .excited, .love, .sing, .proud: return .bounce
        case .surprised, .scared, .angry, .hot: return .shake
        case .hello, .wow: return .pop
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
        case .surprised: return Pose(sx: 1.2, sy: 1.25, mw: 3.2, mc: 0, mo: 3.2, mr: 1, deco: .bang)
        case .scared: return Pose(top: 0.3, tilt: -14, sx: 1.2, sy: 1.2, mw: 4, mc: -1.8, mo: 2.6, mr: 0.55, deco: .sweat)
        case .curious: return Pose(gx: 2.5, skew: 0.25, mw: 2.7, mc: 0.5)
        case .confused: return Pose(top: 0.2, tilt: -6, skew: 0.15, mw: 3.2, mc: -1, deco: .question)
        case .dizzy: return Pose(mw: 3.6, mc: 0, mo: 1.8, mr: 0.65, deco: .spiral)
        case .suspicious: return Pose(top: 0.45, bot: 0.3, gx: 3, mw: 3.2, mc: -0.5)
        case .smug: return Pose(top: 0.35, tilt: -4, mw: 4.5, mc: 1.4)
        case .bored: return Pose(top: 0.55, gy: 1.5, mw: 3.6, mc: -0.5)
        case .tired: return Pose(top: 0.6, gy: 1.5, mw: 3.6, mc: -1)
        case .exhausted: return Pose(top: 0.8, tilt: -6, gy: 2, mw: 3.2, mc: -1.5, mo: 1.5, deco: .sweat)
        case .yawn: return Pose(top: 0.85, mw: 4.5, mc: 0, mo: 5.5, mr: 1)
        case .worried: return Pose(top: 0.35, tilt: -14, mw: 3.6, mc: -1.8, deco: .sweat)
        case .sad: return Pose(top: 0.4, tilt: -18, mw: 4, mc: -2.7)
        case .annoyed: return Pose(top: 0.5, tilt: 10, mw: 3.6, mc: -1)
        case .angry: return Pose(top: 0.45, tilt: 22, mw: 4.5, mc: -2.7, mo: 1.4)
        case .determined: return Pose(top: 0.4, tilt: 14, mw: 4.5, mc: -0.5)
        case .sleepy: return Pose(top: 0.75, mw: 2.7, mc: 0, mo: 0.9)
        case .sleep: return Pose(top: 1, mw: 2.2, mc: 0.9, deco: .z)
        case .sing: return Pose(top: 0.15, bot: 0.5, gy: -0.5, mw: 4.5, mc: 2, mo: 3.5, mr: 0.55, deco: .note)
        case .proud: return Pose(top: 0.3, bot: 0.35, tilt: -6, gy: -1, mw: 5, mc: 3, deco: .sparkle)
        case .shy: return Pose(top: 0.3, bot: 0.4, gx: -3, gy: 1.5, mw: 2.5, mc: 0.8, deco: .blush)
        case .cry: return Pose(top: 0.35, tilt: -18, mw: 4, mc: -2.7, mo: 1.2, mr: 0.4, deco: .tear)
        case .hot: return Pose(top: 0.5, sy: 0.85, mw: 4, mc: -0.5, mo: 3, mr: 0.8, deco: .sweat)
        case .wow: return Pose(sx: 1.3, sy: 1.35, mw: 3.6, mc: 0, mo: 3.8, mr: 1, deco: .sparkle)
        // Menikmati lagu dengan tenang: mata terpejam santai (lengkung tipis ke bawah) dan senyum kecil tertutup.
        case .bliss: return Pose(top: 0.8, sy: 1.08, gy: 0.4, mw: 3.4, mc: 2, mo: 0)
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
            lit.fill(eye, with: .linearGradient(
                Gradient(colors: [.white.opacity(1 - closed), Color(white: 0.85).opacity(1 - closed)]),
                startPoint: CGPoint(x: cx, y: cy - ry), endPoint: CGPoint(x: cx, y: cy + ry)))
            if closed > 0 {
                ctx.fill(Path(roundedRect: CGRect(x: cx - 4.5 * scale, y: cy + 1, width: 9 * scale, height: 2), cornerRadius: 1),
                         with: .color(.white.opacity(0.75 * closed)))
            }
        }
        .frame(width: 14 * scale, height: 16 * scale)
    }
}

/// Mulut garis lengkung; bentuk bulat untuk mulut terbuka digambar terpisah di FaceHead.
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
    case volumeUp, volumeDown, muted, brightUp, brightDown

    var id: String { rawValue }

    var isEvent: Bool {
        switch self {
        case .charging, .chargerFull, .unplugged, .lowBatteryNotice, .audioConnected, .audioDisconnected,
             .downloadDone, .downloadFailed, .downloadCanceled, .capsLock, .inputSource, .networkUp, .networkDown,
             .taskDone, .taskFailed, .alert, .volumeUp, .volumeDown, .muted, .brightUp, .brightDown: return true
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
        case .volumeUp: return L("Volume dinaikkan", "Volume turned up")
        case .volumeDown: return L("Volume diturunkan", "Volume turned down")
        case .muted: return L("Suara dibisukan", "Sound muted")
        case .brightUp: return L("Layar dicerahkan", "Screen brightened")
        case .brightDown: return L("Layar diredupkan", "Screen dimmed")
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
        case .volumeUp: return .wow
        case .volumeDown: return .shy
        case .muted: return .sad
        case .brightUp: return .hot
        case .brightDown: return .sleepy
        }
    }
}

/// Cara wajah memilih ekspresi.
extension Situation {
    /// Kumpulan ekspresi untuk mode Dinamis: wajah berganti-ganti di dalam satu keadaan. Sama dengan POOLS di Windows.
    var pool: [Emotion]? {
        switch self {
        case .normal: return [.idle, .content, .curious, .smug, .proud, .idle, .bored, .shy]
        case .music: return [.bliss, .bliss, .content, .bliss, .content, .bliss]
        case .focus: return [.determined, .suspicious, .determined, .content, .proud]
        case .rest: return [.content, .happy, .sleepy, .joy, .yawn]
        case .offline: return [.sad, .cry, .confused, .worried, .bored]
        case .batteryLow: return [.tired, .worried, .sad, .bored, .sleepy]
        case .batteryCritical: return [.worried, .scared, .exhausted, .cry, .scared]
        case .lateNight: return [.sleepy, .yawn, .tired, .sleepy, .bored]
        case .morning: return [.content, .happy, .yawn, .hello, .proud]
        case .uptimeLong: return [.tired, .bored, .yawn, .tired, .hot]
        case .uptimeVeryLong: return [.exhausted, .dizzy, .tired, .hot, .cry]
        default: return nil
        }
    }
}

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
    /// Arah kursor relatif terhadap kepala (-1.15...1.15), untuk kepala bulat yang menoleh (FaceHead.swift).
    @Published private(set) var gaze = CGSize.zero
    private var gazeReset: Task<Void, Never>?
    /// Irama lagu saat ini (diisi NotchModel dari Spectrum). Dipakai kepala yang mengangguk dan mata yang bergoyang.
    var vibeProvider: (() -> BeatTracker)?
    func vibe() -> BeatTracker? { vibeProvider?() }
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
    private var poolUntil = Date.distantPast
    private var poolState: Situation = .normal
    private var lastVolume: Double?
    private var lastBright: Double?
    /// Musik diputar dan wajah "bergoyang" (mode Dinamis): mata mengangguk pelan mengikuti irama.
    @Published private(set) var groove = false

    var pose: Pose { emotion.pose }

    // MARK: Perintah

    func set(_ next: Emotion, _ animation: Animation = .easeInOut(duration: 0.45)) {
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

    /// Kursor di `mouse`, kepala berpusat di `center` (koordinat layar). Jarak menentukan seberapa jauh kepala menoleh
    /// (kurva ease-out bbot): dekat = menoleh sedikit, jauh = penuh. Dua detik setelah kursor diam, kepala kembali lurus.
    func look(at mouse: NSPoint, from center: NSPoint, reach: CGFloat = 260) {
        guard !sleeping else { return }
        let dx = Double(mouse.x - center.x), dy = Double(center.y - mouse.y) // y layar ke atas → y wajah ke bawah
        let d = max(hypot(dx, dy), 0.001)
        let g0 = min(1, d / Double(reach)), f = g0 * (2 - g0)
        let next = CGSize(width: dx / d * f, height: dy / d * f)
        guard abs(next.width - gaze.width) > 0.015 || abs(next.height - gaze.height) > 0.015 else { return }
        withAnimation(.interpolatingSpring(mass: 1, stiffness: 150, damping: 19)) { gaze = next }
        gazeReset?.cancel()
        gazeReset = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.interpolatingSpring(mass: 1, stiffness: 150, damping: 19)) { self?.gaze = .zero }
        }
    }

    /// Menoleh dimatikan: kembali lurus (sekali).
    func lookAhead() {
        guard gaze != .zero else { return }
        gazeReset?.cancel()
        withAnimation(.interpolatingSpring(mass: 1, stiffness: 150, damping: 19)) { gaze = .zero }
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

    /// Dipanggil tiap 2,5 sampai 5 detik. `flavor: false` hanya menyegarkan suasana (tanpa iseng).
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
        let grooving = cfg.mode == .dynamic && s == .music
        if groove != grooving { groove = grooving }
        var next = cfg.emotion(for: s) ?? .idle
        if s == .normal, cfg.mode == .dynamic {
            // Tidak ada yang istimewa: ganti-ganti santai tiap beberapa belas detik.
            if Date() > neutralUntil {
                neutral = (Situation.normal.pool ?? [.idle]).filter { $0 != neutral }.randomElement() ?? .idle
                if c.idle > 60, Bool.random() { neutral = .bored }
                neutralUntil = Date().addingTimeInterval(Double.random(in: 12...30))
            }
            next = neutral
            poolState = .normal
        } else if cfg.mode == .dynamic, let pool = s.pool {
            // Di dalam satu keadaan wajah berganti-ganti ekspresi dari kumpulannya, tidak diam di satu wajah.
            let now = Date()
            if s != poolState || now > poolUntil {
                let fresh = s != poolState
                poolState = s
                poolUntil = now.addingTimeInterval(s == .music ? Double.random(in: 3.5...8) : Double.random(in: 7...15))
                if let picked = pool.filter({ $0 != base }).randomElement() {
                    base = picked
                    next = picked
                    if !fresh { react(picked.motion) }
                }
            } else {
                next = base
            }
        } else {
            poolState = s
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

    /// Volume atau kecerahan berubah: volume naik takjub, turun malu, bisu sedih, layar terang kepanasan, redup mengantuk.
    func react(to level: NotchModel.Level) {
        let cfg = config()
        guard cfg.mode != .fixed else { return }
        var s: Situation?
        switch level {
        case .volume(let value, let muted):
            let prev = lastVolume
            lastVolume = value
            if muted { s = .muted }
            else if let prev, abs(value - prev) > 0.01 { s = value > prev ? .volumeUp : .volumeDown }
        case .brightness(let value):
            let prev = lastBright
            lastBright = value
            if let prev, abs(value - prev) > 0.01 { s = value > prev ? .brightUp : .brightDown }
        }
        guard let s, let chosen = cfg.emotion(for: s) else { return }
        play([(chosen, 2.2, chosen.motion)])
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
            case .note where right:
                FloatingNote().offset(x: 8, y: -6)
            case .sparkle:
                Twinkle().offset(x: right ? 9 : -9, y: -8)
            case .tear where !right:
                Image(systemName: "drop.fill").font(.system(size: 6)).foregroundStyle(Color(red: 0.49, green: 0.83, blue: 0.99)).offset(x: -2, y: 10)
            case .blush:
                Ellipse().fill(Color(red: 1, green: 0.48, blue: 0.64).opacity(0.6)).frame(width: 10 * scale, height: 4.4 * scale).offset(y: 9)
            default: EmptyView()
            }
        }
        .modifier(Groove(on: face.groove, right: right, face: face))
        // Menoleh ke kursor (rumus kepala bola, disederhanakan untuk mata persegi panjang): mata bergeser searah pandangan;
        // mata di sisi yang dituju sedikit menyempit karena berputar menjauh dari penonton.
        .scaleEffect(x: (right ? 1 : -1) * face.gaze.width > 0 ? 1 - 0.28 * min(1, abs(face.gaze.width)) : 1, y: 1)
        .offset(x: p.gx * 0.5 + face.glance.width + face.gaze.width * 4.5 * scale, y: p.gy * 0.5 + face.glance.height + face.gaze.height * 2.6 * scale)
        .frame(width: 14 * scale, height: 16 * scale)
        .padding(.horizontal, 4)
    }
}

/// Not musik yang naik dan memudar berulang di samping mata (ekspresi bernyanyi).
struct FloatingNote: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { t in
            let phase = (t.date.timeIntervalSinceReferenceDate / 1.3).truncatingRemainder(dividingBy: 1)
            Text("\u{266A}").font(.system(size: 9, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                .opacity(phase < 0.3 ? phase / 0.3 : 1 - (phase - 0.3) / 0.7)
                .offset(x: 3 * phase, y: 2 - 7 * phase)
        }
    }
}

/// Bintang kecil yang berkilau (ekspresi bangga dan takjub).
struct Twinkle: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { t in
            let k = 0.875 + 0.275 * sin(t.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.1)
            Image(systemName: "sparkle").font(.system(size: 7, weight: .bold)).foregroundStyle(Color(red: 0.99, green: 0.9, blue: 0.54))
                .scaleEffect(k)
        }
    }
}

/// Mata mengangguk pelan mengikuti irama saat musik diputar (hanya berjalan selama `on`; selain itu tanpa animasi).
struct Groove: ViewModifier {
    var on: Bool
    var right: Bool
    var face: Face? = nil

    func body(content: Content) -> some View {
        if on {
            TimelineView(.animation(minimumInterval: 1.0 / 30)) { t in
                // Turun tepat di ketukan lagu (BeatTracker); tanpa pelacak, tempo sedang.
                let now = t.date.timeIntervalSinceReferenceDate
                let v = face?.vibe()
                // Santai: anggukan lambat (beberapa ketukan per siklus) dan kecil.
                let depth = v?.slowDepth(at: now) ?? (1 + cos(now * .pi / 1.2)) / 2
                let sway = v?.slowSway(at: now) ?? sin(now * .pi / 1.2)
                let amp = v.map { 0.5 + 0.35 * min(1, $0.energy * 1.4) } ?? 0.6
                content.offset(y: 1.0 * depth * amp).rotationEffect(.degrees((right ? -1 : 1) * 1.2 * sway * amp))
            }
        } else {
            content
        }
    }
}
