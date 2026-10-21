import AppKit
import Carbon.HIToolbox
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Bahasa

/// Bahasa tampilan notch. Default Bahasa Indonesia; bahasa Inggris dipilih di jendela Pengaturan
/// app mandiri. Notch di dalam Cognify selalu Bahasa Indonesia (seperti Cognify).
enum Lang {
    static var english = false
}

/// Teks sesuai bahasa yang dipilih: `L("Simpan", "Save")`.
func L(_ id: String, _ en: String) -> String { Lang.english ? en : id }

// MARK: - Pengaturan app mandiri

/// Pengaturan app mandiri "Cognify Notch" (UserDefaults Mac ini). Di dalam Cognify dipakai
/// nilai default, kecuali fitur yang dikirim Cognify lewat stdin.
@MainActor
final class Preferences: ObservableObject {
    enum HotKeyChoice: String, CaseIterable, Identifiable {
        case ctrlOptN, ctrlOptSpace, optSpace, cmdShiftN

        var id: String { rawValue }

        var label: String {
            switch self {
            case .ctrlOptN: return "⌃⌥N"
            case .ctrlOptSpace: return "⌃⌥Space"
            case .optSpace: return "⌥Space"
            case .cmdShiftN: return "⇧⌘N"
            }
        }

        var keyCode: Int {
            switch self {
            case .ctrlOptN, .cmdShiftN: return kVK_ANSI_N
            case .ctrlOptSpace, .optSpace: return kVK_Space
            }
        }

        var modifiers: Int {
            switch self {
            case .ctrlOptN, .ctrlOptSpace: return controlKey | optionKey
            case .optSpace: return optionKey
            case .cmdShiftN: return cmdKey | shiftKey
            }
        }
    }

    enum Language: String, CaseIterable, Identifiable {
        case id, en
        var id: String { rawValue }
        var label: String { self == .id ? "Bahasa Indonesia" : "English" }
    }

    /// Jeda sebelum notch terbuka saat kursor diarahkan ke sana (detik).
    @Published var hoverDelay: Double { didSet { save("prefs.hoverDelay", hoverDelay) } }
    /// Jeda sebelum notch menutup setelah kursor pergi (detik).
    @Published var closeDelay: Double { didSet { save("prefs.closeDelay", closeDelay) } }
    /// Ukuran panel terbuka: 1 = normal, 1.12 = besar.
    @Published var scale: Double { didSet { save("prefs.scale", scale) } }
    @Published var hotKey: HotKeyChoice { didSet { save("prefs.hotKey", hotKey.rawValue) } }
    @Published var language: Language {
        didSet {
            save("prefs.language", language.rawValue)
            Lang.english = language == .en
        }
    }
    enum Display: String, CaseIterable, Identifiable {
        case notch, main, active
        var id: String { rawValue }
        var label: String {
            switch self {
            case .notch: return L("Layar dengan notch", "Screen with the notch")
            case .main: return L("Layar utama (menu bar)", "Main screen (menu bar)")
            case .active: return L("Layar yang sedang dipakai", "Screen you're using")
            }
        }
    }

    /// Notch dibuka dengan klik, bukan saat kursor diarahkan.
    @Published var openOnClick: Bool { didSet { save("prefs.openOnClick", openOnClick) } }
    /// Layar tempat notch tampil (penting saat memakai monitor tambahan).
    @Published var display: Display { didSet { save("prefs.display", display.rawValue) } }
    /// Kota untuk cuaca di header (dikirim ke Open-Meteo bila fitur cuaca nyala).
    @Published var weatherCity: String { didSet { save("prefs.weatherCity", weatherCity) } }

    /// Urutan tab (rawValue `NotchModel.Tab`).
    @Published var tabOrder: [String] { didSet { save("prefs.tabOrder", tabOrder) } }

    private let defaults: UserDefaults?

