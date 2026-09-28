import AppKit

// Notch Cognify. Dijalankan oleh Tauri (src-tauri/src/notch.rs); lihat Bridge.swift untuk protokolnya.
let arguments = CommandLine.arguments
if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
    MainActor.assumeIsolated {
        Snapshot.run(into: URL(fileURLWithPath: arguments[index + 1]))
    }
    exit(0)
}

// `--selftest <file>`: uji koneksi ke sidecar (env COGNIFY_NOTCH_PORT/TOKEN) tanpa jendela.
if let index = arguments.firstIndex(of: "--selftest"), index + 1 < arguments.count, let info = Bridge().standalone {
    let api = API(info: info)
    let file = URL(fileURLWithPath: arguments[index + 1])
    let done = DispatchSemaphore(value: 0)
    Task {
        do {
            let state = try await api.state()
            print("state:", state.events.map { "\($0.title) @ \($0.due)" }, "diproses:", state.processing)
            print("catatan:", try await api.quickNote("Selftest notch: kumpul tugas besok jam 09.00"))
            print("upload:", try await api.upload(file))
            do { _ = try await api.upload(URL(fileURLWithPath: "/etc/hosts")) } catch { print("ditolak:", error.localizedDescription) }
        } catch {
            print("GAGAL:", error.localizedDescription)
        }
        done.signal()
    }
    done.wait()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // tanpa ikon Dock & menu
let delegate = AppDelegate()
app.delegate = delegate
app.run()
