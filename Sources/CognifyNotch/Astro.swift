import Foundation
import SwiftUI

/// Bintang, rasi, dan planet nyata untuk langit malam. Semua dihitung lokal dari lokasi dan waktu.
enum SkyChart {
    struct Star { let ra: Double; let dec: Double; let mag: Double }
    struct Label { let name: String; let ra: Double; let dec: Double }

    static let stars: [Star] = SkyData.stars.split(separator: ";").compactMap {
        let p = $0.split(separator: ",").compactMap { Double($0) }
        return p.count == 3 ? Star(ra: p[0], dec: p[1], mag: p[2]) : nil
    }
    static let lines: [[Star]] = SkyData.lines.split(separator: "|").map {
        $0.split(separator: ";").compactMap {
            let p = $0.split(separator: ",").compactMap { Double($0) }
            return p.count == 2 ? Star(ra: p[0], dec: p[1], mag: 0) : nil
        }
    }
    static let names: [Label] = SkyData.names.split(separator: ";").compactMap {
        let p = $0.split(separator: ",")
        guard p.count == 3, let ra = Double(p[1]), let dec = Double(p[2]) else { return nil }
        return Label(name: String(p[0]), ra: ra, dec: dec)
    }

    /// Titik pandang pengamat: lintang dan waktu sidereal lokal pada saat tertentu.
    struct Sight {
        let lat: Double
        let lst: Double
        let date: Date

        init(lat: Double, lon: Double, date: Date) {
            self.lat = lat
            self.date = date
            let jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
            let gmst = 280.46061837 + 360.98564736629 * (jd - 2_451_545.0)
            lst = (gmst + lon).truncatingRemainder(dividingBy: 360)
        }

        /// Tinggi dan arah (0 = utara, 90 = timur) dalam derajat.
        func altAz(ra: Double, dec: Double) -> (alt: Double, az: Double) {
            let d = dec * .pi / 180, h = (lst - ra) * .pi / 180, p = lat * .pi / 180
            let alt = asin(max(-1, min(1, sin(d) * sin(p) + cos(d) * cos(p) * cos(h))))
            let az = atan2(-cos(d) * sin(h), sin(d) * cos(p) - cos(d) * cos(h) * sin(p))
            return (alt * 180 / .pi, (az * 180 / .pi + 360).truncatingRemainder(dividingBy: 360))
        }

        /// Layar menghadap selatan di belahan utara dan utara di belahan selatan, lebar pandang 150°.
        func point(_ s: (alt: Double, az: Double), _ size: CGSize) -> CGPoint {
            let facing: Double = lat >= 0 ? 180 : 0
            let d = (s.az - facing + 540).truncatingRemainder(dividingBy: 360) - 180
            return CGPoint(x: size.width / 2 + d / 150 * size.width, y: size.height * (0.66 - s.alt / 62 * 0.62))
        }
    }

    struct Planet { let name: String; let ra: Double; let dec: Double; let mag: Double; let color: Color }

    /// Posisi planet terang dengan unsur orbit sederhana (galat sekitar satu derajat, cukup untuk dilukis).
    static func planets(_ date: Date) -> [Planet] {
        let d = date.timeIntervalSince1970 / 86_400 + 2_440_587.5 - 2_451_543.5
        let rad = Double.pi / 180
        func kepler(_ M: Double, _ e: Double) -> Double {
            var E = M + e * sin(M) * (1 + e * cos(M))
            for _ in 0..<4 { E -= (E - e * sin(E) - M) / (1 - e * cos(E)) }
            return E
        }
        func helio(N: Double, i: Double, w: Double, a: Double, e: Double, M: Double) -> (Double, Double, Double) {
            let E = kepler((M.truncatingRemainder(dividingBy: 360)) * rad, e)
            let xv = a * (cos(E) - e), yv = a * sqrt(1 - e * e) * sin(E)
            let v = atan2(yv, xv), r = hypot(xv, yv), u = v + w * rad
            return (r * (cos(N * rad) * cos(u) - sin(N * rad) * sin(u) * cos(i * rad)),
                    r * (sin(N * rad) * cos(u) + cos(N * rad) * sin(u) * cos(i * rad)),
                    r * sin(u) * sin(i * rad))
        }
        let sun = helio(N: 0, i: 0, w: 282.9404 + 4.70935e-5 * d, a: 1, e: 0.016709 - 1.151e-9 * d, M: 356.0470 + 0.9856002585 * d)
        let ecl = (23.4393 - 3.563e-7 * d) * rad
        let defs: [(String, Double, Double, Double, Double, Double, Double, Double, Color)] = [
            ("Mercury", 48.3313 + 3.24587e-5 * d, 7.0047 + 5e-8 * d, 29.1241 + 1.01444e-5 * d, 0.387098, 0.205635 + 5.59e-10 * d, 168.6562 + 4.0923344368 * d, 0.0, Color(red: 0.82, green: 0.80, blue: 0.78)),
            ("Venus", 76.6799 + 2.46590e-5 * d, 3.3946 + 2.75e-8 * d, 54.8910 + 1.38374e-5 * d, 0.723330, 0.006773 - 1.302e-9 * d, 48.0052 + 1.6021302244 * d, -4.0, Color(red: 1, green: 0.96, blue: 0.82)),
            ("Mars", 49.5574 + 2.11081e-5 * d, 1.8497 - 1.78e-8 * d, 286.5016 + 2.92961e-5 * d, 1.523688, 0.093405 + 2.516e-9 * d, 18.6021 + 0.5240207766 * d, 0.5, Color(red: 1, green: 0.62, blue: 0.42)),
            ("Jupiter", 100.4542 + 2.76854e-5 * d, 1.3030 - 1.557e-7 * d, 273.8777 + 1.64505e-5 * d, 5.20256, 0.048498 + 4.469e-9 * d, 19.8950 + 0.0830853001 * d, -2.2, Color(red: 1, green: 0.93, blue: 0.80)),
            ("Saturn", 113.6634 + 2.38980e-5 * d, 2.4886 - 1.081e-7 * d, 339.3939 + 2.97661e-5 * d, 9.55475, 0.055546 - 9.499e-9 * d, 316.9670 + 0.0334442282 * d, 0.8, Color(red: 0.96, green: 0.90, blue: 0.72)),
        ]
        return defs.map { p in
            let h = helio(N: p.1, i: p.2, w: p.3, a: p.4, e: p.5, M: p.6)
            let x = h.0 + sun.0, y = h.1 + sun.1, z = h.2
            let ye = y * cos(ecl) - z * sin(ecl), ze = y * sin(ecl) + z * cos(ecl)
            let ra = (atan2(ye, x) / rad + 360).truncatingRemainder(dividingBy: 360)
            return Planet(name: p.0, ra: ra, dec: atan2(ze, hypot(x, ye)) / rad, mag: p.7, color: p.8)
        }
    }
}
