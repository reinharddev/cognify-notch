import SwiftUI

/// Halaman Langit: jam, lintasan matahari (setengah lingkaran), dan latar notch yang berubah pelan
/// menurut waktu dan cuaca (cerah, berawan, kabut, gerimis, hujan, salju, badai petir).

enum SkyWeather {
    case clear, partly, overcast, fog, drizzle, rain, snow, thunder

    /// Kode cuaca WMO (Open-Meteo).
    init(code: Int) {
        switch code {
        case 0: self = .clear
        case 1, 2: self = .partly
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67, 80...82: self = .rain
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .thunder
        default: self = .overcast
        }
    }

    var label: String {
        switch self {
        case .clear: return L("Cerah", "Clear")
        case .partly: return L("Cerah berawan", "Partly cloudy")
        case .overcast: return L("Berawan", "Overcast")
        case .fog: return L("Berkabut", "Foggy")
        case .drizzle: return L("Gerimis", "Drizzle")
        case .rain: return L("Hujan", "Rain")
        case .snow: return L("Salju", "Snow")
        case .thunder: return L("Badai petir", "Thunderstorm")
        }
    }

    /// Seberapa abu-abu langitnya (0 = biru bersih).
    fileprivate var grey: Double {
        switch self {
        case .clear: return 0
        case .partly: return 0.18
        case .overcast: return 0.82
        case .fog: return 0.78
        case .drizzle: return 0.72
        case .rain: return 0.86
        case .snow: return 0.72
        case .thunder: return 0.93
        }
    }

    fileprivate var darken: Double {
        switch self {
        case .rain: return 0.8
        case .thunder: return 0.62
        case .drizzle: return 0.9
        default: return 1
        }
    }

    /// Hujan, salju, dan kilat butuh gerak halus; yang lain cukup bergerak pelan (hemat daya).
    fileprivate var fastMotion: Bool { self == .rain || self == .drizzle || self == .snow || self == .thunder }

    fileprivate var clouds: Int {
        switch self {
        case .clear, .fog: return 0
        case .partly: return 3
        case .overcast, .snow: return 7
        case .drizzle, .rain: return 8
        case .thunder: return 9
        }
    }
}

/// Posisi matahari (siang) atau bulan (malam) di sepanjang lintasan: 0 = terbit/terbenam kiri, 1 = kanan.
struct SkyPosition {
    let progress: Double
    let isDay: Bool
    /// Menit dari cakrawala: positif di siang hari (jarak ke terbit atau terbenam terdekat), negatif di malam hari.
    /// Warna langit mengikuti nilai ini supaya fajar dan senja selalu berlangsung pelan (sekitar dua jam) di hari sepanjang apa pun.
    let horizon: Double
    /// Tinggi matahari kasar, -1 (tengah malam) sampai 1 (tengah hari).
    var altitude: Double { (isDay ? 1 : -1) * sin(.pi * progress) }

    @MainActor
    static func at(_ date: Date, sun: WeatherFeed.SunTimes?) -> SkyPosition {
        func clamp(_ v: Double) -> Double { min(1, max(0, v)) }
        if let s = sun {
            if date >= s.sunrise && date <= s.sunset {
                let m = min(date.timeIntervalSince(s.sunrise), s.sunset.timeIntervalSince(date)) / 60
                return SkyPosition(progress: clamp(date.timeIntervalSince(s.sunrise) / s.sunset.timeIntervalSince(s.sunrise)), isDay: true, horizon: m)
            }
            let (start, end) = date > s.sunset ? (s.sunset, s.nextSunrise) : (s.sunset.addingTimeInterval(-86_400), s.sunrise)
            let m = min(date.timeIntervalSince(start), end.timeIntervalSince(date)) / 60
            return SkyPosition(progress: clamp(date.timeIntervalSince(start) / end.timeIntervalSince(start)), isDay: false, horizon: -m)
        }
        // Tanpa lokasi: anggap terbit 06.00 dan terbenam 18.00 di jam Mac ini.
        let c = Calendar.current.dateComponents([.hour, .minute, .second], from: date)
        let h = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        if h >= 6 && h < 18 { return SkyPosition(progress: (h - 6) / 12, isDay: true, horizon: min(h - 6, 18 - h) * 60) }
        let q = h >= 18 ? h - 18 : h + 6
        return SkyPosition(progress: q / 12, isDay: false, horizon: -min(q, 12 - q) * 60)
    }
}

