import SwiftUI

// Token tampilan notch (lihat docs/desain/rencana-penyegaran-notch.md). Warna aksen ada di `Color.accent`,
// gerak di `Animation.notch` dan `.tabSwitch`.

enum Theme {
    /// Isian di atas latar apa pun: putih tembus pandang, jadi ikut warna tema di belakangnya.
    static let card = LinearGradient(colors: [.white.opacity(0.08), .white.opacity(0.05)], startPoint: .top, endPoint: .bottom)
    static let edge = Color.white.opacity(0.09)
    static let track = Color.white.opacity(0.1)
    static let textSecondary = Color.white.opacity(0.55)

    /// Konsentris: panel 28, kartu 20, isi kartu 12, dengan jarak 8.
    enum Radius {
        static let card: CGFloat = 20
        static let item: CGFloat = 12
    }

    /// Kelipatan 4.
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
    }
}
