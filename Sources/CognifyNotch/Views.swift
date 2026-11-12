import NotchTime
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Mode snapshot

private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// Render ke gambar (Snapshot.swift): ImageRenderer tidak bisa menggambar komponen AppKit
    /// (kolom teks, spinner, area drop), jadi diganti gambar biasa.
    var snapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}

// MARK: - Bentuk notch

/// Notch MacBook: sudut atas melengkung ke luar (menyatu dengan tepi layar), sudut bawah membulat.
struct NotchShape: Shape {
    var top: CGFloat
    var bottom: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(top, bottom) }
        set { top = newValue.first; bottom = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addQuadCurve(to: CGPoint(x: r.minX + top, y: r.minY + top), control: CGPoint(x: r.minX + top, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + top, y: r.maxY - bottom))
        p.addQuadCurve(to: CGPoint(x: r.minX + top + bottom, y: r.maxY), control: CGPoint(x: r.minX + top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top - bottom, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.maxX - top, y: r.maxY - bottom), control: CGPoint(x: r.maxX - top, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX - top, y: r.minY + top))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.minY), control: CGPoint(x: r.maxX - top, y: r.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Akar

struct NotchRoot: View {
    @ObservedObject var model: NotchModel
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: model.topInset)
            ZStack(alignment: .top) {
                // Tema kaca mencakup notch terbuka dan tertutup, termasuk sayap dengan mata.
                let glass = model.prefs.activeTheme == .glass
                bodyShape.fill(Color.black)
                    .shadow(color: .black.opacity(glass ? 0 : model.expanded ? 0.45 : model.headMode ? 0.35 : 0), radius: model.headMode ? 6 : 16, y: model.headMode ? 2 : 6)
                    .opacity(glass ? 0 : 1)
                if glass {
                    GlassSurface(shape: bodyShape, tint: model.prefs.glassTintValue, color: model.prefs.glassColor,
                                 distortion: model.prefs.glassDistortionValue)
                        .transition(.opacity)
                }
                if model.expanded && model.tab == .sky {
                    // Latar langit hanya di halaman Langit, penuh sampai ke atas.
                    SkyBackground(weather: model.weather, glass: glass)
                        .clipShape(bodyShape)
                        .opacity(glass ? 0.94 : 1) // tema kaca: langit sedikit bening, kaca di belakangnya tetap terasa
                        .transition(.opacity)
                    if glass {
                        GlassLens(shape: bodyShape)
                        GlassSheen(shape: bodyShape, distortion: min(model.prefs.glassDistortionValue, 0.4))
                            .transition(.opacity)
                    }
                }
                content
                    .id(model.prefs.accentHex) // ganti warna aksen: gambar ulang semua isi
                    .padding(.horizontal, model.expanded ? (model.detached ? 20 : 12) : model.headMode ? 0 : 6) // di dalam lengkungan atas
                    .padding(.top, model.expanded && model.detached ? 12 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipShape(bodyShape)
            }
            .frame(width: model.size.width, height: model.size.height)
            .offset(x: model.shapeOffset + model.edgeShift.width, y: model.edgeShift.height + (model.autoHidden ? -(model.size.height + 12) : 0))
            .opacity(model.autoHidden ? 0 : 1)
            .animation(.easeInOut(duration: 0.4), value: model.tab == .sky)
            .animation(.notch, value: model.expanded) // menutup saat pindah tab tetap meluncur, tidak melompat
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onChange(of: model.dropTargeted) { targeted in
            if targeted { model.setExpanded(true) }
        }
    }

    private var bodyShape: AnyShape {
        if model.headMode { return AnyShape(Circle()) }
        if model.detached {
            let r = model.expanded ? max(16, CGFloat(model.prefs.roundness)) : min(14, model.size.height / 2)
            return AnyShape(RoundedRectangle(cornerRadius: r, style: .continuous))
        }
        return AnyShape(NotchShape(top: model.expanded ? 12 : 6, bottom: model.expanded ? CGFloat(model.prefs.roundness) : 12))
    }

    @ViewBuilder private var content: some View {
        if model.headMode {
            FaceHead(face: model.face, diameter: NotchModel.headSize)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
        } else if model.expanded {
            // Ukuran "Besar": isi digambar pada ukuran normal lalu diperbesar dari atas.
            let scale = model.scale
            ExpandedView(model: model)
                .frame(width: (model.expandedBox.width - (model.detached ? 40 : 24)) / scale, height: model.expandedBox.height / scale)
                .scaleEffect(scale, anchor: .top)
                .frame(width: model.expandedBox.width - (model.detached ? 40 : 24), height: model.expandedBox.height, alignment: .top)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).animation(.notch.delay(0.06)),
                    removal: .opacity.animation(.easeIn(duration: 0.2))
                ))
        } else if let card = model.card {
            NoticeCard(card: card, notchHeight: model.notchSize.height, gap: model.notchSize.width,
                       face: model.features.companion && model.hasNotch ? model.face : nil)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
        } else if let live = model.live {
            LiveWings(live: live, gap: model.barGap, wings: model.wings, media: model.media, spectrum: model.spectrum,
                      face: model.face, lyrics: model.lyrics, onBannerDone: { model.endSongBanner($0) })
                .frame(height: model.notchSize.height)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        }
    }
}

// MARK: - Sayap saat tertutup

struct LiveWings: View {
    let live: NotchModel.Live
    let gap: CGFloat
    let wings: (left: CGFloat, right: CGFloat)
    @ObservedObject var media: MediaMonitor
    let spectrum: Spectrum
    var face: Face? = nil
    var lyrics: LyricsService? = nil
    var onBannerDone: (String) -> Void = { _ in }

    /// Mata mengecil bersama sayapnya supaya tidak terpotong.
    private var eyeScale: CGFloat { min(1, max(0.75, (min(wings.left, wings.right) - 6) / 24)) }

