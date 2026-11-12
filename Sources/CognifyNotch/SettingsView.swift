import AppKit
import ServiceManagement
import SwiftUI

// Jendela Pengaturan app mandiri, bergaya Pengaturan Sistem macOS: sidebar kategori di kiri, di kanan header
// besar lalu kartu pengaturan. Pilihan fitur dan "Buka saat Mac dinyalakan" ada di sini, bukan di menu bar.

enum SettingsPane: String, CaseIterable, Identifiable {
    // Urutan = urutan di sidebar.
    case general, appearance, behavior, companion, features, skins, weather, tabs, data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return L("Umum", "General")
        case .appearance: return L("Tampilan", "Appearance")
        case .behavior: return L("Perilaku", "Behavior")
        case .companion: return L("Teman kecil", "Companion")
        case .features: return L("Fitur", "Features")
        case .skins: return L("Skin", "Skins")
        case .weather: return L("Cuaca", "Weather")
        case .tabs: return L("Urutan tab", "Tab order")
        case .data: return L("Data", "Data")
        }
    }

    var subtitle: String {
        switch self {
        case .general: return L("Bahasa, buka otomatis saat login, dan pembaruan.", "Language, launch at login, and updates.")
        case .appearance: return L("Tema, bentuk, ukuran, dan warna.", "Theme, shape, size, and colors.")
        case .behavior: return L("Cara notch terbuka, tertutup, dan bersembunyi, serta layar dan pintasan.", "How the notch opens, closes, and hides, plus the screen and shortcut.")
        case .companion: return L("Wajah di notch: pilihan ekspresi, kedipan, dan reaksi untuk tiap kejadian.", "The face in the notch: expressions, blinking, and how it reacts to each event.")
        case .features: return L("Pilih fitur notch yang ingin dipakai.", "Choose which notch features to use.")
        case .skins: return L("Widget di desktop ala Rainmeter: wajah Mimik, lirik, dan lainnya.", "Rainmeter-style desktop widgets: the Mimik face, lyrics, and more.")
        case .weather: return L("Cuaca di header dan halaman Langit.", "Weather in the header and on the Sky page.")
        case .tabs: return L("Atur urutan halaman di notch.", "Arrange the pages in the notch.")
        case .data: return L("Cadangkan atau pulihkan catatan, tugas, dan pengaturan.", "Back up or restore notes, tasks, and settings.")
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintpalette.fill"
        case .behavior: return "hand.point.up.left.fill"
        case .companion: return "face.smiling.fill"
        case .features: return "switch.2"
        case .skins: return "macwindow.on.rectangle"
        case .weather: return "cloud.sun.fill"
        case .tabs: return "list.number"
        case .data: return "archivebox.fill"
        }
    }

    /// Warna atas dan bawah gradasi ikon.
    var colors: (Color, Color) {
        switch self {
        case .general: return (Color(white: 0.68), Color(white: 0.42))
        case .appearance: return (Color(red: 0.55, green: 0.52, blue: 1.0), Color(red: 0.32, green: 0.28, blue: 0.82))
        case .behavior: return (Color(red: 1.0, green: 0.7, blue: 0.3), Color(red: 0.95, green: 0.5, blue: 0.1))
        case .companion: return (Color(red: 1.0, green: 0.62, blue: 0.7), Color(red: 0.96, green: 0.3, blue: 0.48))
        case .features: return (Color(red: 0.38, green: 0.66, blue: 1.0), Color(red: 0.1, green: 0.4, blue: 0.95))
        case .skins: return (Color(red: 0.98, green: 0.55, blue: 0.85), Color(red: 0.72, green: 0.25, blue: 0.78))
        case .weather: return (Color(red: 0.45, green: 0.8, blue: 1.0), Color(red: 0.15, green: 0.55, blue: 0.92))
        case .tabs: return (Color(red: 0.42, green: 0.88, blue: 0.5), Color(red: 0.14, green: 0.68, blue: 0.34))
        case .data: return (Color(red: 0.35, green: 0.85, blue: 0.88), Color(red: 0.08, green: 0.58, blue: 0.66))
        }
    }
}

