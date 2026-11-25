import AppKit
import Combine
import NotchDock
import SwiftUI

// Dock melayang (taskbar kustom). Mati secara bawaan; pengguna menyalakannya di Pengaturan > Dock.
// Ini panel milik app, bukan pengganti Dock macOS: Dock bawaan tetap ada (atau auto-hide bila pengguna memilihnya),
// dan dock ini duduk di atasnya. Aturan lebar dan radius ada di NotchDock (diuji terpisah).

/// Aplikasi yang berjalan dan sematan, dalam bentuk yang siap digambar.
@MainActor
final class DockModel: ObservableObject {
    @Published private(set) var running: [DockRunning] = []
    @Published var screenWidth: CGFloat = 1440
    /// Kursor sedang di atas dock: jendela dock dibesarkan (ke atas dan ke samping) supaya ikon yang membesar tidak terpotong.
    @Published var hovering = false
    private var bundleURLs: [String: URL] = [:]
    private var bag: [NSObjectProtocol] = []
    private let prefs: Preferences

    init(prefs: Preferences) {
        self.prefs = prefs
        refresh()
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            bag.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refresh() }
            })
        }
    }

    deinit { for b in bag { NSWorkspace.shared.notificationCenter.removeObserver(b) } }

    func refresh() {
        let me = Bundle.main.bundleIdentifier
        var list: [DockRunning] = []
        var urls: [String: URL] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier, id != me, !list.contains(where: { $0.id == id }) else { continue }
            list.append(DockRunning(id: id, name: app.localizedName ?? id))
            if let u = app.bundleURL { urls[id] = u }
        }
        // Hanya terbitkan bila isinya berubah: pemberitahuan peluncuran datang juga dari proses latar, dan tiap penerbitan menggambar ulang dock.
        if list != running { running = list }
        bundleURLs.merge(urls) { $1 }
    }

    var config: DockConfig { DockConfig(iconSize: CGFloat(prefs.dockIconSize), showClock: prefs.dockClock, modules: prefs.dockModules, links: prefs.dockLinks.count) }
    var fitted: DockConfig { DockLayout.fitted(screenW: screenWidth, config) }
    var entries: [DockEntry] { DockApps.entries(pins: prefs.dockPins, running: running) }

    /// Ikon aplikasi, dibuat sekali per aplikasi. Membuatnya ulang tiap menggambar membuat ikon berkedip dan boros.
    private var iconCache: [String: NSImage] = [:]
    private var menuIconCache: [String: NSImage] = [:]

    func icon(_ id: String) -> NSImage {
        if let cached = iconCache[id] { return cached }
        let image: NSImage
        if let u = bundleURLs[id] ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            bundleURLs[id] = u
            image = NSWorkspace.shared.icon(forFile: u.path)
        } else {
            image = NSWorkspace.shared.icon(for: .applicationBundle)
        }
        iconCache[id] = image
        return image
    }

    func open(_ id: String) {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            app.activate(options: [.activateAllWindows])
        } else if let u = bundleURLs[id] ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: u, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Ikon 16 pt untuk baris menu.
    func menuIcon(_ id: String) -> NSImage {
        if let cached = menuIconCache[id] { return cached }
        let img = (icon(id).copy() as? NSImage) ?? icon(id)
        img.size = NSSize(width: 16, height: 16)
        menuIconCache[id] = img
        return img
    }

    func reveal(_ id: String) {
        if let u = bundleURLs[id] ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { NSWorkspace.shared.activateFileViewerSelecting([u]) }
    }

    func hide(_ id: String) { NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.hide() }

    func pid(_ id: String) -> pid_t? { NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.processIdentifier }
    func windows(_ id: String) -> [AppWindow] { pid(id).map(DockWindows.windows(pid:)) ?? [] }
    func visibleWindowCount(_ id: String) -> Int { pid(id).map(DockWindows.visibleCount(pid:)) ?? 0 }
    func raise(_ w: AppWindow, _ id: String) { if let p = pid(id) { DockWindows.raise(w, pid: p) } }

    func quit(_ id: String) { NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.terminate() }

    func togglePin(_ e: DockEntry) { prefs.dockPins = DockApps.togglePin(prefs.dockPins, id: e.id, name: e.name) }
    func movePin(_ e: DockEntry, by o: Int) { prefs.dockPins = DockApps.movePin(prefs.dockPins, id: e.id, by: o) }

    /// Peluncur aplikasi milik sistem, sama dengan ikon paling kiri di Dock macOS: Apps (macOS 26 ke atas) atau Launchpad.
    /// Bila keduanya tidak ada, folder Aplikasi.
    static let launcher: URL? = ["/System/Applications/Apps.app", "/System/Applications/Launchpad.app"]
        .map { URL(fileURLWithPath: $0) }.first { FileManager.default.fileExists(atPath: $0.path) }

    func openStart() {
        if let url = Self.launcher {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
        }
    }
}

