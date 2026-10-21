import AppKit
import SwiftUI

/// Hover yang tetap bekerja di panel notch.
///
/// Notch sengaja tidak pernah mengaktifkan app-nya (app yang sedang dipakai user tetap aktif), dan
/// selama app tidak aktif macOS tidak mengirim gerakan mouse ke jendelanya: `onHover` SwiftUI dan
/// tracking area AppKit sama-sama diam (teruji). Jadi posisi kursor dibaca sendiri:
/// `NotchController.track()` (20x per detik selama notch terbuka) memanggil `HoverRegistry.update`,
/// yang mencocokkan kursor dengan setiap area hover yang sedang tampil.
@MainActor
final class HoverRegistry {
    static let shared = HoverRegistry()

    private final class Weak {
        weak var view: HoverView?
        init(_ view: HoverView) { self.view = view }
    }

    private var views: [Weak] = []

    fileprivate func add(_ view: HoverView) {
        views.removeAll { $0.view == nil || $0.view === view }
        views.append(Weak(view))
    }

    fileprivate func remove(_ view: HoverView) {
        views.removeAll { $0.view == nil || $0.view === view }
    }

    /// `mouse` dalam koordinat layar; nil = notch tertutup (semua hover dilepas).
    func update(_ mouse: NSPoint?) {
        views.removeAll { $0.view == nil }
        for entry in views {
            guard let view = entry.view else { continue }
            guard let mouse, let window = view.window, !view.isHiddenOrHasHiddenAncestor else {
                view.set(inside: false, point: nil)
                continue
            }
            let local = view.convert(window.convertPoint(fromScreen: mouse), from: nil)
            let inside = view.bounds.contains(local)
            view.set(inside: inside, point: inside ? local : nil)
        }
    }
}

fileprivate final class HoverView: NSView {
    var onHover: ((Bool) -> Void)?
    var onMove: ((CGPoint?) -> Void)?
    private var inside = false
    private var lastPoint: CGPoint?

    override var isFlipped: Bool { true } // koordinat dari kiri atas, seperti SwiftUI

    override func hitTest(_ point: NSPoint) -> NSView? { nil } // klik tetap ke tombol di bawahnya

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        MainActor.assumeIsolated {
            if window != nil { HoverRegistry.shared.add(self) } else { HoverRegistry.shared.remove(self) }
        }
    }

    func set(inside next: Bool, point: CGPoint?) {
        if next != inside {
            inside = next
            onHover?(next)
            if !next { onMove?(nil) }
        }
        if next, point != lastPoint { onMove?(point) }
        lastPoint = point
    }
}

private struct HoverArea: NSViewRepresentable {
    var onHover: ((Bool) -> Void)?
    var onMove: ((CGPoint?) -> Void)?

    func makeNSView(context: Context) -> HoverView {
        let view = HoverView()
        view.onHover = onHover
        view.onMove = onMove
        return view
    }

    func updateNSView(_ view: HoverView, context: Context) {
        view.onHover = onHover
        view.onMove = onMove
    }
}

private struct HoverTracking: ViewModifier {
    var onHover: ((Bool) -> Void)?
    var onMove: ((CGPoint?) -> Void)?
    @Environment(\.snapshot) private var snapshot

    func body(content: Content) -> some View {
        if snapshot { // view AppKit tidak ikut terender di snapshot
            content
        } else {
            content.overlay(HoverArea(onHover: onHover, onMove: onMove))
        }
    }
}

extension View {
    /// Pengganti `onHover` untuk panel notch.
    func notchHover(_ action: @escaping (Bool) -> Void) -> some View {
        modifier(HoverTracking(onHover: action))
    }

    /// Posisi kursor (koordinat lokal, kiri atas) selama berada di atas view ini; nil saat keluar.
    func notchPointer(_ action: @escaping (CGPoint?) -> Void) -> some View {
        modifier(HoverTracking(onMove: action))
    }
}
