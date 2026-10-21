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
            ZStack(alignment: .top) {
                NotchShape(top: model.expanded ? 12 : 6, bottom: model.expanded ? 24 : 12)
                    .fill(Color.black)
                    .shadow(color: .black.opacity(model.expanded ? 0.45 : 0), radius: 16, y: 6)
                content
                    .padding(.horizontal, model.expanded ? 12 : 6) // di dalam lengkungan atas
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .clipShape(NotchShape(top: model.expanded ? 12 : 6, bottom: model.expanded ? 24 : 12))
            }
            .frame(width: model.size.width, height: model.size.height)
            .offset(x: model.shapeOffset)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .onChange(of: model.dropTargeted) { targeted in
            if targeted { model.setExpanded(true) }
        }
    }

    @ViewBuilder private var content: some View {
        if model.expanded {
            // Ukuran "Besar": isi digambar pada ukuran normal lalu diperbesar dari atas.
            let scale = CGFloat(model.prefs.scale)
            ExpandedView(model: model)
                .frame(width: (model.size.width - 24) / scale, height: model.size.height / scale)
                .scaleEffect(scale, anchor: .top)
                .frame(width: model.size.width - 24, height: model.size.height, alignment: .top)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .top)).animation(.notch.delay(0.06)),
                    removal: .opacity.animation(.easeOut(duration: 0.12))
                ))
        } else if let card = model.card {
            NoticeCard(card: card, notchHeight: model.notchSize.height)
                .transition(.opacity.combined(with: .scale(scale: 0.94, anchor: .top)))
        } else if let live = model.live {
            LiveWings(live: live, gap: model.notchSize.width, wings: model.wings, media: model.media, spectrum: model.spectrum,
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
    var face: NotchModel.Face? = nil
    var lyrics: LyricsService? = nil
    var onBannerDone: (String) -> Void = { _ in }

    var body: some View {
        if live.eyes {
            // Notch fisik sebagai wajah: satu mata di tiap sisinya.
            HStack(spacing: 0) {
                if let face {
                    Eye(face: face, right: false).frame(width: max(0, wings.left - 6), alignment: .trailing)
                    Color.clear.frame(width: gap)
                    Eye(face: face, right: true).frame(width: max(0, wings.right - 6), alignment: .leading)
                }
            }
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
            .foregroundStyle(.white)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(text)
            .transition(.asymmetric(insertion: .opacity.combined(with: .offset(y: 6)), removal: .opacity))
            .animation(.easeOut(duration: 0.25), value: text)
    }
}

/// Satu mata. Terbuka (berkedip sesekali), tertutup saat tidur (dengan "z" kecil), dan
/// melengkung senang saat menyapa.
struct Eye: View {
    @ObservedObject var face: NotchModel.Face
    let right: Bool

    var body: some View {
        let mood = face.mood
        ZStack {
            switch mood {
            case .awake, .blink:
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 8, height: mood == .blink ? 1.5 : 12)
                    .shadow(color: Color.accent.opacity(0.9), radius: 4)
            case .asleep:
                Capsule().fill(Color.white.opacity(0.75)).frame(width: 9, height: 2).offset(y: 2)
                if right {
                    Text("z").font(.system(size: 8, weight: .heavy, design: .rounded)).foregroundStyle(.white.opacity(0.6))
                        .offset(x: 9, y: -6)
                }
            case .hello:
                Image(systemName: "chevron.up").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                    .shadow(color: Color.accent.opacity(0.9), radius: 4)
            }
        }
        .frame(width: 14, height: 16)
        .padding(.horizontal, 4)
    }
}

/// Kartu kabar di bawah notch fisik: ikon, judul, keterangan, dan nilai (mis. persen baterai).
struct NoticeCard: View {
    let card: NotchModel.Card
    let notchHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: notchHeight)
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
                            insertion: .opacity.combined(with: .offset(x: model.pageForward ? 24 : -24)),
                            removal: .opacity.animation(.easeOut(duration: 0.1))))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.top, 8)
            if !model.dropTargeted, !(model.toast?.isBanner ?? false) {
                PageDock(tabs: model.tabs, current: model.tab) { model.go(to: $0) }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .zIndex(1) // ikon yang membesar boleh menutupi isi halaman di atasnya
            } else {
                Spacer().frame(height: 12)
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder private var page: some View {
        switch model.tab {
        case .home: HomePanel(model: model, calendar: model.calendar)
        case .music: MusicPanel(model: model, media: model.media)
        case .clock: ClockPanel(clock: model.clock)
        case .water: WaterPanel(water: model.water)
        case .todo: TodoPanel(model: model, todo: model.todo)
        case .notes: NotesPanel(model: model, notes: model.notes)
        case .clipboard: ClipboardPanel(model: model, history: model.clipboard)
        case .tray: TrayPanel(model: model, tray: model.tray)
        case .timer: TimerPanel(timer: model.timer)
        case .mirror: MirrorPanel(camera: model.camera)
        case .shortcuts: ShortcutsPanel(model: model, shortcuts: model.shortcuts)
        }
    }

    /// Baris setinggi notch: judul halaman di kiri notch fisik; tanggal, jam, baterai, dan
    /// equalizer di kanannya. Tengahnya (notch fisik) dibiarkan kosong.
    private var header: some View {
        GeometryReader { geo in
            // Lebar notch fisik dalam koordinat isi (isi diperbesar `scale` kali saat ukuran Besar).
            let gap = model.notchSize.width / CGFloat(model.prefs.scale) + 10
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
                    if let battery = model.battery { BatteryRing(battery: battery) }
                    Text(Self.dateTime(model.now))
                        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
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

    var body: some View {
        let tint: Color = battery.charging ? .green : battery.percent <= 20 ? .red : .white
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 2.2)
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
        .animation(.notch, value: current)
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
                        .background(RoundedRectangle(cornerRadius: side * 0.28, style: .continuous)
                            .fill(tab == current ? Color.accent : Color(white: 0.2)))
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
                if calendar.access != .denied { Placeholder(icon: "checkmark.seal", text: L("Tidak ada acara hari ini & besok", "Nothing today or tomorrow")) }
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
                Text(L("Izinkan Kalender di Pengaturan Sistem → Privasi untuk melihat acaramu di sini.", "Allow Calendar in System Settings → Privacy to see your events here."))
                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45)).padding(.leading, 6)
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
                CalendarRow(event: event, now: model.now, compact: compact, join: { calendar.join(event); model.setExpanded(false) }) {
                    calendar.openCalendarApp()
                }
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
        Button(action: action) {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 2).fill(event.color).frame(width: 4, height: 24).frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(event.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Text(compact ? "\(Relative.long(event.start, allDay: event.allDay, now: now)) · \(event.calendar)" : event.calendar)
                        .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                }
                Spacer(minLength: 6)
                if event.joinable(at: now) {
                    Button(action: join) {
                        Label(compact ? "" : L("Gabung", "Join"), systemImage: "video.fill").labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .help(L("Gabung rapat", "Join meeting"))
                } else if !compact {
                    Text(Relative.long(event.start, allDay: event.allDay, now: now))
                        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(hover ? 0.08 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .notchHover { hover = $0 }
        .help(L("Buka app Kalender", "Open Calendar"))
    }
}

struct QuickNote: View {
    @ObservedObject var model: NotchModel
    var compact = false
    @FocusState private var focused: Bool
    @Environment(\.snapshot) private var snapshot

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
                        .lineLimit(3, reservesSpace: true)
                        .focused($focused)
                        .onSubmit { model.saveNote() }
                        .padding(8)
                }
            }
            .frame(height: 66)
            HStack(spacing: 5) {
                if model.features.calculator, let result = QuickCalc.evaluate(model.note) {
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
                } else if !compact {
                    Image(systemName: "tray.and.arrow.down").font(.system(size: 10))
                    Text(model.appMode ? L("Seret file ke notch → tray", "Drop files on the notch → tray") : L("Seret file atau tautan ke notch", "Drop files or links on the notch")).font(.system(size: 10.5))
                }
                Spacer()
                if model.features.voice { MicButton(voice: model.voice, toggle: model.toggleVoice) }
                Button(model.savingNote ? L("Menyimpan…", "Saving…") : L("Simpan", "Save")) { model.saveNote() }
                    .buttonStyle(PillButtonStyle(prominent: true))
                    .disabled(model.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.savingNote)
            }
            .foregroundStyle(.white.opacity(0.5))
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
            SectionLabel(text: notes.items.isEmpty ? L("Catatan", "Notes") : L("Catatan", "Notes") + " · \(notes.items.count)")
            if notes.items.isEmpty {
                Placeholder(icon: "note.text", text: L("Belum ada catatan. Tulis di Beranda → Catatan cepat.", "No notes yet. Write one in Home → Quick note."))
            } else if snapshot {
                list
            } else {
                ScrollView(.vertical, showsIndicators: false) { list }
            }
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
