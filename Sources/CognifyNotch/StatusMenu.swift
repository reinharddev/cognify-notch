import AppKit
import ServiceManagement
import SwiftUI

/// Ikon menu bar app mandiri "Cognify Notch": pengganti halaman Pengaturan Cognify.
/// Pilihan fitur disimpan di UserDefaults Mac ini (lihat `FeatureToggle`).
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: NotchModel
    private let updater = Updater()
    private var settings: NSWindow?

    init(model: NotchModel) {
        self.model = model
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Cognify Notch")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        model.apply(FeatureToggle.saved())
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "Cognify Notch", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let shortcut = model.features.hotkey ? " " + L("atau tekan", "or press") + " " + model.prefs.hotKey.label : ""
        let hint = NSMenuItem(title: L("Arahkan kursor ke notch", "Point at the notch") + shortcut, action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())
        for (index, toggle) in FeatureToggle.all.enumerated() {
            let entry = NSMenuItem(title: toggle.title(), action: #selector(flip(_:)), keyEquivalent: "")
            entry.target = self
            entry.tag = index
            entry.state = model.features[keyPath: toggle.key] ? .on : .off
            if toggle.key == \.spectrum && !model.features.media { entry.isEnabled = false }
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        let prefs = NSMenuItem(title: L("Pengaturan…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
        let login = NSMenuItem(title: L("Buka saat Mac dinyalakan", "Open at login"), action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        if updater != nil {
            let update = NSMenuItem(title: L("Periksa update…", "Check for updates…"), action: #selector(checkUpdates), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
        }
        let about = NSMenuItem(title: L("Tentang Cognify Notch", "About Cognify Notch"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("Keluar", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    @objc private func flip(_ sender: NSMenuItem) {
        let toggle = FeatureToggle.all[sender.tag]
        FeatureToggle.set(toggle, !model.features[keyPath: toggle.key], model: model)
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            model.show(.failed(L("Tidak bisa mengubah pengaturan login: ", "Couldn't change the login setting: ") + error.localizedDescription))
        }
    }

    @objc private func showSettings() {
        if settings == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model, prefs: model.prefs))
            window.center()
            settings = window
        }
        settings?.title = L("Pengaturan Cognify Notch", "Cognify Notch Settings")
        NSApp.activate(ignoringOtherApps: true)
        settings?.makeKeyAndOrderFront(nil)
    }

    @objc private func checkUpdates() {
        updater?.checkForUpdates()
    }

    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Cognify Notch",
            .credits: NSAttributedString(string: L(
                "Notch ala Dynamic Island dari Cognify: lagu yang diputar, agenda & rapat, catatan cepat dan rekam suara, clipboard, tray file, timer belajar, cermin, pintasan, baterai, AirPods, dan download. Semua berjalan di Mac ini.",
                "A Dynamic Island style notch from Cognify: now playing, agenda & meetings, quick notes and dictation, clipboard, file tray, study timer, mirror, shortcuts, battery, AirPods, and downloads. Everything runs on this Mac.")),
        ])
    }
}

// MARK: - Jendela Pengaturan

struct SettingsView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section(L("Fitur", "Features")) {
                ForEach(FeatureToggle.all) { toggle in
                    Toggle(isOn: Binding(get: { model.features[keyPath: toggle.key] },
                                         set: { FeatureToggle.set(toggle, $0, model: model) })) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(toggle.title())
                            Text(toggle.hint()).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .disabled(toggle.key == \.spectrum && !model.features.media)
                }
            }
            Section(L("Notch", "Notch")) {
                Picker(L("Ukuran panel", "Panel size"), selection: $prefs.scale) {
                    Text(L("Normal", "Normal")).tag(1.0)
                    Text(L("Besar", "Large")).tag(1.12)
                }
                LabeledContent(L("Jeda sebelum terbuka", "Delay before opening")) {
                    Slider(value: $prefs.hoverDelay, in: 0...0.6, step: 0.05) { EmptyView() }
                    Text("\(Int(prefs.hoverDelay * 1000)) ms").monospacedDigit().frame(width: 60, alignment: .trailing)
                }
                LabeledContent(L("Jeda sebelum menutup", "Delay before closing")) {
                    Slider(value: $prefs.closeDelay, in: 0.1...1.5, step: 0.05) { EmptyView() }
                    Text("\(Int(prefs.closeDelay * 1000)) ms").monospacedDigit().frame(width: 60, alignment: .trailing)
                }
                Picker(L("Shortcut keyboard", "Keyboard shortcut"), selection: $prefs.hotKey) {
                    ForEach(Preferences.HotKeyChoice.allCases) { Text($0.label).tag($0) }
                }
                .disabled(!model.features.hotkey)
            }
            Section(L("Urutan tab", "Tab order")) {
                ForEach(prefs.ordered(NotchModel.Tab.allCases), id: \.self) { tab in
                    HStack {
                        Image(systemName: tab.icon).frame(width: 20)
                        Text(tab.label)
                        Spacer()
                        Button { prefs.move(tab, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless).disabled(prefs.ordered(NotchModel.Tab.allCases).first == tab)
                        Button { prefs.move(tab, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless).disabled(prefs.ordered(NotchModel.Tab.allCases).last == tab)
                    }
                }
            }
            Section(L("Bahasa", "Language")) {
                Picker(L("Bahasa tampilan", "Display language"), selection: $prefs.language) {
                    ForEach(Preferences.Language.allCases) { Text($0.label).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 620)
    }
}
