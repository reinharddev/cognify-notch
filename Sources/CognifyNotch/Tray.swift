import AppKit
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// Tray: tempat parkir file sementara di notch. Yang disimpan hanya penunjuk ke file aslinya
/// (bookmark), bukan salinan, jadi file tetap di tempat asalnya dan tray tidak memakan ruang.
struct TrayItem: Codable, Identifiable, Equatable {
    let id: UUID
    var bookmark: Data
    var name: String
}

@MainActor
final class TrayModel: ObservableObject {
    static let maxItems = 30

    @Published private(set) var items: [TrayItem] = []
    @Published var renaming: UUID?

    private let key = "tray.items"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([TrayItem].self, from: data) {
            items = saved.filter { url(for: $0) != nil } // file yang sudah dihapus dibuang
        }
    }

    func url(for item: TrayItem) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: item.bookmark, options: [.withoutUI], bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    func add(_ urls: [URL]) {
        var next = items
        for url in urls where url.isFileURL {
            guard let bookmark = try? url.bookmarkData() else { continue }
            next.removeAll { self.url(for: $0)?.standardizedFileURL == url.standardizedFileURL }
            next.insert(TrayItem(id: UUID(), bookmark: bookmark, name: url.lastPathComponent), at: 0)
        }
        withAnimation(.notch) { items = Array(next.prefix(Self.maxItems)) }
        save()
    }

    func remove(_ item: TrayItem) {
        withAnimation(.notch) { items.removeAll { $0.id == item.id } }
        save()
    }

    func clear() {
        withAnimation(.notch) { items = [] }
        save()
    }

    /// Ganti nama file aslinya (di folder yang sama). Mengembalikan pesan error jika gagal.
    func rename(_ item: TrayItem, to newName: String) -> String? {
        renaming = nil
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
        guard !clean.isEmpty, clean != item.name, let url = url(for: item) else { return nil }
        let target = url.deletingLastPathComponent().appendingPathComponent(clean)
        guard !FileManager.default.fileExists(atPath: target.path) else { return L("Sudah ada file bernama “\(clean)”", "A file named “\(clean)” already exists") }
        do {
            try FileManager.default.moveItem(at: url, to: target)
            guard let index = items.firstIndex(where: { $0.id == item.id }), let bookmark = try? target.bookmarkData() else { return nil }
            items[index] = TrayItem(id: item.id, bookmark: bookmark, name: clean)
            save()
            return nil
        } catch {
            return L("Nama tidak bisa diganti: ", "Couldn't rename: ") + error.localizedDescription
        }
    }

    func airDrop(_ selected: [TrayItem]) {
        let urls = selected.compactMap(url(for:))
        guard !urls.isEmpty, let service = NSSharingService(named: .sendViaAirDrop) else { return }
        service.perform(withItems: urls)
    }

    func open(_ item: TrayItem) {
        if let url = url(for: item) { NSWorkspace.shared.open(url) }
    }

    func reveal(_ item: TrayItem) {
        if let url = url(for: item) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key) }
    }

    // Untuk snapshot.
    func preview(_ urls: [URL]) {
        items = urls.map { TrayItem(id: UUID(), bookmark: (try? $0.bookmarkData()) ?? Data(), name: $0.lastPathComponent) }
    }
}

// MARK: - Tampilan

struct TrayPanel: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var tray: TrayModel
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: tray.items.isEmpty ? "Tray" : "Tray · \(tray.items.count) " + L("file", tray.items.count == 1 ? "file" : "files"))
                Spacer()
                if !tray.items.isEmpty {
                    Button { tray.airDrop(tray.items) } label: { Label(L("AirDrop semua", "AirDrop all"), systemImage: "airplayaudio") }
                        .buttonStyle(PillButtonStyle(prominent: false))
                    Button(L("Kosongkan", "Clear")) { tray.clear() }.buttonStyle(PillButtonStyle(prominent: false))
                }
            }
            if tray.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray").font(.system(size: 22)).foregroundStyle(.white.opacity(0.35))
                    Text(model.appMode ? L("Seret file ke notch untuk menaruhnya di sini.", "Drop files on the notch to park them here.") : "Seret file ke notch lalu lepas di “Taruh di tray”.").font(.system(size: 11.5))
                    Text(L("File tetap di tempat aslinya; tray hanya menyimpan pintasannya.", "Files stay where they are; the tray only keeps a shortcut.")).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.45))
                }
                .foregroundStyle(.white.opacity(0.6))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshot {
                tiles // renderer gambar tidak bisa menggambar ScrollView
            } else {
                ScrollView(.horizontal, showsIndicators: false) { tiles }
            }
        }
    }
}

