import Combine
import Foundation

/// Menulis salinan data Notch untuk Cognify utama. Protokol lengkap: docs/NOTCH_LINK.md di repo Cognify.
///
/// Tidak menulis apa pun sampai pengguna menekan "Hubungkan ke Cognify Notch" di Cognify, yang membuat
/// `link.json` di folder bersama. Berkas itu hilang atau `enabled` bukan true → data dihapus dan
/// penulisan berhenti. Riwayat clipboard hanya ikut bila `share.clipboard` true.
@MainActor
final class NotchLink {
    nonisolated static let schema = 1
    nonisolated static let maxNotes = 100
    nonisolated static let maxClipboard = 40
    nonisolated static let maxAgenda = 50

    // MARK: - Format berkas (harus sinkron dengan docs/NOTCH_LINK.md)

    struct Consent: Decodable {
        var enabled: Bool?
        var share: Share?
        struct Share: Decodable { var clipboard: Bool? }
    }

    struct Todo: Encodable { let id: String; let title: String; let done: Bool; let dueAt: String? }
    struct Note: Encodable { let id: String; let text: String; let createdAt: String }
    struct Clip: Encodable { let id: String; let kind: String; let text: String; let at: String }
    struct Tray: Encodable { let id: String; let name: String; let path: String }
    struct Timer: Encodable { let id: String; let title: String; let durationSec: Int; let endsAt: String; let running: Bool }
    struct Sip: Encodable { let at: String; let ml: Int }
    struct Day: Encodable { let date: String; let ml: Int }
    struct Water: Encodable { let goalMl: Int; let today: [Sip]; let history: [Day] }
    struct Agenda: Encodable {
        let id: String; let title: String; let start: String; let end: String?; let allDay: Bool; let calendar: String
    }
    struct Weather: Encodable { let tempC: Double; let summary: String; let place: String }
    struct Playing: Encodable { let title: String; let artist: String? }
    struct Battery: Encodable { let percent: Int; let charging: Bool }
    struct Now: Encodable { let weather: Weather?; let playing: Playing?; let battery: Battery? }

    struct Payload: Encodable {
        var schema = NotchLink.schema
        var platform = "mac"
        var appVersion: String
        var updatedAt: String
        var todos: [Todo]
        var notes: [Note]
        var clipboard: [Clip]?
        var tray: [Tray]
        var timers: [Timer]
        var water: Water?
        var agenda: [Agenda]
        var now: Now?
    }

    // MARK: - Lokasi

