import AppKit
import Combine
import SwiftUI

// MARK: - Timer belajar (Pomodoro)

@MainActor
final class StudyTimer: ObservableObject {
    enum Mode: String, CaseIterable {
        case focus, rest

        var label: String { self == .focus ? "Fokus" : "Istirahat" }
        var minutes: Int { self == .focus ? 25 : 5 }
    }

    @Published private(set) var mode: Mode = .focus
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var running = false
    @Published private(set) var sessionsToday = 0

    /// Dipanggil saat waktu habis (notch menampilkan pemberitahuan).
    var onFinish: ((Mode) -> Void)?

    private var endDate: Date?
    private var ticker: Timer?
    private let defaults = UserDefaults.standard

    init() {
        sessionsToday = defaults.string(forKey: "timer.day") == Self.today ? defaults.integer(forKey: "timer.sessions") : 0
    }

    var total: TimeInterval { TimeInterval(mode.minutes * 60) }
    var progress: Double { 1 - remaining / total }
    var isIdle: Bool { !running && remaining == total }

    func select(_ next: Mode) {
        guard next != mode || !running else { return }
        stop()
        mode = next
        remaining = total
    }

    func toggle() { running ? pause() : start() }

    func start() {
        endDate = Date().addingTimeInterval(remaining)
        running = true
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        tick()
        running = false
        ticker?.invalidate()
        ticker = nil
    }

    func reset() {
        stop()
        remaining = total
    }

    private func stop() {
        running = false
        ticker?.invalidate()
        ticker = nil
        endDate = nil
    }

    private func tick() {
        guard running, let endDate else { return }
        remaining = max(0, endDate.timeIntervalSinceNow.rounded(.up))
        if remaining <= 0 { finish() }
    }

    private func finish() {
        let finished = mode
        stop()
        if finished == .focus {
            sessionsToday += 1
            defaults.set(Self.today, forKey: "timer.day")
            defaults.set(sessionsToday, forKey: "timer.sessions")
        }
        mode = finished == .focus ? .rest : .focus
        remaining = total
        onFinish?(finished)
    }

    private static var today: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - Status notch

@MainActor
final class NotchModel: ObservableObject {
    enum Tab: CaseIterable {
        case home, notes, tray, timer, mirror, shortcuts

        var icon: String {
            switch self {
            case .home: return "house.fill"
            case .notes: return "note.text"
            case .tray: return "tray.full.fill"
            case .timer: return "timer"
            case .mirror: return "person.crop.square"
            case .shortcuts: return "bolt.fill"
            }
        }

        var label: String {
            switch self {
            case .home: return "Beranda"
            case .notes: return "Catatan"
            case .tray: return "Tray"
            case .timer: return "Timer"
            case .mirror: return "Cermin"
            case .shortcuts: return "Pintasan"
            }
        }
    }

    /// Bagian notch yang bisa dinyalakan/dimatikan di Pengaturan Cognify (dikirim lewat stdin).
    struct Features: Equatable {
        var media = true
        var calendar = false // perlu izin Kalender, jadi default mati
        var camera = true
        var shortcuts = true
        var hud = true
        var spectrum = true // equalizer mengikuti suara asli (izin audio macOS)
    }

    /// Perubahan volume / kecerahan yang sedang ditampilkan.
    enum Level: Equatable {
        case volume(Double, muted: Bool)
        case brightness(Double)
    }

    /// Pesan singkat di notch. `alert` membuka notch sebentar walau kursor tidak di sana.
    enum Toast: Equatable {
        case working(String)
        case done(String)
        case failed(String)
        case alert(title: String, detail: String, action: AlertAction?)
    }

    enum AlertAction: Equatable {
        case startTimer(String) // label tombol
        case open(path: String)
    }

    /// Isi "sayap" kiri-kanan notch saat tertutup (mirip Live Activity).
    struct Live: Equatable {
        let icon: String
        var text: String = ""
        let tint: Color
        var level: Double? = nil // bar volume/kecerahan menggantikan teks
        var media = false // sampul + equalizer
    }

