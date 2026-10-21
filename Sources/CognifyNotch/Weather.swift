import SwiftUI

/// Cuaca di header notch dari Open-Meteo (open-meteo.com, gratis, tanpa akun). Lokasi = nama kota
/// yang diketik user di Pengaturan (bukan GPS); yang dikirim hanya nama kota itu (sekali, untuk
/// mencari koordinatnya) lalu koordinatnya, tiap 30 menit.
@MainActor
final class WeatherFeed: ObservableObject {
    struct Now: Equatable {
        let temperature: Int
        let code: Int
        let place: String

        var symbol: String { WeatherFeed.symbol(code) }
    }

    @Published private(set) var now: Now?
    @Published private(set) var problem: String?

    private var city = ""
    private var enabled = false
    private var timer: Timer?
    private var place: (lat: Double, lon: Double, name: String)?

    func configure(enabled: Bool, city: String) {
        let clean = city.trimmingCharacters(in: .whitespaces)
        guard enabled != self.enabled || clean != self.city else { return }
        self.enabled = enabled
        if clean != self.city { place = nil }
        self.city = clean
        timer?.invalidate()
        timer = nil
        guard enabled, !clean.isEmpty else {
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
                if place == nil { place = try await Self.geocode(city) }
                guard let place else {
                    problem = L("Kota \"\(city)\" tidak ditemukan", "City \"\(city)\" not found")
                    now = nil
                    return
                }
                let (temperature, code) = try await Self.current(lat: place.lat, lon: place.lon)
                withAnimation(.notch) { now = Now(temperature: Int(temperature.rounded()), code: code, place: place.name) }
                problem = nil
            } catch {
                problem = L("Cuaca tidak bisa dimuat", "Couldn't load weather")
            }
        }
    }

    private struct GeoResult: Decodable {
        struct Item: Decodable { let latitude: Double; let longitude: Double; let name: String }
        let results: [Item]?
    }

    private struct Forecast: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
        let current: Current
    }

    nonisolated private static func geocode(_ city: String) async throws -> (lat: Double, lon: Double, name: String)? {
        var url = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        url.queryItems = [URLQueryItem(name: "name", value: city), URLQueryItem(name: "count", value: "1"),
                          URLQueryItem(name: "language", value: "id")]
        let (data, _) = try await URLSession.shared.data(from: url.url!)
        let item = try JSONDecoder().decode(GeoResult.self, from: data).results?.first
        return item.map { ($0.latitude, $0.longitude, $0.name) }
    }

    nonisolated private static func current(lat: Double, lon: Double) async throws -> (Double, Int) {
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = [URLQueryItem(name: "latitude", value: String(format: "%.3f", lat)),
                          URLQueryItem(name: "longitude", value: String(format: "%.3f", lon)),
                          URLQueryItem(name: "current", value: "temperature_2m,weather_code")]
        let (data, _) = try await URLSession.shared.data(from: url.url!)
        let forecast = try JSONDecoder().decode(Forecast.self, from: data)
        return (forecast.current.temperature_2m, forecast.current.weather_code)
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
    func preview(_ value: Now) { now = value }
}