    var body: some View {
        if live.eyes {
            // Notch fisik sebagai wajah: satu mata di tiap sisinya.
            HStack(spacing: 0) {
                if let face {
                    Eye(face: face, right: false).scaleEffect(eyeScale, anchor: .trailing).frame(width: max(0, wings.left - 6), alignment: .trailing)
                    Color.clear.frame(width: gap)
                    Eye(face: face, right: true).scaleEffect(eyeScale, anchor: .leading).frame(width: max(0, wings.right - 6), alignment: .leading)
                }
            }
            .modifier(Wobble(kind: face?.rx ?? .none, amp: 2, t: face?.rxT ?? 0))
        } else {
            wingsBody
        }
    }

    private var wingsBody: some View {
        HStack(spacing: 0) {
            Group {
                if live.lyrics, let lyrics {
                    HStack(spacing: 8) {
                        Artwork(media: media, size: 20)
                        WingLyricLine(lyrics: lyrics, media: media)
                    }
                    .padding(.leading, 8)
                } else if live.media, let title = live.title {
                    HStack(spacing: 8) {
                        Artwork(media: media, size: 20)
                        SongTitle(text: title, onFinish: { onBannerDone(title) })
                    }
                    .padding(.leading, 8)
                } else if live.media {
                    Artwork(media: media, size: 20)
                } else if let title = live.title {
                    HStack(spacing: 6) {
                        Image(systemName: live.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(live.tint)
                        Text(title)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .padding(.horizontal, 8)
                } else {
                    Image(systemName: live.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(live.tint)
                }
            }
            .frame(width: max(0, wings.left - 6))
            Color.clear.frame(width: gap) // area notch fisik
            Group {
                if live.media {
                    Equalizer(playing: true, spectrum: spectrum)
                } else if let end = live.countdown {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(ClockTools.clock(end.timeIntervalSince(context.date)))
                            .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.white)
                    }
                } else if let level = live.level {
                    LevelBar(value: level, tint: live.tint)
                } else {
                    Text(live.text)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .contentTransition(.numericText())
                }
            }
            .frame(width: max(0, wings.right - 6))
        }
    }
}

/// Judul lagu baru di sayap kiri: bergulir sekali bila terlalu panjang, lalu `onFinish`.
struct SongTitle: View {
    let text: String
    let onFinish: () -> Void
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @Environment(\.snapshot) private var snapshot

    private let font = Font.system(size: 12, weight: .semibold, design: .rounded)

    var body: some View {
        // Teks di overlay: panjang judul tidak ikut menentukan lebar sayap.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: 16)
            .overlay(alignment: .leading) {
                Text(text)
                    .font(font)
                    .foregroundStyle(.white)
                    .fixedSize()
                    .background(GeometryReader { t in
                        Color.clear.onAppear { textWidth = t.size.width }.onChange(of: t.size.width) { textWidth = $0 }
                    })
                    .offset(x: offset)
            }
            .background(GeometryReader { b in
                Color.clear.onAppear { boxWidth = b.size.width }.onChange(of: b.size.width) { boxWidth = $0 }
            })
            .clipped()
            .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.88),
                                         .init(color: .clear, location: 1)], startPoint: .leading, endPoint: .trailing))
            .task(id: text) {
                guard !snapshot else { return }
                offset = 0
                try? await Task.sleep(nanoseconds: 600_000_000) // tunggu sayap selesai melebar
                let overflow = textWidth - boxWidth + 16 // + ruang pudar di kanan
                if overflow > 17 {
                    try? await Task.sleep(nanoseconds: 900_000_000)
                    let duration = Double(overflow) / 32
                    withAnimation(.linear(duration: duration)) { offset = -overflow }
                    try? await Task.sleep(nanoseconds: UInt64((duration + 1.4) * 1_000_000_000))
                } else {
                    try? await Task.sleep(nanoseconds: 3_200_000_000)
                }
                guard !Task.isCancelled else { return }
                onFinish()
            }
    }
}

/// Baris lirik yang sedang dinyanyikan, di sayap kiri notch tertutup (diperbarui 2x per detik).
struct WingLyricLine: View {
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var media: MediaMonitor
    @ObservedObject private var style = LyricStyle.shared
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        if snapshot {
            line(at: media.nowPlaying?.timestamp ?? Date())
        } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { context in line(at: context.date) }
        }
    }

    private func line(at date: Date) -> some View {
        var text = ""
        if case .synced(let lines) = lyrics.state, let position = media.nowPlaying?.position(at: date) {
            text = lines.last { $0.time <= position + 0.25 }?.text ?? ""
        }
        return Text(text.isEmpty ? "♪" : text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(style.resolved(artwork: media.artwork).active ?? .white)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(text)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
            .animation(.easeOut(duration: 0.25), value: text)
    }
}

/// Kartu kabar di bawah notch fisik: ikon, judul, keterangan, dan nilai (mis. persen baterai).
struct NoticeCard: View {
    let card: NotchModel.Card
    let notchHeight: CGFloat
    var gap: CGFloat = 0
    var face: Face? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Mata tetap di kiri-kanan notch fisik, jadi terlihat bereaksi pada kabarnya.
            if let face {
                HStack(spacing: 0) {
                    Eye(face: face, right: false).frame(width: 24, alignment: .trailing)
                    Color.clear.frame(width: gap)
                    Eye(face: face, right: true).frame(width: 24, alignment: .leading)
                }
                .modifier(Wobble(kind: face.rx, amp: 2, t: face.rxT))
                .frame(height: notchHeight)
            } else {
                Color.clear.frame(height: notchHeight)
            }
            HStack(spacing: 10) {
                Image(systemName: card.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(card.tint)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(card.tint.opacity(0.18)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.title).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                    if !card.subtitle.isEmpty {
                        Text(card.subtitle).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if let value = card.value {
                    Text(value).font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity)
        }
    }
}

struct LevelBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.18))
            Capsule().fill(tint).frame(width: 46 * max(0, min(1, value)))
        }
        .frame(width: 46, height: 5)
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: value)
    }
}

// MARK: - Terbuka

