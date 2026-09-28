import Foundation
import UniformTypeIdentifiers

/// Data dari `GET /api/notch` (sidecar/cognify_sidecar/features/notch/router.py).
struct NotchEvent: Decodable, Identifiable, Equatable {
    let id: String
    let kind: String // "reminder" | "deadline"
    let title: String
    let subtitle: String?
    let dueAt: String
    let allDay: Bool
    let path: String

    var due: Date { API.parseDate(dueAt) ?? .distantFuture }
}

struct NotchState: Decodable, Equatable {
    let events: [NotchEvent]
    let overdue: Int
    let processing: Int
}

struct APIError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Klien HTTP kecil untuk sidecar lokal (127.0.0.1, token sesi di header).
struct API {
    let info: BackendInfo

    private var base: URL { URL(string: "http://127.0.0.1:\(info.port)")! }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral // tidak ada cache di disk
        config.timeoutIntervalForRequest = 120 // upload + konversi PDF besar
        return URLSession(configuration: config)
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static func parseDate(_ iso: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: iso) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)
    }

    private func request(_ path: String, method: String = "GET") -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue(info.token, forHTTPHeaderField: "X-Cognify-Token")
        return req
    }

    private func perform(_ req: URLRequest) async throws -> Data {
        let (data, response) = try await API.session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = (body?["error"] as? [String: Any])?["message"] as? String
            throw APIError(message: message ?? "Cognify menolak permintaan ini (\(status))")
        }
        return data
    }

    private func json(_ path: String, _ body: [String: Any]) async throws -> Data {
        var req = request(path, method: "POST")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(req)
    }

    func state() async throws -> NotchState {
        try API.decoder.decode(NotchState.self, from: try await perform(request("api/notch")))
    }

    /// Catatan cepat → item Knowledge. Mengembalikan judul yang dipakai.
    func quickNote(_ text: String) async throws -> String {
        let data = try await json("api/notch/note", ["text": text])
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["title"] as? String ?? "Catatan"
    }

    /// Tautan web → item Knowledge (halaman diambil dan diubah jadi teks oleh sidecar).
    func saveURL(_ url: URL) async throws -> String {
        try itemTitle(await json("api/documents/url", ["url": url.absoluteString]))
    }

    /// File (PDF, Word, PowerPoint, gambar) → item Knowledge.
    func upload(_ file: URL) async throws -> String {
        let boundary = "cognify-\(UUID().uuidString)"
        var req = request("api/documents/upload", method: "POST")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let name = file.lastPathComponent.replacingOccurrences(of: "\"", with: "'")
        var body = Data()
        body.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(name)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(try Data(contentsOf: file))
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body
        return try itemTitle(await perform(req))
    }

    private func itemTitle(_ data: Data) throws -> String {
        (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["title"] as? String ?? "Item"
    }
}
