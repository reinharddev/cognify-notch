import Foundation

enum YahooCurrencyRates {
    static func rate(from: String, to: String) async throws -> Double {
        let source = from.uppercased(), target = to.uppercased()
        guard source.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil,
              target.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil,
              source != target else { throw URLError(.badURL) }
        let symbol = "\(source)\(target)=X"
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v8/finance/chart/\(symbol)")!
        components.queryItems = [URLQueryItem(name: "range", value: "1d"), URLQueryItem(name: "interval", value: "1d")]
        var request = URLRequest(url: components.url!, timeoutInterval: 8)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/605.1.15 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let chart = root["chart"] as? [String: Any],
              let result = (chart["result"] as? [[String: Any]])?.first,
              let meta = result["meta"] as? [String: Any],
              let rate = meta["regularMarketPrice"] as? NSNumber,
              rate.doubleValue.isFinite, rate.doubleValue > 0 else {
            throw URLError(.cannotParseResponse)
        }
        return rate.doubleValue
    }

    static func format(_ amount: Double, from: String, to: String, rate: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: Lang.english ? "en_US" : "id_ID")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 4
        let source = formatter.string(from: NSNumber(value: amount)) ?? String(amount)
        let converted = formatter.string(from: NSNumber(value: amount * rate)) ?? String(amount * rate)
        return "\(source) \(from.uppercased()) ≈ \(converted) \(to.uppercased())"
    }
}
