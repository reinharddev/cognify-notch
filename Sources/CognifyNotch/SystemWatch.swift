import AppKit
import Carbon
import Network

/// Caps Lock menyala/mati dan bahasa keyboard berganti. Tanpa izin Aksesibilitas/Input Monitoring:
/// Caps Lock dibaca dari status tombol pengubah (sekali per detik, timer toleran), bahasa keyboard
/// dari notifikasi sistem saat sumber input berganti.
@MainActor
final class KeyboardWatcher {
    var onCapsLock: ((Bool) -> Void)?
    var onInputSource: ((String) -> Void)?

    private var timer: Timer?
    private var observer: NSObjectProtocol?
    private var caps = NSEvent.modifierFlags.contains(.capsLock)
    private var source = KeyboardWatcher.currentSource()

    func setEnabled(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        guard enabled else { return }
        caps = NSEvent.modifierFlags.contains(.capsLock)
        source = Self.currentSource()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkCaps() }
        }
        timer?.tolerance = 0.3
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSource() }
        }
    }

    /// Dipanggil juga dari gerakan/klik mouse supaya perubahan terasa cepat.
    func checkCaps() {
        let now = NSEvent.modifierFlags.contains(.capsLock)
        guard now != caps else { return }
        caps = now
        onCapsLock?(now)
    }

    private func checkSource() {
        let now = Self.currentSource()
        guard let now, now != source else { return }
        source = now
        onInputSource?(now)
    }

    private static func currentSource() -> String? {
        guard let input = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(input, kTISPropertyLocalizedName) else { return nil }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }
}

/// Koneksi internet putus/tersambung lagi (Network.framework, tanpa izin).
@MainActor
final class NetworkWatcher {
    var onChange: ((Bool) -> Void)?

    private var monitor: NWPathMonitor?
    private var online: Bool?

    func setEnabled(_ enabled: Bool) {
        monitor?.cancel()
        monitor = nil
        online = nil
        guard enabled else { return }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.update(up) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "cognify.network"))
        self.monitor = monitor
    }

    private func update(_ up: Bool) {
        defer { online = up }
        guard let online, online != up else { return } // status awal tidak diumumkan
        onChange?(up)
    }
}

/// App yang sedang dipakai memenuhi layar notch (video, game, presentasi) → notch menyingkir.
/// Hanya ukuran & pemilik jendela yang dibaca (tanpa izin Rekam Layar; isi jendela tidak).
enum FullscreenCheck {
    static func active(on screen: NSScreen?) -> Bool {
        guard let screen, let front = NSWorkspace.shared.frontmostApplication,
              front.bundleIdentifier != Bundle.main.bundleIdentifier,
              let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else { return false }
        let size = screen.frame.size
        for window in list {
            guard window[kCGWindowOwnerPID as String] as? pid_t == front.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"] else { continue }
            if width >= size.width, height >= size.height { return true }
        }
        return false
    }
}
