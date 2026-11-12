import AppKit
import SwiftUI

/// Latar panel notch yang bisa diubah: warna, gradien, atau gambar sendiri. Notch yang menempel dan tertutup di Mac
/// berponi tetap hitam supaya menyatu dengan poni fisik; latar dipakai di panel terbuka dan di notch melayang.
enum BackgroundMode: String, CaseIterable, Identifiable {
    case none, color, gradient, image
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: return L("Hitam (bawaan)", "Black (default)")
        case .color: return L("Warna", "Color")
        case .gradient: return L("Gradien", "Gradient")
        case .image: return L("Gambar", "Image")
        }
    }
}

/// Paket tema: satu klik mengatur warna aksen dan latar sekaligus.
struct ThemePreset: Identifiable {
    let id: String
    let name: () -> String
    let accent: String
    let mode: BackgroundMode
    let color1: String
    let color2: String
    let angle: Double

    static let all: [ThemePreset] = [
        ThemePreset(id: "default", name: { L("Bawaan", "Default") }, accent: "", mode: .none, color1: "#000000", color2: "#000000", angle: 135),
        ThemePreset(id: "dusk", name: { L("Senja", "Dusk") }, accent: "#ff9f0a", mode: .gradient, color1: "#2a1550", color2: "#8c2f4f", angle: 150),
        ThemePreset(id: "ocean", name: { L("Laut", "Ocean") }, accent: "#32ade6", mode: .gradient, color1: "#04203a", color2: "#0a5a73", angle: 160),
        ThemePreset(id: "forest", name: { L("Hutan", "Forest") }, accent: "#30d158", mode: .gradient, color1: "#07251a", color2: "#1b4d3a", angle: 145),
        ThemePreset(id: "sakura", name: { L("Sakura", "Sakura") }, accent: "#ff6fa5", mode: .gradient, color1: "#3a1530", color2: "#7a2f5a", angle: 135),
        ThemePreset(id: "neon", name: { L("Neon", "Neon") }, accent: "#bf5af2", mode: .gradient, color1: "#0a0a1f", color2: "#2b0f4a", angle: 120),
        ThemePreset(id: "paper", name: { L("Kertas", "Paper") }, accent: "#0a84ff", mode: .color, color1: "#1f1f24", color2: "#1f1f24", angle: 135),
    ]
}

/// Gambar latar disalin ke folder data app supaya tetap ada walau berkas aslinya dipindah. Tidak ada yang dikirim ke mana pun.
enum BackgroundStore {
    static var folder: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Cognify Notch", isDirectory: true)
    }

    private static var cache: (path: String, image: NSImage)?

    /// Salin gambar pilihan ke folder data app (diperkecil, paling panjang 1600 px). Mengembalikan nama berkas.
    static func importImage(from url: URL) -> String? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > 1600 ? 1600 / longest : 1
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let small = NSImage(size: size)
        small.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1)
        small.unlockFocus()
        guard let tiff = small.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = "background-\(Int(Date().timeIntervalSince1970)).png"
        do { try png.write(to: folder.appendingPathComponent(name), options: .atomic) } catch { return nil }
        // Gambar lama dibuang supaya folder tidak menumpuk.
        if let files = try? FileManager.default.contentsOfDirectory(atPath: folder.path) {
            for f in files where f.hasPrefix("background-") && f != name { try? FileManager.default.removeItem(at: folder.appendingPathComponent(f)) }
        }
        cache = nil
        return name
    }

    static func image(named name: String) -> NSImage? {
        guard !name.isEmpty else { return nil }
        if let cache, cache.path == name { return cache.image }
        guard let image = NSImage(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        cache = (name, image)
        return image
    }

    static func clear(_ name: String) {
        guard !name.isEmpty else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        cache = nil
    }
}

/// Lapisan latar sesuai pilihan; digambar di bawah isi dan dipotong mengikuti bentuk notch.
struct CustomBackground: View {
    @ObservedObject var prefs: Preferences

    var body: some View {
        ZStack {
            switch prefs.bgMode {
            case .none:
                Color.black
            case .color:
                (Color(hex: prefs.bgColorHex) ?? .black)
            case .gradient:
                LinearGradient(colors: [Color(hex: prefs.bgColorHex) ?? .black, Color(hex: prefs.bgColor2Hex) ?? .black],
                               startPoint: Self.point(prefs.bgAngle, start: true), endPoint: Self.point(prefs.bgAngle, start: false))
            case .image:
                if let image = BackgroundStore.image(named: prefs.bgImageName) {
                    GeometryReader { geo in
                        Image(nsImage: image).resizable().scaledToFill()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .blur(radius: prefs.bgBlur * 18)
                            .clipped()
                    }
                } else {
                    Color.black
                }
            }
            // Peredam supaya tulisan tetap terbaca di atas gambar atau warna terang.
            Color.black.opacity(prefs.bgMode == .image || prefs.bgMode == .gradient ? prefs.bgDim : 0)
        }
        .allowsHitTesting(false)
    }

    /// Sudut derajat (0 = ke kanan, searah jarum jam) menjadi titik awal dan akhir gradien.
    static func point(_ angle: Double, start: Bool) -> UnitPoint {
        let r = angle * .pi / 180
        let dx = cos(r) / 2, dy = sin(r) / 2
        return start ? UnitPoint(x: 0.5 - dx, y: 0.5 - dy) : UnitPoint(x: 0.5 + dx, y: 0.5 + dy)
    }
}
