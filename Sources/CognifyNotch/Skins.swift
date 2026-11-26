import AppKit
import Combine
import NotchDock
import SwiftUI
import WebKit

// Skin: jendela transparan di desktop yang menampilkan halaman web kecil (HTML/CSS/JS) dan menerima data dari
// Notch lewat window.cognify. Seperti Rainmeter: pengguna bisa mengedit atau membuat skin sendiri.
//
// Aturan keamanan: halaman skin hanya bisa memuat berkas dari foldernya sendiri (skema skin://, jalur dijaga dari
// "../"), dan tidak ada akses jaringan (CSP `default-src skin: data: blob:` pada semua jawaban). Data yang
// dikirim sama dengan yang sudah ditampilkan Notch; tidak ada yang keluar dari Mac ini.

struct SkinInfo: Identifiable, Equatable {
    let id: String
    let name: String
    let desc: String
    let width: Double
    let height: Double
    /// Skin meminta posisi kursor (untuk wajah yang mengikuti kursor).
    let cursor: Bool
    /// Skin meminta irama lagu (`cognify.onAudio`): kerasnya musik, ketukan, dan tempo, ±15× per detik selama musik diputar.
    let audio: Bool
    /// Skin meminta kabar saat kursor di atas notch (`cognify.onNotch`).
    let notch: Bool
    /// Posisi awal sebelum skin pernah dipindahkan: top|bottom + left|center|right (mis. "bottom-center").
    let anchor: String
    let entry: String
    let folder: URL
}

private struct SkinManifest: Decodable {
    var name: String?
    var description: String?
    var width: Double?
    var height: Double?
    var cursor: Bool?
    var audio: Bool?
    var notch: Bool?
    var anchor: String?
    var entry: String?
}

@MainActor
final class SkinManager: ObservableObject {
    @Published private(set) var skins: [SkinInfo] = []
    @Published private(set) var enabled: Set<String>
    /// Level jendela: false = di desktop (di bawah jendela lain), true = selalu di atas.
    @Published var onTop: Bool { didSet { UserDefaults.standard.set(onTop, forKey: "skins.onTop"); windows.values.forEach { $0.setLevel(onTop) } } }
    /// Ukuran bawaan untuk skin yang belum diatur sendiri (warisan dari satu ukuran untuk semua skin).
    private(set) var scale: Double
    /// Ukuran per skin (id → pengali); dibatasi `maxScale` supaya tidak pernah melewati layar.
    @Published private(set) var scales: [String: Double] = [:]
    /// Warna lirik skin Lirik.
    @Published var lyricStyle = SkinLyricStyle() { didSet { persistLyricStyle(); pushConfig("lyrics") } }

    /// Gaya wajah skin Mimik dari playground di Pengaturan (warna, bentuk, opsi, suasana, efek); dikirim ke skin sebagai `config`.
    @Published var mimik: MimikStyle { didSet { persistMimik(); pushConfig("mimik") } }
    /// Gaya Mimik yang disimpan pengguna dengan nama sendiri (Pengaturan > Skin).
    @Published private(set) var mimikPresets: [MimikPreset] = []

