import CoreLocation
import SwiftUI

/// Cuaca di header notch dari Open-Meteo (open-meteo.com, gratis, tanpa akun). Lokasi = nama kota
/// yang diketik user di Pengaturan, atau koordinat dari tombol Deteksi lokasi (hanya saat ditekan);
/// yang dikirim hanya nama kota itu (sekali, untuk mencari koordinatnya) lalu koordinatnya, tiap 30 menit.
@MainActor
final class WeatherFeed: ObservableObject {
    struct Now: Equatable {
        let temperature: Int
        let code: Int
        let place: String
        var sun: SunTimes?

        var symbol: String { WeatherFeed.symbol(code) }
    }

    /// Waktu matahari di lokasi cuaca (zona waktu lokasi itu).
    struct SunTimes: Equatable {
        let sunrise: Date
        let sunset: Date
        let nextSunrise: Date
        let offset: Int // detik dari UTC di lokasi
    }

    @Published private(set) var now: Now?
    /// Untuk pratinjau/snapshot: jam yang dipakai langit menggantikan jam sekarang.
    var clockOverride: Date?
    /// Perubahan cuaca terakhir: kelas cuaca sebelumnya dan kapan berganti, supaya langit beralih pelan (3 detik).
    private(set) var kindShift: (from: SkyWeather, at: Date)?

    /// Cuaca asal, cuaca tujuan, dan kemajuan peralihannya (0 sampai 1) pada waktu tertentu.
    func blend(at date: Date) -> (from: SkyWeather, to: SkyWeather, t: Double) {
        let to = now.map { SkyWeather(code: $0.code) } ?? .clear
        guard let shift = kindShift else { return (to, to, 1) }
        let t = smooth01(date.timeIntervalSince(shift.at) / 3)
        return t >= 1 ? (to, to, 1) : (shift.from, to, t)
    }
    @Published private(set) var problem: String?

    private var city = ""
    private var coords = "" // "lat,lon" dari tombol Deteksi lokasi; menggantikan pencarian nama kota
    private var enabled = false
    private var timer: Timer?
    private var place: (lat: Double, lon: Double, name: String)?
    /// Lintang dan bujur pengamat bila sudah diketahui; dipakai untuk bintang nyata.
    var observer: (lat: Double, lon: Double)? { place.map { ($0.lat, $0.lon) } }

    func configure(enabled: Bool, city: String, coords: String = "") {
        let clean = city.trimmingCharacters(in: .whitespaces)
        guard enabled != self.enabled || clean != self.city || coords != self.coords else { return }
        self.enabled = enabled
        if clean != self.city || coords != self.coords { place = nil }
        self.city = clean
        self.coords = coords
        timer?.invalidate()
        timer = nil
        guard enabled, !clean.isEmpty || Self.parse(coords) != nil else {
            now = nil
            problem = enabled ? L("Isi nama kota di Pengaturan", "Enter a city in Settings") : nil
            return
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer?.tolerance = 120
    }

    func refresh() {
        let city = city
        Task {
            do {
                if place == nil {
                    if let c = Self.parse(coords) { place = (c.lat, c.lon, city.isEmpty ? L("Lokasi saya", "My location") : city) }
                    else { place = try await Self.geocode(city) }
                }
                guard let place else {
                    problem = L("Kota \"\(city)\" tidak ditemukan", "City \"\(city)\" not found")
                    now = nil
                    return
                }
                let (temperature, code, sun) = try await Self.current(lat: place.lat, lon: place.lon)
                let before = now.map { SkyWeather(code: $0.code) }
                withAnimation(.notch) { now = Now(temperature: Int(temperature.rounded()), code: code, place: place.name, sun: sun) }
                if let before, before != SkyWeather(code: code) { kindShift = (before, Date()) }
                problem = nil
            } catch {
                problem = L("Cuaca tidak bisa dimuat", "Couldn't load weather")
            }
        }
    }

    nonisolated private static func parse(_ coords: String) -> (lat: Double, lon: Double)? {
        let parts = coords.split(separator: ",").compactMap { Double($0) }
        return parts.count == 2 ? (parts[0], parts[1]) : nil
    }

    private struct GeoResult: Decodable {
        struct Item: Decodable { let latitude: Double; let longitude: Double; let name: String }
        let results: [Item]?
    }

    private struct Forecast: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
        struct Daily: Decodable { let sunrise: [String]; let sunset: [String] }
        let current: Current
        let daily: Daily?
        let utc_offset_seconds: Int?
    }

