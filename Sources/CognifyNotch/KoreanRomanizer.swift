import Foundation

/// Romanisasi Hangul berdasarkan PELAFALAN (Revised Romanization), bukan ejaan huruf demi huruf.
/// Contoh: 입술로 → "ipssullo", 빛이 → "bichi", 눈앞에 → "nunape".
/// Aturan yang diterapkan: sambung bunyi (연음), netralisasi huruf akhir, aspirasi ㅎ, penegangan setelah
/// ㄱ/ㄷ/ㅂ, sengau (ㄱ→ng, ㅂ→m, ㄷ→n sebelum ㄴ/ㅁ/ㄹ), asimilasi ㄹ, dan palatalisasi (같이 → gachi).
/// Teks non-Hangul (Latin, tanda baca) dibiarkan apa adanya. Kata yang dipisah satu spasi dianggap
/// satu frasa, seperti saat dinyanyikan.
enum KoreanRomanizer {
    private struct Syl {
        var onset: Character
        var vowel: Int
        var coda: [Character]
    }

    private static let initials: [Character] = Array("ㄱㄲㄴㄷㄸㄹㅁㅂㅃㅅㅆㅇㅈㅉㅊㅋㅌㅍㅎ")
    private static let codas: [[Character]] = [
        [], ["ㄱ"], ["ㄲ"], ["ㄱ", "ㅅ"], ["ㄴ"], ["ㄴ", "ㅈ"], ["ㄴ", "ㅎ"], ["ㄷ"], ["ㄹ"],
        ["ㄹ", "ㄱ"], ["ㄹ", "ㅁ"], ["ㄹ", "ㅂ"], ["ㄹ", "ㅅ"], ["ㄹ", "ㅌ"], ["ㄹ", "ㅍ"], ["ㄹ", "ㅎ"],
        ["ㅁ"], ["ㅂ"], ["ㅂ", "ㅅ"], ["ㅅ"], ["ㅆ"], ["ㅇ"], ["ㅈ"], ["ㅊ"], ["ㅋ"], ["ㅌ"], ["ㅍ"], ["ㅎ"],
    ]
    private static let vowels = [
        "a", "ae", "ya", "yae", "eo", "e", "yeo", "ye", "o", "wa", "wae", "oe", "yo",
        "u", "wo", "we", "wi", "yu", "eu", "ui", "i",
    ]
    private static let onsetRoman: [Character: String] = [
        "ㄱ": "g", "ㄲ": "kk", "ㄴ": "n", "ㄷ": "d", "ㄸ": "tt", "ㄹ": "r", "ㅁ": "m", "ㅂ": "b", "ㅃ": "pp",
        "ㅅ": "s", "ㅆ": "ss", "ㅇ": "", "ㅈ": "j", "ㅉ": "jj", "ㅊ": "ch", "ㅋ": "k", "ㅌ": "t", "ㅍ": "p", "ㅎ": "h",
    ]
    private static let codaRoman: [Character: String] = [
        "ㄱ": "k", "ㄴ": "n", "ㄷ": "t", "ㄹ": "l", "ㅁ": "m", "ㅂ": "p", "ㅇ": "ng",
    ]

    private static func syllable(_ scalar: Unicode.Scalar) -> Syl? {
        let v = Int(scalar.value) - 0xAC00
        guard (0..<11172).contains(v) else { return nil }
        return Syl(onset: initials[v / 588], vowel: (v % 588) / 28, coda: codas[v % 28])
    }

