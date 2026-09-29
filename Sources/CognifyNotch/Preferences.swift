import AppKit
import Carbon.HIToolbox
import SwiftUI

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
