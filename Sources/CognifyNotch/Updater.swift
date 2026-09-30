import AppKit

/// Update otomatis app mandiri "Cognify Notch" lewat Sparkle (MIT).
///
/// Sparkle.framework hanya ada di dalam "Cognify Notch.app" (scripts/build-notch-app.sh), tidak di
/// notch yang dijalankan Cognify, jadi dimuat saat berjalan (bukan di-link): notch di dalam Cognify
/// tetap jalan tanpa framework ini. Alamat appcast & kunci publik ada di Info.plist app
/// (SUFeedURL, SUPublicEDKey); tidak ada profil sistem yang dikirim (SUEnableSystemProfiling = NO).
///
/// Update diperiksa sehari sekali dan, bila "Pasang update otomatis" menyala (default,
/// SUAutomaticallyUpdate), diunduh diam-diam lalu langsung dipasang begitu notch tidak sedang
/// dipakai (lihat `UpdaterDelegate`). App menu bar jarang ditutup, jadi menunggu app keluar
/// (perilaku bawaan Sparkle) bisa membuat update tertahan berhari-hari.
@MainActor
final class Updater {
    private let controller: NSObject
    private let delegate: UpdaterDelegate // Sparkle hanya menyimpan referensi lemah

    init?(canRestart: @escaping () -> Bool) {
        let delegate = UpdaterDelegate(canRestart: canRestart)
        guard let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("Sparkle.framework"),
              let bundle = Bundle(url: url), bundle.load(),
              let type = NSClassFromString("SPUStandardUpdaterController") as? NSObject.Type,
              let allocated = (type as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject,
              let created = allocated.perform(NSSelectorFromString("initWithUpdaterDelegate:userDriverDelegate:"), with: delegate, with: nil)?
                .takeUnretainedValue() as? NSObject
        else { return nil }
        self.delegate = delegate
        controller = created
        controller.perform(NSSelectorFromString("startUpdater")) // periksa terjadwal (sehari sekali)
    }

    private var updater: NSObject? { controller.value(forKey: "updater") as? NSObject }

    /// Unduh & pasang update tanpa bertanya (disimpan Sparkle di UserDefaults app).
    var automatic: Bool {
        get { updater?.value(forKey: "automaticallyDownloadsUpdates") as? Bool ?? false }
        set { updater?.setValue(newValue, forKey: "automaticallyDownloadsUpdates") }
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true) // app menu bar: jendela Sparkle harus tampil di depan
        controller.perform(NSSelectorFromString("checkForUpdates:"), with: nil)
    }
}

/// Delegate Sparkle (dipanggil lewat runtime Objective-C, tanpa header Sparkle).
final class UpdaterDelegate: NSObject {
    private let canRestart: () -> Bool

    init(canRestart: @escaping () -> Bool) {
        self.canRestart = canRestart
    }

    /// Update otomatis sudah terunduh dan siap: pasang sekarang (app mulai ulang ±1 detik) bila
    /// notch sedang tidak dipakai, kalau tidak coba lagi tiap 30 detik.
    @objc(updater:willInstallUpdateOnQuit:immediateInstallationBlock:)
    func updater(_ updater: NSObject, willInstallUpdateOnQuit item: NSObject,
                 immediateInstallationBlock install: @escaping @convention(block) () -> Void) -> Bool {
        let box = UncheckedBox(install)
        let check = canRestart
        func attempt(after seconds: Double) {
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                if check() { box.value() } else { attempt(after: 30) }
            }
        }
        attempt(after: 5)
        return true
    }
}