    /// nil bila teks tidak memuat Hangul.
    static func romanize(_ text: String) -> String? {
        guard text.unicodeScalars.contains(where: { syllable($0) != nil }) else { return nil }
        var out = ""
        var run: [Syl] = []
        var spaceAfter: [Bool] = []
        var pendingSpace = false

        func flush() {
            guard !run.isEmpty else { return }
            let parts = pronounce(run)
            for (i, part) in parts.enumerated() {
                out += part
                if i < parts.count - 1, spaceAfter[i] { out += " " }
            }
            run = []
            spaceAfter = []
        }

        for scalar in text.unicodeScalars {
            if let syl = syllable(scalar) {
                if !run.isEmpty { spaceAfter.append(pendingSpace) }
                pendingSpace = false
                run.append(syl)
            } else if scalar == " ", !run.isEmpty, !pendingSpace {
                pendingSpace = true
            } else {
                // Selain Hangul: tutup frasa; spasi yang tertunda ikut dikeluarkan.
                flush()
                if pendingSpace { out += " " }
                pendingSpace = false
                out.unicodeScalars.append(scalar)
            }
        }
        flush()
        if pendingSpace { out += " " }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let tense: [Character: Character] = ["ㄱ": "ㄲ", "ㄷ": "ㄸ", "ㅂ": "ㅃ", "ㅅ": "ㅆ", "ㅈ": "ㅉ"]
    private static let aspirate: [Character: Character] = ["ㄱ": "ㅋ", "ㄷ": "ㅌ", "ㅈ": "ㅊ"]
    private static let nasal: [Character: Character] = ["ㄱ": "ㅇ", "ㄷ": "ㄴ", "ㅂ": "ㅁ"]

    /// Wakil bunyi huruf akhir tunggal di depan konsonan atau di akhir kata.
    private static func representative(_ c: Character) -> Character {
        switch c {
        case "ㄱ", "ㄲ", "ㅋ": return "ㄱ"
        case "ㄷ", "ㅅ", "ㅆ", "ㅈ", "ㅊ", "ㅌ", "ㅎ": return "ㄷ"
        case "ㅂ", "ㅍ": return "ㅂ"
        default: return c
        }
    }

    private static func pronounce(_ input: [Syl]) -> [String] {
        var s = input
        let n = s.count
        for i in 0..<n {
            let c = s[i].coda
            if c.isEmpty { continue }
            let next: Character? = i + 1 < n ? s[i + 1].onset : nil

            // 1. Sambung bunyi: onset berikutnya kosong (ㅇ).
            if let o = next, o == "ㅇ", c != ["ㅇ"] {
                var moved: Character?
                if c.count == 2 {
                    if c[1] == "ㅎ" {
                        moved = c[0]
                        s[i].coda = []
                    } else {
                        moved = c[1] == "ㅅ" ? "ㅆ" : c[1]
                        s[i].coda = [c[0]]
                    }
                } else if c[0] == "ㅎ" {
                    s[i].coda = []
                } else {
                    moved = c[0]
                    s[i].coda = []
                }
                if var m = moved {
                    if s[i + 1].vowel == 20 { // ㅣ: 굳이 → 구지, 같이 → 가치
                        if m == "ㄷ" { m = "ㅈ" } else if m == "ㅌ" { m = "ㅊ" }
                    }
                    s[i + 1].onset = m
                }
                continue
            }

            if let o = next {
                // 2. Aspirasi: ㅎ + ㄱ/ㄷ/ㅈ → ㅋ/ㅌ/ㅊ.
                if c.contains("ㅎ"), let a = aspirate[o] {
                    s[i + 1].onset = a
                    s[i].coda = c.count == 2 ? [c[0]] : []
                    continue
                }
                if c == ["ㅎ"], o == "ㅅ" {
                    s[i + 1].onset = "ㅆ"
                    s[i].coda = []
                    continue
                }
                // Aspirasi: ㄱ/ㄷ/ㅂ + ㅎ → ㅋ/ㅌ/ㅍ.
                if o == "ㅎ" {
                    let map: [Character: Character] = ["ㄱ": "ㅋ", "ㄲ": "ㅋ", "ㅋ": "ㅋ", "ㄷ": "ㅌ", "ㅅ": "ㅌ", "ㅆ": "ㅌ",
                                                      "ㅈ": "ㅌ", "ㅊ": "ㅌ", "ㅌ": "ㅌ", "ㅂ": "ㅍ", "ㅍ": "ㅍ"]
                    if c.count == 1, let a = map[c[0]] {
                        s[i + 1].onset = a
                        s[i].coda = []
                        continue
                    }
                    if c.count == 2, c[0] == "ㄹ", c[1] != "ㅅ", c[1] != "ㅁ", c[1] != "ㅎ", let a = map[c[1]] {
                        s[i + 1].onset = a
                        s[i].coda = ["ㄹ"]
                        continue
                    }
                }
            }

            // 3. Netralisasi huruf akhir.
            var rep: Character
            let compound = c.count == 2
            if compound {
                switch (c[0], c[1]) {
                case ("ㄱ", "ㅅ"), ("ㅂ", "ㅅ"): rep = c[0] == "ㄱ" ? "ㄱ" : "ㅂ"
                case ("ㄴ", _): rep = "ㄴ"
                case ("ㄹ", "ㄱ"): rep = next == "ㄱ" ? "ㄹ" : "ㄱ"
                case ("ㄹ", "ㅁ"): rep = "ㅁ"
                case ("ㄹ", "ㅍ"): rep = "ㅂ"
                default: rep = "ㄹ"
                }
            } else {
                rep = representative(c[0])
            }

            if let o = next {
                // 4. Penegangan: ㄱ/ㄷ/ㅂ + ㄱ/ㄷ/ㅂ/ㅅ/ㅈ; gabungan akhir (앉다, 닮고, 넓다) juga.
                if "ㄱㄷㅂ".contains(rep) || (compound && "ㄴㅁㄹ".contains(rep)), let t = tense[o] {
                    s[i + 1].onset = t
                }
                // 5. Sengau dan asimilasi ㄹ.
                if "ㄱㄷㅂ".contains(rep), let nz = nasal[rep] {
                    if o == "ㄴ" || o == "ㅁ" {
                        rep = nz
                    } else if o == "ㄹ" {
                        rep = nz
                        s[i + 1].onset = "ㄴ"
                    }
                } else if rep == "ㅁ" || rep == "ㅇ", o == "ㄹ" {
                    s[i + 1].onset = "ㄴ"
                } else if rep == "ㄴ", o == "ㄹ" {
                    rep = "ㄹ"
                } else if rep == "ㄹ", o == "ㄴ" {
                    s[i + 1].onset = "ㄹ"
                }
            }
            s[i].coda = [rep]
        }

        var result: [String] = []
        for i in 0..<n {
            var onset = onsetRoman[s[i].onset] ?? ""
            if s[i].onset == "ㄹ", i > 0, s[i - 1].coda == ["ㄹ"] { onset = "l" }
            let coda = s[i].coda.first.flatMap { codaRoman[$0] } ?? ""
            result.append(onset + vowels[s[i].vowel] + coda)
        }
        return result
    }
}
