import Foundation

/// Data yang dibagikan dari Cognify Notch ke widget macOS. Berkas ini dikompilasi dua kali: ke app
/// (penulis) dan ke ekstensi widget (pembaca, di dalam sandbox). Waktu = detik epoch.
struct WidgetSnapshot: Codable, Equatable {
    struct Event: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var start: Double
        var end: Double?
        var allDay: Bool
        var calendar: String
        /// Tugas (mis. Moodle), bukan acara berjam.
        var isTask: Bool
    }
    struct Todo: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var done: Bool
        var due: Double?
    }
    struct Weather: Codable, Equatable {
        var tempC: Int
        /// Kode cuaca WMO (Open-Meteo), sama dengan yang dipakai Notch.
        var code: Int
        var place: String
    }
    struct Water: Codable, Equatable {
        var goalMl: Int
        var todayMl: Int
    }
    struct Countdown: Codable, Equatable, Identifiable {
        var id: String
        var title: String
        var end: Double
        var total: Double
    }
    struct Note: Codable, Equatable, Identifiable {
        var id: String
        var text: String
        var date: Double
    }
    var updatedAt: Double
    var events: [Event]
    var todos: [Todo]
    // Ditambahkan setelah versi pertama: opsional supaya berkas lama tetap terbaca.
    var weather: Weather? = nil
    var water: Water? = nil
    var timers: [Countdown]? = nil
    var notes: [Note]? = nil

    static let empty = WidgetSnapshot(updatedAt: 0, events: [], todos: [])

    /// Folder asli milik pengguna. Di dalam sandbox `~` menunjuk ke container, jadi diambil dari basis data pengguna.
    static var folder: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent("Library/Application Support/Cognify Notch Widgets", isDirectory: true)
    }
    static var file: URL { folder.appendingPathComponent("widget.json") }

    static func read() -> WidgetSnapshot {
        guard let data = try? Data(contentsOf: file), data.count < 1_000_000,
              let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snap
    }
}
