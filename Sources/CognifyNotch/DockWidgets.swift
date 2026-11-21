import AppKit
import NotchDock
import SwiftUI

// Widget di dock (lagu, cuaca, timer cepat, salinan terakhir). Lebar tiap widget tetap (DockModule.width), sama dengan
// yang dihitung NotchDock, jadi dock tidak pernah melewati layar. Radius turunan dari satu rumus (dockRadii).

/// Tombol kapsul: tinggi tetap, menyorot saat disentuh kursor.
struct DockPill<Label: View>: View {
    let width: CGFloat?
    let radius: CGFloat
    let help: String
    let action: () -> Void
    @ViewBuilder let label: () -> Label
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(width: width, height: DockMetrics.pillH)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.primary.opacity(0.1)))
                .scaleEffect(hover ? 1.1 : 1)
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) { hover = h } }
        .help(help)
    }
}

/// Tombol ikon bulat (tinggi dan lebar `DockMetrics.toolSize`).
struct DockTool: View {
    let symbol: String
    let radius: CGFloat
    let help: String
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.primary)
                .frame(width: DockMetrics.toolSize, height: DockMetrics.toolSize)
                .background(RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color.primary.opacity(0.12)))
                .scaleEffect(hover ? 1.18 : 1)
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { h in withAnimation(.spring(response: 0.28, dampingFraction: 0.62)) { hover = h } }
        .help(help)
    }
}

struct DockModuleView: View {
    let module: DockModule
    /// Bukan @ObservedObject (lihat DockView); hanya `features` yang diikuti, karena menentukan isi beberapa widget.
    let app: NotchModel
    @State private var features: NotchModel.Features
    let cfg: DockConfig
    let cell: CGFloat
    let r: DockRadii

    init(module: DockModule, app: NotchModel, cfg: DockConfig, cell: CGFloat, r: DockRadii) {
        self.module = module; self.app = app; self.cfg = cfg; self.cell = cell; self.r = r
        _features = State(initialValue: app.features)
    }

    var body: some View {
        Group {
            switch module {
            case .media: DockMediaWidget(media: app.media, r: r)
            case .weather: DockWeatherWidget(weather: app.weather, enabled: features.weather)
            case .timer: DockTimerWidget(clock: app.clock, r: r)
            case .clipboard: DockClipboardWidget(history: app.clipboard, r: r)
            case .lyrics: DockLyricsWidget(lyrics: app.lyrics, media: app.media, enabled: features.lyrics && features.media)
            case .battery: DockBatteryWidget()
            case .volume: DockVolumeWidget(r: r)
            case .links: DockLinksWidget(prefs: app.prefs, cfg: cfg, cell: cell, r: r, openSettings: { app.onOpenSettings?() })
            }
        }
        .frame(width: module.width(links: cfg.links, iconSize: cfg.iconSize), height: cell)
        .onReceive(app.$features) { if $0 != features { features = $0 } }
    }
}

struct DockMediaWidget: View {
    @ObservedObject var media: MediaMonitor
    let r: DockRadii

    var body: some View {
        HStack(spacing: 8) {
            art
            VStack(alignment: .leading, spacing: 1) {
                Text(media.nowPlaying?.title ?? L("Tidak ada yang diputar", "Nothing playing"))
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(media.nowPlaying?.artist ?? " ").font(.system(size: 10)).foregroundStyle(Color.primary.opacity(0.65)).lineLimit(1)
                progress
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                control("backward.fill", help: L("Sebelumnya", "Previous")) { media.previous() }
                control(media.nowPlaying?.playing == true ? "pause.fill" : "play.fill", help: L("Putar atau jeda", "Play or pause")) { media.toggle() }
                control("forward.fill", help: L("Berikutnya", "Next")) { media.next() }
            }
            .opacity(media.nowPlaying == nil ? 0.4 : 1)
            .disabled(media.nowPlaying == nil)
        }
        .padding(.horizontal, 4)
    }

    private func control(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        DockTool(symbol: symbol, radius: r.tool, help: help, action: action)
    }

