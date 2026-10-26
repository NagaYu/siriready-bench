import Foundation

/// Text normalization and lexical/phonetic keys used by the MOCK resolver.
///
/// These are deliberately small, deterministic stand-ins (Soundex, edit distance, a toy kana
/// reading table). They are not a model of Apple's ASR, NLU or semantic index.
public enum TextMatching {
    /// Lowercased ASCII word tokens. Possessive `'s` is dropped, apostrophes and hyphens join
    /// ("don't" → "dont", "Stand-up" → "standup"); everything that is not [a-z0-9] separates.
    public static func asciiTokens(_ text: String) -> [String] {
        var s = text.precomposedStringWithCompatibilityMapping.lowercased()
        for apostrophe in ["'s ", "’s "] { s = s.replacingOccurrences(of: apostrophe, with: " ") }
        if s.hasSuffix("'s") || s.hasSuffix("’s") { s.removeLast(2) }
        s = s.replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "-", with: "")
        var tokens: [String] = []
        var current = ""
        for scalar in s.unicodeScalars {
            if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                tokens.append(current); current = ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// NFKC, lowercase, katakana → hiragana, whitespace and middle dots removed.
    public static func japaneseNormalized(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.precomposedStringWithCompatibilityMapping.lowercased().unicodeScalars {
            if scalar.properties.isWhitespace || scalar == "・" { continue }
            if scalar.value >= 0x30A1 && scalar.value <= 0x30F6, let h = Unicode.Scalar(scalar.value - 0x60) {
                out.append(h)
            } else {
                out.append(scalar)
            }
        }
        return String(out)
    }

    public static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
    }

    /// Toy kanji → kana dictionary covering the dataset's vocabulary. A real system would use
    /// a full reading dictionary / ASR lattice; Phase 1 only needs deterministic behaviour.
    static let readings: [(String, String)] = [
        ("佐藤", "さとう"), ("輝", "ひかる"), ("光", "ひかる"), ("鷹瀬", "たかせ"), ("高瀬", "たかせ"),
        ("美月", "みづき"), ("瑞希", "みづき"), ("森", "もり"), ("齊藤", "さいとう"), ("斉藤", "さいとう"),
        ("斎藤", "さいとう"), ("健", "けん"), ("加藤", "かとう"), ("涼", "りょう"), ("遼", "りょう"),
        ("中村", "なかむら"), ("結衣", "ゆい"), ("在庫", "ざいこ"), ("棚卸", "たなおろし"), ("店卸", "たなおろし"),
        ("製品", "せいひん"), ("説明", "せつめい"), ("講演", "こうえん"), ("公演", "こうえん"),
        ("定例", "ていれい"), ("回", "かい"), ("会", "かい"),
    ].sorted { $0.0.count > $1.0.count }

    /// Approximate kana reading of a Japanese string (longest-match replacement with `readings`).
    public static func reading(_ text: String) -> String {
        var s = japaneseNormalized(text)
        for (kanji, kana) in readings { s = s.replacingOccurrences(of: kanji, with: kana) }
        return s
    }

    /// American Soundex. Tokens without letters map to themselves.
    public static func soundex(_ word: String) -> String {
        let letters = Array(word.lowercased().unicodeScalars.filter { $0 >= "a" && $0 <= "z" })
        guard let first = letters.first else { return word }
        func code(_ c: Unicode.Scalar) -> Character? {
            switch c {
            case "b", "f", "p", "v": return "1"
            case "c", "g", "j", "k", "q", "s", "x", "z": return "2"
            case "d", "t": return "3"
            case "l": return "4"
            case "m", "n": return "5"
            case "r": return "6"
            default: return nil
            }
        }
        var result = String(Character(first)).uppercased()
        var last = code(first)
        for c in letters.dropFirst() {
            let d = code(c)
            if let d, d != last { result.append(d) }
            if c != "h" && c != "w" { last = d }
            if result.count == 4 { break }
        }
        return result.padding(toLength: 4, withPad: "0", startingAt: 0)
    }

    /// Optimal string alignment distance (Levenshtein + adjacent transposition).
    public static func osaDistance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        if x.isEmpty { return y.count }
        if y.isEmpty { return x.count }
        var d = Array(repeating: Array(repeating: 0, count: y.count + 1), count: x.count + 1)
        for i in 0...x.count { d[i][0] = i }
        for j in 0...y.count { d[0][j] = j }
        for i in 1...x.count {
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
                if i > 1, j > 1, x[i - 1] == y[j - 2], x[i - 2] == y[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[x.count][y.count]
    }

    /// The part of an utterance that can refer to entities: quoted message bodies (「…」, "…")
    /// and anything after an English body marker (` saying `, `: `) are removed.
    public static func referenceSegment(_ utterance: String) -> String {
        var s = utterance
        for (open, close) in [("「", "」"), ("“", "”")] {
            while let a = s.range(of: open), let b = s.range(of: close, range: a.upperBound..<s.endIndex) {
                s.replaceSubrange(a.lowerBound..<b.upperBound, with: " ")
            }
        }
        for marker in [" saying ", ": "] {
            if let r = s.range(of: marker) { s = String(s[..<r.lowerBound]) }
        }
        return s
    }
}
