import AppKit
import ServiceManagement
import SwiftUI

/// Ikon menu bar app mandiri "Cognify Notch": pengganti halaman Pengaturan Cognify.
/// Pilihan fitur disimpan di UserDefaults Mac ini (lihat `FeatureToggle`).
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: NotchModel
    private let updater: Updater?
    private var settings: NSWindow?

    init(model: NotchModel) {
        self.model = model
        // Update otomatis dipasang hanya saat notch tertutup dan tidak sedang merekam suara.
        updater = Updater(canRestart: { [weak model] in
            MainActor.assumeIsolated { model.map { !$0.expanded && !$0.voice.recording } ?? true }
        })
        super.init()
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Cognify Notch")
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        model.onOpenSettings = { [weak self] in self?.showSettings() }
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
        let prefs = NSMenuItem(title: L("Pengaturan…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(prefs)
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

    @objc private func showSettings() {
        if settings == nil {
            // Muat di layar kecil: tidak melebihi area layar yang terlihat (di bawah menu bar dan notch).
            let area = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
            let w = min(780, area.width - 40), h = min(580, area.height - 70)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: w, height: h),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.minSize = NSSize(width: min(520, w), height: min(360, h))
            window.contentView = NSHostingView(rootView: SettingsView(model: model, prefs: model.prefs, updater: updater))
            window.center()
            var f = window.frame
            f.origin.y = min(f.origin.y, area.maxY - f.height - 40) // di bawah notch yang terbuka
            f.origin.y = max(f.origin.y, area.minY)
            window.setFrame(f, display: false)
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

