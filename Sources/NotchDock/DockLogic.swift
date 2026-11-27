import Foundation
import CoreGraphics

// Aturan dock Mac yang murni (tanpa AppKit atau SwiftUI), supaya bisa diuji. Rumusnya sama dengan dock Notch Windows
// (notch-windows/src/lib/dockLayout.ts): satu baris, tidak boleh melewati layar, radius konsentris.

public enum DockMetrics {
    public static let pad: CGFloat = 10
    public static let gap: CGFloat = 6
    /// Jarak antar ikon aplikasi. Tiap sel sudah punya ruang sendiri di sekeliling ikon.
    public static let cellGap: CGFloat = 2
    /// Jarak minimal dock dari tepi kiri dan kanan layar.
    public static let edge: CGFloat = 16
    /// Dock harus menyisakan tempat untuk sekian ikon aplikasi; selebihnya tidak boleh ditambah.
    public static let minAppSlots = 4
    public static let clockWidth: CGFloat = 92
    public static let pillH: CGFloat = 28
    public static let toolSize: CGFloat = 32
    public static let iconMin: CGFloat = 28
    public static let iconMax: CGFloat = 56

    public static func cell(_ icon: CGFloat) -> CGFloat { icon + 12 }
    /// Lebar terbesar yang boleh dipakai dock di layar selebar `screenW`.
    public static func maxWidth(_ screenW: CGFloat) -> CGFloat { max(240, screenW.rounded(.down) - edge * 2) }
}

/// Widget di antara aplikasi dan jam. Lebarnya tetap (tidak bergantung isi), jadi lebar dock bisa dihitung sebelum digambar.
public enum DockModule: String, CaseIterable, Codable, Identifiable {
    case media, lyrics, weather, timer, clipboard, links, battery, volume
    public var id: String { rawValue }
    /// Lebar modul. Hanya `links` bergantung pada pengaturan (jumlah tautan dan ukuran ikon); sisanya tetap.
    public func width(links: Int = 0, iconSize: CGFloat = 40) -> CGFloat {
        switch self {
        case .media: return 288
        case .lyrics: return 240
        case .weather: return 76
        case .timer: return 173    // padding 4 + ikon 15 + jarak 8 + 3 tombol 46 + 2 jarak 4 (sama dengan dock Windows)
        case .clipboard: return 228
        case .battery: return 60
        case .volume: return 104
        case .links:
            let n = CGFloat(max(1, links))
            return n * DockMetrics.cell(iconSize) + (n - 1) * DockMetrics.cellGap
        }
    }
    /// Data tersimpan: id tak dikenal dan duplikat dibuang.
    public static func clean(_ raw: [String]) -> [DockModule] {
        var seen = Set<DockModule>()
        return raw.compactMap { DockModule(rawValue: $0) }.filter { seen.insert($0).inserted }
    }
}

public struct DockConfig: Equatable {
    public var iconSize: CGFloat
    public var showClock: Bool
    public var modules: [DockModule]
    /// Jumlah pintasan tautan (menentukan lebar modul Tautan).
    public var links: Int
    public init(iconSize: CGFloat = 40, showClock: Bool = true, modules: [DockModule] = [], links: Int = 0) {
        self.links = links
        self.iconSize = min(DockMetrics.iconMax, max(DockMetrics.iconMin, iconSize))
        self.showClock = showClock
        self.modules = modules
    }
}

public enum DockLayout {
    /// Lebar seluruh dock dengan `apps` ikon aplikasi: padding, Start, aplikasi, jam, dan jarak antar kelompok.
    public static func width(apps: Int, _ cfg: DockConfig) -> CGFloat {
        let c = DockMetrics.cell(cfg.iconSize)
        var parts: [CGFloat] = [c]
        if apps > 0 { parts.append(CGFloat(apps) * c + CGFloat(apps - 1) * DockMetrics.cellGap) }
        parts += cfg.modules.map { $0.width(links: cfg.links, iconSize: cfg.iconSize) }
        if cfg.showClock { parts.append(DockMetrics.clockWidth) }
        return DockMetrics.pad * 2 + parts.reduce(0, +) + DockMetrics.gap * CGFloat(parts.count - 1)
    }