    /// Waktu berjalan, garis kemajuan (klik untuk melompat), dan durasi.
    private var progress: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let now = media.nowPlaying
            let pos = now?.position(at: ctx.date) ?? 0
            let ratio = DockMediaTime.ratio(position: pos, duration: now?.duration)
            HStack(spacing: 5) {
                Text(DockMediaTime.label(pos)).frame(minWidth: 24, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.primary.opacity(0.16)).frame(height: 3)
                        Capsule().fill(Color.accent).frame(width: geo.size.width * ratio, height: 3)
                    }
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture { location in
                        if let d = now?.duration, d > 0 { media.seek(to: Double(location.x / max(1, geo.size.width)) * d) }
                    }
                }
                .frame(height: 12)
                Text(now?.duration.map { DockMediaTime.label($0) } ?? "–:––").frame(minWidth: 24, alignment: .trailing)
            }
            .font(.system(size: 9.5).monospacedDigit())
            .foregroundStyle(Color.primary.opacity(0.6))
        }
    }

    @ViewBuilder private var art: some View {
        let size = DockMetrics.toolSize
        Group {
            if let img = media.artwork ?? media.appIcon {
                Image(nsImage: img).resizable().interpolation(.high).scaledToFill()
            } else {
                Image(systemName: "music.note").foregroundStyle(Color.primary.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .background(Color.primary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: r.tool, style: .continuous))
    }
}

struct DockWeatherWidget: View {
    @ObservedObject var weather: WeatherFeed
    let enabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: weather.now?.symbol ?? "cloud.sun.fill").font(.system(size: 16)).symbolRenderingMode(.multicolor)
            Text(weather.now.map { "\($0.temperature)°" } ?? "–").font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Color.primary)
        }
        .help(weather.now?.place ?? (enabled ? L("Cuaca belum tersedia", "Weather not available yet") : L("Nyalakan Cuaca di Pengaturan > Cuaca", "Turn on Weather in Settings > Weather")))
    }
}

struct DockTimerWidget: View {
    @ObservedObject var clock: ClockTools
    let r: DockRadii
    static let presets = [5, 15, 25]

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "timer").font(.system(size: 15)).foregroundStyle(Color.primary.opacity(0.8)).frame(width: 15)
            if let c = clock.countdowns.first {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(ClockTools.clock(max(0, c.end.timeIntervalSince(ctx.date)))).font(.system(size: 15, weight: .semibold).monospacedDigit()).foregroundStyle(Color.primary)
                }
                Spacer(minLength: 0)
                DockTool(symbol: "xmark", radius: r.tool, help: L("Batalkan timer", "Cancel timer")) { clock.cancel(c.id) }
            } else {
                HStack(spacing: 4) {
                    ForEach(Self.presets, id: \.self) { m in
                        DockPill(width: 46, radius: r.pill, help: L("Timer \(m) menit", "\(m) minute timer")) { clock.start(minutes: m) } label: {
                            Text("\(m)m").font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.primary)
                        }
                    }
                }
            }
        }
        .padding(.leading, 4)
    }
}

struct DockClipboardWidget: View {
    @ObservedObject var history: ClipboardHistory
    let r: DockRadii

    var body: some View {
        let items = Array(history.items.filter { $0.kind != .image && ($0.text ?? "").isEmpty == false }.prefix(3))
        HStack(spacing: 4) {
            if items.isEmpty {
                Text(L("Belum ada salinan", "Nothing copied yet")).font(.system(size: 11)).foregroundStyle(Color.primary.opacity(0.6)).frame(maxWidth: .infinity)
            }
            ForEach(items) { item in
                DockPill(width: 72, radius: r.pill, help: item.text ?? "") { history.copy(item) } label: {
                    Text((item.text ?? "").replacingOccurrences(of: "\n", with: " ")).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                        .foregroundStyle(Color.primary).padding(.horizontal, 8)
                }
            }
        }
        .padding(.horizontal, 2)
    }
}