/// Ikon kategori: persegi bulat dengan gradasi dua tone, pinggiran cahaya halus, dan bayangan lembut, seperti di
/// Pengaturan Sistem. Teman kecil dan Notch memakai gambar sendiri (wajah dan notch bermata).
struct PaneIcon: View {
    let pane: SettingsPane
    var size: CGFloat = 26

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [pane.colors.0, pane.colors.1], startPoint: .top, endPoint: .bottom))
            // Kilau lembut di bagian atas.
            shape.fill(LinearGradient(colors: [.white.opacity(0.22), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.55)))
            glyph
        }
        .frame(width: size, height: size)
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.55), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: max(0.6, size * 0.018)))
        .shadow(color: pane.colors.1.opacity(0.35), radius: size * 0.07, y: size * 0.04)
    }

    @ViewBuilder private var glyph: some View {
        switch pane {
        case .companion: face
        case .appearance: notch
        default:
            Image(systemName: pane.symbol)
                .font(.system(size: size * 0.5, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: size * 0.03, y: size * 0.02)
        }
    }

    /// Wajah putih dengan dua mata dan senyum.
    private var face: some View {
        ZStack {
            Circle().fill(Color.white).frame(width: size * 0.64, height: size * 0.64)
                .shadow(color: .black.opacity(0.15), radius: size * 0.03, y: size * 0.02)
            HStack(spacing: size * 0.12) {
                ForEach(0..<2, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: size * 0.04, style: .continuous).fill(pane.colors.1).frame(width: size * 0.075, height: size * 0.13)
                }
            }
            .offset(y: -size * 0.05)
            Smile()
                .stroke(pane.colors.1, style: StrokeStyle(lineWidth: max(1, size * 0.045), lineCap: .round))
                .frame(width: size * 0.2, height: size * 0.06)
                .offset(y: size * 0.1)
        }
    }

    /// Layar dengan notch hitam bermata di tengah atas.
    private var notch: some View {
        let screen = RoundedRectangle(cornerRadius: size * 0.1, style: .continuous)
        return ZStack(alignment: .top) {
            screen.fill(Color.white.opacity(0.95))
            RoundedRectangle(cornerRadius: size * 0.07, style: .continuous).fill(Color.black)
                .frame(width: size * 0.32, height: size * 0.2)
                .offset(y: -size * 0.07)
                .overlay(alignment: .top) {
                    HStack(spacing: size * 0.08) {
                        Circle().fill(Color.white).frame(width: size * 0.05, height: size * 0.05)
                        Circle().fill(Color.white).frame(width: size * 0.05, height: size * 0.05)
                    }
                    .offset(y: size * 0.045)
                }
        }
        .frame(width: size * 0.68, height: size * 0.5)
        .clipShape(screen)
        .shadow(color: .black.opacity(0.15), radius: size * 0.03, y: size * 0.02)
        .offset(y: size * 0.02)
    }
}

/// Senyum kecil untuk ikon Teman kecil.
struct Smile: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.midX, y: r.maxY + r.height))
        return p
    }
}