/// Panel dock: tidak mengaktifkan app ini, sehingga aplikasi yang sedang dipakai tetap aktif saat ikon diklik.
final class DockPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        // Tanpa fullScreenAuxiliary: dock bersembunyi saat aplikasi layar penuh.
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
    }
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class DockController {
    private let prefs: Preferences
    private let app: NotchModel
    private let model: DockModel
    private var panel: DockPanel?
    private var bag = Set<AnyCancellable>()

    init(app: NotchModel) {
        let prefs = app.prefs
        self.prefs = prefs
        self.app = app
        model = DockModel(prefs: prefs)
        prefs.$dockEnabled.sink { [weak self] on in DispatchQueue.main.async { self?.sync(on) } }.store(in: &bag)
        // Semua yang memengaruhi ukuran atau letak: pasang ulang bila berubah.
        let changes: [AnyPublisher<Void, Never>] = [
            prefs.$dockClock.map { _ in }.eraseToAnyPublisher(), prefs.$dockIconSize.map { _ in }.eraseToAnyPublisher(),
            prefs.$dockModules.map { _ in }.eraseToAnyPublisher(), prefs.$dockMagnify.map { _ in }.eraseToAnyPublisher(), model.$hovering.map { _ in }.eraseToAnyPublisher(), prefs.$dockLinks.map { _ in }.eraseToAnyPublisher(), prefs.$dockMargin.map { _ in }.eraseToAnyPublisher(), prefs.$dockPins.map { _ in }.eraseToAnyPublisher(),
            model.$running.map { _ in }.eraseToAnyPublisher(),
            NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification).map { _ in }.eraseToAnyPublisher(),
            // Pengaturan Dock macOS berubah (sembunyikan otomatis, ukuran, posisi): atur ulang jarak dari tepi bawah.
            DistributedNotificationCenter.default().publisher(for: Notification.Name("com.apple.dock.prefchanged")).map { _ in }.eraseToAnyPublisher(),
        ]
        Publishers.MergeMany(changes).dropFirst().debounce(for: .milliseconds(30), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.place() }.store(in: &bag)
    }

    private func sync(_ on: Bool) {
        if on {
            if panel == nil {
                let p = DockPanel()
                p.contentView = NSHostingView(rootView: DockView(model: model, prefs: prefs, app: app))
                panel = p
            }
            place()
            panel?.orderFrontRegardless()
        } else {
            panel?.orderOut(nil)
            panel = nil
        }
    }

    /// Ukuran dari aturan, bukan dari isi: lebarnya pasti dan tidak melewati layar.
    private func place() {
        guard let panel, let screen = NSScreen.screens.first else { return } // layar utama (yang punya menu bar), supaya dock tidak berpindah layar mengikuti fokus
        if model.screenWidth != screen.frame.width { model.screenWidth = screen.frame.width }
        let cfg = model.fitted
        let slots = DockLayout.appSlots(screenW: screen.frame.width, cfg)
        let apps = min(model.entries.count, slots)
        let size = CGSize(width: DockLayout.width(apps: max(apps, 0), cfg), height: DockMetrics.cell(cfg.iconSize) + DockMetrics.pad * 2)
        let native = UserDefaults(suiteName: "com.apple.dock")
        let reserve = NativeDock.reserve(autohide: native?.bool(forKey: "autohide") ?? false, orientation: native?.string(forKey: "orientation") ?? "bottom",
                                         tile: CGFloat(native?.double(forKey: "tilesize") ?? 0), large: CGFloat(native?.double(forKey: "largesize") ?? 0),
                                         magnification: native?.bool(forKey: "magnification") ?? false)
        let o = DockLayout.origin(screen: screen.frame, visible: screen.visibleFrame, size: size, margin: CGFloat(prefs.dockMargin), reserve: reserve)
        // Ruang transparan di sekeliling dock: tipis saat diam (supaya dock bisa membal), dan lebih besar saat kursor di atasnya (supaya ikon
        // yang membesar ke atas dan ke samping tidak terpotong). Jendela yang besar hanya ada selama kursor di atas dock.
        let peak = DockMagnify.peak(percent: prefs.dockMagnify)
        let grown = model.hovering && peak > 1.0001
        let side = grown ? DockMagnify.extraWidth(cell: DockMetrics.cell(cfg.iconSize), peak: peak) / 2 + Self.slack : Self.slack
        let head = grown ? DockMagnify.headroom(icon: cfg.iconSize, peak: peak) : 0
        let frame = CGRect(x: o.x - side, y: o.y, width: size.width + side * 2, height: size.height + head)
        shrinkWork?.cancel()
        if frame.width < panel.frame.width - 0.5 {
            // Mengecil: tunggu animasi selesai dulu, kalau tidak isi dock terpotong di tengah gerakan.
            let work = DispatchWorkItem { [weak panel] in panel?.setFrame(frame, display: true) }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private static let slack: CGFloat = 14
    private var shrinkWork: DispatchWorkItem?
}

// MARK: - Tampilan

struct DockView: View {
    @ObservedObject var model: DockModel
    @ObservedObject var prefs: Preferences
    /// Bukan @ObservedObject: NotchModel menerbitkan perubahan tiap detik (timer, media, dan lainnya) dan itu menggambar ulang seluruh dock.
    /// Tiap widget mengamati data yang dipakainya sendiri.
    let app: NotchModel
    /// Posisi kursor di baris dock (untuk efek tetangga) dan ikon yang sedang diseret.
    @State private var pointerX: CGFloat?
    @State private var dragging: (id: String, dx: CGFloat)?
    @State private var didDrag = false

    var body: some View {
        let cfg = model.fitted
        let r = dockRadii(round: prefs.dockRound, icon: cfg.iconSize)
        let cell = DockMetrics.cell(cfg.iconSize)
        let slots = DockLayout.appSlots(screenW: model.screenWidth, cfg)
        let all = model.entries
        let (shown, rest) = DockLayout.splitByUse(all, slots: slots) { $0.running }
        let shape = shown.map(\.id) + cfg.modules.map(\.rawValue) + (rest.isEmpty ? [] : ["+\(rest.count)"]) + (cfg.showClock ? ["clock"] : [])
        let pop = AnyTransition.scale(scale: 0.4).combined(with: .opacity)
        let peak = DockMagnify.peak(percent: prefs.dockMagnify)
        let barH = cell + DockMetrics.pad * 2
        // Pusat tiap ikon (Start, lalu aplikasi) saat diam, dari tepi kiri baris (rowCenters) dan dari tepi kiri dock (barCenters).
        let rowCenters = [cell / 2] + shown.indices.map { cell + DockMetrics.gap + CGFloat($0) * (cell + DockMetrics.cellGap) + cell / 2 }
        let barCenters = rowCenters.map { $0 + DockMetrics.pad }
        let restWidth = DockLayout.width(apps: shown.count + (rest.isEmpty ? 0 : 1), cfg)
        let scales = DockMagnify.scales(restCenters: barCenters, pointer: dragging == nil ? pointerX : nil, cell: cell, peak: peak)
        let nearest = pointerX == nil || dragging != nil ? -1 : (scales.indices.max { scales[$0] < scales[$1] } ?? -1)
        GeometryReader { geo in
            // Garis pemisah digambar di dalam jarak antar kelompok (gap), jadi lebar dock tidak berubah.
            HStack(spacing: 0) {
                startButton(cfg: cfg, cell: cell, r: r, scale: scales[0], label: nearest == 0)
                if !(shown.isEmpty && rest.isEmpty) {
                    separator(cell)
                    HStack(spacing: DockMetrics.cellGap) {
                        ForEach(Array(shown.enumerated()), id: \.element.id) { i, e in
                            appCell(e, index: i, cfg: cfg, cell: cell, r: r, scale: scales[i + 1], label: nearest == i + 1, centers: rowCenters, shown: shown).transition(pop)
                        }
                        if !rest.isEmpty { overflow(rest, cell: cell, r: r) }
                    }
                }
                ForEach(cfg.modules) { m in
                    separator(cell).transition(pop)
                    DockModuleView(module: m, app: app, cfg: cfg, cell: cell, r: r).transition(pop)
                        .contextMenu {
                            Button(L("Hapus dari dock", "Remove from the dock")) { prefs.dockModules.removeAll { $0 == m } }
                            Divider()
                            dockMenu
                        }
                }
                if cfg.showClock {
                    separator(cell)
                    ClockModule(cell: cell, r: r)
                }
            }
            .coordinateSpace(name: "dockRow")
            // Modul atau aplikasi baru muncul dengan membal, dan dock melebar dengan pegas ke kiri dan kanan.
            .animation(.spring(response: 0.42, dampingFraction: 0.55), value: shape)
            .animation(.interactiveSpring(response: 0.16, dampingFraction: 0.82), value: pointerX)
            .padding(DockMetrics.pad)
            // Latar dan tepinya digambar di belakang dan dipotong sendiri; ikonnya tidak dipotong, jadi bisa tumbuh ke atas melewati dock.
            .background {
                let outline = RoundedRectangle(cornerRadius: r.outer, style: .continuous)
                surface(r.outer).clipShape(outline)
                    .overlay(outline.strokeBorder(Color.primary.opacity(0.16), lineWidth: 1))
            }
            .contextMenu { dockMenu }
            .environment(\.colorScheme, darkInk ? .light : .dark)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    if !model.hovering { model.hovering = true }
                    // Koordinat kursor pada baris saat diam: dock berpusat di jendela dan lebarnya `restWidth` sebelum membesar.
                    let x = p.x - geo.size.width / 2 + restWidth / 2
                    let fromBottom = geo.size.height - p.y
                    let inReach = fromBottom <= barH + cfg.iconSize * (peak - 1) * 0.9 + 8 && x > -cell * 0.4 && x < restWidth + cell * 0.4
                    let next: CGFloat? = inReach ? x : nil
                    if next != pointerX { pointerX = next }
                case .ended:
                    pointerX = nil
                    model.hovering = false
                }
            }
        }
    }

    /// Latar: ikut notch (tema, warna, gradien, atau gambar; hitam bila tidak ada), atau latar dock sendiri.
    @ViewBuilder private func surface(_ radius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        switch prefs.dockBg {
        case .glass:
            GlassSurface(shape: AnyShape(shape), tint: prefs.glassTintValue, color: prefs.glassColor, distortion: prefs.glassDistortionValue)
        case .color:
            Color(hex: prefs.dockBgColorHex) ?? .black
        case .gradient:
            LinearGradient(colors: [Color(hex: prefs.dockBgColorHex) ?? .black, Color(hex: prefs.dockBgColor2Hex) ?? .black], startPoint: .leading, endPoint: .trailing)
        case .follow:
            if prefs.activeTheme == .glass {
                GlassSurface(shape: AnyShape(shape), tint: prefs.glassTintValue, color: prefs.glassColor, distortion: prefs.glassDistortionValue)
            } else if prefs.customBackgroundActive { CustomBackground(prefs: prefs) } else { Color.black.opacity(0.88) }
        }
    }

    /// Teks gelap hanya bila latarnya terang. Kaca dan gambar dianggap gelap (ada pelindung gelap di bawahnya).
    private var darkInk: Bool {
        func luma(_ hex: String) -> Double { DockInk.luminance(hex: hex) ?? 0 }
        switch prefs.dockBg {
        case .color: return DockInk.isDark(onLuminance: luma(prefs.dockBgColorHex))
        case .gradient: return DockInk.isDark(onLuminance: DockInk.gradientLuminance(luma(prefs.dockBgColorHex), luma(prefs.dockBgColor2Hex)))
        case .glass: return false
        case .follow:
            guard prefs.activeTheme != .glass, prefs.customBackgroundActive else { return false }
            switch prefs.bgMode {
            case .color: return DockInk.isDark(onLuminance: luma(prefs.bgColorHex))
            case .gradient: return DockInk.isDark(onLuminance: DockInk.gradientLuminance(luma(prefs.bgColorHex), luma(prefs.bgColor2Hex)))
            default: return false
            }
        }
    }

    /// Garis vertikal tipis di tengah jarak antar kelompok.
    private func separator(_ cell: CGFloat) -> some View {
        Rectangle().fill(Color.primary.opacity(0.18)).frame(width: 1, height: (cell * 0.5).rounded())
            .frame(width: DockMetrics.gap, height: cell)
    }

    /// Daftar jendela aplikasi yang berjalan (butuh izin Aksesibilitas); tanpa izin: jumlah yang terlihat dan tombol meminta izin.
    @ViewBuilder private func windowSection(_ e: DockEntry) -> some View {
        if DockWindows.trusted {
            let ws = model.windows(e.id)
            ForEach(ws) { w in Button(w.title) { model.raise(w, e.id) } }
            if ws.count > 1 { Button(L("Tutup semua jendela", "Close all windows")) { ws.forEach(DockWindows.close) } }
            if ws.isEmpty { Text(L("Tidak ada jendela terbuka", "No open windows")) }
        } else {
            let n = model.visibleWindowCount(e.id)
            Text(n == 1 ? L("1 jendela terbuka", "1 open window") : L("\(n) jendela terbuka", "\(n) open windows"))
            Button(L("Tampilkan daftar jendela…", "Show the window list…")) { DockWindows.requestTrust(); DockWindows.openAccessibilitySettings() }
        }
        Divider()
    }

    /// Menu klik kanan untuk dock itu sendiri (di latar, atau di bawah menu ikon dan widget).
    @ViewBuilder private var dockMenu: some View {
        Button(L("Pengaturan dock…", "Dock settings…")) { app.onOpenSettings?() }
        Button(L("Matikan dock", "Turn the dock off")) { prefs.dockEnabled = false }
    }

    private func mag(_ i: Int, _ centers: [CGFloat], _ reach: CGFloat) -> CGFloat {
        pointerX.map { DockMagnify.scale(distance: $0 - centers[i], reach: reach) } ?? 1
    }

    private func startButton(cfg: DockConfig, cell: CGFloat, r: DockRadii, scale: CGFloat, label: Bool) -> some View {
        HoverCell(cell: cell, radius: r.cell, help: L("Semua aplikasi", "All apps"), iconSize: cfg.iconSize, showLabel: label, scale: scale, action: { model.openStart() }) {
            if let url = DockModel.launcher {
                // Ikon yang sama dengan Dock macOS, supaya jelas ini peluncur aplikasi dan bukan Finder.
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
                    .frame(width: cfg.iconSize, height: cfg.iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: r.tile, style: .continuous))
            } else {
                Image(systemName: "square.grid.2x2.fill").font(.system(size: cell * 0.4, weight: .semibold)).foregroundStyle(Color.primary)
            }
        }
        .contextMenu {
            Button(L("Buka semua aplikasi", "Open all apps")) { model.openStart() }
            Divider()
            dockMenu
        }
    }

    private func appCell(_ e: DockEntry, index: Int, cfg: DockConfig, cell: CGFloat, r: DockRadii, scale: CGFloat, label: Bool, centers: [CGFloat], shown: [DockEntry]) -> some View {
        let isDragged = dragging?.id == e.id
        return HoverCell(cell: cell, radius: r.cell, help: e.name, dot: e.running, iconSize: cfg.iconSize, showLabel: label && !isDragged, scale: isDragged ? max(scale, DockMagnify.maxScale) : scale, action: {
            if didDrag { didDrag = false } else { model.open(e.id) }
        }) {
            Image(nsImage: model.icon(e.id)).resizable().interpolation(.high)
                .frame(width: cfg.iconSize, height: cfg.iconSize)
                .clipShape(RoundedRectangle(cornerRadius: r.tile, style: .continuous))
        }
        .offset(x: isDragged ? dragging?.dx ?? 0 : 0)
        .zIndex(isDragged ? 2 : 0)
        // Seret untuk mengurutkan: hanya aplikasi yang disematkan; dilepas di dekat ikon lain memindahkannya ke sana.
        .simultaneousGesture(DragGesture(minimumDistance: 8, coordinateSpace: .named("dockRow"))
            .onChanged { g in
                guard e.pinned else { return }
                didDrag = true
                dragging = (e.id, g.translation.width)
            }
            .onEnded { g in
                defer { dragging = nil }
                guard e.pinned else { didDrag = false; return }
                let pinnedCells = shown.indices.filter { shown[$0].pinned }
                let x = centers[index + 1] + g.translation.width
                let slot = DockLayout.dropIndex(x: x, centers: pinnedCells.map { centers[$0 + 1] })
                if slot >= 0, let target = pinnedCells[slot] as Int?, let to = prefs.dockPins.firstIndex(where: { $0.id == shown[target].id }) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { prefs.dockPins = DockApps.move(prefs.dockPins, id: e.id, to: to) }
                }
                // Klik yang menyertai akhir seretan diabaikan sekali.
                DispatchQueue.main.async { didDrag = false }
            })
        .contextMenu {
            if e.running { windowSection(e) }
            Button(e.pinned ? L("Lepas sematan", "Unpin") : L("Sematkan", "Pin")) { model.togglePin(e) }
            if e.pinned {
                Button(L("Geser ke kiri", "Move left")) { model.movePin(e, by: -1) }
                Button(L("Geser ke kanan", "Move right")) { model.movePin(e, by: 1) }
            }
            Divider()
            Button(L("Tampilkan di Finder", "Show in Finder")) { model.reveal(e.id) }
            if e.running {
                Button(L("Sembunyikan", "Hide")) { model.hide(e.id) }
                Button(L("Keluar", "Quit")) { model.quit(e.id) }
            }
            Divider()
            dockMenu
        }
    }

    private func overflow(_ rest: [DockEntry], cell: CGFloat, r: DockRadii) -> some View {
        Menu {
            ForEach(rest) { e in
                Button { model.open(e.id) } label: {
                    Label { Text(e.running ? e.name + "  •" : e.name) } icon: { Image(nsImage: model.menuIcon(e.id)) }
                }
            }
        } label: {
            Text("+\(rest.count)").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary)
                .frame(width: cell, height: cell)
                .background(RoundedRectangle(cornerRadius: r.cell, style: .continuous).fill(Color.primary.opacity(0.1)))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .frame(width: cell, height: cell)
        .help(L("Aplikasi lainnya", "More apps"))
    }
}