struct DockLyricsWidget: View {
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var media: MediaMonitor
    let enabled: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { ctx in
            Text(line(at: ctx.date))
                .font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1).truncationMode(.tail)
                .foregroundStyle(Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
        }
        // Lirik hanya diminta bila fitur Lirik menyala (internet, lihat LyricsService); judul dan artis lagu dikirim ke LRCLIB.
        .onAppear { if enabled { lyrics.load(for: media.nowPlaying) } }
        .onChange(of: media.nowPlaying?.title) { _ in if enabled { lyrics.load(for: media.nowPlaying) } }
    }

    private func line(at date: Date) -> String {
        guard enabled else { return L("Nyalakan Lirik di Pengaturan > Fitur", "Turn on Lyrics in Settings > Features") }
        guard media.nowPlaying != nil else { return "♪" }
        if case .synced(let lines) = lyrics.state, let position = media.nowPlaying?.position(at: date) {
            let text = lines.last { $0.time <= position + 0.25 }?.text ?? ""
            return text.isEmpty ? "♪" : text
        }
        return "♪"
    }
}

struct DockBatteryWidget: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            let b = PowerMonitor.current()
            HStack(spacing: 4) {
                Image(systemName: symbol(b)).font(.system(size: 14)).foregroundStyle(Color.primary)
                Text(b.map { "\($0.percent)%" } ?? "AC").font(.system(size: 12, weight: .semibold).monospacedDigit()).foregroundStyle(Color.primary)
            }
            .help(b == nil ? L("Mac ini tidak punya baterai", "This Mac has no battery") : (b!.charging ? L("Mengisi daya", "Charging") : L("Memakai baterai", "On battery")))
        }
    }

    private func symbol(_ b: NotchModel.Battery?) -> String {
        guard let b else { return "powerplug.fill" }
        if b.charging { return "battery.100.bolt" }
        switch b.percent { case ..<13: return "battery.0"; case ..<38: return "battery.25"; case ..<63: return "battery.50"; case ..<88: return "battery.75"; default: return "battery.100" }
    }
}

struct DockVolumeWidget: View {
    let r: DockRadii
    @State private var volume: Double = 0.5
    @State private var before: Double = 0.5
    @State private var editing = false

    var body: some View {
        HStack(spacing: 6) {
            DockTool(symbol: volume <= 0.001 ? "speaker.slash.fill" : volume < 0.5 ? "speaker.wave.1.fill" : "speaker.wave.2.fill", radius: r.tool,
                     help: L("Bisukan atau nyalakan", "Mute or unmute")) { toggleMute() }
            Slider(value: Binding(get: { volume }, set: { volume = $0; AudioOutputs.setVolume(Float($0)) }), in: 0...1) { editing = $0 }
                .controlSize(.mini)
                .frame(width: 52)
        }
        .padding(.horizontal, 2)
        .onAppear { read() }
        // Ikut berubah bila volume diubah dari tombol keyboard.
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in if !editing { read() } }
    }

    private func read() { if let v = AudioOutputs.volume() { volume = Double(v) } }

    private func toggleMute() {
        if volume > 0.001 { before = volume; volume = 0 } else { volume = max(0.1, before) }
        AudioOutputs.setVolume(Float(volume))
    }
}

struct DockLinksWidget: View {
    @ObservedObject var prefs: Preferences
    let cfg: DockConfig
    let cell: CGFloat
    let r: DockRadii
    let openSettings: () -> Void

    var body: some View {
        HStack(spacing: DockMetrics.cellGap) {
            if prefs.dockLinks.isEmpty {
                HoverCell(cell: cell, radius: r.cell, help: L("Tambah tautan di Pengaturan > Dock", "Add links in Settings > Dock"), action: openSettings) {
                    tile(Image(systemName: "plus"), color: .gray.opacity(0.5))
                }
            }
            ForEach(prefs.dockLinks) { link in
                HoverCell(cell: cell, radius: r.cell, help: link.label + " · " + link.url, action: {
                    if let u = URL(string: link.url) { NSWorkspace.shared.open(u) }
                }) {
                    tile(Text(String(link.label.prefix(1)).uppercased()).font(.system(size: cfg.iconSize * 0.45, weight: .bold)), color: Color(hue: DockLinks.hue(link.label) / 360, saturation: 0.55, brightness: 0.55))
                }
                .contextMenu {
                    Button(L("Hapus tautan", "Remove link")) { prefs.dockLinks.removeAll { $0.id == link.id } }
                }
            }
        }
    }

    private func tile<V: View>(_ content: V, color: Color) -> some View {
        content.foregroundStyle(.white)
            .frame(width: cfg.iconSize, height: cfg.iconSize)
            .background(RoundedRectangle(cornerRadius: r.tile, style: .continuous).fill(color))
    }
}
