import AppKit
import SwiftUI

/// Lagu/video yang sedang diputar di app mana pun (Spotify, Apple Music, YouTube di browser, VLC…).
struct NowPlaying: Equatable {
    var title: String
    var artist: String?
    var album: String?
    var duration: Double?
    var elapsed: Double?
    var rate: Double
    var timestamp: Date?
    var playing: Bool
    var bundle: String?

    /// Posisi saat ini (detik), dihitung dari posisi terakhir yang dilaporkan + waktu berjalan.
    func position(at date: Date) -> Double? {
        guard let elapsed else { return nil }
        guard playing, let timestamp else { return elapsed }
        let value = elapsed + date.timeIntervalSince(timestamp) * max(rate, 0)
        return duration.map { min(value, $0) } ?? value
    }
}

/// Menjalankan `libcognify-media.dylib` di dalam /usr/bin/perl (satu-satunya jalan membaca
/// MediaRemote sejak macOS 15.4, lihat CognifyMedia.m) dan membaca laporannya baris per baris.
@MainActor
final class MediaMonitor: ObservableObject {
    @Published private(set) var nowPlaying: NowPlaying?
    @Published private(set) var artwork: NSImage?
    /// Helper gagal berjalan (mis. Apple menutup celahnya): bagian media disembunyikan.
    @Published private(set) var unavailable = false

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var enabled = false
    private var failures = 0

    static var library: URL? {
        let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().deletingLastPathComponent()
        return [exe.appendingPathComponent("libcognify-media.dylib"),                       // dev: .build/release
                exe.appendingPathComponent("../Frameworks/libcognify-media.dylib")]          // Cognify.app
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Muat library, lalu panggil `cognify_media_run` sebagai fungsi XS (cara mediaremote-adapter).
    static let perlScript = """
        use DynaLoader;
        my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or die DynaLoader::dl_error();
        my $sym = DynaLoader::dl_find_symbol($lib, "cognify_media_run") or die DynaLoader::dl_error();
        DynaLoader::dl_install_xsub("main::cognify_media_run", $sym);
        cognify_media_run();
        """

    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        value ? start() : stop()
    }

    private func start() {
        guard enabled, process == nil, let library = Self.library else {
            if Self.library == nil { unavailable = true }
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        p.arguments = ["-e", Self.perlScript, library.path]
        let stdout = Pipe(), stdin = Pipe()
        p.standardOutput = stdout
        p.standardInput = stdin
        p.standardError = FileHandle.nullDevice
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            Task { @MainActor in self?.consume(chunk) }
        }
        p.terminationHandler = { [weak self] proc in
            Task { @MainActor in self?.ended(status: proc.terminationStatus) }
        }
        do {
            try p.run()
            process = p
            input = stdin.fileHandleForWriting
        } catch {
            unavailable = true
        }
    }

    private func ended(status: Int32) {
        process = nil
        input = nil
        guard enabled else { return }
        failures += 1
        if failures > 5 {
            unavailable = true
            nowPlaying = nil
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.start() }
    }

