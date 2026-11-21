import Foundation

/// Mode Daya Rendah macOS. Membacanya bebas (`ProcessInfo.isLowPowerModeEnabled`), tetapi mengubahnya hanya bisa
/// lewat `pmset`, yang butuh root. macOS menampilkan dialog kata sandi (atau Touch ID) lewat
/// `with administrator privileges`; tidak ada yang disimpan, dan tidak ada helper tetap yang dipasang.
enum LowPowerMode {
    enum Failure: Error, Equatable {
        case cancelled
        case failed(String)

        var message: String {
            switch self {
            case .cancelled: return ""
            case .failed(let text): return text
            }
        }
    }

    /// Perintah AppleScript untuk mengatur mode. Dipisah supaya bisa diuji.
    static func script(for on: Bool) -> String {
        "do shell script \"/usr/bin/pmset -a lowpowermode \(on ? 1 : 0)\" with administrator privileges"
    }

    /// Menerjemahkan keluaran `osascript` yang gagal. Kode -128 = pengguna menutup dialog.
    static func failure(from stderr: String) -> Failure {
        if stderr.contains("(-128)") || stderr.lowercased().contains("user canceled") { return .cancelled }
        let line = stderr.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return .failed(line.isEmpty ? L("Mode Daya Rendah gagal diubah", "Could not change Low Power Mode") : line)
    }

    /// Memblokir sampai dialog selesai; panggil dari luar thread utama.
    static func set(_ on: Bool) -> Result<Void, Failure> {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script(for: on)]
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            return .failure(.failed(error.localizedDescription))
        }
        process.waitUntilExit()
        if process.terminationStatus == 0 { return .success(()) }
        let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return .failure(failure(from: text))
    }
}