    /// Berapa ikon aplikasi muat di layar selebar `screenW`.
    public static func appSlots(screenW: CGFloat, _ cfg: DockConfig) -> Int {
        let c = DockMetrics.cell(cfg.iconSize)
        let others = width(apps: 0, cfg) // padding, Start, jam
        let free = DockMetrics.maxWidth(screenW) - others - DockMetrics.gap
        return max(0, Int(((free + DockMetrics.cellGap) / (c + DockMetrics.cellGap)).rounded(.down)))
    }

    /// Apakah dock muat dengan tempat minimal untuk aplikasi. Bila tidak, jam gugur lebih dulu (lihat `fitted`).
    public static func fits(screenW: CGFloat, _ cfg: DockConfig) -> Bool { appSlots(screenW: screenW, cfg) >= DockMetrics.minAppSlots }

    /// Boleh menambah widget `m`? Tidak bila sudah ada, atau bila dock jadi tidak muat.
    public static func canAdd(_ m: DockModule, _ cfg: DockConfig, screenW: CGFloat) -> Bool {
        if cfg.modules.contains(m) { return false }
        var next = cfg; next.modules.append(m)
        return fits(screenW: screenW, next)
    }

    /// Pengaturan yang pasti muat: widget dari ujung kanan gugur dulu, lalu jam. Ukuran ikon dikecilkan hanya sebagai jalan terakhir.
    public static func fitted(screenW: CGFloat, _ cfg: DockConfig) -> DockConfig {
        var out = cfg
        while !fits(screenW: screenW, out), !out.modules.isEmpty { out.modules.removeLast() }
        if !fits(screenW: screenW, out) { out.showClock = false }
        while !fits(screenW: screenW, out) && out.iconSize > DockMetrics.iconMin { out.iconSize -= 4; out.iconSize = max(DockMetrics.iconMin, out.iconSize) }
        return out
    }

    /// Ikon yang digambar dan sisanya (masuk menu "+N"). Satu tempat dipakai tombol "+N" bila ada sisa.
    public static func split<T>(_ items: [T], slots: Int) -> (shown: [T], rest: [T]) {
        if items.count <= slots { return (items, []) }
        let keep = max(0, slots - 1)
        return (Array(items.prefix(keep)), Array(items.dropFirst(keep)))
    }

    /// Seperti `split`, tapi yang sedang terbuka didahulukan tampil: bila tidak semua muat, yang disematkan tapi belum terbuka
    /// masuk "+N" lebih dulu (dari ujung kanan), baru yang terbuka. Urutan yang tampil tidak berubah.
    public static func splitByUse<T>(_ items: [T], slots: Int, isRunning: (T) -> Bool) -> (shown: [T], rest: [T]) {
        if items.count <= slots { return (items, []) }
        let keep = max(0, slots - 1)
        let need = items.count - keep
        var hide = Set<Int>()
        for wantRunning in [false, true] {
            for i in items.indices.reversed() where hide.count < need && isRunning(items[i]) == wantRunning { hide.insert(i) }
        }
        let shown = items.indices.filter { !hide.contains($0) }.map { items[$0] }
        let rest = items.indices.filter { hide.contains($0) }.map { items[$0] }
        return (shown, rest)
    }

    /// Indeks sel terdekat dengan `x` (untuk menjatuhkan ikon yang diseret). -1 bila tidak ada sel.
    public static func dropIndex(x: CGFloat, centers: [CGFloat]) -> Int {
        guard !centers.isEmpty else { return -1 }
        return centers.indices.min { abs(centers[$0] - x) < abs(centers[$1] - x) } ?? -1
    }

