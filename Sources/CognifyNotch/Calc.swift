import Foundation

/// Kalkulator & konversi satuan untuk catatan cepat: "12*3", "(4+5)/2", "15% dari 200",
/// "5 km ke mil", "100 f to c". Semua dihitung di Mac ini; teks yang bukan hitungan diabaikan.
enum QuickCalc {
    /// Hasil siap tampil ("36", "3,11 mi"), atau nil bila teks bukan hitungan.
    static func evaluate(_ raw: String) -> String? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !text.isEmpty, text.count < 80 else { return nil }
        if let converted = convert(text) { return converted }
        if let percent = percentOf(text) { return format(percent) }
        // Hanya angka, operator, kurung, dan spasi; harus ada operator (angka saja bukan hitungan).
        let expression = text.replacingOccurrences(of: "×", with: "*").replacingOccurrences(of: "x", with: "*")
            .replacingOccurrences(of: "÷", with: "/").replacingOccurrences(of: ":", with: "/")
        guard expression.range(of: #"^[0-9.,+\-*/^%() ]+$"#, options: .regularExpression) != nil,
              expression.range(of: #"\d\s*[+\-*/^%]\s*[\d(]"#, options: .regularExpression) != nil
                || expression.range(of: #"\)\s*[+\-*/^]"#, options: .regularExpression) != nil else { return nil }
        var parser = Parser(normalize(expression))
        guard let value = parser.parse(), value.isFinite else { return nil }
        return format(value)
    }

    /// "1.234,5" (gaya Indonesia) dan "1,234.5" sama-sama jadi 1234.5.
    private static func normalize(_ s: String) -> String {
        var out = s
        if out.contains(","), out.contains(".") {
            let lastComma = out.range(of: ",", options: .backwards)!.lowerBound
            let lastDot = out.range(of: ".", options: .backwards)!.lowerBound
            if lastComma > lastDot { out = out.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".") }
            else { out = out.replacingOccurrences(of: ",", with: "") }
        } else if out.components(separatedBy: ".").count > 2 {
            out = out.replacingOccurrences(of: ".", with: "") // 1.250.000 = pemisah ribuan
        } else {
            out = out.replacingOccurrences(of: ",", with: ".")
        }
        return out
    }

    static func format(_ value: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: Lang.english ? "en_US" : "id_ID")
        f.numberStyle = .decimal
        f.maximumFractionDigits = abs(value) < 1 ? 6 : 4
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static func number(_ s: String) -> Double? { Double(normalize(s)) }

    /// "15% dari 200" / "15% of 200".
    private static func percentOf(_ text: String) -> Double? {
        let pattern = #"^([\d.,]+)\s*%\s*(?:dari|of)\s*([\d.,]+)$"#
        guard let m = text.range(of: pattern, options: .regularExpression), m == text.startIndex..<text.endIndex else { return nil }
        let parts = text.components(separatedBy: CharacterSet(charactersIn: "%")).map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let p = number(parts[0]),
              let base = number(parts[1].replacingOccurrences(of: "dari", with: "").replacingOccurrences(of: "of", with: "").trimmingCharacters(in: .whitespaces))
        else { return nil }
        return p / 100 * base
    }

    // MARK: Konversi satuan

    private static let units: [String: Dimension] = [
        "km": UnitLength.kilometers, "m": UnitLength.meters, "cm": UnitLength.centimeters, "mm": UnitLength.millimeters,
        "mi": UnitLength.miles, "mil": UnitLength.miles, "mile": UnitLength.miles, "miles": UnitLength.miles,
        "ft": UnitLength.feet, "kaki": UnitLength.feet, "feet": UnitLength.feet, "in": UnitLength.inches, "inch": UnitLength.inches,
        "inci": UnitLength.inches, "yd": UnitLength.yards,
        "kg": UnitMass.kilograms, "g": UnitMass.grams, "gram": UnitMass.grams, "mg": UnitMass.milligrams,
        "lb": UnitMass.pounds, "lbs": UnitMass.pounds, "pon": UnitMass.pounds, "oz": UnitMass.ounces, "ons": UnitMass.ounces,
        "c": UnitTemperature.celsius, "°c": UnitTemperature.celsius, "celsius": UnitTemperature.celsius,
        "f": UnitTemperature.fahrenheit, "°f": UnitTemperature.fahrenheit, "fahrenheit": UnitTemperature.fahrenheit,
        "k": UnitTemperature.kelvin, "kelvin": UnitTemperature.kelvin,
        "l": UnitVolume.liters, "liter": UnitVolume.liters, "ml": UnitVolume.milliliters, "gal": UnitVolume.gallons,
        "cup": UnitVolume.cups, "gelas": UnitVolume.cups,
        "km/h": UnitSpeed.kilometersPerHour, "kmh": UnitSpeed.kilometersPerHour, "kpj": UnitSpeed.kilometersPerHour,
        "mph": UnitSpeed.milesPerHour, "m/s": UnitSpeed.metersPerSecond,
        "gb": UnitInformationStorage.gigabytes, "mb": UnitInformationStorage.megabytes, "kb": UnitInformationStorage.kilobytes,
        "tb": UnitInformationStorage.terabytes,
        "jam": UnitDuration.hours, "h": UnitDuration.hours, "menit": UnitDuration.minutes, "min": UnitDuration.minutes,
        "detik": UnitDuration.seconds, "s": UnitDuration.seconds,
    ]

    /// "5 km ke mil" / "5km to mi" / "100 f in c".
    private static func convert(_ text: String) -> String? {
        let pattern = #"^([\d.,]+)\s*([a-z°/]+)\s+(?:ke|to|in|=|jadi)\s+([a-z°/]+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text), let r3 = Range(m.range(at: 3), in: text),
              let value = number(String(text[r1])), let from = units[String(text[r2])], let to = units[String(text[r3])],
              type(of: from) == type(of: to) else { return nil }
        let result = Measurement(value: value, unit: from).converted(to: to).value
        return format(result) + " " + String(text[r3])
    }

    // MARK: Pengurai hitungan (+ − × ÷ ^ %, kurung, tanda minus)

    private struct Parser {
        let chars: [Character]
        var i = 0

        init(_ s: String) { chars = Array(s.replacingOccurrences(of: " ", with: "")) }

        mutating func parse() -> Double? {
            guard let v = expression(), i == chars.count else { return nil }
            return v
        }

        private mutating func expression() -> Double? {
            guard var v = term() else { return nil }
            while i < chars.count, chars[i] == "+" || chars[i] == "-" {
                let op = chars[i]; i += 1
                guard let r = term() else { return nil }
                v = op == "+" ? v + r : v - r
            }
            return v
        }

        private mutating func term() -> Double? {
            guard var v = power() else { return nil }
            while i < chars.count, chars[i] == "*" || chars[i] == "/" {
                let op = chars[i]; i += 1
                guard let r = power() else { return nil }
                if op == "/" { guard r != 0 else { return nil }; v /= r } else { v *= r }
            }
            return v
        }

        private mutating func power() -> Double? {
            guard let base = unary() else { return nil }
            if i < chars.count, chars[i] == "^" {
                i += 1
                guard let exp = power() else { return nil }
                return pow(base, exp)
            }
            return base
        }

        private mutating func unary() -> Double? {
            if i < chars.count, chars[i] == "-" { i += 1; return unary().map { -$0 } }
            if i < chars.count, chars[i] == "+" { i += 1; return unary() }
            guard var v = atom() else { return nil }
            if i < chars.count, chars[i] == "%" { i += 1; v /= 100 }
            return v
        }

        private mutating func atom() -> Double? {
            if i < chars.count, chars[i] == "(" {
                i += 1
                guard let v = expression(), i < chars.count, chars[i] == ")" else { return nil }
                i += 1
                return v
            }
            let start = i
            while i < chars.count, chars[i].isNumber || chars[i] == "." { i += 1 }
            return start < i ? Double(String(chars[start..<i])) : nil
        }
    }
}