/// 0...1 dengan awal dan akhir yang landai (tidak ada perubahan tiba-tiba).
func smooth01(_ x: Double) -> Double { let t = min(1, max(0, x)); return t * t * (3 - 2 * t) }

/// Fase bulan: 0 = bulan baru, 0,5 = purnama, kembali ke 1 = bulan baru.
func moonPhase(_ date: Date) -> Double {
    let synodic = 29.530588853
    let days = (date.timeIntervalSince1970 - 947_182_440) / 86_400 // bulan baru 6 Januari 2000 18.14 UTC
    let p = days / synodic
    return p - p.rounded(.down)
}

struct RGB {
    var r: Double, g: Double, b: Double
    func mix(_ o: RGB, _ t: Double) -> RGB { RGB(r: r + (o.r - r) * t, g: g + (o.g - g) * t, b: b + (o.b - b) * t) }
    func scaled(_ k: Double) -> RGB { RGB(r: r * k, g: g * k, b: b * k) }
    var color: Color { Color(red: r, green: g, blue: b) }
}

enum SkyPalette {
    // Menit dari cakrawala → (warna atas, warna bawah). Antar kunci diinterpolasi dengan kurva landai.
    static let keys: [(min: Double, top: RGB, bottom: RGB)] = [
        (-150, RGB(r: 0.03, g: 0.05, b: 0.14), RGB(r: 0.07, g: 0.10, b: 0.24)), // malam
        (-80, RGB(r: 0.05, g: 0.08, b: 0.22), RGB(r: 0.16, g: 0.16, b: 0.36)),
        (-40, RGB(r: 0.11, g: 0.15, b: 0.34), RGB(r: 0.40, g: 0.28, b: 0.52)),  // senja ungu
        (-14, RGB(r: 0.20, g: 0.26, b: 0.50), RGB(r: 0.82, g: 0.45, b: 0.46)),  // merah muda
        (0, RGB(r: 0.26, g: 0.36, b: 0.62), RGB(r: 0.96, g: 0.60, b: 0.36)),    // cakrawala oranye
        (30, RGB(r: 0.28, g: 0.50, b: 0.80), RGB(r: 0.99, g: 0.76, b: 0.56)),   // hangat
        (80, RGB(r: 0.22, g: 0.48, b: 0.86), RGB(r: 0.72, g: 0.82, b: 0.95)),
        (170, RGB(r: 0.16, g: 0.42, b: 0.86), RGB(r: 0.55, g: 0.78, b: 0.97)),  // siang
    ]

    static func base(_ minutes: Double) -> (top: RGB, bottom: RGB) {
        if minutes <= keys[0].min { return (keys[0].top, keys[0].bottom) }
        for i in 1..<keys.count where minutes <= keys[i].min {
            let a = keys[i - 1], b = keys[i]
            let t = smooth01((minutes - a.min) / (b.min - a.min))
            return (a.top.mix(b.top, t), a.bottom.mix(b.bottom, t))
        }
        return (keys.last!.top, keys.last!.bottom)
    }

    /// Seberapa "siang" langitnya, 0 (malam) sampai 1 (siang), berubah landai di sekitar terbit dan terbenam.
    static func day(_ minutes: Double) -> Double { smooth01((minutes + 30) / 80) }