struct ExpandedView: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.frame(height: model.notchSize.height)
            Group {
                if model.dropTargeted {
                    DropChoice(model: model).padding(.horizontal, 14)
                } else if let toast = model.toast, toast.isBanner {
                    ToastBanner(model: model, toast: toast).padding(.horizontal, 14)
                } else {
                    page
                        .id(model.tab)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: model.pageForward ? 10 : -10)),
                            removal: .opacity.animation(.easeOut(duration: 0.08))))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 8)
            if !model.dropTargeted, !(model.toast?.isBanner ?? false) {
                PageDock(tabs: model.tabs, current: model.tab, select: { model.go(to: $0) }, glass: model.prefs.activeTheme == .glass)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .zIndex(1) // ikon yang membesar boleh menutupi isi halaman di atasnya
            } else {
                Spacer().frame(height: 12)
            }
        }
        .foregroundStyle(model.tab == .sky ? SkyPalette.ink(weather: model.weather) : Color.white)
    }

    @ViewBuilder private var page: some View {
        switch model.tab {
        case .home: HomePanel(model: model, calendar: model.calendar)
        case .music: MusicPanel(model: model, media: model.media)
        case .clock: ClockPanel(clock: model.clock)
        case .sky: SkyPanel(weather: model.weather)
        case .water: WaterPanel(water: model.water)
        case .todo: TodoPanel(model: model, todo: model.todo)
        case .notes: NotesPanel(model: model, notes: model.notes)
        case .clipboard: ClipboardPanel(model: model, history: model.clipboard)
        case .tray: TrayPanel(model: model, tray: model.tray)
        case .timer: TimerPanel(timer: model.timer)
        case .mirror: MirrorPanel(camera: model.camera)
        case .shortcuts: ShortcutsPanel(model: model, shortcuts: model.shortcuts)
        case .cognify: CognifyPanel(model: model, hub: model.hub)
        }
    }

    /// Baris setinggi notch: judul halaman di kiri notch fisik; tanggal, jam, baterai, dan
    /// equalizer di kanannya. Tengahnya (notch fisik) dibiarkan kosong.
    /// Warna tulisan header: putih, atau gelap di halaman Langit bila langitnya terang.
    private var headInk: Color { model.tab == .sky ? SkyPalette.ink(weather: model.weather) : .white }

    private var header: some View {
        GeometryReader { geo in
            // Lebar notch fisik dalam koordinat isi (isi diperbesar `scale` kali saat ukuran Besar).
            // Tanpa notch fisik (melayang) tidak ada yang perlu dihindari di tengah, jadi sisi kanan boleh lebih lebar.
            let gap = model.hasNotch ? model.notchSize.width / model.scale + 10 : 16
            let side = max(0, (geo.size.width - gap) / 2)
            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    if !model.appMode {
                        Circle().fill(model.connected ? Color.accent : .gray).frame(width: 6, height: 6)
                    }
                    Text(model.tab.label).font(.system(size: 13, weight: .bold, design: .rounded)).lineLimit(1)
                    if !model.appMode, model.tab == .home, let overdue = model.state?.overdue, overdue > 0 {
                        Text(L("\(overdue) terlambat", "\(overdue) overdue"))
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red.opacity(0.28)))
                            .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.6))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 14)
                .frame(width: side, alignment: .leading)
                Color.clear.frame(width: gap)
                HStack(spacing: 8) {
                    if model.features.weather, let now = model.weather.now {
                        HStack(spacing: 3) {
                            Image(systemName: now.symbol).symbolRenderingMode(.multicolor).font(.system(size: 11))
                            Text("\(now.temperature)°").font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        }
                        .help(now.place)
                    }
                    if let battery = model.battery { BatteryRing(battery: battery, ink: headInk) }
                    Text(Self.dateTime(model.now))
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(headInk.opacity(0.8))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Button { model.onOpenSettings?() } label: {
                        Image(systemName: "gearshape.fill").font(.system(size: 11.5, weight: .semibold)).foregroundStyle(headInk.opacity(0.8))
                    }
                    .buttonStyle(.plain)
                    .help(L("Pengaturan", "Settings"))
                    if model.features.media, model.media.nowPlaying?.playing == true {
                        Equalizer(playing: true, spectrum: model.spectrum)
                    }
                }
                .padding(.trailing, 14)
                .frame(width: side, alignment: .trailing)
            }
            .frame(height: geo.size.height)
        }
    }

    static func dateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Lang.english ? "en_US" : "id_ID")
        f.dateFormat = Lang.english ? "EEE d MMM  h:mm" : "EEE d MMM  HH.mm"
        return f.string(from: date)
    }
}

/// Cincin baterai kecil (hijau saat dicas, merah di bawah 20%).
struct BatteryRing: View {
    let battery: NotchModel.Battery
    var ink: Color = .white

    var body: some View {
        let tint: Color = battery.charging ? .green : battery.percent <= 20 ? .red : ink
        ZStack {
            Circle().stroke(ink.opacity(0.15), lineWidth: 2.2)
            Circle().trim(from: 0, to: CGFloat(battery.percent) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if battery.charging {
                Image(systemName: "bolt.fill").font(.system(size: 6, weight: .bold)).foregroundStyle(tint)
            }
        }
        .frame(width: 13, height: 13)
        .help(L("Baterai \(battery.percent)%", "Battery \(battery.percent)%"))
    }
}

/// Titik halaman di bawah panel. Saat diarahkan kursor berubah seperti Dock macOS: titik jadi
/// ikon halaman, yang paling dekat kursor membesar paling besar dan namanya muncul di atasnya.
/// Klik untuk lompat ke halaman itu.
struct PageDock: View {
    let tabs: [NotchModel.Tab]
    let current: NotchModel.Tab
    let select: (NotchModel.Tab) -> Void
    var previewPointer: CGFloat? = nil // untuk snapshot
    var glass = false // tema kaca: ubin ikon berupa kaca
    @State private var hoverPointer: CGFloat? // posisi x kursor di baris ikon (nil = tidak diarahkan)
    private var pointer: CGFloat? { hoverPointer ?? previewPointer }