    /// `persist: false` (di dalam Cognify / snapshot): nilai default, tidak disimpan.
    init(persist: Bool) {
        let d = persist ? UserDefaults.standard : nil
        defaults = d
        hoverDelay = d?.object(forKey: "prefs.hoverDelay") as? Double ?? 0.09
        closeDelay = d?.object(forKey: "prefs.closeDelay") as? Double ?? 0.35
        scale = d?.object(forKey: "prefs.scale") as? Double ?? 1
        hotKey = (d?.string(forKey: "prefs.hotKey")).flatMap(HotKeyChoice.init) ?? .ctrlOptN
        language = (d?.string(forKey: "prefs.language")).flatMap(Language.init) ?? .id
        tabOrder = d?.stringArray(forKey: "prefs.tabOrder") ?? NotchModel.Tab.allCases.map(\.rawValue)
        openOnClick = d?.bool(forKey: "prefs.openOnClick") ?? false
        display = (d?.string(forKey: "prefs.display")).flatMap(Display.init) ?? .notch
        weatherCity = d?.string(forKey: "prefs.weatherCity") ?? ""
        Lang.english = language == .en
    }

    private func save(_ key: String, _ value: Any) { defaults?.set(value, forKey: key) }

    /// Tab dalam urutan pilihan user; tab baru (belum ada di urutan tersimpan) di belakang.
    func ordered(_ tabs: [NotchModel.Tab]) -> [NotchModel.Tab] {
        tabs.sorted { (tabOrder.firstIndex(of: $0.rawValue) ?? 99) < (tabOrder.firstIndex(of: $1.rawValue) ?? 99) }
    }

    func move(_ tab: NotchModel.Tab, by offset: Int) {
        var order = ordered(NotchModel.Tab.allCases).map(\.rawValue)
        guard let index = order.firstIndex(of: tab.rawValue), order.indices.contains(index + offset) else { return }
        order.swapAt(index, index + offset)
        tabOrder = order
    }
}

// MARK: - Fitur yang bisa dinyalakan/dimatikan (app mandiri)

struct FeatureToggle: Identifiable {
    let key: WritableKeyPath<NotchModel.Features, Bool>
    let defaultsKey: String
    let title: () -> String
    let hint: () -> String

    var id: String { defaultsKey }