    /// Warna langit akhir: dasar menurut jam, ditarik ke abu-abu menurut cuaca (peralihan antar cuaca dicampur pelan).
    static func sky(minutes: Double, from: SkyWeather, to: SkyWeather, blend: Double) -> (top: RGB, bottom: RGB, day: Double) {
        let b = base(minutes)
        let day = Self.day(minutes)
        let greyTop = RGB(r: 0.06, g: 0.07, b: 0.10).mix(RGB(r: 0.45, g: 0.50, b: 0.57), day)
        let greyBottom = RGB(r: 0.12, g: 0.13, b: 0.17).mix(RGB(r: 0.66, g: 0.70, b: 0.75), day)
        let g = from.grey + (to.grey - from.grey) * blend
        let k = from.darken + (to.darken - from.darken) * blend
        return (b.top.mix(greyTop, g).scaled(k), b.bottom.mix(greyBottom, g).scaled(k), day)
    }
}

private func rnd(_ i: Int, _ k: Int) -> Double {
    let v = sin(Double(i * 131 + k * 17) + 1.7) * 43758.5453
    return v - v.rounded(.down)
}

extension SkyPalette {
    /// Warna tulisan di atas langit: putih, bergeser pelan ke gelap bila langitnya terang (kabut, mendung siang).
    @MainActor
    static func ink(weather: WeatherFeed) -> Color {
        let date = weather.clockOverride ?? Date()
        let pos = SkyPosition.at(date, sun: weather.now?.sun)
        let b = weather.blend(at: date)
        let p = sky(minutes: pos.horizon, from: b.from, to: b.to, blend: b.t)
        let mid = p.top.mix(p.bottom, 0.25)
        let luma = 0.299 * mid.r + 0.587 * mid.g + 0.114 * mid.b
        let dark = smooth01((luma - 0.53) / 0.07) // peralihan putih ke gelap halus, tapi sempit supaya tulisan tidak sempat abu-abu pucat
        return RGB(r: 1, g: 1, b: 1).mix(RGB(r: 0.07, g: 0.10, b: 0.16), dark).color
    }
}

/// Latar langit bergerak. Dipasang di belakang isi notch saat halaman Langit terbuka.
struct SkyBackground: View {
    @ObservedObject var weather: WeatherFeed
    /// Tema kaca: kaca asli di atasnya ikut digambar ulang tiap frame, jadi langit digerakkan lebih jarang.
    var glass = false

    var body: some View {
        let blendNow = weather.blend(at: Date())
        let fast = blendNow.from.fastMotion || blendNow.to.fastMotion || blendNow.t < 1
        return TimelineView(.animation(minimumInterval: fast ? 1.0 / 24 : glass ? 1.0 / 6 : 1.0 / 12)) { context in
            let date = weather.clockOverride ?? context.date
            let pos = SkyPosition.at(date, sun: weather.now?.sun)
            let blend = weather.blend(at: context.date)
            let palette = SkyPalette.sky(minutes: pos.horizon, from: blend.from, to: blend.to, blend: blend.t)
            let t = context.date.timeIntervalSinceReferenceDate
            let sight = weather.observer.map { SkyChart.Sight(lat: $0.lat, lon: $0.lon, date: date) }
            ZStack {
                LinearGradient(colors: [palette.top.color, palette.bottom.color], startPoint: .top, endPoint: .bottom)
                Canvas { ctx, size in
                    // Cuaca baru muncul pelan: lapisan cuaca lama memudar sambil yang baru menguat.
                    if blend.t < 1 && blend.from != blend.to {
                        var old = ctx; old.opacity = 1 - blend.t
                        Self.draw(&old, size, t: t, minutes: pos.horizon, day: palette.day, kind: blend.from, sight: sight)
                    }
                    var fresh = ctx; fresh.opacity = blend.from == blend.to ? 1 : blend.t
                    Self.draw(&fresh, size, t: t, minutes: pos.horizon, day: palette.day, kind: blend.to, sight: sight)
                }
            }
        }
    }


