import AppKit

/// Update otomatis app mandiri "Cognify Notch" lewat Sparkle (MIT).
///
/// Sparkle.framework hanya ada di dalam "Cognify Notch.app" (scripts/build-notch-app.sh), tidak di
/// notch yang dijalankan Cognify, jadi dimuat saat berjalan (bukan di-link): notch di dalam Cognify
/// tetap jalan tanpa framework ini. Alamat appcast & kunci publik ada di Info.plist app
/// (SUFeedURL, SUPublicEDKey); tidak ada profil sistem yang dikirim (SUEnableSystemProfiling = NO).
@MainActor
final class Updater {
    private let controller: NSObject

    init?() {
        guard let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("Sparkle.framework"),
              let bundle = Bundle(url: url), bundle.load(),
              let type = NSClassFromString("SPUStandardUpdaterController") as? NSObject.Type,
              let allocated = (type as AnyObject).perform(NSSelectorFromString("alloc"))?.takeUnretainedValue() as? NSObject,
              let created = allocated.perform(NSSelectorFromString("initWithUpdaterDelegate:userDriverDelegate:"), with: nil, with: nil)?
                .takeUnretainedValue() as? NSObject
        else { return nil }
        controller = created
        controller.perform(NSSelectorFromString("startUpdater")) // periksa terjadwal (sehari sekali)
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true) // app menu bar: jendela Sparkle harus tampil di depan
        controller.perform(NSSelectorFromString("checkForUpdates:"), with: nil)
    }
}