    /// Titik kiri-bawah dock: di tengah layar, di atas Dock bawaan macOS (`visible.minY` sudah memperhitungkannya)
    /// dengan jarak `margin`, dan tidak pernah lebih dekat dari `edge` ke tepi kiri atau kanan.
    public static func origin(screen: CGRect, visible: CGRect, size: CGSize, margin: CGFloat, reserve: CGFloat = 0) -> CGPoint {
        let lo = screen.minX + DockMetrics.edge
        let hi = max(lo, screen.maxX - DockMetrics.edge - size.width)
        let x = min(hi, max(lo, screen.midX - size.width / 2))
        // `reserve`: ruang untuk Dock macOS yang disembunyikan otomatis di bawah (tidak masuk `visible`, tapi muncul di sana saat kursor ke tepi).
        return CGPoint(x: x, y: max(visible.minY, screen.minY + max(0, reserve)) + max(0, margin))
    }
}

/// Radius konsentris (radius luar = radius dalam + jarak). Rumusnya sama dengan `dockRadii` di dock Windows.
public struct DockRadii: Equatable {
    public var outer: CGFloat
    public var cell: CGFloat
    public var tile: CGFloat
    /// Tombol kapsul (tinggi `DockMetrics.pillH`) dan tombol ikon bulat (`DockMetrics.toolSize`), di tengah vertikal.
    public var pill: CGFloat
    public var tool: CGFloat
}

public func dockRadii(round: Double, icon: CGFloat) -> DockRadii {
    let t = min(100, max(0, round.isFinite ? round : 100))
    let cellH = DockMetrics.cell(icon)
    let half = (cellH + DockMetrics.pad * 2) / 2
    let outer = (half * CGFloat(0.2 + 0.8 * (t / 100))).rounded()
    func at(_ distance: CGFloat, _ side: CGFloat) -> CGFloat { max(0, min(side / 2, outer - distance)) }
    func mid(_ side: CGFloat) -> CGFloat { at(DockMetrics.pad + (cellH - side) / 2, side) }
    return DockRadii(outer: outer, cell: at(DockMetrics.pad, cellH), tile: at(DockMetrics.pad + (cellH - icon) / 2, icon),
                     pill: mid(DockMetrics.pillH), tool: mid(DockMetrics.toolSize))
}

// MARK: - Aplikasi

public struct DockPin: Codable, Equatable, Hashable {
    public var id: String   // bundle id
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct DockRunning: Equatable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct DockEntry: Equatable, Identifiable {
    public var id: String
    public var name: String
    public var pinned: Bool
    public var running: Bool
}

public enum DockApps {
    /// Yang disematkan di depan (urutan sematan), lalu aplikasi berjalan yang belum disematkan (urutan peluncuran).
    public static func entries(pins: [DockPin], running: [DockRunning]) -> [DockEntry] {
        let live = Set(running.map(\.id))
        var out = pins.map { DockEntry(id: $0.id, name: $0.name, pinned: true, running: live.contains($0.id)) }
        let pinned = Set(pins.map(\.id))
        for r in running where !pinned.contains(r.id) && !out.contains(where: { $0.id == r.id }) {
            out.append(DockEntry(id: r.id, name: r.name, pinned: false, running: true))
        }
        return out
    }

    public static func togglePin(_ pins: [DockPin], id: String, name: String) -> [DockPin] {
        pins.contains { $0.id == id } ? pins.filter { $0.id != id } : pins + [DockPin(id: id, name: name)]
    }

    public static func movePin(_ pins: [DockPin], id: String, by offset: Int) -> [DockPin] {
        guard let from = pins.firstIndex(where: { $0.id == id }) else { return pins }
        let to = from + offset
        guard to >= 0, to < pins.count else { return pins }
        var next = pins
        next.swapAt(from, to)
        return next
    }

    /// Pindahkan sematan `id` ke indeks `to` (dijepit ke rentang yang ada); dipakai saat ikon diseret.
    public static func move(_ pins: [DockPin], id: String, to index: Int) -> [DockPin] {
        guard let from = pins.firstIndex(where: { $0.id == id }) else { return pins }
        let to = max(0, min(pins.count - 1, index))
        guard to != from else { return pins }
        var next = pins
        let item = next.remove(at: from)
        next.insert(item, at: to)
        return next
    }

