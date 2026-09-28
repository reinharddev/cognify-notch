import AppKit
import Combine
import SwiftUI

/// Jendela transparan di atas menu bar, tepat di notch. Tidak pernah mengaktifkan app ini
/// (`.nonactivatingPanel`), jadi app yang sedang dipakai user tetap aktif; panel hanya menjadi
/// "key" saat user mengetik di catatan cepat (seperti Spotlight).
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class NotchController {
    /// Cukup untuk panel terbuka + bayangannya; area transparan lainnya meneruskan klik.
    static let windowSize = CGSize(width: 760, height: 300)

    private let panel = NotchPanel()
    private let model: NotchModel
    private var poller: Timer?
    private var screen: NSScreen?
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var mouseWasDown = false
    private var dropHide: DispatchWorkItem?
    private var swipeX: CGFloat = 0
    private var swiped = false
    private var cancellables = Set<AnyCancellable>()

    init(model: NotchModel) {
        self.model = model
        let host = NSHostingView(rootView: NotchRoot(model: model))
        host.sizingOptions = []
        panel.contentView = host
        place()
        panel.orderFrontRegardless()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.place() }
        }
        // Kursor dibaca 20x per detik: lebih andal daripada event monitor untuk hover + seret
        // file (event seret dari app lain tidak sampai ke monitor), dan bebannya kecil.
        poller = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.track() }
        }
        model.$expanded.removeDuplicates().sink { [weak self] expanded in
            if !expanded { self?.returnFocus() }
        }.store(in: &cancellables)
        // ⌃⌥N: jendela notch menerima ketikan tanpa mengaktifkan app ini (seperti Spotlight).
        model.onKeyboardOpen = { [weak self] in self?.panel.makeKey() }
        // Esc menutup notch; klik di luar notch juga menutupnya (penting saat dibuka lewat keyboard).
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 53, self.model.expanded else { return event }
            MainActor.assumeIsolated { self.model.setExpanded(false) }
            return nil
        }
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.expanded, !self.model.dropTargeted,
                      !self.hotRect(margin: 6).contains(NSEvent.mouseLocation) else { return }
                self.model.setExpanded(false)
            }
        }
        // Geser dua jari ke kiri/kanan di notch = lagu berikutnya/sebelumnya.
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.scroll(event) }
            return event
        }
    }

    /// Letakkan jendela di tengah atas layar yang punya notch (atau layar utama).
    func place() {
        let screens = NSScreen.screens
        let target = screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? screens.first
        guard let target else { return }
        screen = target
        let frame = target.frame
        if target.safeAreaInsets.top > 0 {
            let left = target.auxiliaryTopLeftArea?.width ?? 0
            let right = target.auxiliaryTopRightArea?.width ?? 0
            model.notchSize = CGSize(width: max(120, frame.width - left - right), height: target.safeAreaInsets.top)
            model.hasNotch = true
        } else {
            let menuBar = max(24, frame.maxY - target.visibleFrame.maxY)
            model.notchSize = CGSize(width: 190, height: menuBar)
            model.hasNotch = false
        }
        let size = Self.windowSize
        panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }

    /// Area notch saat ini (koordinat layar), sedikit diperlebar supaya mudah dituju.
    private func hotRect(margin: CGFloat) -> NSRect {
        guard let frame = screen?.frame else { return .zero }
        let size = model.size
        return NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
            .insetBy(dx: -margin, dy: -margin)
    }

    private func track() {
        let mouse = NSEvent.mouseLocation
        let down = NSEvent.pressedMouseButtons & 1 == 1
        let drag = NSPasteboard(name: .drag)
        if down && !mouseWasDown { dragChangeCount = drag.changeCount }
        mouseWasDown = down
        // Seret berisi (file/tautan/teks) = isi pasteboard seret berubah sejak tombol ditekan.
        // Menggeser jendela lain di dekat notch tidak mengubahnya, jadi notch tidak ikut terbuka.
        let draggingContent = down && drag.changeCount != dragChangeCount

        let inside: Bool
        if model.expanded {
            inside = hotRect(margin: 6).contains(mouse)
        } else if draggingContent {
            inside = hotRect(margin: 40).contains(mouse)
        } else if down {
            inside = false // klik/seret biasa di menu bar tidak membuka notch
        } else {
            inside = hotRect(margin: model.hasNotch ? 4 : 2).contains(mouse)
        }
        panel.ignoresMouseEvents = !(inside || model.expanded && hotRect(margin: 6).contains(mouse))
        updateDrop(draggingContent && inside)
        if model.dropTargeted { return } // tetap terbuka selama file berada di atas notch
        model.setHover(inside)
    }

    /// Pilihan "Knowledge / tray" tampil selama isi diseret di atas notch. Disembunyikan sedikit
    /// terlambat: saat tombol mouse dilepas, macOS baru mengirim isi seretnya ke zona tujuan.
    private func updateDrop(_ over: Bool) {
        if over {
            dropHide?.cancel()
            dropHide = nil
            if !model.dropTargeted { withAnimation(.notch) { model.dropTargeted = true } }
        } else if model.dropTargeted, dropHide == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.dropHide = nil
                withAnimation(.notch) { self.model.dropTargeted = false }
            }
            dropHide = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
        }
    }

    private func scroll(_ event: NSEvent) {
        guard model.expanded, model.tab == .home, model.media.nowPlaying != nil, event.hasPreciseScrollingDeltas else { return }
        if event.phase == .began { swipeX = 0; swiped = false }
        swipeX += event.scrollingDeltaX
        guard !swiped, abs(swipeX) > 60, abs(swipeX) > abs(event.scrollingDeltaY) * 2 else { return }
        swiped = true
        // "Natural scrolling": konten mengikuti jari, jadi arah delta terbalik.
        let fingersLeft = event.isDirectionInvertedFromDevice ? swipeX < 0 : swipeX > 0
        fingersLeft ? model.media.next() : model.media.previous()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// Setelah notch menutup, kembalikan keyboard ke app yang sedang dipakai.
    private func returnFocus() {
        guard panel.isKeyWindow else { return }
        panel.makeFirstResponder(nil)
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var model: NotchModel?
    private var statusMenu: StatusMenu?
    private let bridge = Bridge()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let model = NotchModel(bridge: bridge, appMode: bridge.appMode)
            self.model = model
            controller = NotchController(model: model)
            if bridge.appMode {
                statusMenu = StatusMenu(model: model)
                // Pertama kali dibuka: tunjukkan di mana notch-nya.
                if !UserDefaults.standard.bool(forKey: "welcomed") {
                    UserDefaults.standard.set(true, forKey: "welcomed")
                    model.show(.alert(title: "Cognify Notch sudah aktif",
                                      detail: "Arahkan kursor ke notch kapan saja. Pengaturan ada di ikon menu bar.", action: nil))
                }
                return
            }
            bridge.onBackend = { info in MainActor.assumeIsolated { model.connect(info) } }
            bridge.onConfig = { flags in
                MainActor.assumeIsolated {
                    var f = NotchModel.Features()
                    f.media = flags["media"] ?? f.media
                    f.calendar = flags["calendar"] ?? f.calendar
                    f.camera = flags["camera"] ?? f.camera
                    f.shortcuts = flags["shortcuts"] ?? f.shortcuts
                    f.hud = flags["hud"] ?? f.hud
                    f.spectrum = flags["spectrum"] ?? f.spectrum
                    f.power = flags["power"] ?? f.power
                    f.devices = flags["devices"] ?? f.devices
                    f.hotkey = flags["hotkey"] ?? f.hotkey
                    model.apply(f)
                }
            }
            if bridge.standalone != nil { model.apply(NotchModel.Features()) } // uji manual: semua default
            bridge.start()
        }
    }
}