    static let all: [FeatureToggle] = [
        FeatureToggle(key: \.media, defaultsKey: "feature.media",
                      title: { L("Lagu & video yang diputar", "Now playing") },
                      hint: { L("Geser dua jari di notch untuk ganti lagu.", "Swipe with two fingers on the notch to change tracks.") }),
        FeatureToggle(key: \.spectrum, defaultsKey: "feature.spectrum",
                      title: { L("Equalizer mengikuti suara", "Equalizer follows the audio") },
                      hint: { L("Suara hanya diubah jadi tinggi batang, tidak direkam.", "Audio only drives the bars; nothing is recorded.") }),
        FeatureToggle(key: \.calendar, defaultsKey: "feature.calendar",
                      title: { L("Agenda dari Kalender", "Calendar agenda") },
                      hint: { L("Termasuk tombol Gabung untuk rapat Zoom, Meet, dan Teams.", "Includes a Join button for Zoom, Meet, and Teams meetings.") }),
        FeatureToggle(key: \.camera, defaultsKey: "feature.camera",
                      title: { L("Cermin kamera", "Camera mirror") },
                      hint: { L("Kamera hanya menyala selama tab Cermin dibuka.", "The camera is only on while the Mirror tab is open.") }),
        FeatureToggle(key: \.shortcuts, defaultsKey: "feature.shortcuts",
                      title: { L("Pintasan", "Shortcuts") },
                      hint: { L("Jalankan Siri Shortcuts dengan satu klik.", "Run Siri Shortcuts with one click.") }),
        FeatureToggle(key: \.clipboard, defaultsKey: "feature.clipboard",
                      title: { L("Riwayat clipboard", "Clipboard history") },
                      hint: { L("Tersimpan di Mac ini saja. Isi dari pengelola kata sandi dilewati.", "Stored on this Mac only. Password manager content is skipped.") }),
        FeatureToggle(key: \.voice, defaultsKey: "feature.voice",
                      title: { L("Rekam suara jadi catatan", "Voice to note") },
                      hint: { L("Diubah jadi teks di Mac ini, tidak dikirim ke internet.", "Transcribed on this Mac, never sent online.") }),
        FeatureToggle(key: \.hud, defaultsKey: "feature.hud",
                      title: { L("Volume & kecerahan", "Volume & brightness") },
                      hint: { L("Perubahan ditampilkan di notch.", "Changes show up in the notch.") }),
        FeatureToggle(key: \.power, defaultsKey: "feature.power",
                      title: { L("Baterai & charger", "Battery & charger") },
                      hint: { L("Charger dicolok/dicabut, baterai 20% dan 10%.", "Charger plugged in or out, battery at 20% and 10%.") }),
        FeatureToggle(key: \.devices, defaultsKey: "feature.devices",
                      title: { L("AirPods & headphone", "AirPods & headphones") },
                      hint: { L("Nama dan baterai saat tersambung.", "Name and battery when connected.") }),
        FeatureToggle(key: \.downloads, defaultsKey: "feature.downloads",
                      title: { L("Progress download", "Download progress") },
                      hint: { L("File yang sedang diunduh ke folder Downloads.", "Files downloading to your Downloads folder.") }),
        FeatureToggle(key: \.lyrics, defaultsKey: "feature.lyrics",
                      title: { L("Lirik lagu", "Synced lyrics") },
                      hint: { L("Butuh internet: judul, artis, dan durasi lagu dikirim ke LRCLIB (lrclib.net) saat halaman Musik dibuka.",
                                "Needs internet: song title, artist and length are sent to LRCLIB (lrclib.net) when the Music page is open.") }),
        FeatureToggle(key: \.water, defaultsKey: "feature.water",
                      title: { L("Pengingat minum", "Water reminder") },
                      hint: { L("Target harian, grafik per jam, dan pengingat di jam aktif.", "Daily goal, hourly chart and reminders during your hours.") }),
        FeatureToggle(key: \.todo, defaultsKey: "feature.todo",
                      title: { L("Daftar tugas", "To-do list") },
                      hint: { L("Tugas dengan pengingat; tulis \"jam 7\" untuk mengatur waktunya.", "Tasks with reminders; type \"at 7pm\" to set a time.") }),
        FeatureToggle(key: \.companion, defaultsKey: "feature.companion",
                      title: { L("Mata saat diam", "Eyes when idle") },
                      hint: { L("Notch jadi wajah kecil yang berkedip, tertidur, dan menyapa saat kamu kembali.", "The notch becomes a little face that blinks, dozes off and says hi when you're back.") }),
        FeatureToggle(key: \.keyboard, defaultsKey: "feature.keyboard",
                      title: { L("Caps Lock & bahasa keyboard", "Caps Lock & keyboard language") },
                      hint: { L("Kabar singkat saat Caps Lock nyala atau bahasa keyboard berganti.", "A nudge when Caps Lock turns on or the keyboard language changes.") }),
        FeatureToggle(key: \.network, defaultsKey: "feature.network",
                      title: { L("Internet putus/tersambung", "Connection changes") },
                      hint: { L("Kabar saat koneksi internet hilang atau pulih.", "A nudge when you go offline or come back online.") }),
        FeatureToggle(key: \.hideFullscreen, defaultsKey: "feature.hideFullscreen",
                      title: { L("Sembunyi saat layar penuh", "Hide in full-screen apps") },
                      hint: { L("Notch menyingkir saat video, game, atau presentasi memenuhi layar.", "Steps aside for full-screen video, games and presentations.") }),
        FeatureToggle(key: \.lyricsWing, defaultsKey: "feature.lyricsWing",
                      title: { L("Lirik di notch tertutup", "Lyrics in the closed notch") },
                      hint: { L("Baris yang sedang dinyanyikan tampil di sisi kiri notch saat lagu diputar.", "The line being sung shows beside the notch while music plays.") }),
        FeatureToggle(key: \.clockTools, defaultsKey: "feature.clockTools",
                      title: { L("Stopwatch & hitung mundur", "Stopwatch & countdowns") },
                      hint: { L("Halaman stopwatch dengan lap dan beberapa hitung mundur sekaligus.", "A stopwatch with laps and several countdowns at once.") }),
        FeatureToggle(key: \.remindersSync, defaultsKey: "feature.remindersSync",
                      title: { L("Sinkron Daftar Tugas dengan Pengingat", "Sync to-dos with Reminders") },
                      hint: { L("Tugas disimpan di daftar Pengingat bawaan, ikut iCloud ke iPhone. macOS akan meminta izin.", "Tasks live in your default Reminders list and sync to iPhone via iCloud. macOS will ask for permission.") }),
        FeatureToggle(key: \.calculator, defaultsKey: "feature.calculator",
                      title: { L("Kalkulator di catatan cepat", "Calculator in quick note") },
                      hint: { L("Ketik 12*3, 15% dari 200, atau 5 km ke mil; hasilnya langsung muncul.", "Type 12*3, 15% of 200 or 5 km to mi; the answer shows up right away.") }),
        FeatureToggle(key: \.weather, defaultsKey: "feature.weather",
                      title: { L("Cuaca di header", "Weather in the header") },
                      hint: { L("Butuh internet dan nama kota (di bawah): kota dan koordinatnya dikirim ke Open-Meteo tiap 30 menit.", "Needs internet and a city (below): the city and its coordinates are sent to Open-Meteo every 30 minutes.") }),
        FeatureToggle(key: \.hotkey, defaultsKey: "feature.hotkey",
                      title: { L("Buka dengan shortcut keyboard", "Open with a keyboard shortcut") },
                      hint: { L("Esc atau klik di luar notch menutupnya.", "Esc or a click outside closes it.") }),
    ]