    /// Bintang, garis rasi bintang, nama rasi, dan planet pada posisi sebenarnya untuk lokasi dan waktu pengamat
    private static func drawChart(_ ctx: inout GraphicsContext, _ size: CGSize, _ sight: SkyChart.Sight, t: Double, alpha: Double) {
        var seg = Path()
        for line in SkyChart.lines {
            var prev: CGPoint?
            for q in line {
                let s = sight.altAz(ra: q.ra, dec: q.dec)
                let p = sight.point(s, size)
                if let a = prev, s.alt > 1, abs(p.x - a.x) < size.width * 0.5 { seg.move(to: a); seg.addLine(to: p) }
                prev = s.alt > 1 ? p : nil
            }
        }
        ctx.stroke(seg, with: .color(.white.opacity(alpha * 0.15)), lineWidth: 0.6)
        for (i, st) in SkyChart.stars.enumerated() {
            let s = sight.altAz(ra: st.ra, dec: st.dec)
            guard s.alt > -1 else { continue }
            let p = sight.point(s, size)
            guard p.x > -4, p.x < size.width + 4 else { continue }
            let tw = 0.75 + 0.25 * sin(t * (0.8 + rnd(i, 3)) + rnd(i, 4) * 6)
            let r = min(2.4, 0.55 + (4.7 - st.mag) * 0.42)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r)),
                     with: .color(.white.opacity(alpha * tw * smooth01(s.alt / 6) * (0.55 + 0.45 * min(1, (5 - st.mag) / 3)))))
        }
        for pl in SkyChart.planets(sight.date) {
            let s = sight.altAz(ra: pl.ra, dec: pl.dec)
            guard s.alt > 0 else { continue }
            let p = sight.point(s, size), r = 1.8 + min(1.4, max(0, 1 - pl.mag) * 0.4)
            let a = min(1, alpha * 1.3) * smooth01(s.alt / 6)
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r * 2.2, y: p.y - r * 2.2, width: r * 4.4, height: r * 4.4)),
                     with: .radialGradient(Gradient(colors: [pl.color.opacity(0.35 * a), .clear]), center: p, startRadius: 0, endRadius: r * 2.2))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r / 2, y: p.y - r / 2, width: r, height: r)), with: .color(pl.color.opacity(a)))
        }
        for n in SkyChart.names {
            let s = sight.altAz(ra: n.ra, dec: n.dec)
            guard s.alt > 14 else { continue }
            let p = sight.point(s, size)
            guard p.x > 24, p.x < size.width - 24 else { continue }
            ctx.draw(Text(n.name).font(.system(size: 7.5, weight: .medium)).foregroundColor(.white.opacity(alpha * 0.26 * smooth01((s.alt - 14) / 8))), at: p)
        }
    }

    private static func draw(_ ctx: inout GraphicsContext, _ size: CGSize, t: Double, minutes: Double, day: Double, kind: SkyWeather, sight: SkyChart.Sight?) {
        let w = size.width, h = size.height
        // Bintang (malam cerah atau sedikit berawan).
        let starAlpha = smooth01((-minutes - 10) / 70) * (kind == .clear ? 1 : kind == .partly ? 0.6 : 0)
        if starAlpha > 0.02, let sight {
            Self.drawChart(&ctx, size, sight, t: t, alpha: starAlpha)
        } else if starAlpha > 0.02 {
            for i in 0..<48 {
                let tw = 0.6 + 0.4 * sin(t * (0.8 + rnd(i, 3)) + rnd(i, 4) * 6)
                let r = 0.7 + rnd(i, 5) * 0.9
                ctx.fill(Path(ellipseIn: CGRect(x: rnd(i, 1) * w, y: rnd(i, 2) * h * 0.62, width: r, height: r)),
                         with: .color(.white.opacity(starAlpha * tw * 0.9)))
            }
        }
        // Awan.
        let cloudLevel: Double = {
            switch kind {
            case .thunder: return 0.30
            case .rain: return 0.42
            case .drizzle: return 0.55
            case .overcast: return 0.78
            case .snow: return 0.86
            default: return 1
            }
        }() * (0.26 + 0.74 * day)
        for i in 0..<kind.clouds {
            let speed = 0.004 + rnd(i, 6) * 0.006
            let x = (rnd(i, 1) + t * speed).truncatingRemainder(dividingBy: 1) * (w + 260) - 130
            let y = h * (0.04 + rnd(i, 2) * 0.34)
            let r = 24 + rnd(i, 3) * 26
            let tint = Color(red: cloudLevel, green: cloudLevel * 0.99, blue: min(1, cloudLevel * 1.03 + (1 - day) * 0.06))
            let alpha = kind == .partly ? 0.8 : 0.9
            for (dx, dy, k) in [(0.0, 0.0, 1.0), (r * 0.9, r * 0.12, 0.8), (-r * 0.9, r * 0.2, 0.7), (r * 0.35, -r * 0.3, 0.75)] {
                let rr = r * k
                ctx.fill(Path(ellipseIn: CGRect(x: x + dx - rr * 1.2, y: y + dy - rr * 0.6, width: rr * 2.4, height: rr * 1.2)),
                         with: .color(tint.opacity(alpha)))
            }
        }
        // Kabut.
        if kind == .fog {
            for i in 0..<4 {
                let x = sin(t * 0.05 + Double(i) * 1.7) * 60
                ctx.fill(Path(roundedRect: CGRect(x: -80 + x, y: h * (0.18 + Double(i) * 0.2), width: w + 160, height: h * 0.22), cornerRadius: 40),
                         with: .color(.white.opacity(0.10 + 0.05 * day)))
            }
        }
        // Hujan, gerimis, badai: garis jatuh.
        if kind == .rain || kind == .drizzle || kind == .thunder {
            let n = kind == .drizzle ? 28 : kind == .rain ? 70 : 96
            let speed = kind == .drizzle ? 0.8 : 1.5
            let len: Double = kind == .drizzle ? 7 : 12
            for i in 0..<n {
                let y = ((rnd(i, 2) + t * speed * (0.8 + rnd(i, 7) * 0.5)).truncatingRemainder(dividingBy: 1)) * (h + 30) - 15
                let x = rnd(i, 1) * (w + 40) - 20 + y * 0.12
                var p = Path()
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x - len * 0.12, y: y + len))
                ctx.stroke(p, with: .color(.white.opacity(0.28 + rnd(i, 8) * 0.2)), lineWidth: 1)
            }
            // Tetes air di "kaca" yang pelan meluncur.
            for i in 0..<16 {
                let y = ((rnd(i, 12) + t * 0.006 * (0.4 + rnd(i, 13))).truncatingRemainder(dividingBy: 1)) * h
                let x = rnd(i, 11) * w
                let r = 1.4 + rnd(i, 14) * 2.2
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2.3)), with: .color(.white.opacity(0.13)))
                ctx.fill(Path(ellipseIn: CGRect(x: x - r * 0.4, y: y - r * 0.7, width: r * 0.7, height: r * 0.7)), with: .color(.white.opacity(0.35)))
            }
        }
        // Salju.
        if kind == .snow {
            for i in 0..<48 {
                let y = ((rnd(i, 2) + t * 0.07 * (0.6 + rnd(i, 7) * 0.8)).truncatingRemainder(dividingBy: 1)) * (h + 10) - 5
                let x = rnd(i, 1) * w + sin(t * 0.9 + Double(i)) * 8
                let r = 1.2 + rnd(i, 5) * 1.6
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: r * 2, height: r * 2)), with: .color(.white.opacity(0.85)))
            }
        }
        // Kilat.
        if kind == .thunder {
            let cycle = (t / 7.3).truncatingRemainder(dividingBy: 1)
            let flash = max(0, 1 - abs(cycle - 0.5) * 40) + max(0, 0.6 - abs(cycle - 0.54) * 40)
            if flash > 0 { ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white.opacity(min(0.6, flash * 0.5)))) }
        }
    }
}