    /// `COGNIFY_LINK_DIR` menggantikan folder bersama (dipakai uji agar tidak menyentuh folder pengguna).
    static var folder: URL {
        if let custom = ProcessInfo.processInfo.environment["COGNIFY_LINK_DIR"] {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cognify Link", isDirectory: true)
    }

    private var consentURL: URL { Self.folder.appendingPathComponent("link.json") }
    private var dataURL: URL { Self.folder.appendingPathComponent("notch-data.json") }

    // MARK: - Status

    private let model: NotchModel
    private var consent: Consent?
    private var consentStamp: Date??
    private var observer: AnyCancellable?
    private var poll: Foundation.Timer?
    private var heartbeat: Foundation.Timer?
    private var lastKey: Data?
    private let fm = FileManager.default

    init(model: NotchModel) {
        self.model = model
    }

    /// Mulai memantau persetujuan. Murah: satu pemeriksaan tanggal berkas kecil tiap 5 detik.
    func start() {
        checkConsent()
        let timer = Foundation.Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkConsent() }
        }
        timer.tolerance = 3
        poll = timer
    }

    private func checkConsent() {
        let stamp = (try? fm.attributesOfItem(atPath: consentURL.path))?[.modificationDate] as? Date
        if let known = consentStamp, known == stamp { return }
        consentStamp = .some(stamp)

        guard let bytes = try? Data(contentsOf: consentURL),
              let next = try? JSONDecoder().decode(Consent.self, from: bytes), next.enabled == true else {
            if consent != nil { consent = nil; stopPublishing() }
            removeData()
            return
        }
        let wasOn = consent != nil
        consent = next
        if wasOn {
            lastKey = nil // izin berbagi berubah: tulis ulang segera
            write(force: true)
        } else {
            startPublishing()
        }
    }

    private func startPublishing() {
        // objectWillChange terbit sebelum nilainya berubah; throttle membuat penulisan terjadi sesudahnya
        // dan paling sering sekali per 2 detik, sedangkan `lastKey` mencegah menulis isi yang sama.
        let m = model
        observer = Publishers.MergeMany([
            m.notes.objectWillChange.eraseToAnyPublisher(),
            m.todo.objectWillChange.eraseToAnyPublisher(),
            m.tray.objectWillChange.eraseToAnyPublisher(),
            m.clock.objectWillChange.eraseToAnyPublisher(),
            m.water.objectWillChange.eraseToAnyPublisher(),
            m.calendar.objectWillChange.eraseToAnyPublisher(),
            m.weather.objectWillChange.eraseToAnyPublisher(),
            m.clipboard.objectWillChange.eraseToAnyPublisher(),
            m.media.$nowPlaying.map { _ in () }.eraseToAnyPublisher(),
            m.$battery.map { _ in () }.eraseToAnyPublisher(),
        ])
        .throttle(for: .seconds(2), scheduler: RunLoop.main, latest: true)
        .sink { [weak self] _ in self?.write(force: false) }

        // Tanda "Notch masih hidup" meski tidak ada perubahan.
        let beat = Foundation.Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.write(force: true) }
        }
        beat.tolerance = 10
        heartbeat = beat
        write(force: true)
    }

    private func stopPublishing() {
        observer = nil
        heartbeat?.invalidate()
        heartbeat = nil
        lastKey = nil
    }

    private func removeData() {
        try? fm.removeItem(at: dataURL)
    }

    // MARK: - Menulis

    private func write(force: Bool) {
        guard let consent else { return }
        let now = Date()
        var payload = Self.payload(from: model, shareClipboard: consent.share?.clipboard == true, now: now)

        payload.updatedAt = ""
        let encoder = Self.encoder()
        guard let key = try? encoder.encode(payload) else { return }
        if !force, key == lastKey { return }
        lastKey = key

        payload.updatedAt = Self.iso(now)
        guard let bytes = try? encoder.encode(payload) else { return }
        do {
            try bytes.write(to: dataURL, options: .atomic)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: dataURL.path)
        } catch {
            // Folder bersama hilang atau tidak bisa ditulis: coba lagi pada perubahan berikutnya.
        }
    }

    /// Dipakai uji tanpa jendela: `cognify-notch --link-dump <folder>`.
    func dump(to url: URL, shareClipboard: Bool) throws {
        var payload = Self.payload(from: model, shareClipboard: shareClipboard, now: Date())
        payload.updatedAt = Self.iso(Date())
        try Self.encoder().encode(payload).write(to: url, options: .atomic)
    }

    // MARK: - Pemetaan dari model Notch

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return e
    }

    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }

    private static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func weatherText(_ code: Int) -> String {
        switch code {
        case 0: return "Cerah"
        case 1, 2: return "Cerah berawan"
        case 3: return "Berawan"
        case 45, 48: return "Berkabut"
        case 51...57: return "Gerimis"
        case 61...67, 80...82: return "Hujan"
        case 71...77, 85, 86: return "Salju"
        case 95...99: return "Badai petir"
        default: return "Berawan"
        }
    }

    static func payload(from m: NotchModel, shareClipboard: Bool, now: Date) -> Payload {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""

        let todos = m.todo.items.map {
            Todo(id: $0.id.uuidString, title: $0.text, done: $0.done, dueAt: $0.due.map(iso))
        }
        let notes = m.notes.items.prefix(maxNotes).map {
            Note(id: $0.id.uuidString, text: $0.text, createdAt: iso($0.date))
        }
        let clips: [Clip]? = shareClipboard
            ? m.clipboard.items.filter { $0.kind != .image && ($0.text?.isEmpty == false) }.prefix(maxClipboard).map {
                Clip(id: $0.id.uuidString, kind: $0.kind.rawValue, text: $0.text ?? "", at: iso($0.date))
            }
            : nil
        let tray = m.tray.items.compactMap { item -> Tray? in
            guard let url = m.tray.url(for: item) else { return nil }
            return Tray(id: item.id.uuidString, name: item.name, path: url.path)
        }
        let timers = m.clock.countdowns.map {
            Timer(id: $0.id.uuidString, title: $0.label, durationSec: Int($0.total.rounded()), endsAt: iso($0.end), running: $0.end > now)
        }

        let startOfToday = Calendar.current.startOfDay(for: now)
        var perDay: [String: Int] = [:]
        for s in m.water.sips where s.date < startOfToday { perDay[dayKey(s.date), default: 0] += s.ml }
        let water = Water(
            goalMl: m.water.goal,
            today: m.water.sips.filter { $0.date >= startOfToday }.map { Sip(at: iso($0.date), ml: $0.ml) },
            history: perDay.keys.sorted().map { Day(date: $0, ml: perDay[$0] ?? 0) }
        )

        let agenda = m.calendar.events.prefix(maxAgenda).map {
            Agenda(id: $0.id, title: $0.title, start: iso($0.start), end: $0.end.map(iso), allDay: $0.allDay, calendar: $0.calendar)
        }

        let weather = m.weather.now.map { Weather(tempC: Double($0.temperature), summary: weatherText($0.code), place: $0.place) }
        let playing = m.media.nowPlaying.flatMap { $0.playing ? Playing(title: $0.title, artist: $0.artist) : nil }
        let battery = m.battery.map { Battery(percent: $0.percent, charging: $0.charging) }
        let live = (weather == nil && playing == nil && battery == nil) ? nil : Now(weather: weather, playing: playing, battery: battery)

        return Payload(appVersion: version, updatedAt: "", todos: todos, notes: Array(notes), clipboard: clips,
                       tray: tray, timers: timers, water: water, agenda: Array(agenda), now: live)
    }
}