/// Latar sidebar yang tembus pandang (material bawaan macOS).
struct SidebarBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct SettingsView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var prefs: Preferences
    var updater: Updater?
    @State private var pane: SettingsPane? = .general
    @State private var query = ""
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @State private var autoUpdate = false
    /// Wajah contoh di bagian Teman kecil: menunjukkan pilihan yang sedang diubah.
    @StateObject private var preview = Face()
    @StateObject private var locator = LocationFinder()

    private var panes: [SettingsPane] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SettingsPane.allCases }
        return SettingsPane.allCases.filter { $0.title.lowercased().contains(q) || $0.subtitle.lowercased().contains(q) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 230)
                .background(SidebarBackground().ignoresSafeArea())
            Divider()
            detail
        }
        .frame(minWidth: 520, idealWidth: 780, minHeight: 360, idealHeight: 580)
        .ignoresSafeArea()
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(L("Cari", "Search"), text: $query).textFieldStyle(.plain)
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.7)))
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.1)))
            .padding(.horizontal, 14)
            .padding(.top, 52) // di bawah tombol jendela
            .padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(panes) { p in
                        let selected = p == current
                        Button { pane = p } label: {
                            HStack(spacing: 10) {
                                PaneIcon(pane: p)
                                Text(p.title).font(.system(size: 13, weight: selected ? .semibold : .regular))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8)
                            .frame(height: 36)
                            .foregroundStyle(selected ? Color.white : Color.primary)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(selected ? Color(nsColor: .controlAccentColor) : Color.clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if panes.isEmpty {
                        Text(L("Tidak ada hasil", "No results")).font(.callout).foregroundStyle(.secondary).padding(.top, 20)
                    }
                }
                .padding(.horizontal, 10)
            }
        }
    }

    // MARK: Detail

    private var current: SettingsPane { pane ?? panes.first ?? .general }

    private var detail: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    PaneIcon(pane: current, size: 64)
                    Text(current.title).font(.system(size: 24, weight: .bold))
                    Text(current.subtitle).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            content(for: current)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(current)
    }

    @ViewBuilder private func content(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: generalPane
        case .appearance: appearancePane
        case .behavior: behaviorPane
        case .companion: companionPane
        case .features: featuresPane
        case .skins: if let skins = model.skinManager { SkinsPane(skins: skins) }
        case .weather: weatherPane
        case .tabs: tabsPane
        case .data: dataPane
        }
    }

    // MARK: Teman kecil

    /// Pilihan satu keadaan/kejadian di mode "Per kejadian": "auto" (bawaan), "none" (tidak bereaksi), atau nama ekspresi.
    private func choice(_ s: Situation) -> Binding<String> {
        Binding(
            get: { prefs.companionMap[s.rawValue] ?? "auto" },
            set: { value in
                if value == "auto" { prefs.companionMap.removeValue(forKey: s.rawValue) } else { prefs.companionMap[s.rawValue] = value }
                let shown = value == "auto" ? s.emotion : Emotion(rawValue: value)
                if let shown { preview.play([(shown, 2.4, shown.motion)]) }
            })
    }

    private func situationRow(_ s: Situation) -> some View {
        Picker(s.label, selection: choice(s)) {
            Text(L("Bawaan", "Default") + " (" + s.emotion.label + ")").tag("auto")
            if s.isEvent { Text(L("Tidak bereaksi", "No reaction")).tag("none") }
            Divider()
            ForEach(Emotion.allCases) { Text($0.label).tag($0.rawValue) }
        }
    }

    @ViewBuilder private var companionPane: some View {
        Section {
            if let toggle = FeatureToggle.all.first(where: { $0.key == \.companion }) { featureRow(toggle) }
        }
        Section {
            if !model.features.companion {
                Text(L("Nyalakan Teman kecil dulu untuk mengatur yang di bawah.", "Turn on Little companion first to change the settings below."))
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Picker(L("Mode", "Mode"), selection: $prefs.companionMode) {
                        ForEach(CompanionMode.allCases) { Text($0.label).tag($0) }
                    }
                    Text(prefs.companionMode.hint).font(.caption).foregroundStyle(.secondary)
                }
                Circle().fill(Color.black).frame(width: 46, height: 46)
                    .overlay(FaceHead(face: preview, diameter: 46))
            }
            if prefs.companionMode == .fixed {
                Picker(L("Ekspresi", "Expression"), selection: $prefs.companionFixed) {
                    ForEach(Emotion.allCases) { Text($0.label).tag($0) }
                }
                .onChange(of: prefs.companionFixed) { preview.set($0) }
            }
            Toggle(L("Berkedip berkala", "Blink now and then"), isOn: $prefs.companionBlink)
        }
        .disabled(!model.features.companion)
        .onAppear { if prefs.companionMode == .fixed { preview.set(prefs.companionFixed) } }
        if prefs.companionMode == .custom {
            Section(L("Keadaan", "Situations")) {
                ForEach(Situation.states) { situationRow($0) }
            }
            Section(L("Kejadian", "Events")) {
                ForEach(Situation.events) { situationRow($0) }
            }
            Section {
                Button(L("Kembalikan ke bawaan", "Reset to default")) { prefs.companionMap = [:] }
                    .disabled(prefs.companionMap.isEmpty)
            }
        }
    }

    // MARK: Umum

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            model.show(.failed(L("Gagal mengubah pengaturan buka saat login: ", "Couldn't change the launch-at-login setting: ") + error.localizedDescription))
        }
        loginOn = SMAppService.mainApp.status == .enabled
    }

    @ViewBuilder private var generalPane: some View {
        Section {
            Picker(L("Bahasa tampilan", "Display language"), selection: $prefs.language) {
                ForEach(Preferences.Language.allCases) { Text($0.label).tag($0) }
            }
        }
        Section {
            Toggle(L("Buka saat login", "Launch at login"), isOn: Binding(get: { loginOn }, set: setLogin))
            if let updater {
                Toggle(L("Pasang pembaruan otomatis", "Install updates automatically"), isOn: Binding(
                    get: { autoUpdate },
                    set: { autoUpdate = $0; updater.automatic = $0 }))
                    .onAppear { autoUpdate = updater.automatic }
                HStack {
                    Text(L("Versi app", "App version"))
                    Spacer()
                    Button(L("Cek pembaruan…", "Check for updates…")) { updater.checkForUpdates() }
                }
            }
        }
    }

    // MARK: Fitur

    private func featureRow(_ toggle: FeatureToggle) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { model.features[keyPath: toggle.key] },
                                 set: { FeatureToggle.set(toggle, $0, model: model) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(toggle.title())
                    Text(toggle.hint()).font(.caption).foregroundStyle(.secondary)
                    if let why = blockReason(toggle) { Text(why).font(.caption).foregroundStyle(.orange) }
                }
            }
            if toggle.defaultsKey == "feature.clipboard" && model.features.clipboard { clipboardLimitControls }
            if toggle.defaultsKey == "feature.appNotifications" && model.features.appNotifications { appNotificationControls }
        }
        .disabled(blockReason(toggle) != nil)
    }

    /// Fitur yang bergantung pada fitur lain: alasan kenapa barisnya mati, supaya tidak ada saklar yang diam-diam tidak bisa dipakai.
    private func blockReason(_ toggle: FeatureToggle) -> String? {
        let needsMedia = toggle.key == \.spectrum || toggle.key == \.lyrics || toggle.key == \.lyricsWing
        if needsMedia && !model.features.media { return L("Nyalakan \"Lagu & video yang diputar\" dulu.", "Turn on \"Now playing\" first.") }
        if toggle.key == \.lyricsWing && !model.features.lyrics { return L("Nyalakan \"Lirik lagu\" dulu.", "Turn on \"Synced lyrics\" first.") }
        return nil
    }

    private var appNotificationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.appNotes.access == .denied {
                Text(L("Belum ada izin. Beri Akses Disk Penuh ke Cognify Notch di Pengaturan Sistem, lalu nyalakan ulang fitur ini.",
                       "No access yet. Give Cognify Notch Full Disk Access in System Settings, then turn this feature off and on."))
                    .font(.caption).foregroundStyle(.orange)
                HStack {
                    Button(L("Buka Pengaturan Sistem", "Open System Settings")) { AppNotificationWatcher.openPrivacySettings() }
                    Button(L("Cek lagi", "Check again")) { model.appNotes.refreshAccess() }
                }
            }
            Text(L("Teruskan notifikasi dari:", "Forward notifications from:")).font(.caption).foregroundStyle(.secondary)
            ForEach(AppNotificationWatcher.known, id: \.bundle) { app in
                Toggle(app.name, isOn: Binding(
                    get: { prefs.notifyApps.contains(app.bundle) },
                    set: { on in
                        if on { if !prefs.notifyApps.contains(app.bundle) { prefs.notifyApps.append(app.bundle) } }
                        else { prefs.notifyApps.removeAll { $0 == app.bundle } }
                    }))
            }
        }
    }

    private var clipboardLimitControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker(L("Batas riwayat", "History limit"), selection: Binding(
                get: { prefs.clipboardUnlimited },
                set: { value in
                    prefs.clipboardUnlimited = value
                    model.clipboard.applyLimit(unlimited: value, count: prefs.clipboardLimit)
                })) {
                    Text(L("Tanpa batas", "Unlimited")).tag(true)
                    Text(L("Atur sendiri", "Custom")).tag(false)
                }
                .pickerStyle(.segmented)
            if !prefs.clipboardUnlimited {
                HStack {
                    Text(L("Jumlah item", "Item count"))
                    Spacer()
                    TextField("40", value: Binding(
                        get: { prefs.clipboardLimit },
                        set: { value in
                            let safe = max(1, min(100_000, value))
                            prefs.clipboardLimit = safe
                            model.clipboard.applyLimit(unlimited: prefs.clipboardUnlimited, count: safe)
                        }), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 88)
                }
            }
            Text(L("Item yang disematkan tidak dihitung. Gambar hanya disimpan selama app berjalan.", "Pinned items aren't counted. Images are kept only while the app is running."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.leading, 22)
    }

    /// Fitur dikelompokkan supaya mudah dicari. Teman kecil dan Cuaca punya halamannya sendiri.
    private var featureGroups: [(title: String, keys: [KeyPath<NotchModel.Features, Bool>])] {
        [
            (L("Musik", "Music"), [\.media, \.spectrum, \.lyrics, \.lyricsWing]),
            (L("Produktivitas", "Productivity"), [\.calendar, \.todo, \.remindersSync, \.water, \.clockTools, \.clipboard, \.voice, \.calculator, \.shortcuts, \.camera]),
            (L("Sistem dan perangkat", "System and devices"), [\.hud, \.power, \.devices, \.downloads, \.keyboard, \.network, \.appNotifications, \.hideFullscreen, \.hotkey]),
        ]
    }

    @ViewBuilder private var featuresPane: some View {
        let grouped = featureGroups.flatMap(\.keys) + [\.companion, \.weather]
        ForEach(featureGroups, id: \.title) { group in
            Section(group.title) {
                ForEach(FeatureToggle.all.filter { group.keys.contains($0.key) }) { featureRow($0) }
            }
        }
        // Yang belum masuk kelompok mana pun tetap tampil.
        let rest = FeatureToggle.all.filter { !grouped.contains($0.key) }
        if !rest.isEmpty {
            Section(L("Lainnya", "Other")) { ForEach(rest) { featureRow($0) } }
        }
    }

    // MARK: Notch

    private static let accentColors = ["#8f87ff", "#0a84ff", "#30d158", "#ff375f", "#ff9f0a", "#ffd60a", "#bf5af2", "#ffffff"]
    private static let lyricColors = ["#ffffff", "#ffd60a", "#30d158", "#0a84ff", "#ff375f", "#ff9f0a", "#bf5af2", "#8e8e93"]
    private static let equalizerColors = ["#ffffff", "#30d158", "#0a84ff", "#bf5af2", "#ff375f", "#ff9f0a", "#ffd60a"]

    @ViewBuilder private var appearancePane: some View {
        if NotchTheme.glassSupported {
        Section(L("Tema", "Theme")) {
            Picker(L("Tema panel", "Panel theme"), selection: $prefs.theme) {
                ForEach(NotchTheme.allCases) { Text($0.label).tag($0) }
            }
            Text(L("macOS 26 ke atas memakai Liquid Glass. Mac yang lebih lama memakai material transparan dengan pembiasan ringan; efek distorsi tersedia mulai macOS 14.", "macOS 26 and later use Liquid Glass. Older Macs use a translucent material with light refraction; the distortion effect needs macOS 14 or later."))
                .font(.footnote).foregroundStyle(.secondary)
            if prefs.theme == .glass {
                Picker(L("Liquid Glass", "Liquid Glass"), selection: $prefs.glassCustom) {
                    Text(L("Bawaan", "Default")).tag(false)
                    Text(L("Atur sendiri", "Custom")).tag(true)
                }
                .pickerStyle(.segmented)
                if prefs.glassCustom {
                    LabeledContent(L("Bening ke berwarna", "Clear to tinted")) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.on.square").foregroundStyle(.secondary)
                            Slider(value: $prefs.glassTint, in: 0...1) { EmptyView() }
                            Image(systemName: "square.on.square.fill").foregroundStyle(.secondary)
                        }
                    }
                    LabeledContent(L("Warna kaca", "Glass tint")) {
                        HStack(spacing: 8) {
                            ColorPicker("", selection: Binding(get: { Color(hex: prefs.glassTintHex) ?? .black },
                                                               set: { prefs.glassTintHex = $0.hex }), supportsOpacity: false)
                                .labelsHidden()
                            Button(L("Hitam", "Black")) { prefs.glassTintHex = "" }.disabled(prefs.glassTintHex.isEmpty)
                        }
                    }
                    LabeledContent(L("Distorsi dan kilau", "Distortion & sheen")) {
                        HStack(spacing: 8) {
                            Image(systemName: "circle").foregroundStyle(.secondary)
                            Slider(value: $prefs.glassDistortion, in: 0...1) { EmptyView() }
                            Image(systemName: "drop.fill").foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        }
        Section(L("Bentuk, ukuran, dan warna aksen", "Shape, size, and accent color")) {
            Toggle(L("Melayang juga di Mac berponi", "Float on Macs with a notch too"), isOn: $prefs.floatOnNotch)
            if !model.hasNotch { FloatPositionMap(model: model, prefs: prefs) }
            Picker(L("Gaya melayang", "Floating style"), selection: $prefs.floatingStyle) {
                ForEach(Preferences.FloatingStyle.allCases) { Text($0.label).tag($0) }
            }
            LabeledContent(L("Ukuran panel terbuka", "Open panel size")) {
                Slider(value: $prefs.scale, in: 0.7...1.5, step: 0.05) { EmptyView() }
                Text("\(Int((prefs.scale * 100).rounded()))%").monospacedDigit().frame(width: 60, alignment: .trailing)
            }
            LabeledContent(L("Ukuran notch saat diam", "Idle notch size")) {
                Slider(value: $prefs.idleScale, in: 0.6...1.5, step: 0.05) { EmptyView() }
                Text("\(Int(prefs.idleScale * 100))%").monospacedDigit().frame(width: 60, alignment: .trailing)
            }
            if model.hasNotch {
                Text(L("Di Mac berponi, bagian hitam tidak bisa lebih kecil dari poni aslinya; hanya mata di kedua sisi yang mengecil. Pakai Sembunyikan otomatis untuk menghilangkannya sepenuhnya.", "On a Mac with a notch, the black shape can't shrink below the physical notch; only the eyes on each side get smaller. Use auto-hide to hide it completely."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent(L("Kebulatan sudut", "Corner roundness")) {
                Slider(value: $prefs.roundness, in: 0...40, step: 1) { EmptyView() }
                Text("\(Int(prefs.roundness)) pt").monospacedDigit().frame(width: 60, alignment: .trailing)
            }
            LabeledContent(L("Warna aksen", "Accent color")) {
                HStack(spacing: 8) {
                    ForEach(Self.accentColors, id: \.self) { hex in
                        let on = (prefs.accentHex.isEmpty ? Self.accentColors[0] : prefs.accentHex.lowercased()) == hex
                        Circle().fill(Color(hex: hex) ?? .white).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.primary.opacity(on ? 0.9 : 0.15), lineWidth: on ? 2 : 1))
                            .contentShape(Circle())
                            .onTapGesture { prefs.accentHex = hex == Self.accentColors[0] ? "" : hex }
                    }
                    ColorPicker("", selection: Binding(get: { Color(hex: prefs.accentHex) ?? AccentStyle.fallback },
                                                       set: { prefs.accentHex = $0.hex }), supportsOpacity: false)
                        .labelsHidden()
                    Button(L("Bawaan", "Default")) { prefs.accentHex = "" }.disabled(prefs.accentHex.isEmpty)
                }
            }
        }
        Section(L("Warna lirik dan equalizer", "Lyric and equalizer colors")) {
            Toggle(L("Ambil warna lirik dari sampul", "Take lyric colors from the cover"), isOn: $prefs.lyricAuto)
                .disabled(!model.features.lyrics)
            if !model.features.lyrics {
                Text(L("Warna lirik tersedia setelah \"Lirik lagu\" dinyalakan di Fitur.", "Lyric colors become available once \"Synced lyrics\" is on in Features."))
                    .font(.caption).foregroundStyle(.orange)
            }
            if !prefs.lyricAuto && model.features.lyrics {
            LabeledContent(L("Baris lirik yang sedang dinyanyikan", "Current lyric line")) {
                HStack(spacing: 8) {
                    ForEach(Self.lyricColors, id: \.self) { hex in
                        Circle().fill(Color(hex: hex) ?? .white).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.primary.opacity(prefs.lyricActiveHex.lowercased() == hex ? 0.9 : 0.15), lineWidth: prefs.lyricActiveHex.lowercased() == hex ? 2 : 1))
                            .contentShape(Circle())
                            .onTapGesture { prefs.lyricActiveHex = hex }
                    }
                    ColorPicker("", selection: Binding(get: { Color(hex: prefs.lyricActiveHex) ?? .white },
                                                       set: { prefs.lyricActiveHex = $0.hex }), supportsOpacity: false)
                        .labelsHidden()
                    Button(L("Bawaan", "Default")) { prefs.lyricActiveHex = "" }.disabled(prefs.lyricActiveHex.isEmpty)
                }
            }
            LabeledContent(L("Baris lirik lainnya", "Other lyric lines")) {
                HStack(spacing: 8) {
                    ForEach(Self.lyricColors, id: \.self) { hex in
                        Circle().fill(Color(hex: hex) ?? .white).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.primary.opacity(prefs.lyricIdleHex.lowercased() == hex ? 0.9 : 0.15), lineWidth: prefs.lyricIdleHex.lowercased() == hex ? 2 : 1))
                            .contentShape(Circle())
                            .onTapGesture { prefs.lyricIdleHex = hex }
                    }
                    ColorPicker("", selection: Binding(get: { Color(hex: prefs.lyricIdleHex) ?? .white },
                                                       set: { prefs.lyricIdleHex = $0.hex }), supportsOpacity: false)
                        .labelsHidden()
                    Button(L("Bawaan", "Default")) { prefs.lyricIdleHex = "" }.disabled(prefs.lyricIdleHex.isEmpty)
                }
            }
            }
            Toggle(L("Ambil warna equalizer dari sampul", "Take equalizer color from the cover"), isOn: $prefs.equalizerAuto)
            if !prefs.equalizerAuto {
            LabeledContent(L("Warna equalizer", "Equalizer color")) {
                HStack(spacing: 8) {
                    ForEach(Self.equalizerColors, id: \.self) { hex in
                        let on = prefs.equalizerHex.lowercased() == hex
                        Circle().fill(Color(hex: hex) ?? .white).frame(width: 18, height: 18)
                            .overlay(Circle().stroke(Color.primary.opacity(on ? 0.9 : 0.15), lineWidth: on ? 2 : 1))
                            .contentShape(Circle())
                            .onTapGesture { prefs.equalizerHex = hex }
                    }
                    ColorPicker("", selection: Binding(get: { Color(hex: prefs.equalizerHex) ?? .accent },
                                                       set: { prefs.equalizerHex = $0.hex }), supportsOpacity: false)
                        .labelsHidden()
                    Button(L("Bawaan", "Default")) { prefs.equalizerHex = "" }.disabled(prefs.equalizerHex.isEmpty)
                }
            }
            }
        }
    }

    @ViewBuilder private var behaviorPane: some View {
        Section(L("Buka dan sembunyi", "Open and hide")) {
            Picker(L("Notch terbuka saat", "Open the notch on"), selection: $prefs.openOnClick) {
                Text(L("Kursor diarahkan", "Hover")).tag(false)
                Text(L("Diklik", "Click")).tag(true)
            }
            Toggle(L("Sembunyikan saat tidak dipakai", "Hide when idle"), isOn: $prefs.autoHide)
                .disabled(model.detached)
                .help(model.detached ? L("Dinonaktifkan karena notch sedang melayang dan tidak menempel di tepi atas layar, jadi tidak bisa bersembunyi di sana. Tempelkan notch ke tepi atas (posisi Y 0%) untuk memakainya.", "Disabled because the notch is floating and not attached to the top edge, so it cannot hide there. Attach the notch to the top edge (Y 0%) to use it.") : "")
            if model.detached {
                Text(L("Tidak tersedia saat notch melayang.", "Not available while the notch is floating."))
                    .font(.caption).foregroundStyle(.secondary)
            } else if prefs.autoHide {
                Text(L("Notch bersembunyi setelah 3 detik tidak dipakai dan muncul lagi saat kursor ke tepi atas layar. Lagu, pengingat, dan notifikasi tetap muncul sendiri.", "The notch hides after 3 idle seconds and returns when you move the cursor to the top edge. Music, reminders, and alerts still appear on their own."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Picker(L("Tampil di layar", "Show on screen"), selection: $prefs.display) {
                ForEach(Preferences.Display.allCases) { Text($0.label).tag($0) }
            }
            Picker(L("Pintasan keyboard", "Keyboard shortcut"), selection: $prefs.hotKey) {
                ForEach(Preferences.HotKeyChoice.allCases) { Text($0.label).tag($0) }
            }
            .disabled(!model.features.hotkey)
            if !model.features.hotkey {
                Text(L("Nyalakan \"Buka dengan pintasan keyboard\" di Fitur dulu.", "Turn on \"Open with a keyboard shortcut\" in Features first."))
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        Section(L("Waktu tunggu", "Timing")) {
            if prefs.openOnClick {
                Text(L("Jeda sebelum membuka tidak dipakai saat notch dibuka dengan klik.", "The opening delay is not used when the notch opens by clicking."))
                    .font(.caption).foregroundStyle(.orange)
            }
            LabeledContent(L("Tunggu sebelum membuka", "Delay before opening")) {
                Slider(value: $prefs.hoverDelay, in: 0...0.6, step: 0.05) { EmptyView() }
                Text("\(Int(prefs.hoverDelay * 1000)) ms").monospacedDigit().frame(width: 60, alignment: .trailing)
            }
            .disabled(prefs.openOnClick)
            LabeledContent(L("Tunggu sebelum menutup", "Delay before closing")) {
                Slider(value: $prefs.closeDelay, in: 0.1...1.5, step: 0.05) { EmptyView() }
                Text("\(Int(prefs.closeDelay * 1000)) ms").monospacedDigit().frame(width: 60, alignment: .trailing)
            }
        }
    }

    @ViewBuilder private var weatherPane: some View {
        Section {
            if let toggle = FeatureToggle.all.first(where: { $0.key == \.weather }) { featureRow(toggle) }
        }
        Section(L("Lokasi", "Location")) {
            LabeledContent(L("Kota", "City")) {
                TextField(L("mis. Jakarta", "e.g. Jakarta"), text: Binding(get: { prefs.weatherCity },
                                                                         set: { prefs.weatherCity = $0; prefs.weatherCoords = "" }))
                    .textFieldStyle(.roundedBorder)
                    .disabled(!model.features.weather)
            }
            HStack {
                Button {
                    locator.detect { lat, lon, name in
                        prefs.weatherCoords = String(format: "%.4f,%.4f", lat, lon)
                        prefs.weatherCity = name
                    }
                } label: {
                    Label(locator.state == .detecting ? L("Mendeteksi…", "Detecting…") : L("Pakai lokasi saat ini", "Use current location"), systemImage: "location.fill")
                }
                .disabled(!model.features.weather || locator.state == .detecting)
                if !prefs.weatherCoords.isEmpty {
                    Text(L("Memakai lokasi saat ini", "Using current location")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            if case .failed(let message) = locator.state {
                Text(message).font(.caption).foregroundStyle(.orange)
            }
            if model.features.weather, let problem = model.weather.problem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: Urutan tab

    @ViewBuilder private var tabsPane: some View {
        Section {
            ForEach(prefs.ordered(NotchModel.Tab.allCases), id: \.self) { tab in
                HStack {
                    Image(systemName: tab.icon).frame(width: 20)
                    Text(tab.label)
                    Spacer()
                    Button { prefs.move(tab, by: -1) } label: { Image(systemName: "chevron.up") }
                        .buttonStyle(.borderless).disabled(prefs.ordered(NotchModel.Tab.allCases).first == tab)
                    Button { prefs.move(tab, by: 1) } label: { Image(systemName: "chevron.down") }
                        .buttonStyle(.borderless).disabled(prefs.ordered(NotchModel.Tab.allCases).last == tab)
                }
            }
        }
    }

    // MARK: Data & bahasa

    @ViewBuilder private var dataPane: some View {
        Section {
            HStack {
                Text(L("Catatan, tugas, riwayat minum, clipboard, timer, dan pengaturan", "Notes, tasks, water log, clipboard, timers and settings"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(L("Ekspor…", "Export…")) { DataBackup.export() }
                Button(L("Impor…", "Import…")) { DataBackup.importFile() }
            }
        }
    }
}

/// Peta posisi notch melayang (seperti peta pil di Windows): layar kecil dengan titik notch. Klik atau seret titiknya.
struct FloatPositionMap: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var prefs: Preferences

    private var screen: CGSize { model.screenSize }
    private var maxDX: Double { Double(screen.width) / 2 - 60 }
    private var maxDY: Double { Double(screen.height) - 120 }
    private var fx: Double { 0.5 + prefs.floatDX / Double(screen.width) }
    private var fy: Double { (max(model.floatMinDY, prefs.floatDY) + 21) / Double(screen.height) }

    private func set(x: Double, y: Double) {
        prefs.floatDX = max(-maxDX, min(maxDX, (x - 0.5) * Double(screen.width)))
        prefs.floatDY = max(model.floatMinDY, min(maxDY, y * Double(screen.height) - 21))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L("Posisi notch melayang", "Floating notch position"))
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.18))
                    RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.4))
                    Capsule().fill(Color.accentColor)
                        .frame(width: 14, height: 8)
                        .position(x: w * fx, y: h * fy)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    set(x: v.location.x / w, y: v.location.y / h)
                })
            }
            .aspectRatio(screen.width / max(1, screen.height), contentMode: .fit)
            .frame(maxWidth: 320)
            HStack(spacing: 12) {
                Text("X").foregroundStyle(.secondary)
                Stepper(value: Binding(get: { Int((fx * 100).rounded()) }, set: { set(x: Double($0) / 100, y: fy) }), in: 0...100) {
                    Text("\(Int((fx * 100).rounded())) %").monospacedDigit()
                }
                Text("Y").foregroundStyle(.secondary)
                Stepper(value: Binding(get: { Int((fy * 100).rounded()) }, set: { set(x: fx, y: Double($0) / 100) }), in: 0...100) {
                    Text("\(Int((fy * 100).rounded())) %").monospacedDigit()
                }
                Spacer()
                Button(L("Kembalikan", "Reset")) { prefs.floatDX = 0; prefs.floatDY = 0 }
                    .disabled(prefs.floatDX == 0 && prefs.floatDY == 0)
            }
            Text(L("Klik atau seret titik di peta, atau seret notch langsung di layar.", "Click or drag the dot on the map, or drag the notch itself on the screen."))
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
