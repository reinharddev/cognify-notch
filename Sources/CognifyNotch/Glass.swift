import AppKit
import SwiftUI

/// Tema "Liquid Glass": hanya di macOS 26 ke atas, memakai Liquid Glass asli dari sistem (lensa dan pembiasan latar
/// ikut dari sistem) ditambah kilau tepi.
enum NotchTheme: String, CaseIterable, Identifiable {
    case dark, glass
    var id: String { rawValue }
    var label: String { self == .dark ? L("Gelap (bawaan)", "Dark (default)") : "Liquid Glass" }

    /// Liquid Glass asli hanya ada di macOS 26 ke atas; di versi lama pilihannya tidak ditampilkan.
    static var glassSupported: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

struct GlassSurface: View {
    let shape: AnyShape
    /// 0 = bening, 1 = berwarna penuh.
    let tint: Double
    let color: Color
    /// 0 sampai 1: kekuatan kilau tepi dan pantulan cair yang bergerak pelan.
    let distortion: Double

    var body: some View {
        ZStack {
            base
            // Pelindung agar tulisan tetap terbaca di atas latar terang: makin berwarna, makin pekat.
            shape.fill(color.opacity(0.08 + 0.45 * tint))
            GlassSheen(shape: shape, distortion: distortion)
        }
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }

    @ViewBuilder private var base: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(tint < 0.15 ? Glass.clear : Glass.regular.tint(color.opacity(tint * 0.5)), in: shape)
        }
    }

}

/// Kilau di tepi dan pantulan cahaya yang diam. Pantulan yang bergerak tiap frame membuat kaca asli digambar ulang
/// terus-menerus dan memakan sekitar 13% CPU, jadi sengaja tidak dianimasikan.
struct GlassSheen: View {
    let shape: AnyShape
    let distortion: Double

    var body: some View {
        ZStack {
            shape.stroke(
                LinearGradient(colors: [.white.opacity(0.18 + 0.5 * distortion), .white.opacity(0.02), .white.opacity(0.1 + 0.3 * distortion)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1)
            if distortion > 0.02 {
                GeometryReader { geo in
                    Ellipse()
                        .fill(RadialGradient(colors: [.white.opacity(0.22 * distortion), .clear], center: .center, startRadius: 0, endRadius: geo.size.width * 0.28))
                        .frame(width: geo.size.width * 0.6, height: geo.size.height * 0.9)
                        .position(x: geo.size.width * 0.3, y: geo.size.height * 0.3)
                }
                .clipShape(shape)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Lensa kaca asli di atas latar lain (misalnya langit): tepi membiaskan dan mengilap, isi tetap terlihat.
struct GlassLens: View {
    let shape: AnyShape

    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(Glass.clear, in: shape).allowsHitTesting(false)
        }
    }
}

/// Ubin kaca untuk tombol kecil (ikon dock); `tint` mewarnai ubin yang sedang aktif.
struct GlassTile: View {
    let radius: CGFloat
    var tint: Color?

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(tint.map { Glass.regular.tint($0.opacity(0.75)) } ?? Glass.clear, in: shape)
        } else {
            shape.fill(tint ?? Color.white.opacity(0.14))
        }
    }
}
