import Combine
import Foundation
import NotchHub
import SwiftUI

/// Ringkasan Cognify (`cognify-hub.json`) dan perintah ke Cognify (`inbox/`). Semuanya mati selama
/// `link.json` tidak menyatakan terhubung. Protokol: docs/notch/protokol-tautan.md di repo Cognify.
@MainActor
final class CognifyHub: ObservableObject {
    @Published private(set) var linked = false
    @Published private(set) var summary = NotchHub.Summary()
    @Published private(set) var hits: [NotchHub.Hit] = []
    @Published private(set) var searching = false
    @Published private(set) var searchFailed = false

    private var folder: URL { NotchLink.folder }
    private var poll: Foundation.Timer?
    private var stamp: Date??
    private var consentStamp: Date??
    private var searchTask: Task<Void, Never>?
    private let fm = FileManager.default

    func start() {
        refresh()
        let timer = Foundation.Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 2
        poll = timer
    }

    /// Dua pemeriksaan tanggal ubah berkas kecil; isi dibaca ulang hanya bila berganti.
    private func refresh() {
        let consentURL = folder.appendingPathComponent("link.json")
        let cStamp = (try? fm.attributesOfItem(atPath: consentURL.path))?[.modificationDate] as? Date
        if consentStamp == nil || consentStamp! != cStamp {
            consentStamp = .some(cStamp)
            let enabled = (try? Data(contentsOf: consentURL))
                .flatMap { try? JSONDecoder().decode(NotchLink.Consent.self, from: $0) }?.enabled == true
            if enabled != linked {
                linked = enabled
                stamp = nil
                if !enabled { clear() }
            }
        }
        guard linked else { return }
        let hubURL = folder.appendingPathComponent("cognify-hub.json")
        let hStamp = (try? fm.attributesOfItem(atPath: hubURL.path))?[.modificationDate] as? Date
        if stamp != nil, stamp! == hStamp { return }
        stamp = .some(hStamp)
        if let bytes = try? Data(contentsOf: hubURL), let parsed = NotchHub.parseSummary(bytes) {
            summary = parsed
        } else {
            summary = NotchHub.Summary()
        }
    }

    private func clear() {
        summary = NotchHub.Summary()
        searchTask?.cancel()
        hits = []
        searching = false
        searchFailed = false
    }

    // MARK: - Perintah

    @discardableResult
    func send(_ command: NotchHub.Command) -> Bool {
        guard linked else { return false }
        return NotchHub.send(command, folder: folder) != nil
    }

    func open(doc id: String) { send(.open(path: NotchHub.openPath(docID: id))) }

    // MARK: - Cari