    private func stop() {
        input = nil // stdin tertutup → helper keluar sendiri
        process?.terminate()
        process = nil
        nowPlaying = nil
        artwork = nil
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            apply(object)
        }
    }

    private func apply(_ o: [String: Any]) {
        if o["error"] != nil {
            unavailable = true
            return
        }
        failures = 0
        unavailable = false
        if o["idle"] as? Bool == true {
            withAnimation(.notch) { nowPlaying = nil; artwork = nil }
            return
        }
        guard let title = o["title"] as? String else { return }
        if let base64 = o["artwork"] as? String, let data = Data(base64Encoded: base64) {
            artwork = NSImage(data: data)
        } else if (o["artworkKey"] as? Int ?? 0) == 0 {
            artwork = nil
        }
        let next = NowPlaying(
            title: title,
            artist: (o["artist"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            album: o["album"] as? String,
            duration: o["duration"] as? Double,
            elapsed: o["elapsed"] as? Double,
            rate: o["rate"] as? Double ?? 0,
            timestamp: (o["timestamp"] as? Double).map { Date(timeIntervalSince1970: $0) },
            playing: o["playing"] as? Bool ?? false,
            bundle: o["bundle"] as? String
        )
        if next != nowPlaying { withAnimation(.notch) { nowPlaying = next } }
    }

    // MARK: Kontrol

    func send(_ command: String) {
        input?.write((command + "\n").data(using: .utf8)!)
    }

    func toggle() {
        send("toggle")
        if var current = nowPlaying { current.playing.toggle(); current.elapsed = current.position(at: Date()); current.timestamp = Date(); nowPlaying = current }
    }

    func next() { send("next") }
    func previous() { send("prev") }

    /// Ikon app pemutar (dipakai bila lagu tidak punya sampul, mis. Spotify).
    var appIcon: NSImage? {
        guard let bundle = nowPlaying?.bundle,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    var appName: String? {
        guard let bundle = nowPlaying?.bundle,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return nil }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    func openApp() {
        guard let bundle = nowPlaying?.bundle,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    // Untuk snapshot.
    func preview(_ value: NowPlaying?, artwork: NSImage? = nil) {
        nowPlaying = value
        self.artwork = artwork
    }
}

// MARK: - Tampilan

struct Artwork: View {
    @ObservedObject var media: MediaMonitor
    let size: CGFloat

    var body: some View {
        Group {
            if let art = media.artwork {
                Image(nsImage: art).resizable().aspectRatio(contentMode: .fill)
            } else if let icon = media.appIcon {
                Image(nsImage: icon).resizable().aspectRatio(contentMode: .fit).padding(size * 0.12)
                    .background(Color.white.opacity(0.08))
            } else {
                Image(systemName: "music.note").font(.system(size: size * 0.4)).foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.08))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }
}

/// Batang equalizer: pita nada asli dari `Spectrum` (kiri bass → kanan treble) jika tersedia,
/// selain itu animasi selama musik diputar.
struct Equalizer: View {
    let playing: Bool
    @ObservedObject var spectrum: Spectrum
    var tint: Color = .accent
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        if snapshot {
            bars(t: 1.3) // renderer gambar tidak mendukung TimelineView beranimasi
        } else if let bands = spectrum.bands, playing {
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(tint).frame(width: 2.6, height: 3 + 11 * CGFloat(i < bands.count ? bands[i] : 0))
                }
            }
            .frame(height: 14)
            .animation(.linear(duration: 1 / 30), value: bands)
        } else {
            TimelineView(.animation(minimumInterval: 1 / 12, paused: !playing)) { context in
                bars(t: context.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func bars(t: Double) -> some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                Capsule()
                    .fill(tint)
                    .frame(width: 2.6, height: playing ? 4 + 9 * abs(sin(t * (2.1 + Double(i) * 0.7) + Double(i))) : 3)
            }
        }
        .frame(height: 14)
    }
}

struct MediaCard: View {
    @ObservedObject var media: MediaMonitor
    let spectrum: Spectrum

    var body: some View {
        if let now = media.nowPlaying {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button(action: media.openApp) { Artwork(media: media, size: 50) }.buttonStyle(.plain)
                        .help(media.appName.map { "Buka \($0)" } ?? "")
                    VStack(alignment: .leading, spacing: 2) {
                        Marquee(text: now.title, font: .system(size: 12.5, weight: .semibold))
                        Text(now.artist ?? media.appName ?? "").font(.system(size: 11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Equalizer(playing: now.playing, spectrum: spectrum)
                }
                Progress(now: now)
                HStack(spacing: 22) {
                    Spacer(minLength: 0)
                    ControlButton(icon: "backward.fill", size: 13) { media.previous() }
                    ControlButton(icon: now.playing ? "pause.fill" : "play.fill", size: 19) { media.toggle() }
                    ControlButton(icon: "forward.fill", size: 13) { media.next() }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct Progress: View {
    let now: NowPlaying
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        if snapshot {
            bar(at: now.timestamp ?? Date())
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in bar(at: context.date) }
        }
    }

    private func bar(at date: Date) -> some View {
            let position = now.position(at: date) ?? 0
            let duration = now.duration ?? 0
            return VStack(spacing: 3) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.14))
                        Capsule().fill(Color.white.opacity(0.85))
                            .frame(width: duration > 0 ? geo.size.width * min(1, position / duration) : 0)
                    }
                }
                .frame(height: 4)
                HStack {
                    Text(Self.clock(position))
                    Spacer()
                    Text(duration > 0 ? "-" + Self.clock(max(0, duration - position)) : "")
                }
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
            }
    }

    static func clock(_ seconds: Double) -> String {
        let s = Int(seconds.rounded(.down))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60) : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// Teks satu baris yang bergulir pelan jika lebih panjang dari tempatnya (judul lagu).
struct Marquee: View {
    let text: String
    let font: Font
    @State private var textWidth: CGFloat = 0
    @State private var boxWidth: CGFloat = 0
    @State private var offset: CGFloat = 0
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        let overflow = textWidth > boxWidth + 1 && !snapshot
        GeometryReader { box in
            HStack(spacing: 28) {
                Text(text).font(font).fixedSize()
                    .background(GeometryReader { t in Color.clear.onAppear { textWidth = t.size.width }.onChange(of: text) { _ in textWidth = t.size.width } })
                if overflow { Text(text).font(font).fixedSize() }
            }
            .offset(x: offset)
            .onAppear { boxWidth = box.size.width }
        }
        .frame(height: 16)
        .clipped()
        .mask(LinearGradient(stops: overflow ? [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                                 .init(color: .black, location: 0.94), .init(color: .clear, location: 1)]
                                              : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                             startPoint: .leading, endPoint: .trailing))
        .onChange(of: overflow) { _ in restart() }
        .onChange(of: text) { _ in restart() }
        .onAppear { restart() }
    }

    private func restart() {
        offset = 0
        guard textWidth > boxWidth + 1, !snapshot else { return }
        let distance = textWidth + 28
        withAnimation(.linear(duration: Double(distance) / 28).delay(1.5).repeatForever(autoreverses: false)) { offset = -distance }
    }
}

struct ControlButton: View {
    let icon: String
    let size: CGFloat
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size + 16, height: size + 16)
                .background(Circle().fill(Color.white.opacity(hover ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onHover { hover = $0 }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