    private static let base: CGFloat = 20   // ukuran ikon tanpa pembesaran
    private static let peak: CGFloat = 34   // ukuran ikon tepat di bawah kursor
    private static let reach: CGFloat = 64  // jarak (pt) pengaruh pembesaran
    private static let gap: CGFloat = 4

    var body: some View {
        ZStack(alignment: .bottom) {
            if let pointer {
                icons(pointer)
                    .transition(.opacity.combined(with: .scale(scale: 0.6, anchor: .bottom)))
            } else {
                dots.transition(.opacity)
            }
        }
        .frame(height: 6, alignment: .bottom)
        // Area hover setinggi ikon terbesar supaya kursor tidak "jatuh" saat ikon membesar.
        .background(alignment: .bottom) {
            Color.clear
                .frame(width: hoverWidth, height: Self.peak + 14)
                .notchPointer { point in
                    guard let point else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { hoverPointer = nil }
                        return
                    }
                    let x = point.x - (hoverWidth - restWidth) / 2
                    if hoverPointer == nil {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) { hoverPointer = x }
                    } else {
                        // Posisi kursor datang 20x per detik: animasi pendek menghaluskan pembesaran.
                        withAnimation(.easeOut(duration: 0.09)) { hoverPointer = x }
                    }
                }
        }
    }

    private var restWidth: CGFloat { CGFloat(tabs.count) * (Self.base + Self.gap) - Self.gap }
    private var hoverWidth: CGFloat { restWidth + 2 * (Self.peak - Self.base) }

    private var dots: some View {
        HStack(spacing: 5) {
            ForEach(tabs, id: \.self) { tab in
                Capsule()
                    .fill(Color.white.opacity(tab == current ? 0.9 : 0.25))
                    .frame(width: tab == current ? 14 : 5, height: 5)
            }
        }
        .animation(.tabSwitch, value: current)
    }

    /// Ukuran ikon ke-i menurut jaraknya dari kursor (kurva kosinus, seperti Dock).
    private func size(_ index: Int, _ pointer: CGFloat) -> CGFloat {
        let center = CGFloat(index) * (Self.base + Self.gap) + Self.base / 2
        let distance = min(1, abs(pointer - center) / Self.reach)
        return Self.base + (Self.peak - Self.base) * (cos(distance * .pi) + 1) / 2
    }

    private func icons(_ pointer: CGFloat) -> some View {
        let nearest = tabs.indices.min { abs(pointer - centerX($0)) < abs(pointer - centerX($1)) }
        return HStack(alignment: .bottom, spacing: Self.gap) {
            ForEach(Array(tabs.enumerated()), id: \.element) { index, tab in
                let side = size(index, pointer)
                Button { select(tab) } label: {
                    Image(systemName: tab.icon)
                        // Ikon digambar pada satu ukuran tetap lalu diskalakan. Ukuran font yang berubah tiap
                        // gerakan kursor membuat SwiftUI menyimpan ribuan salinan glyph (memori naik berjam-jam).
                        .font(.system(size: Self.peak * 0.46, weight: .semibold))
                        .scaleEffect(side / Self.peak)
                        .frame(width: side, height: side)
                        .background {
                            if glass { GlassTile(radius: side * 0.28, tint: tab == current ? Color.accent : nil) }
                            else { RoundedRectangle(cornerRadius: side * 0.28, style: .continuous).fill(tab == current ? Color.accent : Color(white: 0.2)) }
                        }
                        .foregroundStyle(.white)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .overlay(alignment: .top) {
                    if index == nearest {
                        Text(tab.label)
                            .font(.system(size: 10.5, weight: .semibold))
                            .lineLimit(1)
                            .fixedSize()
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(Color(white: 0.16)))
                            .foregroundStyle(.white)
                            .offset(y: -22)
                    }
                }
            }
        }
        .fixedSize()
    }

    private func centerX(_ index: Int) -> CGFloat { CGFloat(index) * (Self.base + Self.gap) + Self.base / 2 }
}

// MARK: - Beranda: deadline + catatan cepat

struct HomePanel: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var calendar: CalendarFeed

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AgendaList(model: model, calendar: calendar, rows: 3).frame(width: 318)
            QuickNote(model: model, compact: false)
        }
    }
}

/// Satu baris agenda: kegiatan/deadline Cognify atau acara Kalender macOS.
enum AgendaEntry: Identifiable {
    case cognify(NotchEvent)
    case calendar(CalendarEvent)

    var id: String {
        switch self {
        case .cognify(let e): return "c-" + e.id
        case .calendar(let e): return "k-" + e.id
        }
    }

    var date: Date {
        switch self {
        case .cognify(let e): return e.due
        case .calendar(let e): return e.start
        }
    }
}

struct AgendaList: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var calendar: CalendarFeed
    let rows: Int
    var compact = false

    private var entries: [AgendaEntry] {
        let cognify = model.appMode ? [] : (model.state?.events ?? []).map(AgendaEntry.cognify)
        let cal = model.features.calendar ? calendar.events.map(AgendaEntry.calendar) : []
        return (cognify + cal).sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: model.features.calendar ? L("Agenda", "Agenda") : L("Berikutnya", "Up next")).padding(.bottom, 2)
            if model.appMode && !model.features.calendar {
                Placeholder(icon: "calendar", text: L("Nyalakan Kalender lewat ikon notch di menu bar", "Turn on Calendar from the notch icon in the menu bar"))
            } else if model.appMode && entries.isEmpty {
                if calendar.access != .denied && calendar.reminderAccess != .denied {
                    Placeholder(icon: "checkmark.seal", text: L("Tidak ada acara hari ini & besok", "Nothing today or tomorrow"))
                }
            } else if model.appMode {
                agendaRows
            } else if !model.connected {
                Placeholder(icon: "hourglass", text: L("Menghubungkan ke Cognify…", "Connecting to Cognify…"))
            } else if !entries.isEmpty {
                agendaRows
            } else if model.state != nil {
                Placeholder(icon: "checkmark.seal", text: L("Tidak ada deadline 7 hari ke depan", "No deadlines in the next 7 days"))
            }
            if model.features.calendar && calendar.access == .denied {
                PermissionButton(
                    text: L("Izinkan Kalender untuk melihat acara", "Allow Calendar to see events"),
                    pane: "Privacy_Calendars")
            }
            if model.features.calendar && calendar.reminderAccess == .denied {
                PermissionButton(
                    text: L("Izinkan Pengingat untuk melihat pengingat terjadwal", "Allow Reminders to see scheduled reminders"),
                    pane: "Privacy_Reminders")
            }
            Spacer(minLength: 0)
            if !model.appMode, let processing = model.state?.processing, processing > 0 {
                HStack(spacing: 5) {
                    Spinner()
                    Text(L("Memproses \(processing) item…", "Processing \(processing) items…")).font(.system(size: 10.5))
                }
                .foregroundStyle(.white.opacity(0.55))
            }
        }
    }
}

