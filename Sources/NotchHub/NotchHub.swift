import Foundation

/// Sisi Notch dari protokol Cognify: ringkasan `cognify-hub.json` dan perintah `inbox/`.
/// Logika murni (tanpa UI) supaya bisa diuji. Protokol: docs/notch/protokol-tautan.md di repo Cognify.
public enum NotchHub {
    public static let maxHubBytes = 1_000_000
    public static let maxHits = 8
    public static let maxQuery = 200

    // MARK: - Ringkasan

    public struct Lesson: Decodable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let start: Date
        public let end: Date
        public let room: String?
    }

    public struct Doc: Decodable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let kind: String
    }

    public struct Docs: Decodable, Equatable {
        public var pinned: [Doc] = []
        public var recent: [Doc] = []
        public init() {}
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            pinned = (try? c.decode([Doc].self, forKey: .pinned)) ?? []
            recent = (try? c.decode([Doc].self, forKey: .recent)) ?? []
        }
        private enum Keys: String, CodingKey { case pinned, recent }
    }

    public struct Tool: Decodable, Equatable, Identifiable {
        public let id: String
        public let name: String
    }

    public struct Summary: Decodable, Equatable {
        public var lessons: [Lesson] = []
        public var docs = Docs()
        public var tools: [Tool] = []

        public init() {}
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            lessons = (try? c.decode([Lesson].self, forKey: .lessons)) ?? []
            docs = (try? c.decode(Docs.self, forKey: .docs)) ?? Docs()
            tools = (try? c.decode([Tool].self, forKey: .tools)) ?? []
        }
        private enum Keys: String, CodingKey { case lessons, docs, tools }

        /// Pelajaran yang sedang berlangsung, atau yang berikutnya bila belum mulai.
        public func currentOrNext(now: Date) -> (lesson: Lesson, ongoing: Bool)? {
            let sorted = lessons.sorted { $0.start < $1.start }
            if let live = sorted.first(where: { $0.start <= now && now < $0.end }) { return (live, true) }
            if let next = sorted.first(where: { $0.start > now }) { return (next, false) }
            return nil
        }
    }

    /// Hasil baca: nil bila berkas hilang, terlalu besar, atau rusak.
    public static func parseSummary(_ data: Data) -> Summary? {
        guard data.count <= maxHubBytes else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { d in
            let s = try d.singleValueContainer().decode(String.self)
            if let date = parseDate(s) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: d.codingPath, debugDescription: "tanggal: \(s)"))
        }
        return try? decoder.decode(Summary.self, from: data)
    }

    public static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Sisa waktu singkat: "45 mnt", "1 j 20 mnt".
    public static func remaining(_ seconds: TimeInterval, english: Bool) -> String {
        let minutes = max(0, Int((seconds / 60).rounded(.up)))
        let h = minutes / 60, m = minutes % 60
        let hu = english ? "h" : "j", mu = english ? "min" : "mnt"
        if h == 0 { return "\(m) \(mu)" }
        return m == 0 ? "\(h) \(hu)" : "\(h) \(hu) \(m) \(mu)"
    }

    // MARK: - Perintah

    public enum Command: Equatable {
        case open(path: String)
        case newDoc(title: String?, text: String?)
        case noteToDoc(text: String, title: String?)
        case newSticky
        case tool(id: String)
        case search(q: String)
    }

    /// Id hanya huruf, angka, `-`, `_`.
    public static func newID() -> String {
        UUID().uuidString.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    public static func openPath(docID: String) -> String { "/p/\(docID)" }

    public static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 80 && id.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" || $0 == "_" }
    }

    /// Isi JSON sebuah perintah; nil bila tidak sah (path tidak diawali `/`, query kosong, dsb.).
    public static func encode(_ command: Command, id: String) -> Data? {
        var body: [String: Any]
        switch command {
        case .open(let path):
            guard path.hasPrefix("/"), !path.hasPrefix("//") else { return nil }
            body = ["type": "open", "path": path]
        case .newDoc(let title, let text):
            body = ["type": "new_doc"]
            if let title, !title.isEmpty { body["title"] = title }
            if let text, !text.isEmpty { body["text"] = text }
        case .noteToDoc(let text, let title):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            body = ["type": "note_to_doc", "text": text]
            if let title, !title.isEmpty { body["title"] = title }
        case .newSticky:
            body = ["type": "new_sticky"]
        case .tool(let toolID):
            guard !toolID.isEmpty else { return nil }
            body = ["type": "tool", "id": toolID]
        case .search(let q):
            let trimmed = String(q.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxQuery))
            guard !trimmed.isEmpty else { return nil }
            body = ["type": "search", "id": id, "q": trimmed]
        }
        guard isValidID(id) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
              data.count <= 64 * 1024 else { return nil }
        return data
    }

    /// Menulis `inbox/<id>.json` secara atomik (`.tmp` lalu ganti nama). Mengembalikan id, atau nil bila gagal.
    @discardableResult
    public static func send(_ command: Command, id: String = newID(), folder: URL) -> String? {
        guard let data = encode(command, id: id) else { return nil }
        let fm = FileManager.default
        let inbox = folder.appendingPathComponent("inbox", isDirectory: true)
        do {
            try fm.createDirectory(at: inbox, withIntermediateDirectories: true)
            let tmp = inbox.appendingPathComponent("\(id).tmp")
            let final = inbox.appendingPathComponent("\(id).json")
            try data.write(to: tmp)
            try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
            if fm.fileExists(atPath: final.path) { try fm.removeItem(at: final) }
            try fm.moveItem(at: tmp, to: final)
            return id
        } catch {
            return nil
        }
    }

    // MARK: - Hasil pencarian

    public struct Hit: Decodable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let kind: String
        public let snippet: String
    }

    private struct ResultsFile: Decodable {
        let id: String?
        let hits: [Hit]
    }

    /// Hingga 8 hasil; nil bila rusak. `id` berkas harus cocok bila ada.
    public static func parseResults(_ data: Data, expectedID: String) -> [Hit]? {
        guard let file = try? JSONDecoder().decode(ResultsFile.self, from: data) else { return nil }
        if let id = file.id, id != expectedID { return nil }
        return Array(file.hits.prefix(maxHits))
    }

    public static func resultsURL(id: String, folder: URL) -> URL {
        folder.appendingPathComponent("results", isDirectory: true).appendingPathComponent("\(id).json")
    }
}