    /// Data tersimpan: entri rusak dan duplikat dibuang.
    public static func cleanPins(_ raw: [DockPin]) -> [DockPin] {
        var seen = Set<String>()
        return raw.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }
}

// MARK: - Latar dan warna teks

/// Latar dock. `follow` mengikuti notch (tema, warna, gradien, atau gambar); sisanya berdiri sendiri.
public enum DockBackground: String, CaseIterable, Identifiable {
    case follow, glass, color, gradient
    public var id: String { rawValue }
}

/// Warna teks yang terbaca di atas latar: gelap di latar terang, terang di latar gelap (ambang WCAG yang sama dengan dock Windows).
public enum DockInk {
    /// Luminans relatif WCAG dari "#RRGGBB" (atau "RRGGBB"); nil bila bukan warna.
    public static func luminance(hex: String) -> Double? {
        var h = hex.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        func lin(_ c: UInt32) -> Double { let x = Double(c) / 255; return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin((v >> 16) & 255) + 0.7152 * lin((v >> 8) & 255) + 0.0722 * lin(v & 255)
    }

    /// Teks gelap bila latarnya terang. Ambang 0.18 = titik tengah kontras putih dan hitam.
    public static func isDark(onLuminance luma: Double) -> Bool { luma > 0.18 }

    /// Satu luminans untuk dua warna gradien: bila salah satunya terang teks gelap menang, supaya di sisi terang tetap terbaca.
    public static func gradientLuminance(_ a: Double, _ b: Double) -> Double { max(a, b) > 0.45 ? max(a, b) : (a + b) / 2 }
}

/// Efek pembesaran ala Dock macOS: ikon di bawah kursor membesar banyak, tetangganya ikut membesar menurun halus (kurva kosinus),
/// ikon tumbuh ke atas, dan dock melebar mengikutinya. `Magnification` di pengaturan (0 sampai 100) menentukan puncaknya.
public enum DockMagnify {
    public static let maxScale: CGFloat = 1.3
    /// Berapa sel di kiri dan kanan kursor yang ikut membesar.
    public static let reachCells: CGFloat = 2.4

    /// Skala 1 sampai `maxScale` menurut jarak pusat ikon ke kursor; sejauh `reach` atau lebih = 1.
    public static func scale(distance: CGFloat, reach: CGFloat, max maxScale: CGFloat = DockMagnify.maxScale) -> CGFloat {
        guard reach > 0, distance.isFinite else { return 1 }
        let d = Swift.min(1, abs(distance) / reach)
        return 1 + (maxScale - 1) * (CoreGraphics.cos(d * .pi) + 1) / 2
    }

    /// Skala puncak dari pengaturan: 0 = tanpa pembesaran (1), 100 = 2,2 kali.
    public static func peak(percent: Double) -> CGFloat {
        let p = percent.isFinite ? Swift.min(100, Swift.max(0, percent)) : 0
        return 1 + 1.2 * CGFloat(p / 100)
    }

    /// Skala tiap ikon untuk kursor di `pointer` (satu sumbu dengan `restCenters`, pusat saat diam); semua 1 bila kursor nil.
    public static func scales(restCenters: [CGFloat], pointer: CGFloat?, cell: CGFloat, peak: CGFloat) -> [CGFloat] {
        guard let pointer, peak > 1.0001 else { return restCenters.map { _ in 1 } }
        return restCenters.map { scale(distance: pointer - $0, reach: cell * reachCells, max: peak) }
    }

    /// Ruang di atas dock untuk ikon yang tumbuh ke atas dan label namanya.
    public static func headroom(icon: CGFloat, peak: CGFloat) -> CGFloat { (icon * (peak - 1)).rounded(.up) + 34 }

