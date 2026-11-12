import Foundation

/// Aturan kapan alarm berbunyi: jam, hari berulang (kosong = sekali), dan jendela toleransi untuk alarm yang terlambat
/// (Mac tidur atau notch baru dibuka). Murni dan tanpa tampilan, supaya bisa diuji.
public enum AlarmSchedule {
    /// "yyyy-MM-dd" menurut kalender lokal; dipakai supaya satu alarm tidak berbunyi dua kali sehari.
    public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// Alarm jatuh tempo bila aktif, hari cocok (Calendar.weekday: 1 Minggu sampai 7 Sabtu), belum berbunyi hari ini,
    /// dan waktunya sudah tiba tetapi belum lewat `graceMinutes`.
    public static func isDue(hour: Int, minute: Int, days: [Int], enabled: Bool, firedOn: String?, now: Date,
                             graceMinutes: Int = 10, calendar: Calendar = .current) -> Bool {
        guard enabled, firedOn != dayKey(now, calendar: calendar) else { return false }
        let weekday = calendar.component(.weekday, from: now)
        guard days.isEmpty || days.contains(weekday) else { return false }
        let nowMinutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
        let at = hour * 60 + minute
        return nowMinutes >= at && nowMinutes < at + graceMinutes
    }
}