    func savePreset(named name: String) {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        var style = mimik
        let id = mimikPresets.first(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame })?.id ?? UUID()
        style.preset = "saved:" + id.uuidString
        mimikPresets.removeAll { $0.id == id }
        mimikPresets.append(MimikPreset(id: id, name: String(clean.prefix(24)), style: style))
        mimik = style
        persistPresets()
    }

    func deletePreset(_ id: UUID) {
        mimikPresets.removeAll { $0.id == id }
        persistPresets()
    }

    func apply(_ preset: MimikPreset) {
        var style = preset.style
        style.preset = "saved:" + preset.id.uuidString
        mimik = style
    }

    private func persistPresets() {
        guard persists else { return }
        if let data = try? JSONEncoder().encode(mimikPresets) { UserDefaults.standard.set(data, forKey: "skins.mimikPresets") }
    }

    /// Reaksi sesaat yang diminta dari playground (boing, putar, dan seterusnya); `n` naik tiap permintaan.
    @Published private(set) var reaction = (name: "", n: 0)

    /// Mode atur posisi: semua skin naik ke atas, berbingkai, dan bisa diseret bebas.
    @Published var arranging = false { didSet { windows.values.forEach { $0.setArranging(arranging, onTop: onTop) } } }

    private let model: NotchModel
    private var windows: [String: SkinWindow] = [:]
    private var bag = Set<AnyCancellable>()
    private var monitors: [Any] = []
    private var lastCursorSend = Date.distantPast
    private var audioTimer: Timer?

    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Cognify Notch", isDirectory: true).appendingPathComponent("Skins", isDirectory: true)
    }

    init(model: NotchModel) {
        self.model = model
        let d = UserDefaults.standard
        enabled = Set(d.stringArray(forKey: "skins.enabled") ?? [])
        onTop = d.bool(forKey: "skins.onTop")
        let s = d.double(forKey: "skins.scale")
        scale = s == 0 ? 1 : min(max(s, 0.5), 2.5)
        scales = (d.dictionary(forKey: "skins.scales") as? [String: Double]) ?? [:]
        lyricStyle = d.data(forKey: "skins.lyricStyle").flatMap { try? JSONDecoder().decode(SkinLyricStyle.self, from: $0) } ?? SkinLyricStyle()
        mimik = d.data(forKey: "skins.mimik").flatMap { try? JSONDecoder().decode(MimikStyle.self, from: $0) } ?? MimikStyle()
        mimikPresets = d.data(forKey: "skins.mimikPresets").flatMap { try? JSONDecoder().decode([MimikPreset].self, from: $0) } ?? []
    }

    /// Snapshot (gambar uji) tidak boleh menimpa pengaturan pengguna.
    var persists = true

    private func persistMimik() {
        guard persists else { return }
        if let data = try? JSONEncoder().encode(mimik) { UserDefaults.standard.set(data, forKey: "skins.mimik") }
    }

    /// JSON `config` untuk skin Mimik (gaya + reaksi terakhir).
    func configJSON() -> String {
        guard let data = try? JSONEncoder().encode(mimik), var obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return "{}" }
        obj["react"] = ["name": reaction.name, "n": reaction.n] as [String: Any]
        guard let out = try? JSONSerialization.data(withJSONObject: obj), let text = String(data: out, encoding: .utf8) else { return "{}" }
        return text
    }

    private func persistLyricStyle() {
        guard persists, let data = try? JSONEncoder().encode(lyricStyle) else { return }
        UserDefaults.standard.set(data, forKey: "skins.lyricStyle")
    }

    /// `config` untuk satu skin (nil bila skin itu tidak punya pengaturan).
    private func config(for id: String) -> String? {
        switch id {
        case "mimik": return configJSON()
        case "lyrics": return (try? JSONEncoder().encode(lyricStyle)).flatMap { String(data: $0, encoding: .utf8) }
        default: return nil
        }
    }

    private func pushConfig(_ id: String) {
        guard let json = config(for: id) else { return }
        windows[id]?.pushConfig(json: json)
    }

    // MARK: Ukuran per skin

    /// Sisi terpanjang jendela tidak melewati 96% area layar yang terlihat (tanpa menu bar dan Dock).
    func maxScale(of skin: SkinInfo) -> Double {
        let f = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1440, height: 900)
        return max(0.5, min(2.5, f.width * 0.96 / skin.width, f.height * 0.96 / skin.height))
    }

    func scale(of skin: SkinInfo) -> Double { min(max(scales[skin.id] ?? scale, 0.5), maxScale(of: skin)) }

    func setScale(_ value: Double, of skin: SkinInfo) {
        scales[skin.id] = min(max(value, 0.5), maxScale(of: skin))
        if persists { UserDefaults.standard.set(scales, forKey: "skins.scales") }
        windows[skin.id]?.setScale(scale(of: skin))
    }

    func react(_ name: String) {
        reaction = (name, reaction.n + 1)
        pushConfig("mimik")
    }

    func start() {
        installBuiltins()
        scan()
        for skin in skins where enabled.contains(skin.id) { open(skin) }
        if CommandLine.arguments.contains("--skins-arrange") { arranging = true } // uji: mulai langsung dalam mode atur posisi
        // Layar dicabut, ditambah, atau resolusinya berubah: semua skin masuk kembali ke dalam layar.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.windows.values.forEach { $0.refit() } } }
            .store(in: &bag)
        Publishers.MergeMany([
            model.calendar.$events.map { _ in () }.eraseToAnyPublisher(),
            model.todo.$items.map { _ in () }.eraseToAnyPublisher(),
            model.todo.$moodle.map { _ in () }.eraseToAnyPublisher(),
            model.weather.$now.map { _ in () }.eraseToAnyPublisher(),
            model.water.$sips.map { _ in () }.eraseToAnyPublisher(),
            model.clock.$countdowns.map { _ in () }.eraseToAnyPublisher(),
            model.notes.$items.map { _ in () }.eraseToAnyPublisher(),
            model.media.$nowPlaying.map { _ in () }.eraseToAnyPublisher(),
            model.lyrics.$state.map { _ in () }.eraseToAnyPublisher(),
        ])
        .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
        .sink { [weak self] in MainActor.assumeIsolated { self?.pushAll(); self?.updateAudioTimer() } }
        .store(in: &bag)
        // Kursor di atas notch: skin yang meminta menampilkan reaksi (Mimik: kaget, ragu, terkejut, bingung).
        model.hoverEvents.removeDuplicates().sink { [weak self] inside in
            MainActor.assumeIsolated { self?.windows.values.filter { $0.info.notch }.forEach { $0.sendNotchHover(inside) } }
        }.store(in: &bag)
        model.noticeEvents.sink { [weak self] in
            MainActor.assumeIsolated { self?.windows.values.filter { $0.info.notch }.forEach { $0.sendNotice() } }
        }.store(in: &bag)
    }

    /// Irama lagu hanya dikirim selama musik diputar dan ada skin berpermintaan audio yang menyala: ±15× per detik, tiga angka kecil.
    /// Tanpa itu tidak ada pencacah waktu yang jalan.
    private func updateAudioTimer() {
        let needed = windows.values.contains { $0.info.audio } && model.media.nowPlaying?.playing == true
        if needed, audioTimer == nil {
            // 10 kali per detik cukup: wajah menghitung fasenya sendiri di antara kiriman.
            let t = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.sendAudio() }
            }
            t.tolerance = 0.03
            audioTimer = t
        } else if !needed, audioTimer != nil {
            audioTimer?.invalidate()
            audioTimer = nil
            for w in windows.values where w.info.audio { w.sendAudio(energy: 0, beats: 0, period: 0.6, on: false) }
        }
    }

    private func sendAudio() {
        let v = model.spectrum.vibe(at: Date.timeIntervalSinceReferenceDate)
        for w in windows.values where w.info.audio {
            w.sendAudio(energy: v.energy, beats: v.beats, period: v.period, on: v.isAudible)
        }
    }

    /// Pemantau gerakan mouse hanya hidup selama ada skin berpermintaan kursor yang menyala; tanpa skin, tidak ada beban.
    private func updateMonitors() {
        let needed = windows.values.contains { $0.info.cursor }
        if needed, monitors.isEmpty {
            // Pemantau global tidak butuh izin Aksesibilitas untuk gerakan mouse.
            let handler: (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.sendCursor() } }
            if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: handler) { monitors.append(g) }
            if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { e in handler(e); return e }) { monitors.append(l) }
        } else if !needed {
            monitors.forEach { NSEvent.removeMonitor($0) }
            monitors = []
        }
    }

    // MARK: Pasang dan baca

    /// Skin bawaan (Contents/Resources/Skins) disalin ke folder pengguna; yang sudah ada ditimpa hanya bila versi app berganti.
    private func installBuiltins() {
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        var bundled = Bundle.main.resourceURL?.appendingPathComponent("Skins")
        var dev = false
        if bundled.map({ !fm.fileExists(atPath: $0.path) }) ?? true {
            // Build dev (tanpa paket .app): ambil skin langsung dari folder `notch/Skins` di repo supaya perubahannya ikut.
            var up = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
            for _ in 0..<6 {
                up.deleteLastPathComponent()
                let repo = up.appendingPathComponent("Skins")
                if fm.fileExists(atPath: repo.appendingPathComponent("mimik/skin.json").path) { bundled = repo; dev = true; break }
            }
        }
        guard let bundled, let names = try? fm.contentsOfDirectory(atPath: bundled.path) else { return }
        let version = dev ? "dev" : (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0")
        for name in names where !name.hasPrefix(".") {
            let src = bundled.appendingPathComponent(name), dst = Self.folder.appendingPathComponent(name)
            let marker = dst.appendingPathComponent(".builtin-version")
            if !dev, (try? String(contentsOf: marker, encoding: .utf8)) == version { continue }
            if fm.fileExists(atPath: dst.path), !fm.fileExists(atPath: marker.path) { continue } // skin pengguna bernama sama: jangan ditimpa
            try? fm.removeItem(at: dst)
            try? fm.copyItem(at: src, to: dst)
            try? version.write(to: marker, atomically: true, encoding: .utf8)
        }
    }

    func scan() {
        let fm = FileManager.default
        let names = (try? fm.contentsOfDirectory(atPath: Self.folder.path)) ?? []
        skins = names.sorted().compactMap { name -> SkinInfo? in
            guard !name.hasPrefix(".") else { return nil }
            let dir = Self.folder.appendingPathComponent(name, isDirectory: true)
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("skin.json")),
                  let m = try? JSONDecoder().decode(SkinManifest.self, from: data) else { return nil }
            let entry = m.entry ?? "index.html"
            guard fm.fileExists(atPath: dir.appendingPathComponent(entry).path) else { return nil }
            return SkinInfo(id: name, name: m.name ?? name, desc: m.description ?? "", width: min(max(m.width ?? 240, 80), 1200),
                            height: min(max(m.height ?? 240, 60), 900), cursor: m.cursor ?? false, audio: m.audio ?? false, notch: m.notch ?? false, anchor: m.anchor ?? "top-right", entry: entry, folder: dir)
        }
    }

    func reveal() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Self.folder)
    }

    /// Baca ulang folder dan muat ulang halaman semua skin yang menyala (berguna saat mengedit skin).
    func reload() {
        scan()
        for (id, w) in windows { if skins.contains(where: { $0.id == id }) { w.reload() } else { close(id) } }
        for skin in skins where enabled.contains(skin.id) && windows[skin.id] == nil { open(skin) }
    }

    func isOn(_ id: String) -> Bool { enabled.contains(id) }

    /// Hapus posisi tersimpan; skin kembali ke posisi awal (`anchor`).
    func resetPositions() {
        for skin in skins { UserDefaults.standard.removeObject(forKey: "skins.origin.\(skin.id)") }
        for w in windows.values { w.moveToDefault() }
    }

    func setOn(_ id: String, _ on: Bool) {
        if on { enabled.insert(id) } else { enabled.remove(id) }
        UserDefaults.standard.set(Array(enabled), forKey: "skins.enabled")
        if on, let skin = skins.first(where: { $0.id == id }) { open(skin) } else { close(id) }
    }

    private func open(_ skin: SkinInfo) {
        guard windows[skin.id] == nil else { return }
        let w = SkinWindow(info: skin, scale: scale(of: skin), onTop: onTop) { [weak self] in
            MainActor.assumeIsolated { self?.push(to: skin.id, force: true) }
        }
        windows[skin.id] = w
        w.show()
        if arranging { w.setArranging(true, onTop: onTop) }
        updateMonitors()
        updateAudioTimer()
    }

    private func close(_ id: String) {
        windows[id]?.close()
        windows[id] = nil
        updateMonitors()
        updateAudioTimer()
    }

    // MARK: Data

    private func pushAll() { for id in windows.keys { push(to: id) } }

    /// Tanda isi data tanpa bagian yang selalu berubah (waktu kirim, posisi lagu yang maju sendiri): bila sama, tidak dikirim
    /// ulang (hemat daya). Keranjang 10 menit tetap membuat suasana menurut jam menyegar.
    private var lastSignature: [String: String] = [:]

    private func push(to id: String, force: Bool = false) {
        guard let w = windows[id] else { return }
        let json = payload(config: config(for: id))
        let signature = Self.signature(of: json)
        if !force, lastSignature[id] == signature { return }
        lastSignature[id] = signature
        w.push(json: json)
    }

    private static func signature(of json: String) -> String {
        guard var d = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any] else { return json }
        if let now = d.removeValue(forKey: "now") as? Double { d["bucket"] = Int(now / 600_000) }
        if var media = d["media"] as? [String: Any] {
            let sent = (media.removeValue(forKey: "sentAt") as? Double ?? 0) / 1000
            if let position = media["position"] as? Double {
                let playing = media["playing"] as? Bool ?? false
                // Saat diputar, posisi maju sendiri: bandingkan titik mulainya (berubah bila digeser atau ganti lagu).
                media["position"] = ((playing ? position - sent * (media["rate"] as? Double ?? 1) : position) * 1).rounded()
            }
            d["media"] = media
        }
        let data = (try? JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])) ?? Data()
        return String(data: data, encoding: .utf8) ?? json
    }

    private func sendCursor() {
        let now = Date()
        guard now.timeIntervalSince(lastCursorSend) > 1.0 / 30 else { return }
        lastCursorSend = now
        let p = NSEvent.mouseLocation
        for w in windows.values where w.info.cursor { w.sendCursor(p) }
    }

    /// Satu objek JSON. Posisi lagu dikirim sebagai titik acuan (`position` pada `sentAt`) supaya skin menghitung
    /// sendiri tanpa menunggu pesan tiap detik.
    private func payload(config: String? = nil) -> String {
        let m = model, now = Date()
        let ms = now.timeIntervalSince1970 * 1000
        var d: [String: Any] = ["now": ms]
        if let np = m.media.nowPlaying {
            d["media"] = [
                "title": np.title, "artist": np.artist ?? "", "album": np.album ?? "", "playing": np.playing,
                "duration": np.duration ?? NSNull(), "position": np.position(at: now) ?? NSNull(), "rate": np.rate, "sentAt": ms,
            ] as [String: Any]
        }
        switch m.lyrics.state {
        case .synced(let lines):
            d["lyrics"] = ["state": "synced", "lines": lines.map { ["t": $0.time, "text": $0.text, "reading": $0.reading ?? ""] }] as [String: Any]
        case .plain(let text): d["lyrics"] = ["state": "plain", "text": text]
        case .loading: d["lyrics"] = ["state": "loading"]
        case .instrumental: d["lyrics"] = ["state": "instrumental"]
        default: d["lyrics"] = ["state": "none"]
        }
        if let w = m.weather.now { d["weather"] = ["tempC": w.temperature, "code": w.code, "place": w.place] as [String: Any] }
        let start = Calendar.current.startOfDay(for: now)
        d["water"] = ["goalMl": m.water.goal, "todayMl": m.water.sips.filter { $0.date >= start }.reduce(0) { $0 + $1.ml }]
        d["events"] = (m.calendar.events + m.todo.moodle).sorted { $0.start < $1.start }.map {
            ["title": $0.title, "start": $0.start.timeIntervalSince1970 * 1000, "end": $0.end.map { $0.timeIntervalSince1970 * 1000 } ?? NSNull(),
             "allDay": $0.allDay, "calendar": $0.calendar, "isTask": $0.isTask] as [String: Any]
        }
        d["todos"] = m.todo.items.map { ["title": $0.text, "done": $0.done, "due": $0.due.map { $0.timeIntervalSince1970 * 1000 } ?? NSNull()] as [String: Any] }
        d["timers"] = m.clock.countdowns.map { ["title": $0.label, "end": $0.end.timeIntervalSince1970 * 1000, "total": $0.total * 1000] as [String: Any] }
        d["notes"] = m.notes.items.prefix(8).map { ["text": String($0.text.prefix(240)), "date": $0.date.timeIntervalSince1970 * 1000] as [String: Any] }
        if let config, let obj = (try? JSONSerialization.jsonObject(with: Data(config.utf8))) { d["config"] = obj }
        guard let data = try? JSONSerialization.data(withJSONObject: d), let s = String(data: data, encoding: .utf8) else { return "{}" }
        return s
    }
}

