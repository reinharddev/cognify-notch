import AppKit
import SQLite3

/// Notifikasi app lain (WhatsApp, Discord, dan seterusnya) yang ikut tampil di notch.
///
/// Sumbernya database Pusat Notifikasi macOS di Mac ini (`group.com.apple.usernoted/db2/db`), dibaca
/// hanya-baca. macOS menutup folder itu kecuali app punya izin **Akses Disk Penuh**, jadi tanpa izin
/// `access` bernilai `.denied` dan tidak ada yang dibaca. Isi notifikasi hanya lewat di memori: tidak
/// disimpan, tidak dicatat, dan tidak dikirim ke mana pun. Hanya app yang dipilih pengguna yang diteruskan.
@MainActor
final class AppNotificationWatcher: ObservableObject {
    struct Message: Equatable {
        let bundle: String
        let app: String
        let title: String
        let body: String
    }

    enum Access { case unknown, ok, denied }

    /// Dipanggil untuk tiap notifikasi baru dari app yang dipilih.
    var onMessage: ((Message) -> Void)?
    /// Bundle id app yang diteruskan ke notch.
    var allowed: () -> Set<String> = { [] }
    @Published private(set) var access: Access = .unknown

    private var timer: Timer?
    private var lastID: Int64 = 0
    private static let path = NSHomeDirectory() + "/Library/Group Containers/group.com.apple.usernoted/db2/db"

    /// App yang ditawarkan di Pengaturan: bundle id → nama.
    static let known: [(bundle: String, name: String)] = [
        ("net.whatsapp.WhatsApp", "WhatsApp"),
        ("com.hnc.Discord", "Discord"),
        ("ru.keepcoder.Telegram", "Telegram"),
        ("com.tdesktop.Telegram", "Telegram"),
        ("com.apple.MobileSMS", "Pesan"),
        ("com.apple.mail", "Mail"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.microsoft.teams2", "Teams"),
    ]

    static func name(of bundle: String) -> String {
        known.first { $0.bundle == bundle }?.name ?? bundle.split(separator: ".").last.map(String.init) ?? bundle
    }

    func setEnabled(_ enabled: Bool) {
        timer?.invalidate()
        timer = nil
        guard enabled else { return }
        lastID = Self.query { _ in }.maxID ?? 0 // mulai dari sekarang: yang lama tidak dimunculkan
        refreshAccess()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer?.tolerance = 1
    }

    /// Cek ulang izin (mis. setelah pengguna memberi Akses Disk Penuh).
    func refreshAccess() {
        access = Self.canOpen() ? .ok : .denied
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func poll() {
        let result = Self.query(after: lastID) { _ in }
        if result.denied {
            if access != .denied { access = .denied }
            return
        }
        if access != .ok { access = .ok }
        guard !result.rows.isEmpty else { return }
        lastID = max(lastID, result.maxID ?? lastID)
        let wanted = allowed()
        for row in result.rows where wanted.contains(row.bundle) {
            onMessage?(Message(bundle: row.bundle, app: Self.name(of: row.bundle), title: row.title, body: row.body))
        }
    }

    // MARK: Pembacaan database

    private struct Row { let bundle: String; let title: String; let body: String }
    private struct Result { var rows: [Row] = []; var maxID: Int64?; var denied = false }

    private static func canOpen() -> Bool {
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return false }
        return sqlite3_exec(db, "SELECT 1 FROM record LIMIT 1", nil, nil, nil) == SQLITE_OK
    }

    private static func query(after: Int64 = -1, _ each: (Row) -> Void) -> Result {
        var result = Result()
        var db: OpaquePointer?
        defer { sqlite3_close(db) }
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { result.denied = true; return result }
        sqlite3_busy_timeout(db, 200)
        let sql = """
            SELECT record.rec_id, app.identifier, record.data FROM record
            JOIN app ON app.app_id = record.app_id
            WHERE record.rec_id > ? ORDER BY record.rec_id
            """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { result.denied = true; return result }
        sqlite3_bind_int64(stmt, 1, after)
        while sqlite3_step(stmt) == SQLITE_ROW {
            let id = sqlite3_column_int64(stmt, 0)
            result.maxID = max(result.maxID ?? id, id)
            guard after >= 0, let cBundle = sqlite3_column_text(stmt, 1) else { continue }
            let bundle = String(cString: cBundle)
            var title = "", body = ""
            if let blob = sqlite3_column_blob(stmt, 2) {
                let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 2)))
                if let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let req = plist["req"] as? [String: Any] {
                    title = req["titl"] as? String ?? ""
                    body = req["body"] as? String ?? ""
                    if let sub = req["subt"] as? String, !sub.isEmpty { title = title.isEmpty ? sub : "\(title) · \(sub)" }
                }
            }
            let row = Row(bundle: bundle, title: title, body: body)
            result.rows.append(row)
            each(row)
        }
        return result
    }
}