    /// Tulis `search`, lalu cek `results/<id>.json` tiap 100 ms; menyerah setelah 3 detik.
    func search(_ query: String) {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard linked, !q.isEmpty else { hits = []; searching = false; searchFailed = false; return }
        let id = NotchHub.newID()
        guard NotchHub.send(.search(q: q), id: id, folder: folder) != nil else { searchFailed = true; return }
        searching = true
        searchFailed = false
        let url = NotchHub.resultsURL(id: id, folder: folder)
        searchTask = Task { [weak self] in
            let deadline = Date().addingTimeInterval(3)
            while !Task.isCancelled, Date() < deadline {
                if let data = try? Data(contentsOf: url), let found = NotchHub.parseResults(data, expectedID: id) {
                    try? FileManager.default.removeItem(at: url)
                    self?.hits = found
                    self?.searching = false
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            guard !Task.isCancelled else { return }
            self?.hits = []
            self?.searching = false
            self?.searchFailed = true
        }
    }

    func clearSearch() {
        searchTask?.cancel()
        hits = []
        searching = false
        searchFailed = false
    }
}

// MARK: - Tampilan

struct CognifyPanel: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var hub: CognifyHub
    @State private var query = ""

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                lessonCard
                actions
                toolsGrid
                Spacer(minLength: 0)
            }
            .frame(width: 250)
            VStack(alignment: .leading, spacing: 6) {
                searchField
                if !query.trimmingCharacters(in: .whitespaces).isEmpty {
                    results
                } else {
                    docsList
                }
                Spacer(minLength: 0)
            }
        }
        .onDisappear { query = ""; hub.clearSearch() }
    }

    // Pelajaran

    private var lessonCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: L("Pelajaran hari ini", "Today's lessons"))
            TimelineView(.periodic(from: .now, by: 30)) { context in
                if let (lesson, ongoing) = hub.summary.currentOrNext(now: context.date) {
                    let target = ongoing ? lesson.end : lesson.start
                    VStack(alignment: .leading, spacing: 2) {
                        Text(lesson.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text((ongoing ? L("Berlangsung, sisa ", "In progress, ") : L("Mulai ", "Starts in "))
                             + NotchHub.remaining(target.timeIntervalSince(context.date), english: Lang.english)
                             + (ongoing && Lang.english ? " left" : "")
                             + (lesson.room.map { " · \($0)" } ?? ""))
                            .font(.system(size: 10.5)).foregroundStyle(ongoing ? Color.accent : .white.opacity(0.6)).lineLimit(1)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
                } else {
                    Placeholder(icon: "checkmark.seal",
                                text: hub.summary.lessons.isEmpty ? L("Tidak ada pelajaran hari ini", "No lessons today")
                                                                  : L("Pelajaran hari ini sudah selesai", "Lessons are done for today"))
                }
            }
        }
    }

    // Buat baru

    private var actions: some View {
        HStack(spacing: 6) {
            chip("doc.badge.plus", L("Dokumen", "Doc")) { hub.send(.newDoc(title: nil, text: nil)) }
            chip("note.text.badge.plus", L("Catatan melayang", "Sticky")) { hub.send(.newSticky) }
        }
    }

    private var toolsGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !hub.summary.tools.isEmpty { SectionLabel(text: L("Alat", "Tools")).padding(.top, 2) }
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 5), GridItem(.flexible(), spacing: 5)], spacing: 5) {
                    ForEach(hub.summary.tools) { tool in
                        chip("wrench.and.screwdriver", tool.name) { hub.send(.tool(id: tool.id)) }
                    }
                }
            }
        }
    }

    private func chip(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.accent)
                Text(title).font(.system(size: 10.5, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Cari

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11))
            TextField(L("Cari dokumen di Cognify…", "Search Cognify docs…"), text: $query)
                .textFieldStyle(.plain).font(.system(size: 12))
                .onSubmit { hub.search(query) }
            if hub.searching { Spinner() }
        }
        .foregroundStyle(.white.opacity(0.75))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.08)))
        .onChange(of: query) { if $0.trimmingCharacters(in: .whitespaces).isEmpty { hub.clearSearch() } }
    }

    @ViewBuilder private var results: some View {
        if hub.searching {
            Placeholder(icon: "hourglass", text: L("Mencari…", "Searching…"))
        } else if hub.searchFailed {
            Placeholder(icon: "exclamationmark.triangle", text: L("Cognify tidak menjawab. Pastikan app terbuka.", "Cognify did not answer. Make sure the app is open."))
        } else if hub.hits.isEmpty {
            Placeholder(icon: "magnifyingglass", text: L("Tekan Enter untuk mencari", "Press Enter to search"))
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 4) {
                    ForEach(hub.hits) { hit in
                        docButton(id: hit.id, title: hit.title, kind: hit.kind, detail: hit.snippet)
                    }
                }
            }
        }
    }

    // Dokumen

    private var docsList: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 4) {
                if !hub.summary.docs.pinned.isEmpty {
                    SectionLabel(text: L("Disematkan", "Pinned"))
                    ForEach(hub.summary.docs.pinned) { docButton(id: $0.id, title: $0.title, kind: $0.kind, detail: nil) }
                }
                if !hub.summary.docs.recent.isEmpty {
                    SectionLabel(text: L("Terbaru", "Recent")).padding(.top, 2)
                    ForEach(hub.summary.docs.recent) { docButton(id: $0.id, title: $0.title, kind: $0.kind, detail: nil) }
                }
                if hub.summary.docs.pinned.isEmpty && hub.summary.docs.recent.isEmpty {
                    Placeholder(icon: "doc", text: L("Belum ada dokumen", "No documents yet"))
                }
            }
        }
    }

    private func docButton(id: String, title: String, kind: String, detail: String?) -> some View {
        Button { hub.open(doc: id) } label: {
            HStack(spacing: 8) {
                Image(systemName: kind == "board" ? "scribble" : kind == "table" ? "tablecells" : "doc.text")
                    .font(.system(size: 11)).foregroundStyle(Color.accent).frame(width: 14)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title.isEmpty ? L("Tanpa judul", "Untitled") : title).font(.system(size: 11.5, weight: .medium)).lineLimit(1)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.system(size: 10)).foregroundStyle(.white.opacity(0.5)).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.07)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