    /// Fitur tersimpan app mandiri. Kalender default nyala (satu-satunya sumber agenda).
    static func saved() -> NotchModel.Features {
        var features = NotchModel.Features()
        features.calendar = true
        for toggle in all where UserDefaults.standard.object(forKey: toggle.defaultsKey) != nil {
            features[keyPath: toggle.key] = UserDefaults.standard.bool(forKey: toggle.defaultsKey)
        }
        return features
    }

    @MainActor
    static func set(_ toggle: FeatureToggle, _ value: Bool, model: NotchModel) {
        var features = model.features
        features[keyPath: toggle.key] = value
        UserDefaults.standard.set(value, forKey: toggle.defaultsKey)
        model.apply(features)
    }
}

// MARK: - Cadangan data

/// Ekspor/impor data app mandiri ke satu file (property list): catatan, tugas, riwayat minum,
/// clipboard (teks), timer, pengaturan, dan pilihan fitur. Tray tidak ikut (bookmark file hanya
/// berlaku di Mac ini); gambar clipboard tidak disimpan sejak awal.
@MainActor
enum DataBackup {
    private static let prefixes = ["notes.", "todo.", "water.", "clipboard.", "timer.", "clock.", "prefs.", "feature."]

    static func export() {
        let all = UserDefaults.standard.dictionaryRepresentation().filter { key, _ in prefixes.contains { key.hasPrefix($0) } }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = L("Cadangan Cognify Notch.plist", "Cognify Notch Backup.plist")
        panel.allowedContentTypes = [.propertyList]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? PropertyListSerialization.data(fromPropertyList: ["cognifyNotch": 1, "data": all], format: .xml, options: 0)
        else { return }
        try? data.write(to: url)
    }

    /// Mengganti data Mac ini dengan isi file, lalu app dibuka ulang supaya semuanya termuat.
    static func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              root["cognifyNotch"] != nil, let values = root["data"] as? [String: Any]
        else {
            let alert = NSAlert()
            alert.messageText = L("File ini bukan cadangan Cognify Notch", "This file isn't a Cognify Notch backup")
            alert.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = L("Ganti data di Mac ini dengan isi cadangan?", "Replace this Mac's data with the backup?")
        alert.informativeText = L("Catatan, tugas, riwayat minum, clipboard, timer, dan pengaturan sekarang akan diganti. Cognify Notch lalu dibuka ulang.",
                                  "Current notes, tasks, water log, clipboard, timers and settings will be replaced. Cognify Notch will then restart.")
        alert.addButton(withTitle: L("Ganti", "Replace"))
        alert.addButton(withTitle: L("Batal", "Cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for (key, value) in values where prefixes.contains(where: { key.hasPrefix($0) }) {
            UserDefaults.standard.set(value, forKey: key)
        }
        UserDefaults.standard.synchronize()
        relaunch()
    }

    private static func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }
}