    /// Lebar tambahan dock saat ikon membesar (jumlah pertumbuhan lebar paling banyak), dengan sedikit cadangan.
    public static func extraWidth(cell: CGFloat, peak: CGFloat) -> CGFloat { ((peak - 1) * reachCells * cell).rounded(.up) + 12 }
}

// MARK: - Tautan

public struct DockLink: Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var url: String
    public init(id: String = UUID().uuidString, label: String, url: String) { self.id = id; self.label = label; self.url = url }
}

public enum DockLinks {
    public static let maxCount = 8

    /// Pintasan hanya untuk http dan https (dibuka lewat sistem, jadi skema lain ditolak). Nil bila bukan alamat web.
    public static func normalize(_ input: String) -> String? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return nil }
        let withScheme = text.range(of: "^[A-Za-z][A-Za-z0-9+.-]*://", options: .regularExpression) != nil ? text : "https://" + text
        guard let url = URL(string: withScheme), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty, host.contains(".") || host == "localhost" else { return nil }
        return url.absoluteString
    }

    /// Nama bawaan dari alamat: host tanpa "www.".
    public static func defaultLabel(for url: String) -> String {
        let host = URL(string: url)?.host ?? url
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Data tersimpan: entri rusak dibuang, alamat dirapikan, dan dibatasi `maxCount`.
    public static func clean(_ raw: [DockLink]) -> [DockLink] {
        var out: [DockLink] = []
        for l in raw {
            guard let url = normalize(l.url), !l.id.isEmpty else { continue }
            out.append(DockLink(id: l.id, label: String(l.label.prefix(24)), url: url))
        }
        return Array(out.prefix(maxCount))
    }

    /// Warna ikon pengganti (0 sampai 360) dari nama, supaya tiap tautan punya warna yang tetap.
    public static func hue(_ name: String) -> Double {
        var h = 0
        for u in name.unicodeScalars { h = (h * 31 + Int(u.value)) % 360 }
        return Double(h)
    }
}

// MARK: - Jendela aplikasi

public enum DockWindowTitle {
    /// Judul untuk baris menu: kosong menjadi "Tanpa judul", spasi dirapikan, dipotong 60 karakter, dan jendela yang diminimalkan ditandai.
    public static func display(_ raw: String?, minimized: Bool) -> String {
        let collapsed = (raw ?? "").split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        var title = collapsed.isEmpty ? "Untitled" : String(collapsed.prefix(60))
        if collapsed.count > 60 { title += "…" }
        return minimized ? title + " (minimized)" : title
    }
}

// MARK: - Kemajuan lagu

public enum DockMediaTime {
    /// Waktu untuk label: "1:21" atau "1:02:03".
    public static func label(_ seconds: Double) -> String {
        let s = max(0, Int(seconds.isFinite ? seconds : 0))
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%d:%02d", m, r)
    }

    /// Kemajuan 0 sampai 1; 0 bila durasi tidak diketahui.
    public static func ratio(position: Double, duration: Double?) -> Double {
        guard let duration, duration > 0, position.isFinite else { return 0 }
        return min(1, max(0, position / duration))
    }
}


/// Dock macOS bawaan yang disembunyikan otomatis di tepi bawah muncul menimpa dock kita saat kursor ke tepi. `visibleFrame`
/// tidak menghitungnya (Dock yang tersembunyi tidak memakai ruang), jadi dock kita menyisakan ruang setinggi Dock itu.
public enum NativeDock {
    /// Tinggi yang perlu disisakan di tepi bawah. Nol bila Dock tidak otomatis tersembunyi atau tidak di bawah
    /// (kalau tampil terus, `visibleFrame` sudah memperhitungkannya).
    public static func reserve(autohide: Bool, orientation: String, tile: CGFloat, large: CGFloat, magnification: Bool) -> CGFloat {
        guard autohide, orientation == "bottom" else { return 0 }
        let icon = magnification ? max(tile, large) : tile
        return (icon > 0 ? icon : 48) + 34 // ikon + bantalan Dock + jarak ke tepi
    }
}
