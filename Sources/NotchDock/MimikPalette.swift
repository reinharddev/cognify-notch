import Foundation

// Palet acak untuk playground skin Mimik. Acak dulu memilih tiga warna bebas dan sering menghasilkan mata yang nyaris tak
// terlihat; kini kepala dan mata dijamin kontras (WCAG minimal 7:1), cincin berada di antara keduanya, dan rona dipilih dari
// skema yang serasi (satu rona, berdekatan, atau berlawanan).

public enum MimikPalette {
    public struct Colors: Equatable {
        public var skin: String, ink: String, ring: String
    }

    static func rgb(hue: Double, sat: Double, bri: Double) -> (Double, Double, Double) {
        let h = (hue - hue.rounded(.down)) * 6, c = bri * sat, x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1)), m = bri - c
        let (r, g, b): (Double, Double, Double)
        switch Int(h) {
        case 0: (r, g, b) = (c, x, 0)
        case 1: (r, g, b) = (x, c, 0)
        case 2: (r, g, b) = (0, c, x)
        case 3: (r, g, b) = (0, x, c)
        case 4: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        return (r + m, g + m, b + m)
    }

    static func hex(_ c: (Double, Double, Double)) -> String {
        func byte(_ v: Double) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", byte(c.0), byte(c.1), byte(c.2))
    }

    static func parse(_ hex: String) -> (Double, Double, Double)? {
        var h = hex; if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        return (Double((v >> 16) & 255) / 255, Double((v >> 8) & 255) / 255, Double(v & 255) / 255)
    }

    static func luminance(_ c: (Double, Double, Double)) -> Double {
        func lin(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
    }

    /// Rasio kontras WCAG (1...21) antara dua warna hex.
    public static func contrast(_ a: String, _ b: String) -> Double {
        guard let x = parse(a), let y = parse(b) else { return 1 }
        let la = luminance(x), lb = luminance(y)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    public static func random<G: RandomNumberGenerator>(using g: inout G) -> Colors {
        let hue = Double.random(in: 0..<1, using: &g)
        let dark = Double.random(in: 0..<1, using: &g) < 0.75
        let inkHue = hue + [0, 0, 0.08, -0.08, 0.5, 0.33].randomElement(using: &g)!
        let skin = dark ? rgb(hue: hue, sat: .random(in: 0.35...0.8, using: &g), bri: .random(in: 0.07...0.2, using: &g))
                        : rgb(hue: hue, sat: .random(in: 0.04...0.2, using: &g), bri: .random(in: 0.93...0.98, using: &g))
        var inkSat = dark ? Double.random(in: 0.2...0.7, using: &g) : Double.random(in: 0.5...0.9, using: &g)
        var inkBri = dark ? Double.random(in: 0.9...1.0, using: &g) : Double.random(in: 0.12...0.3, using: &g)
        let skinHex = hex(skin)
        var inkHex = hex(rgb(hue: inkHue, sat: inkSat, bri: inkBri))
        var guardCount = 0
        while contrast(skinHex, inkHex) < 7, guardCount < 30 {
            inkBri = dark ? min(1, inkBri + 0.03) : max(0.02, inkBri - 0.03)
            inkSat = max(0, inkSat - 0.03)
            inkHex = hex(rgb(hue: inkHue, sat: inkSat, bri: inkBri))
            guardCount += 1
        }
        let ink = parse(inkHex)!
        let ring = (skin.0 + (ink.0 - skin.0) * 0.28, skin.1 + (ink.1 - skin.1) * 0.28, skin.2 + (ink.2 - skin.2) * 0.28)
        return Colors(skin: skinHex, ink: inkHex, ring: hex(ring))
    }

    public static func random() -> Colors {
        var g = SystemRandomNumberGenerator()
        return random(using: &g)
    }
}
