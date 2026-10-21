import AppKit
import CryptoKit
import SwiftUI

/// Lirik tersinkron dari LRCLIB (lrclib.net, perpustakaan lirik gratis dari komunitas).
///
/// Yang dikirim ke LRCLIB hanya judul, artis, album, dan durasi lagu, dan hanya saat halaman
/// Musik terbuka (bukan setiap ganti lagu). Hasilnya disimpan di Mac ini
/// (~/Library/Caches/<bundle>/lyrics), jadi lagu yang sama tidak diminta dua kali.
@MainActor
final class LyricsService: ObservableObject {
    struct Line: Equatable, Identifiable {
        let id: Int
        let time: Double // detik
        let text: String
    }

    enum State: Equatable {
        case idle
        case loading
        case synced([Line])
        case plain(String) // lirik tanpa waktu
        case instrumental
        case missing
        case failed
    }

    @Published private(set) var state: State = .idle
    private var key: String?
    private var task: Task<Void, Never>?

    nonisolated private static let cacheDir: URL? = {
        guard let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.reinhard.cognify.notch").appendingPathComponent("lyrics")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Muat lirik untuk lagu ini (tidak melakukan apa-apa bila lagunya sama dengan sebelumnya).
    func load(for song: NowPlaying?) {
        guard let song, !song.title.isEmpty else {
            task?.cancel()
            key = nil
            state = .idle
            return
        }
        let next = [song.title, song.artist ?? "", song.album ?? ""].joined(separator: "\u{1F}")
        guard next != key else { return }
        key = next
        task?.cancel()
        state = .loading
        let title = song.title, artist = song.artist ?? "", album = song.album ?? "", duration = song.duration
        task = Task { [weak self] in
            let result = await Self.fetch(title: title, artist: artist, album: album, duration: duration)
            guard !Task.isCancelled, let self, self.key == next else { return }
            withAnimation(.notch) { self.state = result }
        }
    }

    /// Hapus status (fitur dimatikan).
    func reset() {
        task?.cancel()
        key = nil
        state = .idle
    }

    // MARK: Ambil & simpan

    private struct Record: Codable {
        let syncedLyrics: String?
        let plainLyrics: String?
        let instrumental: Bool?
        let duration: Double?
    }

    nonisolated private static func cacheURL(_ title: String, _ artist: String) -> URL? {
        let digest = SHA256.hash(data: Data((title + "\u{1F}" + artist).lowercased().utf8))
        let name = digest.map { String(format: "%02x", $0) }.joined().prefix(32)
        return cacheDir?.appendingPathComponent("\(name).json")
    }

    nonisolated private static func fetch(title: String, artist: String, album: String, duration: Double?) async -> State {
        let cache = cacheURL(title, artist)
        if let cache, let data = try? Data(contentsOf: cache) {
            if data.isEmpty { return .missing } // sudah pernah dicari, tidak ada
            if let record = try? JSONDecoder().decode(Record.self, from: data) { return state(from: record) }
        }
        var get = URLComponents(string: "https://lrclib.net/api/get")!
        get.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        if !album.isEmpty { get.queryItems?.append(URLQueryItem(name: "album_name", value: album)) }
        if let duration, duration > 0 { get.queryItems?.append(URLQueryItem(name: "duration", value: String(Int(duration.rounded())))) }
        do {
            if let record: Record = try await request(get.url!), record.syncedLyrics != nil || record.plainLyrics != nil || record.instrumental == true {
                save(record, to: cache)
                return state(from: record)
            }
            // Cocok persis tidak ada (album/durasi beda): cari, pilih yang durasinya paling dekat.
            var search = URLComponents(string: "https://lrclib.net/api/search")!
            search.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
            let found: [Record] = try await request(search.url!) ?? []
            let best = found
                .filter { $0.syncedLyrics != nil || $0.plainLyrics != nil }
                .min { a, b in
                    let target = duration ?? 0
                    let da = abs((a.duration ?? target) - target) + (a.syncedLyrics == nil ? 1000 : 0)
                    let db = abs((b.duration ?? target) - target) + (b.syncedLyrics == nil ? 1000 : 0)
                    return da < db
                }
            if let best, duration == nil || abs((best.duration ?? duration!) - duration!) < 8 {
                save(best, to: cache)
                return state(from: best)
            }
            if let cache { try? Data().write(to: cache) }
            return .missing
        } catch {
            return .failed
        }
    }

    /// GET JSON; nil bila 404.
    nonisolated private static func request<T: Decodable>(_ url: URL) async throws -> T? {
        var req = URLRequest(url: url, timeoutInterval: 10)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        req.setValue("Cognify Notch \(version) (https://github.com/reinharddev/cognify-notch)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard (200..<300).contains(status) else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode(T.self, from: data)
    }

    nonisolated private static func save(_ record: Record, to url: URL?) {
        guard let url, let data = try? JSONEncoder().encode(record) else { return }
        try? data.write(to: url)
    }

    nonisolated private static func state(from record: Record) -> State {
        if record.instrumental == true { return .instrumental }
        if let synced = record.syncedLyrics, case let lines = parse(synced), !lines.isEmpty { return .synced(lines) }
        if let plain = record.plainLyrics?.trimmingCharacters(in: .whitespacesAndNewlines), !plain.isEmpty { return .plain(plain) }
        return .missing
    }

    /// "[01:02.34] teks" (satu baris bisa punya beberapa waktu) → baris berurutan menurut waktu.
    nonisolated static func parse(_ lrc: String) -> [Line] {
        let stamp = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        var lines: [(Double, String)] = []
        for raw in lrc.split(whereSeparator: \.isNewline) {
            let row = String(raw)
            let range = NSRange(row.startIndex..., in: row)
            let matches = stamp.matches(in: row, range: range)
            guard !matches.isEmpty, let last = matches.last, let end = Range(last.range, in: row) else { continue }
            let text = row[end.upperBound...].trimmingCharacters(in: .whitespaces)
            for m in matches {
                guard let mm = Range(m.range(at: 1), in: row), let ss = Range(m.range(at: 2), in: row),
                      let minutes = Double(row[mm]), let seconds = Double(row[ss]) else { continue }
                lines.append((minutes * 60 + seconds, text))
            }
        }
        return lines.sorted { $0.0 < $1.0 }.enumerated().map { Line(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }

    // Untuk snapshot.
    func preview(_ value: State) { state = value }
}

/// Lirik berjalan: baris yang sedang dinyanyikan terang dan di tengah, baris lain redup.
/// Klik baris untuk lompat ke bagian itu.
struct LyricsView: View {
    @ObservedObject var lyrics: LyricsService
    @ObservedObject var media: MediaMonitor
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        switch lyrics.state {
        case .synced(let lines):
            if snapshot {
                SyncedLines(lines: lines, position: media.nowPlaying.flatMap { $0.position(at: $0.timestamp ?? Date()) } ?? 0, seek: { _ in })
            } else {
                TimelineView(.periodic(from: .now, by: 0.25)) { context in
                    SyncedLines(lines: lines, position: media.nowPlaying?.position(at: context.date) ?? 0) { time in
                        media.seek(to: time)
                    }
                }
            }
        case .plain(let text):
            ScrollView(.vertical, showsIndicators: false) {
                Text(text).font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        case .loading:
            message("music.note", L("Mencari lirik…", "Finding lyrics…"))
        case .instrumental:
            message("pianokeys", L("Lagu instrumental", "Instrumental"))
        case .missing:
            message("text.badge.xmark", L("Lirik lagu ini belum ada di LRCLIB", "No lyrics for this song on LRCLIB yet"))
        case .failed:
            message("wifi.slash", L("Lirik tidak bisa dimuat. Periksa internet.", "Couldn't load lyrics. Check your connection."))
        case .idle:
            message("music.note.list", L("Putar lagu untuk melihat liriknya", "Play a song to see its lyrics"))
        }
    }

    private func message(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 16))
            Text(text).font(.system(size: 11.5)).multilineTextAlignment(.center)
        }
        .foregroundStyle(.white.opacity(0.45))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SyncedLines: View {
    let lines: [LyricsService.Line]
    let position: Double
    let seek: (Double) -> Void

    var body: some View {
        // Sedikit lebih awal supaya baris menyala tepat saat mulai dinyanyikan.
        let current = lines.lastIndex { $0.time <= position + 0.25 } ?? -1
        let window = (max(0, current - 1)...min(lines.count - 1, max(0, current) + 3))
        VStack(alignment: .leading, spacing: 7) {
            ForEach(lines[window]) { line in
                let active = line.id == current
                Button { seek(line.time) } label: {
                    Text(line.text.isEmpty ? "♪" : line.text)
                        .font(.system(size: active ? 15 : 12.5, weight: active ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(active ? 1 : (line.id < current ? 0.3 : 0.45)))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(L("Lompat ke baris ini", "Jump to this line"))
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: current)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.8),
                                     .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
    }
}

/// Halaman Musik: kartu lagu di kiri, lirik di kanan (bila fitur lirik nyala).
struct MusicPanel: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var media: MediaMonitor
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        if media.nowPlaying == nil {
            VStack(spacing: 8) {
                Image(systemName: "music.note").font(.system(size: 22))
                Text(L("Belum ada lagu yang diputar", "Nothing is playing"))
                    .font(.system(size: 12, weight: .medium))
                Text(L("Spotify, Apple Music, YouTube di browser, dan lainnya muncul di sini.",
                       "Spotify, Apple Music, YouTube in your browser and more show up here."))
                    .font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
            }
            .foregroundStyle(.white.opacity(0.6))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.features.lyrics {
            HStack(alignment: .top, spacing: 18) {
                MediaCard(media: media, spectrum: model.spectrum).frame(width: 200)
                Divider().overlay(Color.white.opacity(0.08))
                LyricsView(lyrics: model.lyrics, media: media)
            }
            .onAppear { if !snapshot { model.lyrics.load(for: media.nowPlaying) } }
            .onChange(of: media.nowPlaying?.title) { _ in model.lyrics.load(for: media.nowPlaying) }
        } else {
            MediaCard(media: media, spectrum: model.spectrum).frame(width: 300).frame(maxWidth: .infinity)
        }
    }
}