/// Tombol yang langsung membuka panel Privasi yang tepat; macOS tidak menanyakan ulang izin yang sudah ditolak.
struct PermissionButton: View {
    let text: String
    let pane: String
    var body: some View {
        Button {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "lock.open").font(.system(size: 10))
                Text(text).font(.system(size: 10.5, weight: .medium))
            }
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(Capsule().fill(.white.opacity(0.14)))
            .foregroundStyle(.white.opacity(0.9))
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
    }
}

struct EventRow: View {
    let event: NotchEvent
    let now: Date
    var compact = false
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: event.kind == "deadline" ? "calendar.badge.clock" : "bell.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(soon ? Color.orange : Color.accent)
                    .frame(width: 24, height: 24)
                    .background(RoundedRectangle(cornerRadius: 7).fill((soon ? Color.orange : Color.accent).opacity(0.18)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    if compact {
                        Text([Relative.long(event.due, allDay: event.allDay, now: now), event.subtitle].compactMap { $0 }.joined(separator: " · "))
                            .font(.system(size: 10.5)).foregroundStyle(soon ? Color.orange : .white.opacity(0.5)).lineLimit(1)
                    } else if let subtitle = event.subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                if !compact {
                    Text(Relative.long(event.due, allDay: event.allDay, now: now))
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(soon ? Color.orange : .white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hover ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .notchHover { hover = $0 }
    }

    private var soon: Bool { !event.allDay && event.due.timeIntervalSince(now) < 60 * 60 }
}

extension AgendaList {
    var agendaRows: some View {
        ForEach(entries.prefix(rows)) { entry in
            switch entry {
            case .cognify(let event):
                EventRow(event: event, now: model.now, compact: compact) { model.open(event.path) }
            case .calendar(let event):
                CalendarRow(event: event, now: model.now, compact: compact,
                            join: { calendar.join(event); model.setExpanded(false) },
                            action: { calendar.openCalendarApp() })
            }
        }
    }
}

struct CalendarRow: View {
    let event: CalendarEvent
    let now: Date
    var compact = false
    var join: () -> Void = {}
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: action) {
                HStack(spacing: 9) {
                    RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 4, height: 24).frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(event.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                        Text("\(Relative.long(event.start, allDay: event.allDay, now: now)) · \(event.calendar)")
                            .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                        if compact, let description = event.notes?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
                            Text(description).font(.system(size: 9.5)).foregroundStyle(.white.opacity(0.62))
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 6)
                }
                .padding(.horizontal, 6).padding(.vertical, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Buka di app Kalender", "Open in Calendar"))
            if let link = event.link,
               let url = URL(string: link), url.scheme != nil {
                Button { NSWorkspace.shared.open(url) } label: {
                    Image(systemName: "link").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.62)).frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Buka tautan acara", "Open event link"))
            }
            if event.joinable(at: now) {
                Button(action: join) {
                    Label(compact ? "" : L("Gabung", "Join"), systemImage: "video.fill").labelStyle(.titleAndIcon)
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .padding(.trailing, 4)
                .help(L("Gabung rapat", "Join meeting"))
            }
        }
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hover || imminent ? 0.07 : 0)))
        .notchHover { hover = $0 }
    }

    /// Acara yang segera mulai atau sedang berlangsung diberi latar, seperti desain.
    private var imminent: Bool { !event.allDay && (event.joinable(at: now) || event.start.timeIntervalSince(now) < 60 * 60 && event.start > now) }
}

struct QuickNote: View {
    @ObservedObject var model: NotchModel
    var compact = false
    @FocusState private var focused: Bool
    @Environment(\.snapshot) private var snapshot
    @State private var currencyResult: String?
    @State private var currencyFailed = false

    /// Waktu yang terbaca dari catatan; pengingat dibuat saat Enter, kecuali dimatikan.
    private var reminder: ParsedTime? { model.features.todo ? TimeParser.parse(model.note) : nil }
    private var calcActive: Bool {
        model.features.calculator && (QuickCalc.currencyPair(model.note) != nil || QuickCalc.preview(model.note) != nil)
    }

