import AppKit
import ApplicationServices
import NotchDock

// Jendela tiap aplikasi di menu klik kanan dock. Judul dan mengangkat jendela butuh izin Aksesibilitas (Pengaturan Sistem >
// Privasi & Keamanan); tanpa izin dock hanya bisa menghitung jendela yang terlihat. Tidak ada data yang dikirim ke mana pun:
// judul dibaca lokal untuk baris menu.

struct AppWindow: Identifiable {
    let id: Int
    let title: String
    let minimized: Bool
    fileprivate let element: AXUIElement
}

enum DockWindows {
    static var trusted: Bool { AXIsProcessTrusted() }

    /// Memunculkan dialog izin sistem (hanya sekali per sesi app oleh sistem), lalu pengguna menyalakannya di Pengaturan Sistem.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
    }

    /// Jendela aplikasi (termasuk yang diminimalkan), dengan judulnya. Kosong tanpa izin atau bila aplikasi tidak menjawab.
    static func windows(pid: pid_t) -> [AppWindow] {
        guard trusted else { return [] }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.35) // aplikasi yang macet tidak boleh menahan menu
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success, let list = value as? [AXUIElement] else { return [] }
        return list.enumerated().compactMap { index, el in
            var role: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role)
            guard (role as? String) == kAXWindowRole as String else { return nil }
            var title: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &title)
            var mini: CFTypeRef?
            AXUIElementCopyAttributeValue(el, kAXMinimizedAttribute as CFString, &mini)
            return AppWindow(id: index, title: DockWindowTitle.display(title as? String, minimized: (mini as? Bool) == true),
                             minimized: (mini as? Bool) == true, element: el)
        }
    }

    /// Jumlah jendela yang terlihat di Space ini, tanpa izin (judulnya tidak tersedia tanpa izin Perekaman Layar).
    static func visibleCount(pid: pid_t) -> Int {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return 0 }
        return info.filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }.count
    }

    static func raise(_ window: AppWindow, pid: pid_t) {
        if window.minimized { AXUIElementSetAttributeValue(window.element, kAXMinimizedAttribute as CFString, kCFBooleanFalse) }
        AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate(options: [])
    }

    static func close(_ window: AppWindow) {
        var button: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window.element, kAXCloseButtonAttribute as CFString, &button) == .success, let b = button else { return }
        AXUIElementPerformAction(b as! AXUIElement, kAXPressAction as CFString)
    }
}
