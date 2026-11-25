import Foundation

// Pelacak irama untuk wajah Mimik (Skin Mimik dan Kepala Mimik): dari kerasnya suara tiap ~30 ms menebak kapan ketukan terjadi
// dan seberapa cepat temponya, lalu memberi fase yang dipakai kepala untuk mengangguk tepat di ketukan. Tanpa suara asli
// (izin audio ditolak) wajah tetap mengangguk pada tempo sedang. Sama dengan beat.ts di Windows.

public struct BeatTracker {
    /// Kerasnya musik yang dihaluskan, 0...1. Nol = tidak ada suara.
    public private(set) var energy = 0.0
    /// Perkiraan detik per ketukan (0,3 sampai 1,1).
    public private(set) var period = 0.6
    /// Jumlah ketukan yang terdeteksi sejak mulai.
    public private(set) var beats = 0
    /// Waktu ketukan terakhir (detik); jangkar fase.
    public private(set) var lastBeat = -100.0

    private var mean = 0.0
    private var primed = false
    private var previous = 0.0
    private var intervals: [Double] = []

    public init() {}

    /// Suara terdengar (di atas ambang diam).
    public var isAudible: Bool { energy > 0.04 }

    /// Satu cuplikan kerasnya suara (0...1) pada waktu `t`. Mengembalikan true bila ini ketukan baru.
    @discardableResult
    public mutating func feed(level: Double, at t: Double) -> Bool {
        let level = min(1, max(0, level))
        if !primed { primed = true; mean = level; previous = level } // tanpa ini suara datar pun dianggap ketukan di awal
        energy += (level - energy) * (level > energy ? 0.35 : 0.12)
        let threshold = mean * 1.28 + 0.04
        var beat = false
        if level > threshold, level >= previous, t - lastBeat > 0.27, energy > 0.05 {
            let gap = t - lastBeat
            if gap > 0.3, gap < 1.1 {
                intervals.append(gap)
                if intervals.count > 8 { intervals.removeFirst() }
                let sorted = intervals.sorted()
                period = period * 0.65 + sorted[sorted.count / 2] * 0.35
            }
            lastBeat = t
            beats += 1
            beat = true
        }
        mean += (level - mean) * 0.06
        previous = level
        // Lama tanpa ketukan: tempo kembali ke sedang dan sisa interval dibuang.
        if t - lastBeat > 2.5 { period += (0.6 - period) * 0.05; intervals.removeAll() }
        return beat
    }

    /// Tanpa data suara sama sekali (mis. izin audio ditolak) tetapi musik diputar: ketukan sintetis pada tempo sedang.
    public mutating func feedSteady(at t: Double) {
        energy += (0.55 - energy) * 0.1
        if t - lastBeat >= period - 0.001 { lastBeat = t; beats += 1 }
    }

    /// Fase dalam satu ketukan, 0 (tepat di ketukan) sampai 1.
    public func phase(at t: Double) -> Double {
        let p = (t - lastBeat) / period
        return p - p.rounded(.down)
    }

    /// Seberapa dalam anggukan sekarang: 1 tepat di ketukan, 0 di antara ketukan.
    public func depth(at t: Double) -> Double { (1 + cos(2 * .pi * phase(at: t))) / 2 }

    /// Anggukan santai: satu siklus meliputi beberapa ketukan (2, atau 4 bila tempo cepat) sehingga selalu pelan, minimal ~1,3 detik
    /// per anggukan, dan tetap sejalan dengan ketukan. Fase 0 jatuh pada ketukan kelipatan siklus.
    public func slowCycle() -> Int { period * 2 >= 1.3 ? 2 : 4 }

    public func slowPhase(at t: Double) -> Double {
        let k = Double(slowCycle())
        let p = ((t - lastBeat) / period + Double(beats % slowCycle())) / k
        return p - p.rounded(.down)
    }

    /// 1 saat kepala paling rendah (di tengah anggukan), 0 saat tegak; melengkung halus.
    public func slowDepth(at t: Double) -> Double { (1 + cos(2 * .pi * slowPhase(at: t))) / 2 }

    /// Miring perlahan ke satu sisi lalu ke sisi lain dalam satu siklus: -1...1.
    public func slowSway(at t: Double) -> Double { sin(2 * .pi * slowPhase(at: t)) }

    /// Goyangan kiri-kanan: berganti arah tiap ketukan, -1...1.
    public func sway(at t: Double) -> Double { (beats % 2 == 0 ? 1 : -1) * sin(.pi * phase(at: t)) }
}