    @ViewBuilder private var reminderLine: some View {
        if let reminder {
            if reminder.isPast {
                Label(L("Waktu sudah lewat, pengingat tidak dibuat", "Time has passed, no reminder"), systemImage: "clock.badge.exclamationmark")
                    .font(.system(size: 10.5)).foregroundStyle(Color.orange).lineLimit(1)
            } else {
                Button { model.noteReminderOff.toggle() } label: {
                    let when = Relative.long(reminder.date, allDay: false, now: model.now) + (reminder.tentative ? "?" : "")
                    Label(model.noteReminderOff ? L("Pengingat dimatikan", "Reminder off") : L("Pengingat: ", "Reminder: ") + when,
                          systemImage: model.noteReminderOff ? "bell.slash" : "bell.fill")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(model.noteReminderOff ? .white.opacity(0.4) : Color.accent)
                        .strikethrough(model.noteReminderOff)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .help(model.noteReminderOff ? L("Klik untuk menyalakan pengingat", "Click to turn the reminder on")
                                            : L("Dibuat saat Enter · klik untuk mematikan", "Created on Enter · click to turn off"))
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: L("Catatan cepat", "Quick note"))
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(focused ? 0.1 : 0.07))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accent.opacity(focused ? 0.7 : 0), lineWidth: 1))
                if snapshot {
                    Text(model.note.isEmpty ? L("Tulis sesuatu, tekan Enter…", "Type something, press Enter…") : model.note)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(model.note.isEmpty ? 0.4 : 1))
                        .padding(8)
                } else {
                    TextField(L("Tulis sesuatu, tekan Enter…", "Type something, press Enter…"), text: $model.note, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .lineLimit(compact ? 3 : 1, reservesSpace: compact)
                        .focused($focused)
                        .onSubmit { model.saveNote() }
                        .padding(8)
                        .padding(.trailing, compact ? 0 : 26)
                }
                if !compact && model.features.voice {
                    MicButton(voice: model.voice, toggle: model.toggleVoice)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                        .padding(.trailing, 8)
                }
            }
            .frame(height: compact ? 66 : 36)
            HStack(spacing: 5) {
                if model.features.calculator, QuickCalc.currencyPair(model.note) != nil {
                    if let currencyResult {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(currencyResult, forType: .string)
                            model.show(.done(L("Hasil disalin", "Result copied")))
                        } label: {
                            Text(currencyResult).font(.system(size: 11.5, weight: .bold, design: .rounded).monospacedDigit())
                                .foregroundStyle(Color.accent).lineLimit(1)
                        }
                        .buttonStyle(.plain)
                        .help(L("Kurs Yahoo Finance · klik untuk menyalin", "Yahoo Finance rate · click to copy"))
                    } else if currencyFailed {
                        Text(L("Kurs tidak tersedia", "Rate unavailable")).font(.system(size: 10.5))
                    } else {
                        Text(L("Mengambil kurs Yahoo…", "Fetching Yahoo rate…")).font(.system(size: 10.5))
                    }
                } else if model.features.calculator, let result = QuickCalc.preview(model.note) {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(result, forType: .string)
                        model.show(.done(L("Hasil disalin", "Result copied")))
                    } label: {
                        Text("= " + result).font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Color.accent).lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help(L("Klik untuk menyalin hasil", "Click to copy the result"))
                } else if reminder != nil {
                    reminderLine
                } else if !compact {
                    Text(model.savingNote ? L("Menyimpan…", "Saving…") : L("Enter menyimpan ke Catatan", "Enter saves to Notes")).font(.system(size: 10.5))
                }
                Spacer()
                if model.hub.linked {
                    Button(L("Jadikan dokumen", "Make doc")) { model.noteToDoc() }
                        .buttonStyle(PillButtonStyle(prominent: false))
                        .disabled(model.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if calcActive, reminder != nil { reminderLine }
                if compact {
                    if model.features.voice { MicButton(voice: model.voice, toggle: model.toggleVoice) }
                    Button(model.savingNote ? L("Menyimpan…", "Saving…") : L("Simpan", "Save")) { model.saveNote() }
                        .buttonStyle(PillButtonStyle(prominent: true))
                        .disabled(model.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.savingNote)
                }
            }
            .foregroundStyle(.white.opacity(0.5))
        }
        .onChange(of: model.note) { if $0.isEmpty { model.noteReminderOff = false } }
        .task(id: model.note) {
            currencyResult = nil
            currencyFailed = false
            guard !snapshot, model.features.calculator, let pair = QuickCalc.currencyPair(model.note) else { return }
            do {
                try await Task.sleep(nanoseconds: 400_000_000)
                let rate = try await YahooCurrencyRates.rate(from: pair.from, to: pair.to)
                guard !Task.isCancelled else { return }
                currencyResult = YahooCurrencyRates.format(pair.amount, from: pair.from, to: pair.to, rate: rate)
            } catch {
                if !Task.isCancelled { currencyFailed = true }
            }
        }
    }
}

// MARK: - Timer

/// Tiga kolom: cincin waktu (kiri), pengaturan mode & durasi (tengah), tombol mulai (kanan).
struct TimerPanel: View {
    @ObservedObject var timer: StudyTimer
    @Namespace private var segment