/// Sel ikon. Dengan `scale` (efek pembesaran dock): lebarnya ikut membesar sehingga tetangga bergeser, ikonnya tumbuh ke atas dari tepi
/// bawahnya, dan namanya muncul di atas ikon bila `showLabel`. Tanpa `scale`: hanya ikonnya yang membesar saat disentuh kursor.
struct HoverCell<Content: View>: View {
    let cell: CGFloat
    let radius: CGFloat
    let help: String
    var dot = false
    var iconSize: CGFloat = 0
    var showLabel = false
    var scale: CGFloat? = nil
    let action: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var hover = false

    var body: some View {
        let grows = scale != nil
        let s = scale ?? (hover ? DockMagnify.maxScale : 1)
        Button(action: action) {
            ZStack {
                content().scaleEffect(s, anchor: .bottom)
                if dot {
                    Circle().fill(Color.primary.opacity(0.9)).frame(width: 4, height: 4)
                        .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 2)
                }
            }
            .frame(width: grows ? cell * s : cell, height: cell)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if showLabel && !help.isEmpty {
                // Nama di atas ikon yang membesar, seperti Dock macOS: dasar label 6 pt di atas puncak ikon.
                let top = cell / 2 + iconSize / 2 - iconSize * s
                Text(help).font(.system(size: 12, weight: .medium)).lineLimit(1).fixedSize()
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(Color(white: 0.16, opacity: 0.96)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5))
                    .offset(y: top - 32)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .zIndex(hover || s > 1.05 ? 1 : 0)
        .onHover { h in withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) { hover = h } }
        // Tanpa efek pembesaran, nama muncul sebagai tooltip.
        .help(grows && showLabel ? "" : help)
    }
}

struct ClockModule: View {
    let cell: CGFloat
    let r: DockRadii

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            VStack(spacing: 1) {
                Text(ctx.date, format: .dateTime.hour().minute()).font(.system(size: 17, weight: .semibold).monospacedDigit())
                Text(ctx.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated)).font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.7))
            }
            .foregroundStyle(Color.primary)
            .frame(width: DockMetrics.clockWidth, height: cell)
        }
    }
}