    nonisolated private static func geocode(_ city: String) async throws -> (lat: Double, lon: Double, name: String)? {
        var url = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        url.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"),
                          URLQueryItem(name: "language", value: "id")]
        let (data, _) = try await URLSession.shared.data(from: url.url!)
        let item = try JSONDecoder().decode(GeoResult.self, from: data).results?.first
        return item.map { ($0.latitude, $0.longitude, $0.name) }
    }

    nonisolated private static func current(lat: Double, lon: Double) async throws -> (Double, Int, SunTimes?) {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [URLQueryItem(name: "latitude", value: String(format: "%.3f", lat)),
                          URLQueryItem(name: "longitude", value: String(format: "%.3f", lon)),
                          URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
                          URLQueryItem(name: "daily", value: "sunrise,sunset"),
                          URLQueryItem(name: "timezone", value: "auto"),
                          URLQueryItem(name: "forecast_days", value: "2")]
        let (data, _) = try await URLSession.shared.data(from: url.url!)
        let forecast = try JSONDecoder().decode(Forecast.self, from: data)
        var sun: SunTimes?
        if let daily = forecast.daily, let offset = forecast.utc_offset_seconds, daily.sunrise.count >= 2, daily.sunset.count >= 1 {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(secondsFromGMT: offset)
            f.dateFormat = "yyyy-MM-dd'T'HH:mm"
            if let rise = f.date(from: daily.sunrise[0]), let set = f.date(from: daily.sunset[0]), let next = f.date(from: daily.sunrise[1]) {
                sun = SunTimes(sunrise: rise, sunset: set, nextSunrise: next, offset: offset)
            }
        }
        return (forecast.current.temperature_2m, forecast.current.weather_code, sun)
    }

    /// Kode cuaca WMO → ikon SF Symbols (siang/malam disederhanakan menurut jam).
    nonisolated static func symbol(_ code: Int) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let night = hour < 6 || hour >= 18
        switch code {
        case 0: return night ? "moon.stars.fill" : "sun.max.fill"
        case 1, 2: return night ? "cloud.moon.fill" : "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    // Untuk snapshot.
    func preview(_ value: Now, lat: Double = -6.2, lon: Double = 106.8) { now = value; place = (lat, lon, value.place) }
}


/// Tombol "Deteksi lokasi": satu kali baca lokasi Mac ini (izin Layanan Lokasi), lalu nama kotanya dicari lewat
/// Apple. Koordinat disimpan di Mac ini dan hanya dikirim ke Open-Meteo untuk mengambil cuaca.
@MainActor
final class LocationFinder: NSObject, ObservableObject, CLLocationManagerDelegate {
    enum State: Equatable { case idle, detecting, failed(String) }
    @Published private(set) var state: State = .idle
    private let manager = CLLocationManager()
    private var done: ((Double, Double, String) -> Void)?

    private var timeout: Task<Void, Never>?

    func detect(_ done: @escaping (Double, Double, String) -> Void) {
        self.done = done
        state = .detecting
        // Jangan menggantung selamanya bila izin tidak pernah dijawab atau lokasi tidak datang.
        timeout?.cancel()
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            guard !Task.isCancelled, let self, self.state == .detecting else { return }
            self.fail(L("Tidak ada jawaban lokasi. Pastikan Layanan Lokasi menyala dan Cognify Notch diizinkan di Pengaturan Sistem → Privasi → Layanan Lokasi.",
                        "No location answer. Make sure Location Services is on and Cognify Notch is allowed in System Settings → Privacy → Location Services."))
        }
        NSApp.activate(ignoringOtherApps: true) // jendela izin muncul di depan
        manager.delegate = self
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: fail(L("Izinkan Layanan Lokasi untuk Cognify Notch di Pengaturan Sistem → Privasi.", "Allow Location Services for Cognify Notch in System Settings → Privacy."))
        default: manager.requestLocation()
        }
    }


    private func fail(_ message: String) { timeout?.cancel(); state = .failed(message); done = nil }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.state == .detecting else { return }
            if status == .denied || status == .restricted {
                self.fail(L("Izin lokasi ditolak. Ubah di Pengaturan Sistem → Privasi.", "Location permission denied. Change it in System Settings → Privacy."))
            } else if status != .notDetermined {
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        CLGeocoder().reverseGeocodeLocation(location) { places, _ in
            let name = places?.first.flatMap { $0.locality ?? $0.subAdministrativeArea ?? $0.administrativeArea }
            Task { @MainActor in
                self.state = .idle
                self.done?(location.coordinate.latitude, location.coordinate.longitude, name ?? "")
                self.done = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.fail(L("Lokasi tidak bisa dibaca. Coba lagi.", "Couldn't read your location. Try again.")) }
    }
}