    var body: some View {
        HStack(alignment: .center, spacing: 22) {
            ring
            VStack(alignment: .leading, spacing: 11) {
                modePicker
                HStack(spacing: 10) {
                    stepper
                    presets
                }
                sessions
            }
            .disabled(timer.running)
            .opacity(timer.running ? 0.55 : 1)
            .animation(.notch, value: timer.running)
            Spacer(minLength: 0)
            controls
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
    }

    private var tint: Color { timer.mode == .focus ? .accent : .green }

    // Cincin + sisa waktu (+ jam selesai saat berjalan).
    private var ring: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 7)
            Circle()
                .trim(from: 0, to: timer.progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.25), value: timer.progress)
            VStack(spacing: 2) {
                Text(StudyTimer.clock(timer.remaining))
                    .font(.system(size: 27, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text(timer.running ? L("Selesai ", "Ends ") + Self.endTime(timer.remaining) : timer.mode.label)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(timer.running ? tint : .white.opacity(0.5))
            }
        }
        .frame(width: 124, height: 124)
    }

    // Fokus | Istirahat, penanda bergeser di antara keduanya.
    private var modePicker: some View {
        HStack(spacing: 0) {
            ForEach(StudyTimer.Mode.allCases, id: \.self) { mode in
                let selected = timer.mode == mode
                Button { withAnimation(.notch) { timer.select(mode) } } label: {
                    HStack(spacing: 5) {
                        Image(systemName: mode == .focus ? "brain.head.profile" : "cup.and.saucer.fill").font(.system(size: 10))
                        Text(mode.label).font(.system(size: 11.5, weight: .semibold))
                        Text("\(timer.minutes(mode))m").font(.system(size: 10.5, weight: .medium).monospacedDigit())
                            .foregroundStyle(.white.opacity(selected ? 0.8 : 0.45))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background {
                        if selected {
                            Capsule().fill(mode == .focus ? Color.accent : Color.green.opacity(0.85))
                                .matchedGeometryEffect(id: "mode", in: segment)
                        }
                    }
                    .foregroundStyle(.white.opacity(selected ? 1 : 0.6))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    // − 25 menit +
    private var stepper: some View {
        let step = timer.mode == .focus ? 5 : 1
        return HStack(spacing: 0) {
            Button { timer.adjust(by: -step) } label: {
                Image(systemName: "minus").font(.system(size: 10, weight: .bold)).frame(width: 26, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .help(L("Kurangi \(step) menit", "\(step) min shorter"))
            Text(L("\(timer.minutes(timer.mode)) menit", "\(timer.minutes(timer.mode)) min"))
                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                .frame(minWidth: 62)
            Button { timer.adjust(by: step) } label: {
                Image(systemName: "plus").font(.system(size: 10, weight: .bold)).frame(width: 26, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .help(L("Tambah \(step) menit", "\(step) min longer"))
        }
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    // 25/5 · 50/10 · 90/15
    private var presets: some View {
        HStack(spacing: 2) {
            ForEach(StudyTimer.presets, id: \.focus) { preset in
                let selected = timer.focusMinutes == preset.focus && timer.restMinutes == preset.rest
                Button { withAnimation(.notch) { timer.setMinutes(focus: preset.focus, rest: preset.rest) } } label: {
                    Text("\(preset.focus)/\(preset.rest)")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Capsule().stroke(Color.white.opacity(selected ? 0.35 : 0), lineWidth: 1))
                        .foregroundStyle(.white.opacity(selected ? 0.95 : 0.45))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Satu titik per sesi fokus hari ini.
    private var sessions: some View {
        HStack(spacing: 7) {
            HStack(spacing: 4) {
                ForEach(0..<max(4, min(8, timer.sessionsToday)), id: \.self) { i in
                    Circle().fill(i < timer.sessionsToday ? Color.accent : Color.white.opacity(0.14)).frame(width: 6, height: 6)
                }
            }
            Text(timer.sessionsToday == 0 ? L("Belum ada sesi fokus hari ini", "No focus sessions yet today")
                                          : L("\(timer.sessionsToday) sesi fokus hari ini", "\(timer.sessionsToday) focus sessions today"))
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // Tombol mulai/jeda besar + ulang.
    private var controls: some View {
        VStack(spacing: 10) {
            Button(action: { timer.toggle() }) {
                Image(systemName: timer.running ? "pause.fill" : "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .offset(x: timer.running ? 0 : 2)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(tint))
                    .shadow(color: tint.opacity(0.45), radius: 10, y: 3)
                    .contentShape(Circle())
            }
            .buttonStyle(PressableStyle())
            .help(timer.running ? L("Jeda", "Pause") : (timer.isIdle ? L("Mulai", "Start") : L("Lanjut", "Resume")))
            Button(action: { timer.reset() }) {
                Label(L("Ulang", "Reset"), systemImage: "arrow.counterclockwise")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(timer.isIdle ? 0.3 : 0.7))
            }
            .buttonStyle(.plain)
            .disabled(timer.isIdle)
        }
        .padding(.trailing, 6)
    }

    private static func endTime(_ remaining: TimeInterval) -> String {
        let f = DateFormatter()
        f.dateFormat = Lang.english ? "h:mm a" : "HH.mm"
        return f.string(from: Date().addingTimeInterval(remaining))
    }
}

// MARK: - Catatan (app mandiri)

struct NotesPanel: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var notes: LocalNotes
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                SectionLabel(text: notes.items.isEmpty ? L("Catatan", "Notes") : L("Catatan", "Notes") + " · \(notes.items.count)")
                if !snapshot { addField }
            }
            if notes.items.isEmpty {
                Placeholder(icon: "note.text", text: L("Belum ada catatan. Tulis di kolom di atas lalu tekan Enter.", "No notes yet. Type above and press Enter."))
            } else if snapshot {
                list
            } else {
                ScrollView(.vertical, showsIndicators: false) { list }
            }
        }
    }

    @State private var draft = ""
    @State private var savingDraft = false
    @FocusState private var focused: Bool

    /// Tulis catatan langsung di halaman ini (Enter menyimpan).
    private var addField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.45))
            TextField(L("Tambah catatan…", "Add a note…"), text: $draft)
                .textFieldStyle(.plain).font(.system(size: 11.5)).focused($focused)
                .onSubmit(add)
            if !draft.trimmingCharacters(in: .whitespaces).isEmpty || savingDraft {
                Button(savingDraft ? L("Mengambil kurs…", "Fetching rate…") : L("Simpan", "Save"), action: add)
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(savingDraft)
            }
        }
        .padding(.horizontal, 10).frame(height: 26)
        .background(Capsule().fill(Color.white.opacity(focused ? 0.12 : 0.08)))
        .overlay(Capsule().stroke(Color.accent.opacity(focused ? 0.7 : 0), lineWidth: 1))
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !savingDraft else { return }
        draft = ""
        guard model.features.calculator, let pair = QuickCalc.currencyPair(text) else {
            notes.add(model.features.calculator ? QuickCalc.annotated(text) : text)
            model.show(.done(L("Catatan tersimpan", "Note saved")))
            return
        }
        savingDraft = true
        Task {
            defer { savingDraft = false }
            let noteText: String
            do {
                let rate = try await YahooCurrencyRates.rate(from: pair.from, to: pair.to)
                noteText = text + "\n= " + YahooCurrencyRates.format(pair.amount, from: pair.from, to: pair.to, rate: rate)
            } catch {
                noteText = text + "\n= " + L("Kurs tidak tersedia", "Rate unavailable")
            }
            notes.add(noteText)
            model.show(.done(L("Catatan tersimpan", "Note saved")))
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(notes.items) { note in NoteRow(note: note, notes: notes, model: model) }
        }
    }
}

struct NoteRow: View {
    let note: LocalNote
    @ObservedObject var notes: LocalNotes
    @ObservedObject var model: NotchModel
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(note.text).font(.system(size: 12)).lineLimit(2)
                Text(Self.format(note.date)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }
            Spacer(minLength: 8)
            if hover {
                Button { notes.copy(note); model.show(.done(L("Catatan disalin", "Note copied"))) } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).help(L("Salin", "Copy"))
                if model.hub.linked {
                    Button { model.noteToDoc(note.text) } label: { Image(systemName: "doc.badge.plus") }
                        .buttonStyle(.plain).help(L("Jadikan dokumen di Cognify", "Make a Cognify doc"))
                }
                Button { notes.remove(note) } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).help(L("Hapus", "Delete"))
            }
        }
        .font(.system(size: 11.5))
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hover ? 0.1 : 0.06)))
        .notchHover { hover = $0 }
    }

    static func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Lang.english ? "en_US" : "id_ID")
        f.dateFormat = Calendar.current.isDateInToday(date) ? (Lang.english ? "'Today' h:mm a" : "'Hari ini' HH.mm") : (Lang.english ? "EEE MMM d, h:mm a" : "EEE d MMM, HH.mm")
        return f.string(from: date)
    }
}

