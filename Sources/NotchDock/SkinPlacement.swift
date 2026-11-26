import Foundation

// Penempatan jendela skin: tidak pernah keluar layar, baik saat diperbesar maupun diseret. Layar tujuan saat menyeret adalah
// layar tempat kursor berada, jadi skin tetap bisa dipindah ke layar kedua. Sama dengan `clamp_to` dan `fit_scale` di skins.rs.

public enum SkinPlacement {
    /// Menggeser `frame` supaya seluruhnya berada di dalam `area` (bila lebih besar dari area, menempel di tepi kiri dan bawah).
    public static func clamp(_ frame: CGRect, into area: CGRect) -> CGRect {
        var f = frame
        f.origin.x = min(max(f.origin.x, area.minX), max(area.minX, area.maxX - f.width))
        f.origin.y = min(max(f.origin.y, area.minY), max(area.minY, area.maxY - f.height))
        return f
    }

    /// Pengali yang diminta, dikecilkan bila dengan itu skin tidak muat di layar (96% area terlihat). Paling kecil 50%.
    public static func fit(_ wanted: Double, base: CGSize, area: CGSize) -> Double {
        let limit = min(area.width * 0.96 / base.width, area.height * 0.96 / base.height)
        return max(0.5, min(wanted, limit, 2.5))
    }
}