/// Isi halaman Langit: jam besar, kota dan cuaca (kiri), setengah lingkaran lintasan matahari (kanan).
struct SkyPanel: View {
    @ObservedObject var weather: WeatherFeed
    private var ink: Color { SkyPalette.ink(weather: weather) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12)) { context in
            let date = weather.clockOverride ?? context.date
            let sun = weather.now?.sun
            let pos = SkyPosition.at(date, sun: sun)
            HStack(alignment: .center, spacing: 20) {
                info(date: date, sun: sun, isDay: pos.isDay)
                    .frame(width: 210, alignment: .leading)
                arc(pos: pos, sun: sun, date: date, t: context.date.timeIntervalSinceReferenceDate)
                    .frame(maxWidth: .infinity)
            }
            .foregroundStyle(ink)
        }
    }

    private func zone(_ sun: WeatherFeed.SunTimes?) -> TimeZone { sun.flatMap { TimeZone(secondsFromGMT: $0.offset) } ?? .current }

    private func format(_ date: Date, _ sun: WeatherFeed.SunTimes?) -> String {
        let f = DateFormatter()
        f.timeZone = zone(sun)
        f.dateFormat = "HH.mm"
        return f.string(from: date)
    }

    private func info(date: Date, sun: WeatherFeed.SunTimes?, isDay: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(format(date, sun))
                .font(.system(size: 46, weight: .light, design: .rounded).monospacedDigit())
            if let now = weather.now {
                let kind = SkyWeather(code: now.code)
                HStack(spacing: 6) {
                    Image(systemName: isDay ? now.symbol : (now.code == 0 ? "moon.stars.fill" : now.code <= 2 ? "cloud.moon.fill" : now.symbol)).font(.system(size: 12, weight: .semibold))
                    Text("\(now.temperature)° · \(kind.label)").font(.system(size: 12.5, weight: .semibold))
                }
                Text(now.place).font(.system(size: 10.5)).foregroundStyle(ink.opacity(0.75)).lineLimit(1)
            } else {
                Text(weather.problem ?? L("Nyalakan Cuaca dan isi kota di Pengaturan untuk matahari dan cuaca asli (sementara 06.00 sampai 18.00).",
                                          "Turn on Weather and enter a city in Settings for real sun times and weather (6 am to 6 pm for now)."))
                    .font(.system(size: 10.5)).foregroundStyle(ink.opacity(0.75)).lineLimit(3)
            }
        }
        .shadow(color: .black.opacity(ink == .white ? 0.35 : 0), radius: 3)
    }

    private func arc(pos: SkyPosition, sun: WeatherFeed.SunTimes?, date: Date, t: Double) -> some View {
        Canvas { ctx, size in
            let base = size.height - 26
            let rx = size.width / 2 - 28
            let ry = min(rx * 0.28, base - 10) // tinggi busur; busur lingkaran landai (bukan setengah lingkaran penuh)
            let rc = (rx * rx + ry * ry) / (2 * ry) // jari-jari lingkaran yang melewati kedua ujung dan puncak
            let half = asin(rx / rc)
            let cx = size.width / 2
            func point(_ p: Double) -> CGPoint {
                // Busur lingkaran dangkal: bulat mulus di puncak dan menyentuh cakrawala dengan sudut kecil.
                let phi = -half + 2 * half * p
                return CGPoint(x: cx + rc * sin(phi), y: base + rc - ry - rc * cos(phi))
            }
            // Garis cakrawala.
            var horizon = Path()
            horizon.move(to: CGPoint(x: 8, y: base))
            horizon.addLine(to: CGPoint(x: size.width - 8, y: base))
            ctx.stroke(horizon, with: .color(ink.opacity(0.55)), lineWidth: 1)
            // Lintasan setengah lingkaran: seluruhnya redup, yang sudah dilalui terang.
            func track(_ to: Double) -> Path {
                var p = Path()
                p.move(to: point(0))
                for k in 1...90 { let q = to * Double(k) / 90; p.addLine(to: point(q)) }
                return p
            }
            ctx.stroke(track(1), with: .color(ink.opacity(0.28)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            ctx.stroke(track(pos.progress), with: .color(ink.opacity(0.85)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            // Matahari (siang) atau bulan dengan fasenya (malam), muncul dan hilang landai di cakrawala.
            let c = point(pos.progress)
            if pos.isDay { Self.drawSun(&ctx, c, t: t, horizon: pos.horizon) }
            else { Self.drawMoon(&ctx, c, phase: moonPhase(date), south: (weather.observer?.lat ?? 0) < 0) }
            // Jam terbit dan terbenam di bawah garis.
            let rise = ctx.resolve(Text("↑ " + (sun.map { format($0.sunrise, sun) } ?? "06.00")).font(.system(size: 11, weight: .semibold)).foregroundColor(ink.opacity(0.85)))
            let set = ctx.resolve(Text("↓ " + (sun.map { format($0.sunset, sun) } ?? "18.00")).font(.system(size: 11, weight: .semibold)).foregroundColor(ink.opacity(0.85)))
            ctx.draw(rise, at: CGPoint(x: cx - rx, y: base + 14), anchor: .center)
            ctx.draw(set, at: CGPoint(x: cx + rx, y: base + 14), anchor: .center)
        }
        .frame(height: 138)
    }

    /// Matahari: cakram bergradasi, pendar lembut, dan sinar pendek yang berputar pelan. Makin dekat cakrawala makin oranye.
    private static func drawSun(_ ctx: inout GraphicsContext, _ c: CGPoint, t: Double, horizon: Double) {
        let warm = 1 - smooth01(horizon / 90)
        let tint = RGB(r: 1, g: 0.95, b: 0.74).mix(RGB(r: 1, g: 0.58, b: 0.24), warm)
        let core = RGB(r: 1, g: 0.99, b: 0.92).mix(RGB(r: 1, g: 0.86, b: 0.6), warm)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 26, y: c.y - 26, width: 52, height: 52)),
                 with: .radialGradient(Gradient(colors: [tint.color.opacity(0.5), tint.color.opacity(0)]), center: c, startRadius: 4, endRadius: 26))
        for i in 0..<12 {
            let a = Double(i) * .pi / 6 + t * 0.12
            let len = 4.2 + 1.6 * sin(t * 1.4 + Double(i) * 0.9)
            var ray = Path()
            ray.move(to: CGPoint(x: c.x + cos(a) * 13.5, y: c.y + sin(a) * 13.5))
            ray.addLine(to: CGPoint(x: c.x + cos(a) * (13.5 + len), y: c.y + sin(a) * (13.5 + len)))
            ctx.stroke(ray, with: .color(tint.color.opacity(0.9)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 9, y: c.y - 9, width: 18, height: 18)),
                 with: .radialGradient(Gradient(colors: [core.color, tint.color]), center: CGPoint(x: c.x - 2.5, y: c.y - 2.5), startRadius: 0, endRadius: 12))
    }

    /// Bulan dengan fase sebenarnya: sisi yang terang di kanan saat membesar, di kiri saat mengecil.
    private static func drawMoon(_ ctx: inout GraphicsContext, _ c: CGPoint, phase: Double, south: Bool) {
        let r: Double = 10
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 24, y: c.y - 24, width: 48, height: 48)),
                 with: .radialGradient(Gradient(colors: [Color(red: 0.78, green: 0.84, blue: 1).opacity(0.32), .clear]), center: c, startRadius: 4, endRadius: 24))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Color(red: 0.66, green: 0.72, blue: 0.9).opacity(0.3)))
        let k = cos(2 * .pi * phase)       // 1 bulan baru, 0 separuh, -1 purnama
        let side: Double = (phase < 0.5 ? 1 : -1) * (south ? -1 : 1) // sisi terang, terbalik di belahan selatan
        var lit = Path()
        let n = 36
        for i in 0...n { // tepi bulan di sisi terang, dari atas ke bawah
            let th = -Double.pi / 2 + Double.pi * Double(i) / Double(n)
            let p = CGPoint(x: c.x + side * r * cos(th), y: c.y + r * sin(th))
            if i == 0 { lit.move(to: p) } else { lit.addLine(to: p) }
        }
        for i in 0...n { // garis terminator kembali ke atas
            let th = Double.pi / 2 - Double.pi * Double(i) / Double(n)
            lit.addLine(to: CGPoint(x: c.x + side * r * k * cos(th), y: c.y + r * sin(th)))
        }
        lit.closeSubpath()
        ctx.fill(lit, with: .color(Color(red: 0.96, green: 0.97, blue: 1)))
    }
}
