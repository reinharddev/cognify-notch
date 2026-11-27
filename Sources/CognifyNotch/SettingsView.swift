import AppKit
import ServiceManagement
import SwiftUI
import NotchDock

// Jendela Pengaturan app mandiri, bergaya Pengaturan Sistem macOS: sidebar kategori di kiri, di kanan header
// besar lalu kartu pengaturan. Pilihan fitur dan "Buka saat Mac dinyalakan" ada di sini, bukan di menu bar.

enum SettingsPane: String, CaseIterable, Identifiable {
    // Urutan = urutan di sidebar.
    case general, appearance, companion, behavior, features, tabs, skins, dock

    /// Kata kunci isi bagian ini, supaya pencarian menemukan pengaturan, bukan hanya nama bagiannya.
    var keywords: String {
        switch self {
        case .general: return "language login launch update version backup export import restore data"
        case .appearance: return "theme background image color accent gradient shape size roundness liquid glass pack floating pill face style notch width lyric equalizer"
        case .companion: return "face cogniface expression eyes blink mode reaction situation moment"
        case .behavior: return "open hide auto click hover delay screen shortcut keyboard"
        case .features: return "music lyrics equalizer clipboard tasks water calculator camera mirror stopwatch alarm battery charger download headphone caps lock internet weather city location calendar"
        case .tabs: return "order tab page start"
        case .skins: return "desktop widget skin cogniface mimik"
        case .dock: return "dock taskbar bar apps floating clock pin icon link"
        }
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .companion: return "CogniFace"
        case .behavior: return "Behavior"
        case .features: return "Features"
        case .tabs: return "Tabs"
        case .skins: return "Desktop widgets"
        case .dock: return "Dock"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Opening at login, updates, and data."
        case .appearance: return "Theme, background, shape, size, and colors."
        case .companion: return "The face in the notch: expressions, blinking, and reactions."
        case .behavior: return "How the notch opens, closes, and hides."
        case .features: return "Pick the features you want in the notch."
        case .tabs: return "Start tab and page order in the notch."
        case .skins: return "CogniFace, lyrics and more on your desktop."
        case .dock: return "Beta. A floating app bar at the bottom of the screen."
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "circle.lefthalf.filled"
        case .companion: return "face.smiling"
        case .behavior: return "cursorarrow"
        case .features: return "switch.2"
        case .tabs: return "macwindow"
        case .skins: return "square.grid.2x2"
        case .dock: return "dock.rectangle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var prefs: Preferences
    var updater: Updater?
    @State private var pane: SettingsPane? = .general
    @State private var query = ""
    @State private var bgError = ""
    @State private var dockLinkLabel = ""
    @State private var dockLinkURL = ""
    @State private var dockLinkError = ""
    @State private var loginOn = SMAppService.mainApp.status == .enabled
    @State private var autoUpdate = false
    /// Wajah contoh di bagian Teman kecil: menunjukkan pilihan yang sedang diubah.
    @StateObject private var preview = Face()
    @StateObject private var locator = LocationFinder()

    private var panes: [SettingsPane] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return SettingsPane.allCases }
        return SettingsPane.allCases.filter { ($0.title + " " + $0.subtitle + " " + $0.keywords).lowercased().contains(q) }
    }

    private var accent: Color { Color(hex: prefs.accentHex) ?? AccentStyle.fallback }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 180)
                .background(Color.white.opacity(0.03))
            Rectangle().fill(Color.white.opacity(0.07)).frame(width: 1)
            detail
        }
        .background(Color.black)
        .frame(minWidth: 720, idealWidth: 780, minHeight: 360, idealHeight: 600)
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .tint(accent)
        .toggleStyle(MiniSwitch(trailing: true))
        .labeledContentStyle(SettingsRowStyle())
        .buttonStyle(PillButtonStyle(prominent: false, large: true))
    }

    // MARK: Sidebar

    private var sidebar: some View {
        VStack(spacing: Theme.Space.s) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).font(.system(size: 12))
                TextField("Search settings", text: $query).textFieldStyle(.plain).font(.system(size: 12))
            }
            .notchFieldBox(height: 30, radius: 15)
            .padding(.top, 46) // di bawah tombol jendela
            ScrollView(showsIndicators: false) {
                VStack(spacing: 2) {
                    ForEach(panes) { p in
                        let selected = p == current
                        Button { pane = p } label: {
                            HStack(spacing: Theme.Space.s) {
                                Image(systemName: p.symbol).font(.system(size: 13)).frame(width: 18)
                                Text(p.title).font(.system(size: 13, weight: .semibold))
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 10)
                            .frame(height: 32)
                            .foregroundStyle(selected ? Color.white : Theme.textSecondary)
                            .background(Capsule().fill(selected ? accent.opacity(0.28) : Color.clear))
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                    if panes.isEmpty { SettingsNote("Nothing found").padding(.top, 20) }
                }
            }
        }
        .padding(.horizontal, Theme.Space.s)
        .padding(.bottom, Theme.Space.s)
    }

    // MARK: Detail

    private var current: SettingsPane { pane.flatMap { panes.contains($0) ? $0 : nil } ?? panes.first ?? .general }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(current.title).font(.system(size: 20, weight: .bold))
                    SettingsNote(current.subtitle)
                }
                content(for: current)
            }
            .font(.system(size: 12.5))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.m + Theme.Space.xs)
            .padding(.top, 40)
            .padding(.bottom, Theme.Space.m)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(current)
    }

    @ViewBuilder private func content(for pane: SettingsPane) -> some View {
        switch pane {
        case .general: generalPane
        case .appearance: appearancePane
        case .companion: companionPane
        case .behavior: behaviorPane
        case .features: featuresPane
        case .tabs: tabsPane
        case .skins: if let skins = model.skinManager { SkinsPane(skins: skins) }
        case .dock: dockPane
        }
    }

    // MARK: Dock

    private func dockModuleName(_ m: DockModule) -> String {
        switch m {
        case .media: return L("Lagu yang diputar", "Now playing")
        case .weather: return L("Cuaca", "Weather")
        case .timer: return L("Timer cepat (5, 15, 25 menit)", "Quick timer (5, 15, 25 min)")
        case .clipboard: return L("3 salinan terakhir", "Last 3 copies")
        case .lyrics: return L("Lirik", "Lyrics")
        case .links: return L("Pintasan tautan", "Link shortcuts")
        case .battery: return L("Baterai", "Battery")
        case .volume: return L("Volume", "Volume")
        }
    }

    /// Fitur lain yang dibutuhkan widget, bila belum menyala; nil bila siap dipakai.
    private func dockModuleNeeds(_ m: DockModule) -> String? {
        switch m {
        case .media where !model.features.media: return L("Nyalakan dulu \"Lagu & video yang diputar\" di Fitur.", "First turn on \"Now playing\" in Features.")
        case .weather where !model.features.weather: return L("Nyalakan dulu Cuaca di Fitur, lalu isi kota di Cuaca.", "First turn on Weather in Features, then set a city under Weather.")
        case .lyrics where !(model.features.lyrics && model.features.media): return L("Nyalakan dulu Lirik dan \"Lagu & video yang diputar\" di Fitur.", "First turn on Lyrics and \"Now playing\" in Features.")
        case .clipboard where !model.features.clipboard: return L("Nyalakan dulu riwayat Clipboard di Fitur.", "First turn on Clipboard history in Features.")
        default: return nil
        }
    }

    private func addDockLink() {
        guard let url = DockLinks.normalize(dockLinkURL) else { dockLinkError = L("Alamat webnya tidak valid.", "That doesn't look like a web address."); return }
        let name = dockLinkLabel.trimmingCharacters(in: .whitespaces)
        prefs.dockLinks.append(DockLink(label: String((name.isEmpty ? DockLinks.defaultLabel(for: url) : name).prefix(24)), url: url))
        dockLinkLabel = ""; dockLinkURL = ""; dockLinkError = ""
    }

    private func moveDockModule(_ m: DockModule, by offset: Int) {
        guard let from = prefs.dockModules.firstIndex(of: m), prefs.dockModules.indices.contains(from + offset) else { return }
        prefs.dockModules.swapAt(from, from + offset)
    }

    @ViewBuilder private var dockPane: some View {
        SettingsCard {
            Toggle(isOn: $prefs.dockEnabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(L("Nyalakan dock (Beta)", "Turn on the dock (Beta)"))
                    Text(L("Bilah melayang berisi Start, aplikasi yang lagi jalan, dan jam. Dock macOS tetap ada.", "A floating bar with Start, your running apps, and a clock. The macOS Dock stays put."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        // Tidak ada yang terlihat selama dock mati, jadi tidak bisa diubah.
        Group {
            SettingsCard(L("Isi", "Contents")) {
                Toggle(L("Tampilkan jam", "Show the clock"), isOn: $prefs.dockClock)
                if prefs.dockPins.isEmpty {
                    Text(L("Klik kanan ikon di dock buat menyematkan aplikasinya.", "Right-click an icon in the dock to pin the app.")).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(prefs.dockPins, id: \.id) { pin in
                        HStack {
                            Text(pin.name)
                            Spacer()
                            Button { prefs.dockPins = DockApps.movePin(prefs.dockPins, id: pin.id, by: -1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                            Button { prefs.dockPins = DockApps.movePin(prefs.dockPins, id: pin.id, by: 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                            Button { prefs.dockPins = DockApps.togglePin(prefs.dockPins, id: pin.id, name: pin.name) } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                        }
                    }
                }
            }
            SettingsCard(L("Jendela per aplikasi", "Windows per app")) {
                HStack {
                    Text(DockWindows.trusted ? L("Izin Aksesibilitas sudah aktif: klik kanan ikon buat lihat semua jendelanya.", "Accessibility is on: right-click an icon to see all its windows.")
                                             : L("Klik kanan ikon bisa menampilkan semua jendela aplikasi, tapi perlu izin Aksesibilitas dulu.", "Right-clicking an icon can list all of an app's windows, but it needs Accessibility access first."))
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if !DockWindows.trusted { Button(L("Beri izin…", "Allow…")) { DockWindows.requestTrust(); DockWindows.openAccessibilitySettings() } }
                }
                Text(L("Judul jendela cuma dibaca di Mac ini buat menu, tidak dikirim ke mana pun.", "Window titles are only read on this Mac, for the menu. Nothing is sent anywhere."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(L("Latar dock", "Dock background")) {
                NotchDropdown(L("Latar", "Background"), selection: $prefs.dockBg, options: [
                    DropdownOption(.follow, L("Ikut notch", "Follow notch")), DropdownOption(.glass, L("Kaca", "Glass")),
                    DropdownOption(.color, L("Warna", "Color")), DropdownOption(.gradient, L("Gradien", "Gradient")),
                ])
                if prefs.dockBg == .color || prefs.dockBg == .gradient {
                    LabeledContent(prefs.dockBg == .gradient ? L("Warna awal", "Start color") : L("Warna", "Color")) {
                        NotchColorPicker(selection: Binding(get: { Color(hex: prefs.dockBgColorHex) ?? .black }, set: { prefs.dockBgColorHex = $0.hex }))
                    }
                }
                if prefs.dockBg == .gradient {
                    LabeledContent(L("Warna akhir", "End color")) {
                        NotchColorPicker(selection: Binding(get: { Color(hex: prefs.dockBgColor2Hex) ?? .black }, set: { prefs.dockBgColor2Hex = $0.hex }))
                    }
                }
                Text(L("Ikut notch pakai tema dan latar yang sama dengan notch. Warna tulisan otomatis menyesuaikan biar tetap terbaca.", "Follow notch uses the same theme and background as the notch. Text color adjusts itself so it stays readable."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(L("Widget", "Widgets")) {
                let cfg = DockConfig(iconSize: CGFloat(prefs.dockIconSize), showClock: prefs.dockClock, modules: prefs.dockModules, links: prefs.dockLinks.count)
                let screenW = NSScreen.main?.frame.width ?? 1440
                ForEach(prefs.dockModules) { m in
                    VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(dockModuleName(m))
                        Spacer()
                        Button { moveDockModule(m, by: -1) } label: { Image(systemName: "chevron.left") }.buttonStyle(.borderless)
                        Button { moveDockModule(m, by: 1) } label: { Image(systemName: "chevron.right") }.buttonStyle(.borderless)
                        Button { prefs.dockModules.removeAll { $0 == m } } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                    }
                    if let need = dockModuleNeeds(m) { Text(need).font(.caption).foregroundStyle(.orange) }
                    }
                }
                ForEach(DockModule.allCases.filter { !prefs.dockModules.contains($0) }) { m in
                    let fits = DockLayout.canAdd(m, cfg, screenW: screenW)
                    let need = dockModuleNeeds(m)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(dockModuleName(m)).foregroundStyle(fits && need == nil ? .primary : .secondary)
                            Spacer()
                            if !fits { Text(L("Tidak muat", "No room")).font(.caption).foregroundStyle(.secondary) }
                            else { Button(L("Tambah", "Add")) { prefs.dockModules.append(m) }.disabled(need != nil) }
                        }
                        if fits, let need { Text(need).font(.caption).foregroundStyle(.orange) }
                    }
                }
                Text(L("Dock tidak akan lebih lebar dari layar: kalau penuh, widget tidak bisa ditambah, dan kalau layarnya menyempit, yang paling kanan disembunyikan.", "The dock never gets wider than the screen. When it's full you can't add more widgets, and on a narrower screen the right-most ones drop off."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(L("Tautan", "Links")) {
                ForEach(prefs.dockLinks) { link in
                    HStack {
                        VStack(alignment: .leading, spacing: 0) { Text(link.label); Text(link.url).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        Button { prefs.dockLinks.removeAll { $0.id == link.id } } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                    }
                }
                HStack {
                    NotchField(L("Nama (opsional)", "Name (optional)"), text: $dockLinkLabel).frame(width: 140)
                    NotchField(L("Alamat, mis. youtube.com", "Address, e.g. youtube.com"), text: $dockLinkURL).onSubmit(addDockLink)
                    Button(L("Tambah", "Add"), action: addDockLink).disabled(dockLinkURL.isEmpty || prefs.dockLinks.count >= DockLinks.maxCount)
                }
                if !dockLinkError.isEmpty { Text(dockLinkError).font(.caption).foregroundStyle(.orange) }
                Text(L("Buat widget Pintasan tautan (maksimal \(DockLinks.maxCount)). Cuma alamat web (http atau https).", "Used by the Link shortcuts widget (up to \(DockLinks.maxCount)). Web addresses only (http or https)."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard(L("Ukuran", "Size"), note: "The dock never gets wider than the screen. Anything that doesn't fit goes into the +N button.") {
                SliderRow(title: "Icon size", value: $prefs.dockIconSize, range: Double(DockMetrics.iconMin)...Double(DockMetrics.iconMax), step: 4, text: { "\(Int($0))" }, standard: 40)
                SliderRow(title: "Magnification", value: $prefs.dockMagnify, range: 0...100, step: 5, text: { $0 < 1 ? "Off" : "\(Int($0))" }, standard: 65)
                SliderRow(title: "Distance from bottom", value: $prefs.dockMargin, range: 0...48, step: 2, text: { "\(Int($0))" }, standard: 10)
                SliderRow(title: "Roundness", value: $prefs.dockRound, range: 0...100, step: 5, text: { "\(Int($0))" }, standard: 100)
            }
        }
        .disabled(!prefs.dockEnabled)
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
        NotchDropdown(s.label, selection: choice(s), options:
            [DropdownOption("auto", L("Bawaan", "Default") + " (" + s.emotion.label + ")")]
            + (s.isEvent ? [DropdownOption("none", L("Tidak bereaksi", "No reaction"))] : [])
            + Emotion.allCases.map { DropdownOption($0.rawValue, $0.label) })
    }

    @ViewBuilder private var companionPane: some View {
        SettingsCard {
            if let toggle = FeatureToggle.all.first(where: { $0.key == \.companion }) { featureRow(toggle) }
            Group {
                LabeledContent {
                    NotchDropdown("Mode", selection: $prefs.companionMode, options: CompanionMode.allCases.map { DropdownOption($0, $0.label) }).labelsHidden().fixedSize()
                    Circle().fill(Color.black).frame(width: 34, height: 34).overlay(FaceHead(face: preview, diameter: 34))
                } label: { SettingsLabel(title: "Mode", hint: prefs.companionMode.hint) }
                if prefs.companionMode == .fixed {
                    NotchDropdown("Expression", selection: $prefs.companionFixed, options: Emotion.allCases.map { DropdownOption($0, $0.label) })
                        .onChange(of: prefs.companionFixed) { preview.set($0) }
                }
                Toggle("Blink now and then", isOn: $prefs.companionBlink)
                Toggle("Turn toward the cursor", isOn: $prefs.companionFollow)
            }
            .disabled(!model.features.companion)
        }
        .onAppear { if prefs.companionMode == .fixed { preview.set(prefs.companionFixed) } }
        if prefs.companionMode == .custom {
            HStack(alignment: .top, spacing: Theme.Space.s) {
                SettingsCard("Situations") { ForEach(Situation.states) { situationRow($0) } }
                SettingsCard("Moments") { ForEach(Situation.events) { situationRow($0) } }
            }
            .disabled(!model.features.companion)
            Button("Reset to default") { prefs.companionMap = [:] }.disabled(prefs.companionMap.isEmpty || !model.features.companion)
        }
    }

    // MARK: Umum

    private func setLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            model.show(.failed(L("Gagal mengubah pengaturan buka saat login: ", "Couldn't change the open-at-login setting: ") + error.localizedDescription))
        }
        loginOn = SMAppService.mainApp.status == .enabled
    }

    @ViewBuilder private var generalPane: some View {
        SettingsCard {
            Toggle("Open at login", isOn: Binding(get: { loginOn }, set: setLogin))
            if let updater {
                Toggle("Install updates automatically", isOn: Binding(get: { autoUpdate }, set: { autoUpdate = $0; updater.automatic = $0 }))
                    .onAppear { autoUpdate = updater.automatic }
                LabeledContent("App version") { Button("Check for updates…") { updater.checkForUpdates() } }
            }
        }
        SettingsCard("Data") {
            LabeledContent("Notes, tasks, clipboard and settings") {
                Button("Export…") { DataBackup.export() }
                Button("Import…") { DataBackup.importFile() }
            }
        }
    }

    // MARK: Fitur

    private func featureRow(_ toggle: FeatureToggle) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Toggle(isOn: Binding(get: { model.features[keyPath: toggle.key] },
                                 set: { FeatureToggle.set(toggle, $0, model: model) })) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(toggle.title())
                    if let why = blockReason(toggle) { SettingsNote(why, warning: true) }
                }
            }
            .help(toggle.hint())
            if toggle.defaultsKey == "feature.clipboard" && model.features.clipboard { clipboardLimitControls }
            if toggle.defaultsKey == "feature.appNotifications" && model.features.appNotifications { appNotificationControls }
        }
        .disabled(blockReason(toggle) != nil)
    }

    /// Fitur yang bergantung pada fitur lain: alasan kenapa barisnya mati, supaya tidak ada saklar yang diam-diam tidak bisa dipakai.
    private func blockReason(_ toggle: FeatureToggle) -> String? {
        let needsMedia = toggle.key == \.spectrum || toggle.key == \.lyrics || toggle.key == \.lyricsWing
        if needsMedia && !model.features.media { return L("Nyalakan dulu \"Lagu & video yang diputar\".", "Turn on \"Now playing\" first.") }
        if toggle.key == \.lyricsWing && !model.features.lyrics { return L("Nyalakan dulu \"Lirik lagu\".", "Turn on \"Synced lyrics\" first.") }
        return nil
    }

    private var appNotificationControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.appNotes.access == .denied {
                Text(L("Izinnya belum ada. Beri Cognify Notch Akses Disk Penuh di Pengaturan Sistem, lalu matikan dan nyalakan lagi fitur ini.",
                       "No access yet. Give Cognify Notch Full Disk Access in System Settings, then switch this feature off and back on."))
                    .font(.caption).foregroundStyle(.orange)
                HStack {
                    Button(L("Buka Pengaturan Sistem", "Open System Settings")) { AppNotificationWatcher.openPrivacySettings() }
                    Button(L("Cek lagi", "Check again")) { model.appNotes.refreshAccess() }
                }
            }
            Text(L("Teruskan notifikasi dari:", "Show notifications from:")).font(.caption).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            LabeledContent("History limit") {
                NotchSegmented(title: "History limit", selection: Binding(
                    get: { prefs.clipboardUnlimited },
                    set: { prefs.clipboardUnlimited = $0; model.clipboard.applyLimit(unlimited: $0, count: prefs.clipboardLimit) }),
                    options: [DropdownOption(true, "Unlimited"), DropdownOption(false, "Custom")])
            }
            if !prefs.clipboardUnlimited {
                LabeledContent("Item count") {
                    TextField("40", value: Binding(
                        get: { prefs.clipboardLimit },
                        set: { value in
                            prefs.clipboardLimit = max(1, min(100_000, value))
                            model.clipboard.applyLimit(unlimited: prefs.clipboardUnlimited, count: prefs.clipboardLimit)
                        }), format: .number)
                        .labelsHidden().textFieldStyle(.plain).notchFieldBox().frame(width: 72)
                }
            }
        }
        .help("Pinned items don't count. Images are only kept while the app is running.")
    }

    private typealias FeatureGroup = (title: String, keys: [KeyPath<NotchModel.Features, Bool>])

    /// Dua kolom seperti mockup. Teman kecil ada di halaman CogniFace, Cuaca di kartunya sendiri.
    private var featureColumns: [[FeatureGroup]] {
        [
            [("Media", [\.media, \.lyrics, \.spectrum, \.lyricsWing]),
             ("Study", [\.calendar, \.todo, \.remindersSync, \.water, \.clockTools, \.calculator, \.voice]),
             ("Tools", [\.clipboard, \.camera, \.micTest, \.shortcuts])],
            [("System", [\.power, \.downloads, \.devices, \.keyboard, \.network, \.hud, \.appNotifications, \.hideFullscreen, \.hotkey])],
        ]
    }

    private func featureCard(_ group: FeatureGroup) -> some View {
        SettingsCard(group.title) {
            ForEach(group.keys, id: \.self) { key in
                if let toggle = FeatureToggle.all.first(where: { $0.key == key }) { featureRow(toggle) }
            }
        }
    }

    @ViewBuilder private var featuresPane: some View {
        let known = featureColumns.flatMap { $0 }.flatMap(\.keys) + [\.companion, \.weather]
        // Yang belum masuk kelompok mana pun tetap tampil.
        let rest = FeatureToggle.all.map { $0.key as KeyPath }.filter { !known.contains($0) }
        HStack(alignment: .top, spacing: Theme.Space.s) {
            VStack(spacing: Theme.Space.m) { ForEach(featureColumns[0], id: \.title) { featureCard($0) } }
            VStack(spacing: Theme.Space.m) {
                ForEach(featureColumns[1], id: \.title) { featureCard($0) }
                weatherCard
                if !rest.isEmpty { featureCard(("Other", rest)) }
            }
        }
    }

    // MARK: Notch

    private static let accentColors = ["#8f87ff", "#0a84ff", "#30d158", "#ff375f", "#ff9f0a", "#ffd60a", "#bf5af2", "#ffffff"]
    private static let lyricColors = ["#ffffff", "#ffd60a", "#30d158", "#0a84ff", "#ff375f", "#ff9f0a", "#bf5af2", "#8e8e93"]
    private static let equalizerColors = ["#ffffff", "#30d158", "#0a84ff", "#bf5af2", "#ff375f", "#ff9f0a", "#ffd60a"]

    private func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        bgError = prefs.chooseBackgroundImage(url) ? "" : L("Gambar ini tidak bisa dibuka.", "Couldn't open that image.")
    }

    private func hexColor(_ hex: ReferenceWritableKeyPath<Preferences, String>, _ fallback: Color) -> Binding<Color> {
        Binding(get: { Color(hex: prefs[keyPath: hex]) ?? fallback }, set: { prefs[keyPath: hex] = $0.hex })
    }

    private func colorRow(_ title: String, _ hex: ReferenceWritableKeyPath<Preferences, String>, _ fallback: Color = .black) -> some View {
        LabeledContent(title) { NotchColorPicker(selection: hexColor(hex, fallback), title: title) }
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    /// Gaya wajah melayang yang benar-benar tampil (tanpa Ekspresi CogniFace ia jadi kapsul).
    private var faceStyle: Bool { prefs.style(physicalNotch: model.physicalNotch) == .head && model.features.companion }

    @ViewBuilder private var appearancePane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Style").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary).padding(.horizontal, Theme.Space.s)
            NotchStyleChooser(prefs: prefs, physicalNotch: model.physicalNotch)
        }
        SettingsStage(prefs: prefs, model: model, height: 104)
        if model.detached {
            SettingsCard("Position", note: "Drag the marker, or drag the notch itself on screen. It snaps to the center.") {
                FloatPositionPad(model: model, prefs: prefs).frame(maxWidth: .infinity).padding(.vertical, Theme.Space.xs)
                LabeledContent("Back to top center") {
                    Button("Reset") { model.moveFloating(dx: 0, dy: 0) }
                        .disabled(prefs.floatDX == 0 && prefs.floatDY <= max(model.floatMinDY, 8))
                }
            }
        }
        SettingsCard("Theme") {
            if NotchTheme.glassSupported {
                NotchDropdown("Theme", selection: $prefs.theme, options: NotchTheme.allCases.map { DropdownOption($0, $0.label) })
            }
            NotchDropdown("Theme pack", selection: Binding(
                get: { ThemePreset.all.first { $0.accent.lowercased() == prefs.accentHex.lowercased() && $0.mode == prefs.bgMode }?.name() ?? "" },
                set: { name in if let preset = ThemePreset.all.first(where: { $0.name() == name }) { prefs.applyPreset(preset) } }),
                options: [DropdownOption("", "Choose a pack")] + ThemePreset.all.map { DropdownOption($0.name(), $0.name()) })
            if prefs.theme == .glass {
                LabeledContent("Liquid Glass") {
                    NotchSegmented(title: "Liquid Glass", selection: $prefs.glassCustom, options: [DropdownOption(false, "Default"), DropdownOption(true, "Custom")])
                }
                if prefs.glassCustom {
                    SliderRow(title: "Clear to tinted", value: $prefs.glassTint, range: 0...1, text: percent)
                    colorRow("Glass tint", \.glassTintHex)
                    SliderRow(title: "Distortion & sheen", value: $prefs.glassDistortion, range: 0...1, text: percent)
                }
            }
        }
        SettingsCard("Panel background", note: prefs.theme == .glass ? "Custom backgrounds don't apply with Liquid Glass." : nil) {
            NotchDropdown("Background type", selection: $prefs.bgMode, options: BackgroundMode.allCases.map { DropdownOption($0, $0.label) })
            if prefs.bgMode == .color || prefs.bgMode == .gradient { colorRow(prefs.bgMode == .gradient ? "Start color" : "Color", \.bgColorHex) }
            if prefs.bgMode == .gradient {
                colorRow("End color", \.bgColor2Hex)
                SliderRow(title: "Direction", value: $prefs.bgAngle, range: 0...360, step: 5, text: { "\(Int($0))°" })
            }
            if prefs.bgMode == .image {
                LabeledContent {
                    if let image = BackgroundStore.image(named: prefs.bgImageName) {
                        Image(nsImage: image).resizable().scaledToFill().frame(width: 52, height: 32).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Button(prefs.bgImageName.isEmpty ? "Choose image…" : "Change image…") { chooseBackgroundImage() }
                } label: { SettingsLabel(title: "Image", hint: bgError.isEmpty ? "A smaller copy stays in the app's data folder." : bgError) }
                SliderRow(title: "Blur", value: $prefs.bgBlur, range: 0...1, step: 0.05, text: percent)
            }
            if prefs.bgMode == .image || prefs.bgMode == .gradient {
                SliderRow(title: "Dim", value: $prefs.bgDim, range: 0...0.8, step: 0.05, text: percent)
            }
            if prefs.bgMode != .none { Toggle("Idle notch follows background", isOn: $prefs.idleThemed) }
        }
        .disabled(prefs.theme == .glass)
        SettingsCard("Shape and size") {
            SliderRow(title: "Notch width", hint: "Only on displays without a hardware notch.", value: $prefs.notchWidth, range: 84...220, step: 2,
                      text: { "\(Int($0)) pt" }, standard: 116)
                .disabled(model.physicalNotch || prefs.floatingStyle != .attached)
            SliderRow(title: "Open panel size", value: $prefs.scale, range: 0.7...1.5, step: 0.05, text: percent, standard: 1)
            SliderRow(title: "Idle notch size", value: $prefs.idleScale, range: 0.6...1.5, step: 0.05, text: percent, standard: 1)
            SliderRow(title: "Corner roundness", value: $prefs.roundness, range: 0...40, step: 1, text: { "\(Int($0))" }, standard: 24)
            LabeledContent("Accent color") {
                if !prefs.accentHex.isEmpty { Button("Default") { prefs.accentHex = "" } }
                NotchColorPicker(selection: hexColor(\.accentHex, AccentStyle.fallback), title: "Accent color")
            }
        }
        SettingsCard("Lyrics and equalizer", note: model.features.lyrics ? nil : "Turn on synced lyrics in Features to pick lyric colors.") {
            // Wajah melayang menaruh lirik di sampingnya: saklar tampil mati, pilihan tersimpan tidak diubah.
            Toggle(isOn: Binding(get: { prefs.lyricsBelow && !faceStyle }, set: { prefs.lyricsBelow = $0 })) {
                SettingsLabel(title: "Lyrics below the notch", hint: faceStyle ? "Only available with the Notch and Floating pill styles." : "A second line under the closed notch or pill. Hides when the pointer is on it.")
            }
            .disabled(faceStyle || !model.features.lyrics || !model.features.lyricsWing)
            Toggle("Match lyric colors to cover", isOn: $prefs.lyricAuto).disabled(!model.features.lyrics)
            if !prefs.lyricAuto && model.features.lyrics {
                colorRow("Current line", \.lyricActiveHex, .white)
                colorRow("Other lines", \.lyricIdleHex, .white)
            }
            Toggle("Match equalizer color to cover", isOn: $prefs.equalizerAuto)
            if !prefs.equalizerAuto { colorRow("Equalizer color", \.equalizerHex, .accent) }
        }
    }

    @ViewBuilder private var behaviorPane: some View {
        SettingsCard("Open and hide") {
            LabeledContent("Open the notch on") {
                NotchSegmented(title: "Open the notch on", selection: $prefs.openOnClick, options: [DropdownOption(false, "Hover"), DropdownOption(true, "Click")])
            }
            Toggle(isOn: $prefs.autoHide) {
                SettingsLabel(title: "Hide when idle", hint: model.detached ? "Not available while floating." : "Hides after 3 seconds, returns at the top edge.")
            }
            .disabled(model.detached)
            NotchDropdown("Show on screen", selection: $prefs.display, options: Preferences.Display.allCases.map { DropdownOption($0, $0.label) })
            NotchDropdown("Keyboard shortcut", selection: $prefs.hotKey, options: Preferences.HotKeyChoice.allCases.map { DropdownOption($0, $0.label) })
                .disabled(!model.features.hotkey)
        }
        SettingsCard("Timing", note: prefs.openOnClick ? "The opening delay doesn't apply when you open the notch by clicking." : nil) {
            SliderRow(title: "Delay before opening", value: $prefs.hoverDelay, range: 0...0.6, step: 0.05, text: { "\(Int($0 * 1000)) ms" })
                .disabled(prefs.openOnClick)
            SliderRow(title: "Delay before closing", value: $prefs.closeDelay, range: 0.1...1.5, step: 0.05, text: { "\(Int($0 * 1000)) ms" })
        }
    }

    private var weatherCard: some View {
        SettingsCard("Weather") {
            if let toggle = FeatureToggle.all.first(where: { $0.key == \.weather }) { featureRow(toggle) }
            LabeledContent("City") {
                NotchField("e.g. Jakarta", text: Binding(get: { prefs.weatherCity }, set: { prefs.weatherCity = $0; prefs.weatherCoords = "" }))
                    .frame(width: 130)
                    .disabled(!model.features.weather)
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                LabeledContent("Location") {
                    Button(locator.state == .detecting ? "Detecting…" : "Use current location") {
                        locator.detect { lat, lon, name in
                            prefs.weatherCoords = String(format: "%.4f,%.4f", lat, lon)
                            prefs.weatherCity = name
                        }
                    }
                    .disabled(!model.features.weather || locator.state == .detecting)
                }
                if case .failed(let message) = locator.state { SettingsNote(message, warning: true) }
                if model.features.weather, let problem = model.weather.problem { SettingsNote(problem, warning: true) }
            }
        }
    }

    // MARK: Urutan tab

    @ViewBuilder private var tabsPane: some View {
        let order = prefs.ordered(NotchModel.Tab.allCases)
        HStack(spacing: 5) {
            ForEach(Array(order.enumerated()), id: \.element) { index, _ in
                Capsule().fill(index == 0 ? accent : Theme.track).frame(width: index == 0 ? 18 : 5, height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.s)
        .background(Capsule().fill(Theme.card))
        SettingsCard("When the notch opens") {
            NotchDropdown("Show", selection: $prefs.startTab,
                          options: [DropdownOption("", "Last tab")] + model.tabs.map { DropdownOption($0.rawValue, $0.label) })
        }
        VStack(alignment: .leading, spacing: 6) {
            Text("Tab order").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textSecondary).padding(.horizontal, Theme.Space.s)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 186), spacing: 6)], spacing: 6) {
                ForEach(Array(order.enumerated()), id: \.element) { index, tab in
                    HStack(spacing: Theme.Space.s) {
                        Text("\(index + 1)").font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22).background(Circle().fill(Theme.track))
                        Text(tab.label).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "line.3.horizontal").foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.leading, 6).padding(.trailing, 10)
                    .frame(height: 34)
                    .background(Capsule().fill(Theme.card))
                    .contentShape(Capsule())
                    .draggable(tab.rawValue)
                    .dropDestination(for: String.self) { items, _ in
                        guard let moved = items.first.flatMap(NotchModel.Tab.init) else { return false }
                        withAnimation(.tabSwitch) { prefs.move(moved, onto: tab) }
                        return true
                    }
                    // Tanpa menyeret (keyboard dan VoiceOver).
                    .contextMenu {
                        Button("Move earlier") { prefs.move(tab, by: -1) }
                        Button("Move later") { prefs.move(tab, by: 1) }
                    }
                    .accessibilityAction(named: "Move earlier") { prefs.move(tab, by: -1) }
                    .accessibilityAction(named: "Move later") { prefs.move(tab, by: 1) }
                }
            }
            SettingsNote("Drag to reorder.").padding(.horizontal, Theme.Space.s)
        }
    }
}

/// Pilihan gaya: tiga kartu bergambar.
struct NotchStyleChooser: View {
    @ObservedObject var prefs: Preferences
    let physicalNotch: Bool

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(Preferences.FloatingStyle.allCases) { style in
                let selected = prefs.style(physicalNotch: physicalNotch) == style
                let shape = RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                Button { prefs.setStyle(style) } label: {
                    VStack(spacing: 2) {
                        preview(style)
                            .frame(maxWidth: .infinity).frame(height: 58)
                            .background(LinearGradient(colors: [Color(red: 0.49, green: 0.54, blue: 0.66), Color(red: 0.79, green: 0.6, blue: 0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .padding(.bottom, Theme.Space.xs)
                        Text(style.label).font(.system(size: 12, weight: .bold))
                        Text(style.hint).font(.system(size: 11)).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(6).padding(.bottom, Theme.Space.xs)
                    .background(shape.fill(selected ? Color.accent.opacity(0.14) : Theme.track))
                    .overlay(shape.strokeBorder(selected ? Color.accent : Theme.edge, lineWidth: selected ? 2 : 1))
                    .contentShape(shape)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func preview(_ style: Preferences.FloatingStyle) -> some View {
        let eyes = HStack(spacing: 8) { ForEach(0..<2, id: \.self) { _ in Capsule().fill(.white).frame(width: 4, height: 9) } }
        switch style {
        case .attached:
            NotchShape(top: 4, bottom: 10).fill(.black).frame(width: 86, height: 24).overlay(eyes).frame(maxHeight: .infinity, alignment: .top)
        case .pill:
            Capsule().fill(.black).frame(width: 62, height: 28).overlay(eyes)
        case .head:
            Circle().fill(.black).frame(width: 36, height: 36).overlay(eyes)
        }
    }
}

/// Bentuk dengan dua sudut bawah membulat (bentuk notch yang menempel).
struct UnderRounded: Shape {
    var radius: CGFloat
    func path(in r: CGRect) -> Path {
        let k = min(radius, r.height, r.width / 2)
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - k))
        p.addQuadCurve(to: CGPoint(x: r.maxX - k, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + k, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - k), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

/// Miniatur layar: seret penandanya untuk memindahkan notch melayang (wajah dan lirik ikut sebagai satu grup).
struct FloatPositionPad: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var prefs: Preferences
    private static let width: CGFloat = 280

    var body: some View {
        let scale = Self.width / model.screenSize.width
        let height = model.screenSize.height * scale
        let marker = prefs.floatingStyle == .head ? CGSize(width: 18, height: 18) : CGSize(width: 36, height: 14)
        let x = max(0, min(Self.width - marker.width, Self.width / 2 + prefs.floatDX * scale - marker.width / 2))
        let y = min(height - marker.height, model.floatingDY * scale)
        ZStack(alignment: .topLeading) {
            Theme.track
            Theme.track.frame(height: 9) // menu bar
            // Garis tengah menyala saat notch tepat di tengah.
            Rectangle().fill(prefs.floatDX == 0 ? Color.accent : Theme.edge).frame(width: 1, height: height).offset(x: Self.width / 2)
            Capsule().fill(.black)
                .overlay(Capsule().strokeBorder(Color.accent, lineWidth: 1.5))
                .frame(width: marker.width, height: marker.height)
                .offset(x: x, y: y)
        }
        .frame(width: Self.width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.item, style: .continuous))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
            model.moveFloating(dx: (drag.location.x - Self.width / 2) / scale, dy: (drag.location.y - marker.height / 2) / scale)
        })
        .accessibilityElement()
        .accessibilityLabel("Floating position")
        .accessibilityAction(named: "Move left") { move(-40, 0) }
        .accessibilityAction(named: "Move right") { move(40, 0) }
        .accessibilityAction(named: "Move up") { move(0, -40) }
        .accessibilityAction(named: "Move down") { move(0, 40) }
    }

    private func move(_ x: Double, _ y: Double) {
        model.moveFloating(dx: prefs.floatDX + x, dy: model.floatingDY + y)
    }
}

/// Pratinjau hidup di Pengaturan: gaya, bentuk notch, ukuran, lengkung, aksen, dan latar mengikuti pilihan saat ini.
struct SettingsStage: View {
    @ObservedObject var prefs: Preferences
    @ObservedObject var model: NotchModel
    var height: CGFloat
    @State private var open = false

    private var accent: Color { Color(hex: prefs.accentHex) ?? AccentStyle.fallback }

    /// Gaya yang benar-benar tampil di layar ini.
    private var style: Preferences.FloatingStyle { prefs.style(physicalNotch: model.physicalNotch) }
    private var floating: Bool { style != .attached }
    /// Wajah bulat butuh Ekspresi CogniFace; tanpanya notch diam tampil sebagai kapsul.
    private var head: Bool { style == .head && model.features.companion && !open }

    private var size: CGSize {
        if open { return CGSize(width: 340, height: floating ? 88 : 92) }
        if head { return CGSize(width: NotchModel.headSize, height: NotchModel.headSize) }
        if floating {
            return CGSize(width: 84 * prefs.idleScale, height: max(NotchController.floatingMinHeight, NotchController.floatingHeight * prefs.idleScale))
        }
        // +12: lengkung cekung di kiri dan kanan atas.
        return CGSize(width: (model.physicalNotch ? 150 : prefs.notchWidth) * prefs.idleScale + 12, height: 32)
    }

    private var shape: AnyShape {
        if head { return AnyShape(Circle()) }
        if floating { return AnyShape(RoundedRectangle(cornerRadius: open ? max(16, prefs.roundness) : size.height / 2, style: .continuous)) }
        return AnyShape(NotchShape(top: open ? 12 : 6, bottom: open ? CGFloat(prefs.roundness) : 12))
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.1, green: 0.09, blue: 0.19), Color(red: 0.24, green: 0.16, blue: 0.39), Color(red: 0.44, green: 0.23, blue: 0.49)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Color.black.opacity(0.28).frame(height: 22).frame(maxHeight: .infinity, alignment: .top)
            ZStack(alignment: .top) {
                if (open || floating || prefs.idleThemed) && prefs.customBackgroundActive && !head { CustomBackground(prefs: prefs) } else { Color.black }
                if head {
                    FaceHead(face: model.face, diameter: NotchModel.headSize)
                } else {
                    HStack(spacing: 10) {
                        if model.features.companion {
                            Capsule().fill(accent).frame(width: 8, height: 13)
                            Capsule().fill(accent).frame(width: 8, height: 13)
                        }
                    }
                    .frame(height: open ? 32 : size.height)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .padding(.top, floating ? 8 : 0) // kapsul dan wajah tidak menempel di tepi atas
            .animation(.easeOut(duration: 0.15), value: open)
            .animation(.easeOut(duration: 0.15), value: size)
            .animation(.easeOut(duration: 0.15), value: style)
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Spacer()
                    Text(L("Pratinjau langsung", "Live preview")).font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
                    Button(L("Buka / tutup", "Open / close")) { open.toggle() }
                        .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.white)
                        .padding(.horizontal, 9).padding(.vertical, 2).background(Capsule().fill(Color.white.opacity(0.18)))
                }
                .padding(.trailing, 10).padding(.bottom, 8)
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.08)))
        .padding(.horizontal, 2)
    }
}
