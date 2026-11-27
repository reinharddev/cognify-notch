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
    static let windowSize = CGSize(width: 1060, height: 420)

    private let panel = NotchPanel()
    private let model: NotchModel
    private var poller: Timer?
    private var fallback: Timer?
    private var screen: NSScreen?
    private var ignoring = true
    private var hiddenForFullscreen = false
    private var dragChangeCount = NSPasteboard(name: .drag).changeCount
    private var dragCountNow = 0
    private var mouseWasDown = false
    private var dropHide: DispatchWorkItem?
    private var swipeX: CGFloat = 0
    private var swiped = false
    private var nextSwipe = Date.distantPast
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
        // Kursor dibaca 20x per detik, tapi hanya selama perlu: kursor dekat notch, notch terbuka,
        // atau tombol mouse ditekan (seret file dari app lain tidak mengirim event ke monitor, jadi
        // saat menyeret posisi tetap dibaca berkala). Di luar itu tidak ada timer: gerakan mouse
        // (monitor global) yang membangunkan pembacaan lagi, jadi notch diam tidak memakai CPU.
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown]) { [weak self] event in
            MainActor.assumeIsolated { self?.wake() }
            return event
        }
        // Cadangan bila ada gerakan yang tidak terlapor (mis. saat input aman aktif).
        fallback = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.wake() }
        }
        fallback?.tolerance = 0.5
        model.$expanded.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateEdgeShift(); self?.wake() }
        }.store(in: &cancellables)
        wake()
        model.$expanded.removeDuplicates().sink { [weak self] expanded in
            if !expanded { self?.returnFocus() }
        }.store(in: &cancellables)
        // ⌃⌥N: jendela notch menerima ketikan tanpa mengaktifkan app ini (seperti Spotlight).
        model.onKeyboardOpen = { [weak self] in self?.panel.makeKey() }
        // Esc menutup notch; klik di luar notch juga menutupnya (penting saat dibuka lewat keyboard).
        // Keyboard saat notch terbuka lewat shortcut: Esc menutup, ← → pindah halaman, 1-9 lompat
        // ke halaman ke-n. Panah & angka dibiarkan untuk kolom teks yang sedang diketik.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let code = event.keyCode, flags = event.modifierFlags, chars = event.charactersIgnoringModifiers
            let handled = MainActor.assumeIsolated { self.key(code: code, flags: flags, chars: chars) }
            return handled ? nil : event
        }
        // "Buka dengan klik": klik di notch membuka panel (hover tidak lagi membuka).
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, self.model.prefs.openOnClick, !self.model.expanded,
                      self.hotRect(margin: 4).contains(NSEvent.mouseLocation) else { return }
                self.model.setExpanded(true)
            }
            return event
        }
        // Seret notch melayang untuk memindahkannya (seperti di Windows).
        for mask: NSEvent.EventTypeMask in [.leftMouseDown, .leftMouseDragged, .leftMouseUp] {
            NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
                let type = event.type
                MainActor.assumeIsolated { self?.drag(type) }
            }
            NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
                let type = event.type
                MainActor.assumeIsolated { self?.drag(type) }
                return event
            }
        }
        model.prefs.$floatDX.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.place() } }.store(in: &cancellables)
        model.prefs.$floatDY.dropFirst().sink { [weak self] _ in DispatchQueue.main.async { self?.place() } }.store(in: &cancellables)
        model.prefs.$idleScale.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyIdleScale() }
        }.store(in: &cancellables)
        // Ganti gaya atau lebar: ukur ulang dan pindahkan jendela.
        model.prefs.$floatingStyle.dropFirst().map { _ in () }.merge(with: model.prefs.$notchWidth.dropFirst().map { _ in () })
            .sink { [weak self] _ in DispatchQueue.main.async { self?.place() } }.store(in: &cancellables)
        model.prefs.$floatOnNotch.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.place() }
        }.store(in: &cancellables)
        model.prefs.$display.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.place() }
        }.store(in: &cancellables)
        NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.model.expanded, !self.model.dropTargeted,
                      !self.hotRect(margin: 6).contains(NSEvent.mouseLocation) else { return }
                self.model.setExpanded(false)
            }
        }
        // Layar penuh: diperiksa saat app aktif atau Space berganti (tanpa polling).
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Animasi masuk/keluar layar penuh perlu waktu sebelum ukuran jendela final.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { self?.checkFullscreen() }
                }
            }
        }
        // Geser dua jari: pindah halaman (di halaman Musik: ganti lagu).
        NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            MainActor.assumeIsolated { self?.scroll(event) }
            return event
        }
    }

    /// Letakkan jendela di tengah atas layar yang punya notch (atau layar utama).
    /// Tombol keyboard di panel yang terbuka; true = sudah ditangani.
    private func key(code: UInt16, flags: NSEvent.ModifierFlags, chars: String?) -> Bool {
        guard model.expanded else { return false }
        if code == 53 { // Esc
            model.setExpanded(false)
            return true
        }
        let typing = panel.firstResponder is NSTextView
        let plain = flags.intersection([.command, .option, .control]).isEmpty
        guard !typing, plain else { return false }
        switch code {
        case 123: model.page(-1); return true // ←
        case 124: model.page(1); return true  // →
        default: break
        }
        if let digit = chars.flatMap(Int.init), (1...9).contains(digit), digit <= model.tabs.count {
            model.go(to: model.tabs[digit - 1])
            return true
        }
        return false
    }

    /// Layar tempat notch tampil, menurut pilihan di Pengaturan.
    private func targetScreen() -> NSScreen? {
        let screens = NSScreen.screens
        switch model.prefs.display {
        case .notch: return screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? screens.first
        case .main: return screens.first // layar dengan menu bar utama
        case .active: return screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? screens.first
        }
    }

    func place() {
        let target = targetScreen()
        guard let target else { return }
        screen = target
        let frame = target.frame
        if target.safeAreaInsets.top > 0 && !model.prefs.floatOnNotch {
            let left = target.auxiliaryTopLeftArea?.width ?? 0
            let right = target.auxiliaryTopRightArea?.width ?? 0
            model.baseNotchSize = CGSize(width: max(120, frame.width - left - right), height: target.safeAreaInsets.top)
            model.hasNotch = true
        } else {
            let menuBar = max(24, frame.maxY - target.visibleFrame.maxY)
            model.baseNotchSize = CGSize(width: 190, height: menuBar)
            model.hasNotch = false
        }
        model.screenSize = frame.size
        // Layar ini punya poni fisik, walau notch sedang dipakai melayang (hasNotch mati karena itu). Pengaturan memakainya supaya saklar
        // "Melayang juga di Mac berponi" tetap terlihat dan bisa dimatikan lagi.
        model.physicalNotch = target.safeAreaInsets.top > 0
        model.floatMinDY = target.safeAreaInsets.top > 0 ? Double(target.safeAreaInsets.top) + 2 : 0
        applyIdleScale()
        let size = Self.windowSize
        // Notch melayang boleh dipindah dengan menyeretnya; geseran dijaga tetap di dalam layar.
        var dx = 0.0, dy = 0.0
        if !model.hasNotch {
            dx = max(-(frame.width / 2 - 60), min(frame.width / 2 - 60, model.prefs.floatDX))
            dy = min(frame.height - 120, model.floatingDY)
        }
        let base = NSRect(x: frame.midX - size.width / 2 + dx, y: frame.maxY - size.height - dy + model.topInset, width: size.width, height: size.height)
        baseFrame = base
        if model.detached && model.prefs.autoHide { model.prefs.autoHide = false } // melayang tidak bisa bersembunyi di tepi atas
        panel.setFrame(base, display: true)
        model.edgeShift = .zero
    }

    /// Posisi jendela saat notch tertutup (sebelum digeser untuk panel terbuka).
    private var baseFrame: NSRect?

    /// Notch melayang yang dibuka dekat tepi kiri, kanan, atau bawah layar: jendelanya digeser supaya panel penuh
    /// terlihat. Bentuk diberi geseran awal yang sama dengan arah sebaliknya lalu meluncur ke 0, jadi tidak melompat.
    private func updateEdgeShift() {
        guard let screen, let base = baseFrame else { return }
        if model.expanded && !model.hasNotch {
            let area = screen.visibleFrame.insetBy(dx: 8, dy: 8)
            let size = model.size
            let left = base.midX - size.width / 2 + model.shapeOffset
            var sx: CGFloat = 0, sy: CGFloat = 0
            if size.width >= area.width { sx = area.midX - (left + size.width / 2) }
            else if left < area.minX { sx = area.minX - left }
            else if left + size.width > area.maxX { sx = area.maxX - (left + size.width) }
            let bottom = base.maxY - model.topInset - size.height
            if bottom < area.minY { sy = area.minY - bottom }
            guard sx != 0 || sy != 0 else { return }
            let target = base.offsetBy(dx: sx, dy: sy)
            guard panel.frame != target else { return }
            panel.setFrame(target, display: true)
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) { model.edgeShift = CGSize(width: -sx, height: sy) } // SwiftUI y ke bawah
            withAnimation(.notch) { model.edgeShift = .zero }
        } else if panel.frame != base, !model.expanded {
            // Menutup: bentuk meluncur ke posisi lama, lalu jendela dikembalikan.
            let back = CGSize(width: base.midX - panel.frame.midX, height: panel.frame.minY - base.minY)
            withAnimation(.notch) { model.edgeShift = back }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                guard let self, !self.model.expanded, let base = self.baseFrame else { return }
                var t = Transaction(); t.disablesAnimations = true
                withTransaction(t) { self.model.edgeShift = .zero }
                self.panel.setFrame(base, display: true)
            }
        }
    }

    private var dragStart: (mouse: NSPoint, dx: Double, dy: Double)?

    private func drag(_ type: NSEvent.EventType) {
        let mouse = NSEvent.mouseLocation
        switch type {
        case .leftMouseDown:
            dragStart = nil
            guard !model.hasNotch, !model.expanded, hotRect(margin: 4).contains(mouse) else { return }
            dragStart = (mouse, model.prefs.floatDX, model.floatingDY)
        case .leftMouseDragged:
            guard let s = dragStart, !model.expanded else { return }
            let mx = mouse.x - s.mouse.x, my = mouse.y - s.mouse.y
            guard abs(mx) + abs(my) > 4 else { return }
            model.moveFloating(dx: s.dx + mx, dy: s.dy - my)
            place()
        default:
            dragStart = nil
        }
    }

    /// Tinggi notch melayang saat tertutup (pt) pada skala 100%, dan batas bawahnya saat diperkecil.
    static let floatingHeight: CGFloat = 36
    static let floatingMinHeight: CGFloat = 28

    /// Ukuran notch diam = ukuran bawaan layar × pilihan pengguna. Di Mac ber-notch tidak lebih kecil dari notch fisik.
    private func applyIdleScale() {
        let s = CGFloat(model.prefs.idleScale)
        let f = model.hasNotch ? max(1, s) : s
        var base = model.baseNotchSize
        if !model.hasNotch { base.width = model.detached ? 84 : CGFloat(model.prefs.notchWidth) }
        // Notch melayang (jauh dari tepi atas) tidak berbatasan dengan menu bar, jadi diberi tinggi tersendiri:
        // setinggi menu bar (24 pt) pil-nya tampak gepeng. Yang menempel di tepi atas tetap setinggi menu bar.
        let height: CGFloat = model.hasNotch ? base.height
            : model.detached ? max(Self.floatingMinHeight, (Self.floatingHeight * f).rounded())
            : max(20, (base.height * f).rounded())
        model.notchSize = CGSize(width: (base.width * f).rounded(), height: height)
    }

    /// Area notch saat ini (koordinat layar), sedikit diperlebar supaya mudah dituju.
    private func hotRect(margin: CGFloat) -> NSRect {
        guard screen != nil else { return .zero }
        let frame = panel.frame // ikut bergeser saat notch melayang dipindah
        let size = model.size
        return NSRect(x: frame.midX - size.width / 2 + model.shapeOffset, y: frame.maxY - model.topInset - (model.lyricRow ? model.notchSize.height : size.height), width: size.width + model.lyricGroupWidth, height: model.lyricRow ? model.notchSize.height : size.height)
            .insetBy(dx: -margin, dy: -margin)
    }

    /// Tempat baris lirik di bawah notch (koordinat layar), tidak tergantung sedang tampil atau disembunyikan.
    private func lyricRect() -> NSRect {
        let bar = hotRect(margin: 0)
        let height = NotchModel.lyricRowHeight + (model.detached ? 8 : 0)
        return NSRect(x: bar.minX, y: bar.minY - height, width: bar.width, height: height)
    }

    /// Kursor dekat notch (atau sedang ada yang perlu diikuti) → pembacaan 20x per detik menyala.
    private func needsTracking(_ mouse: NSPoint) -> Bool {
        model.expanded || model.dropTargeted || NSEvent.pressedMouseButtons & 1 == 1 || mouseWasDown
            || hotRect(margin: 90).contains(mouse)
    }

    private func wake() {
        model.noteActivity()
        if model.prefs.companionFollow, model.headMode || model.live?.eyes == true {
            // Kepala melayang atau mata di notch: menoleh ke arah kursor. Mati: kembali lurus.
            let r = hotRect(margin: 0)
            model.face.look(at: NSEvent.mouseLocation, from: NSPoint(x: r.midX - model.lyricGroupWidth / 2, y: r.midY))
        } else if !model.prefs.companionFollow {
            model.face.lookAhead()
        }
        model.tickAutoHide()
        // "Layar yang sedang dipakai": notch pindah begitu kursor pindah ke layar lain.
        if model.prefs.display == .active, !model.expanded,
           let here = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }), here != screen {
            place()
        }
        guard poller == nil, needsTracking(NSEvent.mouseLocation) else { return }
        poller = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.track() }
        }
        track()
    }

    private func track() {
        let mouse = NSEvent.mouseLocation
        let down = NSEvent.pressedMouseButtons & 1 == 1
        // Pasteboard seret hanya dibaca saat tombol ditekan (setiap pembacaan = panggilan ke sistem).
        if down {
            let count = NSPasteboard(name: .drag).changeCount
            if !mouseWasDown { dragChangeCount = count }
            dragCountNow = count
        }
        mouseWasDown = down
        // Seret berisi (file/tautan/teks) = isi pasteboard seret berubah sejak tombol ditekan.
        // Menggeser jendela lain di dekat notch tidak mengubahnya, jadi notch tidak ikut terbuka.
        let draggingContent = down && dragCountNow != dragChangeCount

        let inside: Bool
        if model.expanded {
            inside = hotRect(margin: 6).contains(mouse)
        } else if draggingContent {
            inside = hotRect(margin: 40).contains(mouse)
        } else if down {
            inside = false // klik/seret biasa di menu bar tidak membuka notch
        } else {
            inside = hotRect(margin: model.hasNotch ? 4 : model.headMode ? 8 : 2).contains(mouse)
        }
        let ignore = !(inside || model.expanded && hotRect(margin: 6).contains(mouse))
        if ignore != ignoring { // setiap penggantian = transaksi ke window server
            ignoring = ignore
            panel.ignoresMouseEvents = ignore
        }
        updateDrop(draggingContent && inside)
        if !model.dropTargeted { model.setHover(inside) } // tetap terbuka selama file berada di atas notch
        // Kursor di baris lirik: sembunyikan barisnya. Area itu di luar `hotRect`, jadi klik tetap diteruskan.
        let overLyric = model.lyricRow && lyricRect().contains(mouse)
        if overLyric != model.lyricHidden { model.lyricHidden = overLyric }
        HoverRegistry.shared.update(model.expanded ? mouse : nil) // hover di dalam panel (lihat Hover.swift)
        if !needsTracking(mouse) {
            poller?.invalidate()
            poller = nil
        }
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

    /// Geser dua jari ke kiri/kanan di panel terbuka: di halaman Musik ganti lagu, di halaman lain
    /// pindah halaman.
    private func scroll(_ event: NSEvent) {
        guard model.expanded, event.hasPreciseScrollingDeltas else { return }
        // Hanya saat kursor di dalam panel, dan sisa dorongan (inersia) setelah jari diangkat
        // diabaikan: satu geseran = satu halaman, tidak bisa terlewat dua sekaligus.
        guard event.momentumPhase.isEmpty, hotRect(margin: 0).contains(NSEvent.mouseLocation) else { return }
        if event.phase == .began { swipeX = 0; swiped = false }
        swipeX += event.scrollingDeltaX
        guard !swiped, abs(swipeX) > 60, abs(swipeX) > abs(event.scrollingDeltaY) * 2,
              Date() >= nextSwipe else { return }
        swiped = true
        nextSwipe = Date().addingTimeInterval(0.35)
        // "Natural scrolling": konten mengikuti jari, jadi arah delta terbalik.
        let fingersLeft = event.isDirectionInvertedFromDevice ? swipeX < 0 : swipeX > 0
        if model.tab == .music, model.media.nowPlaying != nil {
            fingersLeft ? model.media.next() : model.media.previous()
        } else {
            model.page(fingersLeft ? 1 : -1)
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// App layar penuh di layar notch → notch disembunyikan sampai app itu keluar dari layar penuh.
    private func checkFullscreen() {
        let hide = model.features.hideFullscreen && FullscreenCheck.active(on: screen)
        guard hide != hiddenForFullscreen else { return }
        hiddenForFullscreen = hide
        if hide {
            model.setExpanded(false)
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    /// Setelah notch menutup, kembalikan keyboard ke app yang sedang dipakai tanpa
    /// menyembunyikan dan menampilkan ulang panel (yang membuat notch berkedip).
    private func returnFocus() {
        guard panel.isKeyWindow else { return }
        panel.makeFirstResponder(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self, !self.model.expanded, self.panel.isKeyWindow,
                  let app = NSWorkspace.shared.frontmostApplication,
                  app.processIdentifier != NSRunningApplication.current.processIdentifier else { return }
            app.activate(options: [])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: NotchController?
    private var model: NotchModel?
    private var statusMenu: StatusMenu?
    private var link: NotchLink?
    private var dock: DockController?
    private var widgetExport: WidgetExport?
    private var skinManager: SkinManager?
    private let bridge = Bridge()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            let model = NotchModel(bridge: bridge, appMode: bridge.appMode, prefs: Preferences(persist: bridge.appMode))
            self.model = model
            controller = NotchController(model: model)
            dock = DockController(app: model)
            // Menyalin data ke Cognify hanya setelah pengguna menghubungkannya di Cognify.
            link = NotchLink(model: model)
            link?.start()
            model.hub.start()
            widgetExport = WidgetExport(model: model)
            widgetExport?.start()
            skinManager = SkinManager(model: model)
            model.skinManager = skinManager
            skinManager?.start()
            if bridge.appMode {
                statusMenu = StatusMenu(model: model)
                // Pertama kali dibuka: tunjukkan di mana notch-nya.
                if !UserDefaults.standard.bool(forKey: "welcomed") {
                    UserDefaults.standard.set(true, forKey: "welcomed")
                    model.show(.alert(title: L("Cognify Notch sudah aktif", "Cognify Notch is on"),
                                      detail: L("Arahkan kursor ke notch kapan saja. Pengaturannya ada di ikon menu bar.",
                                                "Hover over the notch any time. Settings are in the menu bar icon."), action: nil))
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
                    f.clipboard = flags["clipboard"] ?? f.clipboard
                    f.downloads = flags["downloads"] ?? f.downloads
                    f.voice = flags["voice"] ?? f.voice
                    f.lyrics = flags["lyrics"] ?? f.lyrics
                    f.water = flags["water"] ?? f.water
                    f.todo = flags["todo"] ?? f.todo
                    f.companion = flags["companion"] ?? f.companion
                    f.keyboard = flags["keyboard"] ?? f.keyboard
                    f.network = flags["network"] ?? f.network
                    f.hideFullscreen = flags["hide_fullscreen"] ?? f.hideFullscreen
                    model.apply(f)
                }
            }
            if bridge.standalone != nil { model.apply(NotchModel.Features()) } // uji manual: semua default
            bridge.start()
        }
    }
}