    @Published var expanded = false
    @Published var tab: Tab = .home
    @Published var dropTargeted = false
    @Published var state: NotchState?
    @Published var connected = false
    @Published var toast: Toast?
    @Published var note = ""
    @Published var savingNote = false
    @Published var notchSize = CGSize(width: 185, height: 32)
    @Published var hasNotch = true
    @Published var now = Date()
    @Published private(set) var features = Features()
    @Published private(set) var level: Level?

    /// App mandiri "Cognify Notch" (tanpa Cognify): agenda dari Kalender saja, catatan cepat
    /// disimpan di notch, seret file langsung ke tray, pengaturan lewat ikon menu bar.
    let appMode: Bool
    let notes = LocalNotes()
    let timer = StudyTimer()
    let media = MediaMonitor()
    let spectrum = Spectrum()
    let tray = TrayModel()
    let calendar = CalendarFeed()
    let camera = CameraMirror()
    let shortcuts = ShortcutsModel()
    private let levels = SystemLevels()
    private var levelTask: Task<Void, Never>?
    let bridge: Bridge?
    private(set) var api: API?

    private var hovering = false
    private var collapseTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var announced = Set<String>()
    private var changes = Set<AnyCancellable>()

    init(bridge: Bridge?, appMode: Bool = false) {
        self.bridge = bridge
        self.appMode = appMode
        // Sayap notch & ukurannya bergantung pada timer: teruskan perubahannya.
        for publisher in [timer.objectWillChange.eraseToAnyPublisher(), media.objectWillChange.eraseToAnyPublisher(),
                          tray.objectWillChange.eraseToAnyPublisher(), calendar.objectWillChange.eraseToAnyPublisher(),
                          notes.objectWillChange.eraseToAnyPublisher()] {
            publisher.sink { [weak self] in self?.objectWillChange.send() }.store(in: &changes)
        }
        levels.onChange = { [weak self] level in self?.showLevel(level) }
        media.$nowPlaying.sink { [weak self] now in
            DispatchQueue.main.async { self?.updateSpectrum(playing: now?.playing == true) }
        }.store(in: &changes)
        timer.onFinish = { [weak self] mode in
            NSSound(named: "Glass")?.play()
            self?.tab = .timer
            self?.show(.alert(
                title: mode == .focus ? "Waktu fokus selesai" : "Istirahat selesai",
                detail: mode == .focus ? "Istirahat 5 menit dulu, lalu lanjut lagi." : "Siap fokus lagi?",
                action: .startTimer(mode == .focus ? "Mulai istirahat" : "Mulai fokus")
            ))
        }
    }

    // MARK: Ukuran

    static let expandedSize = CGSize(width: 680, height: 222)
    static let wing: CGFloat = 76

    var size: CGSize {
        if expanded { return CGSize(width: Self.expandedSize.width, height: Self.expandedSize.height + notchSize.height - 32) }
        if live != nil { return CGSize(width: notchSize.width + Self.wing * 2, height: notchSize.height) }
        return notchSize
    }

    var live: Live? {
        switch level {
        case .volume(let value, let muted)?:
            let icon = muted || value == 0 ? "speaker.slash.fill" : value < 0.34 ? "speaker.wave.1.fill" : value < 0.67 ? "speaker.wave.2.fill" : "speaker.wave.3.fill"
            return Live(icon: icon, tint: .white, level: muted ? 0 : value)
        case .brightness(let value)?:
            return Live(icon: value < 0.5 ? "sun.min.fill" : "sun.max.fill", tint: .yellow, level: value)
        case nil: break
        }
        switch toast {
        case .working(let text)?: return Live(icon: "arrow.down.circle", text: text, tint: .accent)
        case .done?: return Live(icon: "checkmark.circle.fill", text: "Tersimpan", tint: .green)
        case .failed?: return Live(icon: "exclamationmark.circle.fill", text: "Gagal", tint: .orange)
        case .alert?: return Live(icon: "bell.fill", text: "Sekarang", tint: .accent)
        case nil: break
        }
        if timer.running {
            return Live(icon: timer.mode == .focus ? "brain.head.profile" : "cup.and.saucer.fill",
                        text: StudyTimer.clock(timer.remaining), tint: timer.mode == .focus ? .accent : .green)
        }
        if let next = state?.events.first(where: { !$0.allDay }),
           next.due.timeIntervalSince(now) <= 60 * 60, next.due > now {
            return Live(icon: next.kind == "deadline" ? "calendar.badge.clock" : "bell", text: Relative.short(next.due, now: now), tint: .orange)
        }
        if features.media, media.nowPlaying?.playing == true {
            return Live(icon: "music.note", tint: .accent, media: true)
        }
        return nil
    }