// MARK: - Jendela

private final class SkinPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Tahan ⌥ (Option) lalu seret untuk memindahkan skin (atau mode Atur posisi); klik biasa diteruskan ke halaman.
private final class SkinWebView: WKWebView {
    /// Mode atur posisi: seret tanpa ⌥, klik tidak diteruskan ke halaman.
    var arranging = false
    /// WebKit memasang tampilan internal di atas web view, jadi tanpa ini `mouseDown` di bawah tidak pernah menerima klik
    /// saat mode seret aktif.
    override func hitTest(_ point: NSPoint) -> NSView? {
        if arranging || NSEvent.modifierFlags.contains(.option) { return self }
        return super.hitTest(point)
    }
    private var dragStart: (mouse: NSPoint, origin: NSPoint)?
    private func screenPoint(_ event: NSEvent) -> NSPoint? { window?.convertPoint(toScreen: event.locationInWindow) }
    override func mouseDown(with event: NSEvent) {
        guard arranging || event.modifierFlags.contains(.option), let window, let p = screenPoint(event) else { super.mouseDown(with: event); return }
        dragStart = (p, window.frame.origin)
    }
    /// Dipanggil sesudah skin dilepas (mis. dipindah ke layar yang lebih kecil: ukurannya disesuaikan).
    var onDragEnd: (() -> Void)?
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let window, let now = screenPoint(event) else { super.mouseDragged(with: event); return }
        let target = NSRect(x: start.origin.x + now.x - start.mouse.x, y: start.origin.y + now.y - start.mouse.y,
                            width: window.frame.width, height: window.frame.height)
        // Tidak pernah keluar layar: dibatasi ke layar tempat kursor berada (jadi masih bisa dipindah ke layar kedua).
        let screen = NSScreen.screens.first { NSMouseInRect(now, $0.frame, false) } ?? window.screen ?? NSScreen.main
        guard let area = screen?.visibleFrame else { window.setFrameOrigin(target.origin); return }
        window.setFrameOrigin(SkinPlacement.clamp(target, into: area).origin)
    }
    override func mouseUp(with event: NSEvent) {
        if dragStart != nil { dragStart = nil; onDragEnd?() } else { super.mouseUp(with: event) }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Melayani skin://app/<jalur> dari folder skin saja. Jalur di luar folder ditolak; semua jawaban membawa CSP tanpa jaringan.
final class SkinScheme: NSObject, WKURLSchemeHandler {
    let root: URL
    let entry: String
    init(root: URL, entry: String) { self.root = root.standardizedFileURL; self.entry = entry }

    private static let types = ["html": "text/html", "js": "text/javascript", "mjs": "text/javascript", "css": "text/css", "json": "application/json",
                                "svg": "image/svg+xml", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
                                "webp": "image/webp", "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf", "otf": "font/otf"]

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        var path = url.path.removingPercentEncoding ?? url.path
        if path == "" || path == "/" { path = "/" + entry }
        let file = root.appendingPathComponent(String(path.dropFirst())).standardizedFileURL
        guard file.path.hasPrefix(root.path + "/"), let data = try? Data(contentsOf: file) else {
            task.didReceive(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            task.didFinish()
            return
        }
        let type = Self.types[file.pathExtension.lowercased()] ?? "application/octet-stream"
        let headers = ["Content-Type": type, "Content-Length": "\(data.count)", "Cache-Control": "no-store",
                       "Content-Security-Policy": "default-src skin: data: blob: 'unsafe-inline' 'unsafe-eval'"]
        task.didReceive(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

@MainActor
final class SkinWindow: NSObject, WKNavigationDelegate {
    let info: SkinInfo
    private let panel: SkinPanel
    private let web: SkinWebView
    private var scale: Double
    /// Ukuran yang dipilih pengguna; `scale` bisa lebih kecil bila layar tempat skin berada tidak muat.
    private var wanted: Double
    private var loaded = false
    private let onReady: () -> Void
    private var moveObserver: NSObjectProtocol?

    static let bridge = """
    window.cognify = { data: {}, _h: [],
      on(fn) { this._h.push(fn); fn(this.data) },
      _push(d) { this.data = d; this._h.forEach(f => { try { f(d) } catch (e) { console.error(e) } }) },
      _nt: [], onNotice(fn) { this._nt.push(fn) },
      _notice() { this._nt.forEach(f => { try { f() } catch (x) { console.error(x) } }) },
      _n: [], onNotch(fn) { this._n.push(fn) },
      _notch(on) { this._n.forEach(f => { try { f(on) } catch (x) { console.error(x) } }) },
      _a: [], onAudio(fn) { this._a.push(fn) },
      _audio(e, b, p, on) { this._a.forEach(f => { try { f(e, b, p, on) } catch (x) { console.error(x) } }) },
      _cfg(c) { this.data = Object.assign({}, this.data, { config: c }); this._h.forEach(f => { try { f(this.data) } catch (e) { console.error(e) } }) },
      _cursor(x, y) { window.dispatchEvent(new PointerEvent('pointermove', { clientX: x, clientY: y, bubbles: true })) } };
    """

    init(info: SkinInfo, scale: Double, onTop: Bool, onReady: @escaping () -> Void) {
        self.info = info
        self.scale = scale
        self.wanted = scale
        self.onReady = onReady
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(SkinScheme(root: info.folder, entry: info.entry), forURLScheme: "skin")
        config.userContentController.addUserScript(WKUserScript(source: Self.bridge, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = SkinWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.pageZoom = scale
        let size = NSSize(width: info.width * scale, height: info.height * scale)
        panel = SkinPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        web.onDragEnd = { [weak self] in MainActor.assumeIsolated { self?.refit() } }
        web.navigationDelegate = self
        panel.contentView = web
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        setLevel(onTop)
        let origin = Self.savedOrigin(info.id) ?? Self.defaultOrigin(size, anchor: info.anchor)
        let target = NSRect(origin: origin, size: size)
        let screen = NSScreen.screens.first { $0.frame.intersects(target) } ?? NSScreen.main
        panel.setFrameOrigin(screen.map { SkinPlacement.clamp(target, into: $0.visibleFrame).origin } ?? origin)
        moveObserver = NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: panel, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { UserDefaults.standard.set(NSStringFromPoint(self.panel.frame.origin), forKey: "skins.origin.\(self.info.id)") } }
        }
    }

    private static func savedOrigin(_ id: String) -> NSPoint? {
        UserDefaults.standard.string(forKey: "skins.origin.\(id)").map(NSPointFromString)
    }

    private static func defaultOrigin(_ size: NSSize, anchor: String) -> NSPoint {
        let f = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin = 32.0
        let x: Double
        if anchor.hasSuffix("left") { x = f.minX + margin }
        else if anchor.hasSuffix("center") { x = f.midX - size.width / 2 }
        else { x = f.maxX - size.width - margin }
        let y = anchor.hasPrefix("bottom") ? f.minY + margin : f.maxY - size.height - margin
        return NSPoint(x: x, y: y)
    }

    func show() {
        web.load(URLRequest(url: URL(string: "skin://app/")!))
        panel.orderFrontRegardless()
    }

    func close() {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        web.navigationDelegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
    }

    func reload() { loaded = false; web.reloadFromOrigin() }

    func setArranging(_ on: Bool, onTop: Bool) {
        web.arranging = on
        web.wantsLayer = true
        web.layer?.borderWidth = on ? 2 : 0
        web.layer?.borderColor = NSColor.controlAccentColor.cgColor
        web.layer?.cornerRadius = 12
        setLevel(on ? true : onTop)
    }

    func moveToDefault() {
        panel.setFrameOrigin(Self.defaultOrigin(panel.frame.size, anchor: info.anchor))
    }

    func setLevel(_ onTop: Bool) {
        panel.level = onTop ? .floating : NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    func setScale(_ value: Double) {
        wanted = value
        refit()
    }

    /// Menyesuaikan dengan layar tempat skin berada: ukuran dikecilkan bila tidak muat, dan jendela digeser ke dalam layar.
    func refit() {
        let area = (panel.screen ?? NSScreen.main)?.visibleFrame
        let value = area.map { SkinPlacement.fit(wanted, base: CGSize(width: info.width, height: info.height), area: $0.size) } ?? wanted
        scale = value
        web.pageZoom = value
        var frame = panel.frame
        let newSize = NSSize(width: info.width * value, height: info.height * value)
        frame.origin.y += frame.height - newSize.height // sudut kiri atas tetap
        frame.size = newSize
        panel.setFrame(area.map { SkinPlacement.clamp(frame, into: $0) } ?? frame, display: true)
    }

    func push(json: String) {
        guard loaded else { return }
        web.evaluateJavaScript("window.cognify._push(\(json))", completionHandler: nil)
    }

    func sendNotice() {
        guard loaded else { return }
        web.evaluateJavaScript("window.cognify._notice()", completionHandler: nil)
    }

    func sendNotchHover(_ inside: Bool) {
        guard loaded else { return }
        web.evaluateJavaScript("window.cognify._notch(\(inside))", completionHandler: nil)
    }

    /// Irama lagu untuk skin berpermintaan audio (lihat `SkinManager.sendAudio`).
    func sendAudio(energy: Double, beats: Int, period: Double, on: Bool) {
        guard loaded else { return }
        web.evaluateJavaScript("window.cognify._audio(\(String(format: "%.3f", energy)),\(beats),\(String(format: "%.3f", period)),\(on))", completionHandler: nil)
    }

    /// Hanya `config` yang berubah (playground): tanpa membangun ulang seluruh data.
    func pushConfig(json: String) {
        guard loaded else { return }
        web.evaluateJavaScript("window.cognify._cfg(\(json))", completionHandler: nil)
    }

    /// Titik layar (asal kiri bawah) → piksel CSS di dalam skin (asal kiri atas).
    func sendCursor(_ p: NSPoint) {
        guard loaded else { return }
        let f = panel.frame
        let x = (p.x - f.minX) / scale, y = (f.maxY - p.y) / scale
        web.evaluateJavaScript("window.cognify._cursor(\(Int(x)),\(Int(y)))", completionHandler: nil)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        MainActor.assumeIsolated { loaded = true; onReady() }
    }

    nonisolated func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // Hanya halaman skin sendiri; tautan keluar tidak dibuka.
        decisionHandler(action.request.url?.scheme == "skin" ? .allow : .cancel)
    }
}

// MARK: - Pengaturan

struct SkinsPane: View {
    @ObservedObject var skins: SkinManager

    var body: some View {
        if let mimik = skins.skins.first(where: { $0.id == "mimik" }), skins.isOn("mimik") {
            Section(L("Mimik: atur wajahmu", "Mimik: make a face you like")) { MimikPlayground(skins: skins, info: mimik) }
        }
        Section {
            if skins.skins.isEmpty {
                Text(L("Belum ada skin. Letakkan folder skin di folder skin lalu tekan Muat ulang.", "No skins yet. Put a skin folder in the skins folder, then press Reload."))
                    .foregroundStyle(.secondary)
            }
            ForEach(skins.skins) { skin in
                Toggle(isOn: Binding(get: { skins.isOn(skin.id) }, set: { skins.setOn(skin.id, $0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(skin.name)
                        if !skin.desc.isEmpty { Text(skin.desc).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if skins.isOn(skin.id) {
                    HStack {
                        Text(L("Ukuran", "Size")).foregroundStyle(.secondary)
                        Slider(value: Binding(get: { skins.scale(of: skin) }, set: { skins.setScale($0, of: skin) }), in: 0.5...max(0.55, skins.maxScale(of: skin))) { EmptyView() }
                        Text("\(Int((skins.scale(of: skin) * 100).rounded()))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                        Button { skins.setScale(1, of: skin) } label: { Image(systemName: "arrow.counterclockwise") }
                            .disabled(abs(skins.scale(of: skin) - 1) < 0.005)
                            .help(L("Atur ulang", "Reset"))
                    }
                }
            }
        } footer: {
            Text(L("Pindahkan skin dengan mode Atur posisi di bawah, atau tahan ⌥ (Option) lalu seret. Skin tidak punya akses internet dan hanya membaca folder skinnya sendiri.",
                   "Move skins with Arrange positions below, or hold ⌥ (Option) and drag. Skins have no internet access and only read their own folder."))
        }
        if skins.isOn("lyrics") {
            Section(L("Warna lirik", "Lyrics colour")) {
                ColorPicker(L("Baris yang dinyanyikan", "Current line"), selection: hexColor($skins.lyricStyle.color), supportsOpacity: false)
                ColorPicker(L("Judul dan baris berikutnya", "Title and next line"), selection: hexColor($skins.lyricStyle.sub), supportsOpacity: false)
                Button(L("Kembalikan ke putih", "Reset to white")) { skins.lyricStyle = SkinLyricStyle() }
                    .disabled(skins.lyricStyle == SkinLyricStyle())
            }
        }
        Section {
            Toggle(isOn: $skins.arranging) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L("Atur posisi", "Arrange positions"))
                    Text(L("Skin berbingkai dan bisa diseret bebas ke mana saja. Matikan setelah selesai; posisinya tersimpan.",
                           "Skins get an outline and can be dragged anywhere. Turn it off when done; positions are saved."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Button(L("Kembalikan ke posisi awal", "Reset positions")) { skins.resetPositions() }
        }
        Section(L("Tampilan", "Display")) {
            Picker(L("Posisi jendela", "Window level"), selection: $skins.onTop) {
                Text(L("Di desktop (di bawah jendela lain)", "On the desktop (below other windows)")).tag(false)
                Text(L("Selalu di atas", "Always on top")).tag(true)
            }
        }
        Section {
            HStack {
                Button(L("Buka folder skin", "Open skins folder")) { skins.reveal() }
                Button(L("Muat ulang", "Reload")) { skins.reload() }
            }
        }
    }
}

