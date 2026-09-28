import Foundation

/// Komunikasi dengan Cognify (Rust, src-tauri/src/notch.rs) lewat satu baris JSON per pesan.
///
/// Masuk (stdin):  {"type":"backend","port":51234,"token":"..."}  → alamat & token sidecar
///                 {"type":"backend","port":null}                → sidecar belum siap / mati
///                 {"type":"config","media":true,"calendar":false,"camera":true,"shortcuts":true,"hud":true,"spectrum":true}
/// Keluar (stdout): {"type":"open","path":"/reminders"}          → tampilkan jendela Cognify di halaman itu
///
/// stdin ditutup (Cognify keluar atau crash) → program ini ikut keluar. Untuk uji manual tanpa
/// Tauri: isi env COGNIFY_NOTCH_PORT + COGNIFY_NOTCH_TOKEN (tidak menunggu stdin).
///
/// Tanpa `--embedded` (dibuka sebagai app "Cognify Notch" dari Finder) stdin tidak dibaca sama
/// sekali: itu mode app mandiri tanpa Cognify (lihat NotchModel.appMode).
struct BackendInfo: Equatable {
    let port: Int
    let token: String
}

final class Bridge {
    var onBackend: ((BackendInfo?) -> Void)?
    var onConfig: (([String: Bool]) -> Void)?
    private var buffer = Data()

    let standalone: BackendInfo? = {
        let env = ProcessInfo.processInfo.environment
        guard let port = env["COGNIFY_NOTCH_PORT"].flatMap(Int.init), let token = env["COGNIFY_NOTCH_TOKEN"] else { return nil }
        return BackendInfo(port: port, token: token)
    }()

    /// Dijalankan oleh Cognify (src-tauri/src/notch.rs menambahkan argumen ini).
    static let embedded = CommandLine.arguments.contains("--embedded")

    /// App mandiri: bukan dijalankan Cognify dan bukan uji manual.
    var appMode: Bool { !Self.embedded && standalone == nil }

    func start() {
        if let info = standalone {
            DispatchQueue.main.async { self.onBackend?(info) }
            return
        }
        guard Self.embedded else { return }
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                exit(0) // Cognify sudah tidak ada
            }
            DispatchQueue.main.async { self?.consume(chunk) }
        }
    }

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(line)
        }
    }

    private func handle(_ line: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        if object["type"] as? String == "config" {
            onConfig?(object.compactMapValues { $0 as? Bool })
            return
        }
        guard object["type"] as? String == "backend" else { return }
        if let port = object["port"] as? Int, let token = object["token"] as? String {
            onBackend?(BackendInfo(port: port, token: token))
        } else {
            onBackend?(nil)
        }
    }

    /// Minta Cognify menampilkan jendelanya di halaman `path`.
    func open(path: String) {
        guard standalone == nil else {
            FileHandle.standardError.write("[notch] buka \(path)\n".data(using: .utf8)!)
            return
        }
        send(["type": "open", "path": path])
    }

    private func send(_ object: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: object) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }
}