    /// Tab yang terlihat sesuai fitur yang dinyalakan.
    var tabs: [Tab] {
        Tab.allCases.filter {
            switch $0 {
            case .mirror: return features.camera
            case .shortcuts: return features.shortcuts
            case .notes: return appMode
            default: return true
            }
        }
    }

    private func updateSpectrum(playing: Bool) {
        spectrum.setActive(features.media && features.spectrum && playing)
    }

    func apply(_ next: Features) {
        features = next
        media.setEnabled(next.media)
        updateSpectrum(playing: media.nowPlaying?.playing == true)
        calendar.setEnabled(next.calendar)
        levels.setEnabled(next.hud)
        if !tabs.contains(tab) { tab = .home }
    }

    // Untuk snapshot.
    func preview(level next: Level?, features next2: Features? = nil) {
        level = next
        if let next2 { features = next2 }
    }

    private func showLevel(_ next: Level) {
        levelTask?.cancel()
        withAnimation(.notch) { level = next }
        levelTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_600_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.notch) { self?.level = nil }
        }
    }

    // MARK: Hover & buka-tutup

    func setHover(_ inside: Bool) {
        guard inside != hovering else { return }
        hovering = inside
        collapseTask?.cancel()
        if inside {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 90_000_000) // lewat sekilas tidak membuka notch
                guard !Task.isCancelled else { return }
                self?.setExpanded(true)
            }
        } else {
            collapseTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                self?.setExpanded(false)
            }
        }
    }

    func setExpanded(_ value: Bool) {
        guard value != expanded else { return }
        withAnimation(.notch) { expanded = value }
        if value {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            refresh()
        }
    }

    // MARK: Data

    func connect(_ info: BackendInfo?) {
        api = info.map(API.init)
        connected = info != nil
        refreshTask?.cancel()
        guard info != nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.load()
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    func refresh() { Task { await load() } }

    private func load() async {
        guard let api else { return }
        do {
            let next = try await api.state()
            now = Date()
            if next != state { withAnimation(.notch) { state = next } }
            announceDue()
        } catch {
            // Sidecar sedang restart; coba lagi pada putaran berikutnya.
        }
    }

    /// Kegiatan yang jatuh tempo sekarang (bukan sepanjang hari) → notch terbuka sebentar.
    private func announceDue() {
        for event in state?.events ?? [] where !event.allDay && !announced.contains(event.id) {
            let wait = event.due.timeIntervalSinceNow
            if wait <= 0 && wait > -120 {
                announced.insert(event.id)
                NSSound(named: "Glass")?.play()
                show(.alert(title: event.title, detail: event.subtitle ?? "Sekarang", action: .open(path: event.path)))
            } else if wait > 0 && wait < 35 {
                Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
                    await self?.load()
                }
            }
        }
    }

    // MARK: Aksi

    func show(_ next: Toast) {
        toastTask?.cancel()
        withAnimation(.notch) { toast = next }
        if case .alert = next { setExpanded(true) }
        let seconds: Double
        switch next {
        case .working: return
        case .done, .failed: seconds = 3.5
        case .alert: seconds = 7
        }
        toastTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            withAnimation(.notch) { self.toast = nil }
            if case .alert = next, !self.hovering { self.setExpanded(false) }
        }
    }

    func saveNote() {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if appMode, !text.isEmpty {
            notes.add(text)
            note = ""
            show(.done("Catatan tersimpan di tab Catatan"))
            return
        }
        guard !text.isEmpty, let api, !savingNote else { return }
        savingNote = true
        Task {
            do {
                let title = try await api.quickNote(text)
                note = ""
                show(.done("Catatan “\(title)” tersimpan"))
                await load()
            } catch {
                show(.failed(error.localizedDescription))
            }
            savingNote = false
        }
    }

    /// File, tautan, atau teks yang diseret ke notch.
    func save(files: [URL], links: [URL], texts: [String]) {
        guard let api else {
            show(.failed("Cognify belum siap. Coba lagi sebentar."))
            return
        }
        let total = files.count + links.count + texts.count
        guard total > 0 else { return }
        Task {
            var saved: [String] = []
            var failure: String?
            for (i, file) in files.enumerated() {
                show(.working(total > 1 ? "\(i + 1)/\(total)" : "Menyimpan"))
                do { saved.append(try await api.upload(file)) } catch { failure = "\(file.lastPathComponent): \(error.localizedDescription)" }
            }
            for link in links {
                show(.working(total > 1 ? "\(saved.count + 1)/\(total)" : "Menyimpan"))
                do { saved.append(try await api.saveURL(link)) } catch { failure = error.localizedDescription }
            }
            for text in texts {
                do { saved.append(try await api.quickNote(text)) } catch { failure = error.localizedDescription }
            }
            if let failure {
                show(.failed(saved.isEmpty ? failure : "\(saved.count) tersimpan. \(failure)"))
            } else {
                show(.done(saved.count == 1 ? "“\(saved[0])” masuk Knowledge" : "\(saved.count) item masuk Knowledge"))
            }
            await load()
        }
    }

    func open(_ path: String) {
        bridge?.open(path: path)
        setExpanded(false)
    }
}