// MARK: - Pesan

extension NotchModel.Toast {
    /// Pesan yang menggantikan isi panel saat notch terbuka (selain status "sedang menyimpan").
    var isBanner: Bool {
        if case .working = self { return false }
        return true
    }
}

struct ToastBanner: View {
    @ObservedObject var model: NotchModel
    let toast: NotchModel.Toast

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 48, height: 48)
                .background(Circle().fill(tint.opacity(0.18)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                if let detail { Text(detail).font(.system(size: 11.5)).foregroundStyle(.white.opacity(0.6)).lineLimit(2) }
            }
            Spacer(minLength: 8)
            if case .alert(_, _, let action?) = toast {
                switch action {
                case .startTimer(let label):
                    Button(label) { model.toast = nil; model.timer.start() }.buttonStyle(PillButtonStyle(prominent: true, large: true))
                case .drink:
                    Button(L("Minum \(model.water.glass) ml", "Drink \(model.water.glass) ml")) { model.toast = nil; model.water.drink(); model.setExpanded(false) }
                        .buttonStyle(PillButtonStyle(prominent: true, large: true))
                case .todoDone(let id):
                    Button(L("Selesai", "Done")) { model.toast = nil; model.todo.toggle(id); model.setExpanded(false) }
                        .buttonStyle(PillButtonStyle(prominent: true, large: true))
                case .join(let url):
                    Button(L("Gabung", "Join")) { model.toast = nil; NSWorkspace.shared.open(url); model.setExpanded(false) }
                        .buttonStyle(PillButtonStyle(prominent: true, large: true))
                case .open(let path):
                    Button(L("Buka", "Open")) { model.toast = nil; model.open(path) }.buttonStyle(PillButtonStyle(prominent: true, large: true))
                case .openApp(let bundle):
                    Button(L("Buka", "Open")) {
                        model.toast = nil
                        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
                        model.setExpanded(false)
                    }.buttonStyle(PillButtonStyle(prominent: true, large: true))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 8)
    }

    private var icon: String {
        switch toast {
        case .done: return "checkmark"
        case .failed: return "exclamationmark.triangle.fill"
        case .alert(_, _, .startTimer?): return "timer"
        case .alert(_, _, .join?): return "video.fill"
        case .alert(_, _, .drink?): return "drop.fill"
        case .alert(_, _, .todoDone?): return "checklist"
        case .alert(_, _, .openApp?): return "message.fill"
        default: return "bell.fill"
        }
    }

    private var tint: Color {
        switch toast {
        case .done: return .green
        case .failed: return .orange
        default: return .accent
        }
    }

    private var title: String {
        switch toast {
        case .done(let text), .failed(let text), .working(let text): return text
        case .alert(let title, _, _): return title
        }
    }

    private var detail: String? {
        if case .alert(_, let detail, _) = toast { return detail }
        if case .failed = toast { return model.appMode ? nil : L("Coba lagi, atau buka Cognify untuk detailnya.", "Try again, or open Cognify for details.") }
        return nil
    }
}

// MARK: - Komponen kecil

/// Spinner kecil tanpa komponen AppKit (ProgressView tidak ikut terender di snapshot).
struct Spinner: View {
    @State private var spin = false
    var body: some View {
        Circle()
            .trim(from: 0.15, to: 1)
            .stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
            .frame(width: 10, height: 10)
            .rotationEffect(.degrees(spin ? 360 : 0))
            .onAppear { withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) { spin = true } }
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.white.opacity(0.42))
            .padding(.leading, 6)
    }
}

struct Placeholder: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 12))
            Text(text).font(.system(size: 11.5))
        }
        .foregroundStyle(.white.opacity(0.5))
        .padding(.leading, 6).padding(.top, 4)
    }
}

struct PillButtonStyle: ButtonStyle {
    var prominent: Bool
    var large = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: large ? 12 : 11, weight: .semibold))
            .padding(.horizontal, large ? 14 : 10)
            .padding(.vertical, large ? 7 : 4)
            .background(Capsule().fill(prominent ? Color.accent.opacity(enabled ? 0.9 : 0.35) : Color.white.opacity(0.12)))
            .foregroundStyle(.white.opacity(enabled ? 1 : 0.5))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

// MARK: - Isi yang diseret

enum DropLoader {
    /// File lokal, tautan web, dan teks biasa dari item yang diseret (Finder, browser, editor).
    static func load(_ providers: [NSItemProvider], done: @escaping ([URL], [URL], [String]) -> Void) {
        var files: [URL] = [], links: [URL] = [], texts: [String] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for provider in providers {
            group.enter()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, url.isFileURL { lock.lock(); files.append(url); lock.unlock() }
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") { lock.lock(); links.append(url); lock.unlock() }
                    group.leave()
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    lock.lock()
                    if let url = URL(string: clean), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), !clean.contains(" ") {
                        links.append(url)
                    } else if !clean.isEmpty {
                        texts.append(clean)
                    }
                    lock.unlock()
                    group.leave()
                }
            } else {
                group.leave()
            }
        }
        group.notify(queue: .main) { done(files, links, texts) }
    }
}