extension TrayPanel {
    var tiles: some View {
        HStack(spacing: 8) {
            ForEach(tray.items) { item in
                TrayTile(model: model, tray: tray, item: item)
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 2)
    }
}

struct TrayTile: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var tray: TrayModel
    let item: TrayItem
    @State private var hover = false
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        let url = tray.url(for: item)
        VStack(spacing: 5) {
            Thumbnail(url: url)
                .frame(width: 64, height: 64)
                .overlay(alignment: .topTrailing) {
                    if hover {
                        Button { tray.remove(item) } label: {
                            Image(systemName: "xmark.circle.fill").font(.system(size: 14)).foregroundStyle(.white, Color(white: 0.3))
                        }
                        .buttonStyle(.plain).offset(x: 6, y: -6).help(L("Keluarkan dari tray", "Remove from tray"))
                    }
                }
            if tray.renaming == item.id {
                TextField("", text: $draft)
                    .textFieldStyle(.plain).font(.system(size: 10.5)).multilineTextAlignment(.center)
                    .focused($editing)
                    .onSubmit { commitRename() }
                    .onExitCommand { tray.renaming = nil }
                    .padding(.horizontal, 3).background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.15)))
                    .onAppear { draft = item.name; editing = true }
            } else {
                Text(item.name).font(.system(size: 10.5)).lineLimit(2).multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.85))
                    .onTapGesture(count: 2) { tray.renaming = item.id }
            }
        }
        .frame(width: 84, height: 108, alignment: .top)
        .padding(.top, 4)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(hover ? 0.08 : 0)))
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { tray.open(item) }
        .onDrag { url.map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider() } // seret keluar ke app lain
        .contextMenu {
            Button(L("Buka", "Open")) { tray.open(item) }
            Button(L("Tampilkan di Finder", "Show in Finder")) { tray.reveal(item) }
            Button("AirDrop") { tray.airDrop([item]) }
            Button(L("Ganti nama", "Rename")) { tray.renaming = item.id }
            Divider()
            if !model.appMode {
                Button("Simpan ke Knowledge") { if let url { model.save(files: [url], links: [], texts: []) } }
            }
            Divider()
            Button(L("Keluarkan dari tray", "Remove from tray")) { tray.remove(item) }
        }
        .help("\(item.name)\nKlik dua kali untuk membuka, klik kanan untuk pilihan lain, seret untuk memindahkan.")
    }

    private func commitRename() {
        if let error = tray.rename(item, to: draft) { model.show(.failed(error)) }
    }
}

/// Pratinjau file (Quick Look) dengan cadangan ikon Finder.
struct Thumbnail: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
            } else if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "questionmark.folder").font(.system(size: 28)).foregroundStyle(.white.opacity(0.4))
            }
        }
        .task(id: url) {
            guard let url else { return }
            let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 64, height: 64), scale: 2, representationTypes: .thumbnail)
            if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                image = rep.nsImage
            }
        }
    }
}

// MARK: - Seret ke notch: pilih tujuan

struct DropChoice: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        HStack(spacing: 10) {
            if !model.appMode {
            DropTargetZone(icon: "brain.head.profile", title: "Simpan ke Knowledge",
                           detail: "PDF, Word, PowerPoint, gambar, tautan, teks") { files, links, texts in
                model.save(files: files, links: links, texts: texts)
            }
            }
            DropTargetZone(icon: "tray.full.fill", title: L("Taruh di tray", "Add to tray"),
                           detail: L("Parkir sementara, AirDrop, ganti nama", "Park, AirDrop, rename")) { files, links, texts in
                if files.isEmpty {
                    model.show(.failed(model.appMode ? L("Tray hanya untuk file.", "The tray only holds files.") : "Tray hanya untuk file. Tautan & teks bisa disimpan ke Knowledge."))
                } else {
                    model.tray.add(files)
                    model.tab = .tray
                    model.show(.done(files.count == 1 ? "“\(files[0].lastPathComponent)” di tray" : "\(files.count) file di tray"))
                }
            }
        }
    }
}

struct DropTargetZone: View {
    let icon: String
    let title: String
    let detail: String
    let onDrop: ([URL], [URL], [String]) -> Void
    @State private var targeted = false
    @Environment(\.snapshot) private var snapshot

    var body: some View {
        let zone = VStack(spacing: 7) {
            Image(systemName: icon).font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Color.accent)
                .scaleEffect(targeted ? 1.15 : 1)
            Text(title).font(.system(size: 12.5, weight: .semibold))
            Text(detail).font(.system(size: 10.5)).foregroundStyle(.white.opacity(0.5)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.accent.opacity(targeted ? 1 : 0.5), style: StrokeStyle(lineWidth: targeted ? 2 : 1.5, dash: [6, 5]))
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.accent.opacity(targeted ? 0.22 : 0.07)))
        )
        .animation(.notch, value: targeted)

        if snapshot {
            zone
        } else {
            zone.onDrop(of: [.fileURL, .url, .plainText], isTargeted: $targeted) { providers in
                DropLoader.load(providers, done: onDrop)
                return true
            }
        }
    }
}
