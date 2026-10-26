import Foundation

/// Text-level view of one Swift source file.
///
/// This is deliberately *not* a Swift parser (see README "Limits of the static audit").
/// `code` has comments blanked out; `masked` additionally blanks string-literal contents so
/// braces and keywords inside strings do not confuse structure detection. Both keep the
/// original UTF-16 length and line breaks, so offsets and line numbers line up across all three.
public struct SourceFile: Sendable {
    public let path: String
    public let text: String
    public let code: String
    public let masked: String
    private let lineStarts: [Int]

    public init(path: String, text: String) {
        self.path = path
        self.text = text
        let (code, masked) = SourceScanner.blank(text)
        self.code = code
        self.masked = masked
        var starts = [0]
        for (i, unit) in text.utf16.enumerated() where unit == 0x0A { starts.append(i + 1) }
        self.lineStarts = starts
    }

    /// 1-based line number of a UTF-16 offset.
    public func line(at offset: Int) -> Int {
        var lo = 0, hi = lineStarts.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if lineStarts[mid] <= offset { lo = mid } else { hi = mid - 1 }
        }
        return lo + 1
    }

    public func code(in range: NSRange) -> String { (code as NSString).substring(with: range) }
    public func masked(in range: NSRange) -> String { (masked as NSString).substring(with: range) }
}

/// A type-level declaration found by pattern matching (struct/class/enum/actor/extension/protocol).
public struct Declaration: Sendable {
    public var kind: String
    public var name: String
    /// Raw attribute text preceding the declaration, e.g. `@AppIntent(schema: .messages.sendMessage)`.
    public var attributes: String
    public var conformances: [String]
    public var file: String
    public var line: Int
    /// Body between the braces, comments removed (string literals kept).
    public var body: String
    /// Body with comments and string contents blanked.
    public var maskedBody: String
}

public struct RegexMatch: Sendable {
    public var range: NSRange
    public var groups: [String?]
    public var groupRanges: [NSRange]
}

public enum SourceScanner {
    public static func matches(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [RegexMatch] {
        // Patterns are compile-time constants in this module; a bad one is a programming error.
        let regex = try! NSRegularExpression(pattern: pattern, options: options)
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { m in
            var groups: [String?] = []
            var ranges: [NSRange] = []
            for g in 0..<m.numberOfRanges {
                let r = m.range(at: g)
                ranges.append(r)
                groups.append(r.location == NSNotFound ? nil : ns.substring(with: r))
            }
            return RegexMatch(range: m.range, groups: groups, groupRanges: ranges)
        }
    }

    /// Blanks comments (→ `code`) and additionally string contents (→ `masked`), preserving length.
    static func blank(_ text: String) -> (code: String, masked: String) {
        let units = Array(text.utf16)
        var code = units
        var masked = units
        let space: UInt16 = 0x20, newline: UInt16 = 0x0A
        let slash: UInt16 = 0x2F, star: UInt16 = 0x2A, quote: UInt16 = 0x22, backslash: UInt16 = 0x5C
        func blankBoth(_ i: Int) { if units[i] != newline { code[i] = space; masked[i] = space } }
        func blankMasked(_ i: Int) { if units[i] != newline { masked[i] = space } }
        func at(_ i: Int) -> UInt16? { i < units.count ? units[i] : nil }

        var i = 0
        while i < units.count {
            let c = units[i]
            if c == slash, at(i + 1) == slash {
                while i < units.count, units[i] != newline { blankBoth(i); i += 1 }
            } else if c == slash, at(i + 1) == star {
                var depth = 0
                while i < units.count {
                    if units[i] == slash, at(i + 1) == star { depth += 1; blankBoth(i); blankBoth(i + 1); i += 2; continue }
                    if units[i] == star, at(i + 1) == slash {
                        depth -= 1; blankBoth(i); blankBoth(i + 1); i += 2
                        if depth == 0 { break }
                        continue
                    }
                    blankBoth(i); i += 1
                }
            } else if c == quote, at(i + 1) == quote, at(i + 2) == quote {
                i += 3
                while i < units.count, !(units[i] == quote && at(i + 1) == quote && at(i + 2) == quote) {
                    blankMasked(i); i += 1
                }
                i += 3
            } else if c == quote {
                i += 1
                while i < units.count, units[i] != quote, units[i] != newline {
                    if units[i] == backslash { blankMasked(i); i += 1; if i < units.count { blankMasked(i) }; i += 1; continue }
                    blankMasked(i); i += 1
                }
                i += 1
            } else {
                i += 1
            }
        }
        return (String(decoding: code, as: UTF16.self), String(decoding: masked, as: UTF16.self))
    }

    private static let declarationPattern =
        #"(?m)^[ \t]*((?:@\w+(?:\([^()\n]*(?:\([^()\n]*\)[^()\n]*)*\))?\s+)*)(?:(?:public|private|fileprivate|internal|open|final|package|nonisolated|indirect)\s+)*(struct|class|enum|actor|extension|protocol)\s+([A-Za-z_][\w.]*)([^{\n]*)\{"#

    public static func declarations(in file: SourceFile) -> [Declaration] {
        let maskedUnits = Array(file.masked.utf16)
        return matches(declarationPattern, in: file.masked).compactMap { m in
            guard let kind = m.groups[2], let name = m.groups[3] else { return nil }
            let open = m.range.location + m.range.length - 1
            guard let close = matchingBrace(maskedUnits, open: open) else { return nil }
            let bodyRange = NSRange(location: open + 1, length: close - open - 1)
            return Declaration(
                kind: kind,
                name: name,
                attributes: m.groups[1] ?? "",
                conformances: parseConformances(m.groups[4] ?? ""),
                file: file.path,
                line: file.line(at: m.groupRanges[2].location),
                body: file.code(in: bodyRange),
                maskedBody: file.masked(in: bodyRange)
            )
        }
    }

    static func parseConformances(_ rest: String) -> [String] {
        var s = rest.trimmingCharacters(in: .whitespaces)
        guard s.hasPrefix(":") else { return [] }
        s.removeFirst()
        if let w = s.range(of: " where ") { s = String(s[..<w.lowerBound]) }
        return s.split(separator: ",").map { part in
            var t = part.trimmingCharacters(in: .whitespaces)
            if let lt = t.firstIndex(of: "<") { t = String(t[..<lt]) }
            return t
        }.filter { !$0.isEmpty }
    }

    private static func matchingBrace(_ units: [UInt16], open: Int) -> Int? {
        var depth = 0
        var i = open
        while i < units.count {
            if units[i] == 0x7B { depth += 1 } else if units[i] == 0x7D {
                depth -= 1
                if depth == 0 { return i }
            }
            i += 1
        }
        return nil
    }
}
