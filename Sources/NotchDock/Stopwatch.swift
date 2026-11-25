import Foundation

// Hitungan stopwatch berbasis jam dinding (wall clock), supaya benar saat Mac tidur atau app ditutup. Yang disimpan hanya
// waktu mulai (`startedAt`), detik sebelum jeda terakhir (`accumulated`), dan lap. Waktu berjalan dihitung dari jam sekarang
// dikurangi jam mulai, jadi tidur dan pembukaan ulang app tidak mengubah hasilnya. Sama dengan stopwatch.ts di Windows.

public struct StopwatchSnapshot: Codable, Equatable {
    public var startedAt: Double? // detik sejak 1970 saat dinyalakan; nil = berhenti
    public var accumulated: Double
    public var laps: [Double]

    public init(startedAt: Double? = nil, accumulated: Double = 0, laps: [Double] = []) {
        self.startedAt = startedAt
        self.accumulated = accumulated
        self.laps = laps
    }
}

public enum StopwatchMath {
    /// Detik berjalan. Jam sistem yang dimundurkan tidak menghasilkan angka negatif.
    public static func elapsed(accumulated: Double, startedAt: Double?, now: Double) -> Double {
        max(0, accumulated + (startedAt.map { max(0, now - $0) } ?? 0))
    }

    /// Detik → jam, menit, detik utuh (jam tidak dibatasi 24).
    public static func split(_ seconds: Double) -> (h: Int, m: Int, s: Int) {
        let whole = Int(max(0, seconds).rounded(.down))
        return (whole / 3600, whole / 60 % 60, whole % 60)
    }

    /// Bacaan dari penyimpanan yang mungkin rusak: nilai negatif atau bukan angka dibuang.
    public static func sanitized(_ s: StopwatchSnapshot) -> StopwatchSnapshot {
        func ok(_ v: Double) -> Bool { v.isFinite && v >= 0 }
        return StopwatchSnapshot(startedAt: s.startedAt.flatMap { ok($0) ? $0 : nil }, accumulated: ok(s.accumulated) ? s.accumulated : 0, laps: s.laps.filter(ok))
    }
}
