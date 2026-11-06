import AppKit
import SwiftUI

/// Tema kaca: macOS 26 memakai Liquid Glass asli; versi lama memakai material dan refraksi ringan buatan app.
enum NotchTheme: String, CaseIterable, Identifiable {
    case dark, glass
    var id: String { rawValue }
    var label: String { self == .dark ? L("Gelap (bawaan)", "Dark (default)") : "Liquid Glass" }

    /// Tema kaca punya fallback untuk versi lama; macOS 26 memakai Liquid Glass asli.
    static var glassSupported: Bool { true }
}

struct GlassSurface: View {
    let shape: AnyShape
    /// 0 = bening, 1 = berwarna penuh.
    let tint: Double
    let color: Color
    /// 0 sampai 1: kekuatan kilau tepi dan refraksi pada pantulan.
    let distortion: Double

    var body: some View {
        ZStack {
            base
            // Pelindung agar tulisan tetap terbaca di atas latar terang: makin berwarna, makin pekat.
            shape.fill(color.opacity(0.08 + 0.45 * tint))
            GlassSheen(shape: shape, distortion: distortion)
            if #unavailable(macOS 26.0) {
                LiquidRefraction(shape: shape, strength: min(distortion, 0.55))
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
    }

    @ViewBuilder private var base: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(tint < 0.15 ? Glass.clear : Glass.regular.tint(color.opacity(tint * 0.5)), in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }

}

/// Distorsi halus pada pantulan kaca, bukan pada desktop di balik panel. Tidak dianimasikan.
private struct LiquidRefraction: View {
    let shape: AnyShape
    let strength: Double

    var body: some View {
        GeometryReader { geo in
            ZStack {
                LinearGradient(colors: [.white.opacity(0.08), .clear, .white.opacity(0.035)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Ellipse()
                    .fill(RadialGradient(colors: [.white.opacity(0.14 * strength), .clear],
                                         center: .center, startRadius: 0, endRadius: geo.size.width * 0.34))
                    .frame(width: geo.size.width * 0.66, height: geo.size.height * 0.8)
                    .position(x: geo.size.width * 0.32, y: geo.size.height * 0.3)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .modifier(LiquidDistortion(size: geo.size, strength: strength))
            .clipShape(shape)
        }
        .allowsHitTesting(false)
    }
}

private struct LiquidDistortion: ViewModifier {
    let size: CGSize
    let strength: Double

    @ViewBuilder func body(content: Content) -> some View {
        if #available(macOS 14.0, *) {
            content.distortionEffect(
                ShaderLibrary.bundle(.module).liquidRefraction(
                    .float2(CGSize(width: size.width, height: size.height)),
                    .float(Float(strength * 1.8))),
                maxSampleOffset: CGSize(width: 2, height: 2))
        } else {
            content
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
