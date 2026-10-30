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
    private let updater: NSObject
    /// Hanya terisi pada jalur cadangan (jendela bawaan Sparkle); jalur utama memakai `UpdateDriver`.
    private let fallbackController: NSObject?
    private let delegate: UpdaterDelegate // Sparkle hanya menyimpan referensi lemah
    private let driver: UpdateDriver?     // idem

    init?(canRestart: @escaping () -> Bool) {
        let delegate = UpdaterDelegate(canRestart: canRestart)
        guard let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("Sparkle.framework"),
              let bundle = Bundle(url: url), bundle.load()
        else { return nil }
        self.delegate = delegate

        // Jalur utama: SPUUpdater dengan antarmuka kustom Cognify Notch (UpdateUI.swift).
        var holder: Updater?
        let driver = UpdateDriver(
            automaticGet: { MainActor.assumeIsolated { holder?.automatic ?? false } },
            automaticSet: { on in MainActor.assumeIsolated { holder?.automatic = on } }
        )
        if let custom = Updater.makeUpdater(delegate: delegate, driver: driver) {
            updater = custom
            fallbackController = nil
            self.driver = driver
            holder = self
            return
        }

        // Cadangan: jendela bawaan Sparkle, bila SPUUpdater tidak bisa dibuat (mis. API Sparkle berubah).
        guard let type = NSClassFromString("SPUStandardUpdaterController") as? NSObject.Type,
              let allocated = (type as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject,
              let created = allocated.perform(NSSelectorFromString("initWithUpdaterDelegate:userDriverDelegate:"), with: delegate, with: nil)?
                .takeUnretainedValue() as? NSObject
        else { return nil }
        created.perform(NSSelectorFromString("startUpdater")) // periksa terjadwal (sehari sekali)
        fallbackController = created
        self.driver = nil
        guard let inner = created.value(forKey: "updater") as? NSObject else { return nil }
        updater = inner
    }

    /// Buat dan jalankan `SPUUpdater(hostBundle:applicationBundle:userDriver:delegate:)` lewat runtime.
    private static func makeUpdater(delegate: UpdaterDelegate, driver: UpdateDriver) -> NSObject? {
        guard let type = NSClassFromString("SPUUpdater") as? NSObject.Type,
              let allocated = (type as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject
        else { return nil }
        let initSel = NSSelectorFromString("initWithHostBundle:applicationBundle:userDriver:delegate:")
        guard type.instancesRespond(to: initSel), let initImp = class_getMethodImplementation(type, initSel) as IMP? else { return nil }
        typealias Init = @convention(c) (AnyObject, Selector, Bundle, Bundle, AnyObject, AnyObject?) -> AnyObject?
        guard let created = unsafeBitCast(initImp, to: Init.self)(allocated, initSel, Bundle.main, Bundle.main, driver, delegate) as? NSObject
        else { return nil }

        // -startUpdater: mengisi NSError; hanya dipakai untuk tahu berhasil atau tidak (periksa terjadwal sehari sekali).
        let startSel = NSSelectorFromString("startUpdater:")
        guard created.responds(to: startSel), let startImp = created.method(for: startSel) as IMP? else { return nil }
        typealias Start = @convention(c) (AnyObject, Selector, UnsafeMutablePointer<AnyObject?>?) -> Bool
        var error: AnyObject?
        guard unsafeBitCast(startImp, to: Start.self)(created, startSel, &error) else { return nil }
        return created
    }

    /// Unduh & pasang update tanpa bertanya (disimpan Sparkle di UserDefaults app).
    var automatic: Bool {
        get { updater.value(forKey: "automaticallyDownloadsUpdates") as? Bool ?? false }
        set { updater.setValue(newValue, forKey: "automaticallyDownloadsUpdates") }
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true) // app menu bar: jendela pembaruan harus tampil di depan
        if let controller = fallbackController {
            controller.perform(NSSelectorFromString("checkForUpdates:"), with: nil)
        } else {
            updater.perform(NSSelectorFromString("checkForUpdates"))
        }
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
