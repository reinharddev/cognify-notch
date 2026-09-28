import AppKit
import ServiceManagement

/// Ikon menu bar app mandiri "Cognify Notch": pengganti halaman Pengaturan Cognify.
/// Pilihan fitur disimpan di UserDefaults Mac ini.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: NotchModel
    private let updater = Updater()
    private let defaults = UserDefaults.standard

    private struct Toggle {
        let title: String
        let key: WritableKeyPath<NotchModel.Features, Bool>
        let defaultsKey: String
    }

    private let toggles: [Toggle] = [
        Toggle(title: "Lagu & video yang diputar", key: \.media, defaultsKey: "feature.media"),
        Toggle(title: "Equalizer mengikuti suara", key: \.spectrum, defaultsKey: "feature.spectrum"),
        Toggle(title: "Agenda dari Kalender", key: \.calendar, defaultsKey: "feature.calendar"),
        Toggle(title: "Cermin kamera", key: \.camera, defaultsKey: "feature.camera"),
        Toggle(title: "Pintasan", key: \.shortcuts, defaultsKey: "feature.shortcuts"),
        Toggle(title: "Volume & kecerahan", key: \.hud, defaultsKey: "feature.hud"),
        Toggle(title: "Baterai & charger", key: \.power, defaultsKey: "feature.power"),
        Toggle(title: "AirPods & headphone", key: \.devices, defaultsKey: "feature.devices"),
        Toggle(title: "Buka dengan \(HotKey.label)", key: \.hotkey, defaultsKey: "feature.hotkey"),
    ]

    init(model: NotchModel) {
        self.model = model
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Cognify Notch")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        model.apply(savedFeatures())
    }

    /// Fitur tersimpan. App mandiri: Kalender default nyala (satu-satunya sumber agenda).
    private func savedFeatures() -> NotchModel.Features {
        var features = NotchModel.Features()
        features.calendar = true
        for toggle in toggles where defaults.object(forKey: toggle.defaultsKey) != nil {
            features[keyPath: toggle.key] = defaults.bool(forKey: toggle.defaultsKey)
        }
        return features
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "Cognify Notch", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let hint = NSMenuItem(title: "Arahkan kursor ke notch atau tekan \(HotKey.label)", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        for (index, toggle) in toggles.enumerated() {
            let entry = NSMenuItem(title: toggle.title, action: #selector(flip(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = index
            entry.state = model.features[keyPath: toggle.key] ? .on : .off
            if toggle.key == \.spectrum && !model.features.media { entry.isEnabled = false }
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let login = NSMenuItem(title: "Buka saat Mac dinyalakan", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        if updater != nil {
            let update = NSMenuItem(title: "Periksa update…", action: #selector(checkUpdates), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
        }
        let about = NSMenuItem(title: "Tentang Cognify Notch", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Keluar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func flip(_ sender: NSMenuItem) {
        let toggle = toggles[sender.tag]
        var features = model.features
        features[keyPath: toggle.key].toggle()
        defaults.set(features[keyPath: toggle.key], forKey: toggle.defaultsKey)
        model.apply(features)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            model.show(.failed("Tidak bisa mengubah pengaturan login: \(error.localizedDescription)"))
        }
    }

    @objc private func checkUpdates() {
        updater?.checkForUpdates()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Cognify Notch",
            .credits: NSAttributedString(string: "Notch ala Dynamic Island dari Cognify: lagu yang diputar, agenda, catatan cepat, tray file, timer belajar, cermin, pintasan, baterai, dan AirPods. Semua berjalan di Mac ini."),
        ])
    }
}
