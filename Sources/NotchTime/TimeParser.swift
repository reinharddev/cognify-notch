import Foundation

/// Hasil membaca waktu dari teks bebas (Bahasa Indonesia, bahasa gaul pelajar, dan sedikit Inggris).
public struct ParsedTime: Equatable {
    public var date: Date
    /// Hasil tebakan (mis. "jam 7" dibaca 19.00 karena 07.00 sudah lewat). Tampilkan dengan tanda tanya.
    public var tentative: Bool
    /// Waktunya jelas tetapi sudah lewat; pengingat tidak dibuat.
    public var isPast: Bool
}

/// Pembaca waktu berbasis aturan dan konteks. Angka hanya dianggap jam bila ada petunjuk di sekitarnya
/// (kata "jam", tanda ":", satuan WIB, kata hari, dst.), jadi "bab 2.10" atau "versi 3.15" tidak jadi pengingat.
public enum TimeParser {
    public static func parse(_ text: String, now: Date = Date()) -> ParsedTime? {
        var s = normalize(text)
        if find(#"\b(?:tadi|kemarin|kemaren|yesterday|ago)\b|\blalu\b"#, in: s) != nil { return nil }
        s = maskNonTimeNumbers(s)
        let cal = Calendar.current

        if let rel = relative(&s, now: now, cal: cal) { return rel }

        let day = parseDay(&s, now: now, cal: cal)
        let part = partOfDay(s)
        let clock = findClock(s, dayContext: day != nil || part != nil)

        let today = cal.startOfDay(for: now)
        var hour: Int, minute: Int
        var dayShift = 0
        var period: String?
        if let clock {
            hour = clock.hour
            minute = clock.minute
            period = clock.period ?? part
            switch period {
            case "pm", "sore", "malam", "petang":
                if hour == 12, period == "malam" { hour = 0; dayShift = 1 } else if hour < 12 { hour += 12 }
            case "siang": if hour < 11 { hour += 12 }
            case "am", "pagi", "subuh": if hour == 12 { hour = 0 }
            default: break
            }
        } else if let part {
            (hour, minute) = defaultTime(part)
            if part == "tengah malam" { dayShift = 1 }
        } else if day != nil {
            hour = 9; minute = 0
        } else {
            return nil
        }

        let base = cal.date(byAdding: .day, value: dayShift, to: day?.date ?? today) ?? today
        guard var date = cal.date(bySettingHour: hour, minute: minute, second: 0, of: base) else { return nil }
        if date >= now { return ParsedTime(date: date, tentative: false, isPast: false) }

        if day?.weekday == true {
            date = cal.date(byAdding: .day, value: 7, to: date) ?? date
            return ParsedTime(date: date, tentative: false, isPast: false)
        }
        if day == nil, clock != nil {
            // Hanya jam yang sudah lewat. "jam 7" pukul 10 pagi, tanpa keterangan, paling mungkin 19.00.
            if period == nil, (1...11).contains(clock!.hour),
               let evening = cal.date(bySettingHour: clock!.hour + 12, minute: minute, second: 0, of: base), evening > now {
                return ParsedTime(date: evening, tentative: true, isPast: false)
            }
            if let tomorrow = cal.date(byAdding: .day, value: 1, to: date) {
                return ParsedTime(date: tomorrow, tentative: true, isPast: false)
            }
        }
        return ParsedTime(date: date, tentative: false, isPast: true)
    }

    // MARK: Normalisasi

    private static let slang: [(String, String)] = [
        (#"\bbsk\b|\bbsok\b|\bbesokk+\b|\bbesoq\b|\bbesuk\b"#, "besok"),
        (#"\blusaa+\b"#, "lusa"),
        (#"\bmlm\b|\bmlam\b|\bmalem\b"#, "malam"),
        (#"\bsre\b|\bsoree+\b"#, "sore"),
        (#"\bpg\b|\bpgi\b"#, "pagi"),
        (#"\bsiangg+\b|\bsiank\b"#, "siang"),
        (#"\bntar\b|\bntr\b|\bnanti\b"#, "nanti"),
        (#"\bpkl\b\.?|\bpukull\b"#, "pukul"),
        (#"\bjm\b|\bjamm+\b|\bj\.\s*(?=\d)"#, "jam"),
        (#"\bwib\.?\b"#, "wib"),
        (#"\bdua\s+belas\b"#, "duabelas"),
        (#"\bsetengah\s+jam\b"#, "setengahjam"),
        (#"\bsebentar\s+lagi\b|\bbentar\s+lagi\b|\bsbntr\s+lagi\b"#, "sebentarlagi"),
    ]

    private static func normalize(_ text: String) -> String {
        var s = " " + text.lowercased().folding(options: .diacriticInsensitive, locale: nil) + " "
        for (pattern, replacement) in slang {
            s = s.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return s
    }

    /// Angka yang jelas bukan jam: nomor bab, halaman, versi, harga, ukuran, nomor bertingkat.
    private static func maskNonTimeNumbers(_ input: String) -> String {
        var s = input
        let label = #"\b(?:bab|subbab|sub bab|hal|halaman|hlm|no|nomor|pasal|ayat|versi|ver|v|soal|nomer|gambar|gbr|tabel|tab|rp|idr|ch|chapter|lampiran|fig|figure|modul|unit|pertemuan|sesi|poin|butir)\.?\s*\d+(?:[.,:]\d+)*"#
        s = s.replacingOccurrences(of: label, with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: #"[$€£]\s*\d+(?:[.,]\d+)*"#, with: " ", options: .regularExpression)
        let unit = #"\d+[.,]\d+\s*(?:kg|gr|g|cm|mm|km|m|%|persen|juta|jt|ribu|rb|k|gb|mb|kb|mah|sks|pts|poin|nilai|ml|l|watt|w)(?![a-z])"#
        s = s.replacingOccurrences(of: unit, with: " ", options: .regularExpression)
        // 1.2.3 atau 2.4.1.5 (bukan tanggal d.m.yyyy)
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\d.])\d+(?:\.\d+){2,}(?![\d.])"#) else { return s }
        let ns = s as NSString
        for m in regex.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            let piece = ns.substring(with: m.range)
            if piece.range(of: #"^\d{1,2}\.\d{1,2}\.\d{4}$"#, options: .regularExpression) != nil { continue }
            s = (s as NSString).replacingCharacters(in: m.range, with: " ")
        }
        return s
    }

    // MARK: Pembantu regex

    private static func find(_ pattern: String, in text: String) -> (groups: [String?], range: Range<String.Index>)? {
        all(pattern, in: text).first
    }

    private static func all(_ pattern: String, in text: String) -> [(groups: [String?], range: Range<String.Index>)] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m in
            guard let range = Range(m.range, in: text) else { return nil }
            let groups = (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: text).map { String(text[$0]) } }
            return (groups, range)
        }
    }

    private static func int(_ s: String?) -> Int? { s.flatMap { Int($0) } }

    private static let numberWords: [String: Int] = [
        "satu": 1, "dua": 2, "tiga": 3, "empat": 4, "lima": 5, "enam": 6, "tujuh": 7, "delapan": 8, "sembilan": 9,
        "sepuluh": 10, "sebelas": 11, "duabelas": 12,
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9,
        "ten": 10, "eleven": 11, "twelve": 12,
    ]
    private static let words = numberWords.keys.sorted { $0.count > $1.count }.joined(separator: "|")
    private static let periods = "am|pm|pagi|siang|sore|malam|subuh|petang"

    // MARK: Relatif ("2 jam lagi")

    private static func relative(_ s: inout String, now: Date, cal: Calendar) -> ParsedTime? {
        func make(_ seconds: TimeInterval, tentative: Bool = false) -> ParsedTime? {
            let t = now.addingTimeInterval(seconds)
            let rounded = Date(timeIntervalSinceReferenceDate: (t.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
            return ParsedTime(date: rounded, tentative: tentative, isPast: false)
        }
        if find(#"\bsebentarlagi\b"#, in: s) != nil { return make(15 * 60, tentative: true) }
        if find(#"\bsetengahjam\s+(?:lagi|ke\s*depan)\b"#, in: s) != nil { return make(30 * 60) }
        if find(#"\bsejam\s+(?:lagi|ke\s*depan)\b"#, in: s) != nil { return make(3600) }
        if find(#"\bsemenit\s+lagi\b"#, in: s) != nil { return make(60) }
        if find(#"\bsehari\s+lagi\b"#, in: s) != nil { return make(86_400) }
        let unit = #"(menit|mnt|min|minutes?|jam|hours?|hr|hari|days?)"#
        let pattern = #"(?<![\d.,:])(?:(\d{1,3})|("# + words + #"))\s*"# + unit + #"\s+(?:lagi|ke\s*depan|dari sekarang)\b"#
        if let f = find(pattern, in: s), let n = int(f.groups[1]) ?? f.groups[2].flatMap({ numberWords[$0] }) {
            let u = f.groups[3] ?? ""
            if u.hasPrefix("m") { return make(Double(n) * 60) }
            if u.hasPrefix("j") || u.hasPrefix("h") && u != "hari" { return make(Double(n) * 3600) }
            return make(Double(n) * 86_400)
        }
        if let f = find(#"\bin\s+(\d{1,3})\s*(min|minutes?|hours?|hrs?|h|days?)\b"#, in: s), let n = int(f.groups[1]) {
            let u = f.groups[2] ?? ""
            if u.hasPrefix("m") { return make(Double(n) * 60) }
            if u.hasPrefix("d") { return make(Double(n) * 86_400) }
            return make(Double(n) * 3600)
        }
        return nil
    }

    // MARK: Bagian hari

    private static func partOfDay(_ s: String) -> String? {
        guard let f = find(#"\b(tengah malam|subuh|pagi|siang|sore|petang|malam)\b"#, in: s) else { return nil }
        // "menginap 2 malam", "3 hari 2 malam": jumlah malam, bukan waktu.
        if f.groups[1] == "malam" {
            let before = s[s.startIndex..<f.range.lowerBound].trimmingCharacters(in: .whitespaces)
            if before.range(of: #"\d$"#, options: .regularExpression) != nil,
               before.range(of: #"(?:jam|pukul|at|@)\s*\d{1,2}(?:[.:]\d{2})?$"#, options: .regularExpression) == nil { return nil }
        }
        return f.groups[1]
    }

    private static func defaultTime(_ part: String) -> (Int, Int) {
        switch part {
        case "subuh": return (5, 0)
        case "pagi": return (7, 0)
        case "siang": return (12, 0)
        case "sore": return (16, 0)
        case "petang": return (17, 0)
        case "tengah malam": return (0, 0)
        default: return (19, 0)
        }
    }

    // MARK: Jam

    private struct Clock { var hour: Int; var minute: Int; var period: String? }

    private static func findClock(_ s: String, dayContext: Bool) -> Clock? {
        // A. Dengan kata penanda: jam 7, pukul 19.30, jam tujuh, jam setengah 8, jam 7 kurang 10, jam 10an, at 5pm, @9
        let cue = #"(?:\b(jam|pukul|at|sampai|sebelum|sekitar|pas|menjelang)\b|(@))\s*(?:(setengah|half past)\s*)?(?:(\d{1,2})|("# + words + #"))(?:[.:](\d{2}))?(?:an(?![a-z]))?(?:\s*(kurang|lewat|lebih)\s*(\d{1,2}|seperempat))?\s*(?:(\#(periods))\b)?"#
        for f in all(cue, in: s) {
            let weak = f.groups[1].map { ["sampai", "sebelum", "sekitar", "pas", "menjelang"].contains($0) } ?? false
            guard var hour = int(f.groups[4]) ?? f.groups[5].flatMap({ numberWords[$0] }) else { continue }
            guard hour < 24 else { continue }
            var minute = int(f.groups[6]) ?? 0
            guard minute < 60 else { continue }
            if weak, f.groups[6] == nil, f.groups[7] == nil, f.groups[8] == nil, f.groups[9] == nil { continue }
            if f.groups[3] != nil { hour = hour == 1 ? 12 : hour - 1; minute = 30 }
            if let how = f.groups[8] {
                let amount = how == "seperempat" ? 15 : (Int(how) ?? 0)
                let total = hour * 60 + minute + (f.groups[7] == "kurang" ? -amount : amount)
                hour = ((total / 60) % 24 + 24) % 24
                minute = (total % 60 + 60) % 60
            }
            return Clock(hour: hour, minute: minute, period: f.groups[9])
        }
        // B. Titik dua: 14:30
        if let f = all(#"(?<![\d.:,/\-])(\d{1,2}):(\d{2})(?![\d:])\s*(?:(\#(periods)|wib|wita|wit)\b)?"#, in: s)
            .first(where: { int($0.groups[1]) ?? 99 < 24 && int($0.groups[2]) ?? 99 < 60 }) {
            return Clock(hour: int(f.groups[1])!, minute: int(f.groups[2])!, period: periodOnly(f.groups[3]))
        }
        // C. Titik: 14.30 hanya dengan satuan di belakangnya atau kata hari di teks.
        for f in all(#"(?<![\d.:,/\-])(\d{1,2})\.(\d{2})(?![\d.,:])\s*(?:(\#(periods)|wib|wita|wit)\b)?"#, in: s) {
            guard let h = int(f.groups[1]), let m = int(f.groups[2]), h < 24, m < 60 else { continue }
            if f.groups[3] != nil || dayContext { return Clock(hour: h, minute: m, period: periodOnly(f.groups[3])) }
        }
        // D. "7 pagi", "5 sore", "10 am" tanpa kata jam. "malam" dikecualikan ("2 malam" = dua malam).
        if let f = all(#"(?<![\d.:,/\-])(\d{1,2})\s*(am|pm|pagi|sore|siang)\b"#, in: s)
            .first(where: { int($0.groups[1]) ?? 99 <= 12 && int($0.groups[1]) ?? 0 >= 1 }) {
            return Clock(hour: int(f.groups[1])!, minute: 0, period: f.groups[2])
        }
        return nil
    }

    private static func periodOnly(_ s: String?) -> String? {
        guard let s, !["wib", "wita", "wit"].contains(s) else { return nil }
        return s
    }

    // MARK: Tanggal

    private static let monthNumbers: [String: Int] = [
        "januari": 1, "january": 1, "jan": 1, "februari": 2, "pebruari": 2, "february": 2, "feb": 2,
        "maret": 3, "march": 3, "mar": 3, "april": 4, "apr": 4, "mei": 5, "may": 5,
        "juni": 6, "june": 6, "jun": 6, "juli": 7, "july": 7, "jul": 7,
        "agustus": 8, "august": 8, "agu": 8, "agt": 8, "aug": 8,
        "september": 9, "sept": 9, "sep": 9, "oktober": 10, "october": 10, "okt": 10, "oct": 10,
        "november": 11, "nopember": 11, "nov": 11, "desember": 12, "december": 12, "des": 12, "dec": 12,
    ]
    private static let weekdayNumbers: [String: Int] = [
        "minggu": 1, "ahad": 1, "sunday": 1, "senin": 2, "monday": 2, "selasa": 3, "tuesday": 3,
        "rabu": 4, "wednesday": 4, "kamis": 5, "thursday": 5, "jumat": 6, "jum'at": 6, "jumaat": 6, "friday": 6,
        "sabtu": 7, "saturday": 7,
    ]

    /// Tanggal dari teks; bagian yang dikenali dihapus dari `text`.
    private static func parseDay(_ text: inout String, now: Date, cal: Calendar) -> (date: Date, weekday: Bool)? {
        let today = cal.startOfDay(for: now)
        let thisYear = cal.component(.year, from: now)
        let names = monthNumbers.keys.sorted { $0.count > $1.count }.joined(separator: "|")

        func make(_ d: Int, _ m: Int, _ y: Int?) -> Date? {
            guard (1...12).contains(m), (1...31).contains(d) else { return nil }
            var c = DateComponents(); c.day = d; c.month = m; c.year = y ?? thisYear
            guard let date = cal.date(from: c), cal.component(.day, from: date) == d else { return nil }
            if y == nil, date < today { c.year = thisYear + 1; return cal.date(from: c) }
            return date
        }
        func take(_ found: (groups: [String?], range: Range<String.Index>), _ date: Date?, weekday: Bool = false) -> (Date, Bool)? {
            guard let date else { return nil }
            text.replaceSubrange(found.range, with: " ")
            return (date, weekday)
        }

        if let f = find(#"(?<![\d/.\-:])(\d{1,2})([/\-.])(\d{1,2})(?:\2(\d{4}))?(?![\d:])"#, in: text),
           f.groups[4] != nil || f.groups[2] == "/",
           let r = take(f, make(int(f.groups[1]) ?? 0, int(f.groups[3]) ?? 0, int(f.groups[4]))) { return (r.0, r.1) }
        if let f = find(#"\b(\d{1,2})(?:st|nd|rd|th)?\s+("# + names + #")\b(?:\s+(\d{4})\b)?"#, in: text),
           let r = take(f, make(int(f.groups[1]) ?? 0, monthNumbers[f.groups[2] ?? ""] ?? 0, int(f.groups[3]))) { return (r.0, r.1) }
        if let f = find(#"\b("# + names + #")\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s+(\d{4})\b)?"#, in: text),
           let r = take(f, make(int(f.groups[2]) ?? 0, monthNumbers[f.groups[1] ?? ""] ?? 0, int(f.groups[3]))) { return (r.0, r.1) }
        if let f = find(#"\b(?:minggu depan|pekan depan|next week)\b"#, in: text), let r = take(f, cal.date(byAdding: .day, value: 7, to: today)) { return (r.0, r.1) }
        if let f = find(#"\b(?:bulan depan|next month)\b"#, in: text), let r = take(f, cal.date(byAdding: .month, value: 1, to: today)) { return (r.0, r.1) }
        if let f = find(#"\b(?:tahun depan|next year)\b"#, in: text), let r = take(f, cal.date(byAdding: .year, value: 1, to: today)) { return (r.0, r.1) }
        if let f = find(#"\b(?:tahun|year)\s+(\d{4})\b"#, in: text), let y = int(f.groups[1]), y >= thisYear {
            var c = DateComponents(); c.year = y; c.month = 1; c.day = 1
            let date = y == thisYear ? today : cal.date(from: c)
            if let r = take(f, date) { return (r.0, r.1) }
        }
        if let f = find(#"\b(?:bulan|month|in)\s+("# + names + #")\b"#, in: text), let m = monthNumbers[f.groups[1] ?? ""] {
            let date = m == cal.component(.month, from: now) ? today : make(1, m, nil)
            if let r = take(f, date) { return (r.0, r.1) }
        }
        if let f = find(#"\b(?:tgl|tanggal|date)\.?\s*(\d{1,2})\b(?![/.:\-]\d)"#, in: text), let d = int(f.groups[1]) {
            let month = cal.component(.month, from: now)
            var date = make(d, month, thisYear)
            if let current = date, current < today {
                date = cal.date(byAdding: .month, value: 1, to: cal.date(from: DateComponents(year: thisYear, month: month, day: 1)) ?? today)
                    .flatMap { cal.date(bySetting: .day, value: d, of: $0) }
            }
            if let r = take(f, date) { return (r.0, r.1) }
        }
        if let f = find(#"\b(?:lusa|day after tomorrow)\b"#, in: text), let r = take(f, cal.date(byAdding: .day, value: 2, to: today)) { return (r.0, r.1) }
        if let f = find(#"\b(?:besok|tomorrow)\b"#, in: text), let r = take(f, cal.date(byAdding: .day, value: 1, to: today)) { return (r.0, r.1) }
        if let f = find(#"\b(?:hari ini|today)\b"#, in: text), let r = take(f, today) { return (r.0, r.1) }
        // Nama hari. "senin depan" dibaca Senin berikutnya; "minggu ini", "minggu 3", "minggu lalu" bukan hari Minggu.
        let days = weekdayNumbers.keys.sorted { $0.count > $1.count }.joined(separator: "|")
        for f in all(#"\b(?:hari\s+)?("# + days + #")\b(?!\s+(?:ini|lalu|ke|\d))(\s+depan\b)?"#, in: text) {
            guard let wd = weekdayNumbers[f.groups[1] ?? ""] else { continue }
            if f.groups[1] == "minggu" {
                let before = text[text.startIndex..<f.range.lowerBound].trimmingCharacters(in: .whitespaces)
                if before.range(of: #"(?:tiap|setiap|per|selama)$"#, options: .regularExpression) != nil { continue }
            }
            var ahead = (wd - cal.component(.weekday, from: now) + 7) % 7
            if f.groups[2] != nil, ahead == 0 { ahead = 7 }
            if let r = take(f, cal.date(byAdding: .day, value: ahead, to: today), weekday: true) { return (r.0, r.1) }
        }
        return nil
    }
}