// MARK: - Catatan lokal (app mandiri)

struct LocalNote: Codable, Identifiable, Equatable {
    let id: UUID
    var text: String
    let date: Date
}

@MainActor
final class LocalNotes: ObservableObject {
    @Published private(set) var items: [LocalNote] = []
    private let key = "notes.items"

    init() {
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode([LocalNote].self, from: data) {
            items = saved
        }
    }

    func add(_ text: String) {
        withAnimation(.notch) { items.insert(LocalNote(id: UUID(), text: text, date: Date()), at: 0) }
        items = Array(items.prefix(100))
        save()
    }

    func remove(_ note: LocalNote) {
        withAnimation(.notch) { items.removeAll { $0.id == note.id } }
        save()
    }

    func copy(_ note: LocalNote) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(note.text, forType: .string)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
    }

    // Untuk snapshot.
    func preview(_ texts: [String]) {
        items = texts.enumerated().map { LocalNote(id: UUID(), text: $1, date: Date().addingTimeInterval(Double(-$0) * 3600)) }
    }
}

// MARK: - Format waktu (Bahasa Indonesia)

enum Relative {
    private static let calendar = Calendar.current

    private static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "HH.mm"
        return f.string(from: date)
    }

    private static func day(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "id_ID")
        f.dateFormat = "EEE d MMM"
        return f.string(from: date)
    }

    /// "15 menit lagi", "Hari ini 14.00", "Besok", "Sen 29 Sep 10.00".
    static func long(_ due: Date, allDay: Bool, now: Date) -> String {
        if allDay {
            if calendar.isDate(due, inSameDayAs: now) { return "Hari ini" }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) { return "Besok" }
            return day(due)
        }
        let minutes = Int(due.timeIntervalSince(now) / 60)
        if minutes < 1 { return "Sekarang" }
        if minutes < 60 { return "\(minutes) menit lagi" }
        if minutes < 6 * 60 { return "\(minutes / 60) jam lagi" }
        if calendar.isDate(due, inSameDayAs: now) { return "Hari ini \(time(due))" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
            return "Besok \(time(due))"
        }
        return "\(day(due)) \(time(due))"
    }

    /// Untuk sayap notch: "15m", "1j".
    static func short(_ due: Date, now: Date) -> String {
        let minutes = max(0, Int(due.timeIntervalSince(now) / 60))
        return minutes < 60 ? "\(minutes)m" : "\(minutes / 60)j"
    }
}

extension Animation {
    /// Pegas yang dipakai semua perubahan bentuk notch.
    static let notch = Animation.spring(response: 0.42, dampingFraction: 0.8)
}

extension Color {
    /// Ungu Cognify (#4f46e5) yang diterangkan supaya terbaca di atas hitam.
    static let accent = Color(red: 0.56, green: 0.53, blue: 1.0)
}
