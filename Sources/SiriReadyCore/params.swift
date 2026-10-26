import Foundation

// Parameter scoring (Phase 2).
//
// `ParamExtractor.extract` is the MOCK slot filler: deterministic rules that read message bodies,
// times, days, event titles and invitees out of the utterance. It stands in for Siri's slot
// filling, which AppIntentsTesting cannot observe. Real runs pass these values to the app and
// check what the app actually persisted against `expected.params`.

public enum ParamExtractor {
    static let enWrappers = ["could you please ", "hey, ", "i need you to "]
    static let jaPrefixes = ["すみません、", "ねえ、", "お願いなんだけど、"]
    static let jaSuffixes = ["もらえる？", "おいてほしい", "、お願い"]
    static let enDays = ["next monday", "tomorrow", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    static let jaDays = ["来週の月曜", "明日", "月曜", "火曜", "水曜", "木曜", "金曜", "土曜", "日曜"]

    /// Slot values for `intent` read from the utterance (keys follow `expected.params`).
    /// With a catalog, a calendar mention is resolved to a CalendarEntity id (MOCK lookup).
    public static func extract(_ utterance: String, intent: String?, catalog: EntityCatalog? = nil) -> [String: String] {
        var out: [String: String] = [:]
        switch intent {
        case "SendMessageIntent", "DraftMessageIntent":
            if let body = body(utterance) { out["body"] = body }
        case "SetMessageReadStatusIntent":
            out["is_read"] = "true"
        case "CreateEventIntent":
            if let t = title(utterance) { out["title"] = t }
            if let d = day(utterance) { out["day"] = d }
            if let h = time(utterance) { out["time"] = h }
            if let l = location(utterance) { out["location"] = l }
            if let c = calendarMention(utterance) {
                out["calendar_mention"] = c
                let pool = catalog?.entities.filter { $0.type == "CalendarEntity" } ?? []
                out["calendar"] = EntityMatcher.search(c, in: pool, semantic: true).first?.id ?? c
            }
        case "UpdateEventIntent":
            if let d = day(utterance) { out["day"] = d }
            if let h = time(utterance) { out["time"] = h }
        case "ShareEventIntent":
            if let p = invitee(utterance) { out["invitee"] = p }
        default:
            break
        }
        return out
    }

    /// Comparison form of a parameter value: NFKC, lowercased, trimmed of spaces and end punctuation.
    public static func normalize(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased()
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "?？.。!！")))
    }

    /// True when every expected parameter has an equal (normalized) actual value. Extra actual keys are ignored.
    public static func matches(expected: [String: JSONScalar], actual: [String: String]) -> Bool {
        expected.allSatisfy { key, value in actual[key].map(normalize) == normalize(value.description) }
    }

    // MARK: slots

    static func firstMatch(_ pattern: String, in text: String, group: Int = 1) -> String? {
        SourceScanner.matches(pattern, in: text, options: [.caseInsensitive]).first?.groups[group] ?? nil
    }

    static func body(_ u: String) -> String? {
        if let quoted = firstMatch("「([^」]*)」", in: u) { return quoted }
        var s = u
        if let r = s.range(of: " saying ") {
            s = String(s[r.upperBound...])
        } else if let r = s.range(of: ": ") {
            s = String(s[r.upperBound...])
        } else {
            return nil
        }
        if let r = s.range(of: " but don't send it") { s = String(s[..<r.lowerBound]) }
        return s
    }

    static func time(_ u: String) -> String? {
        firstMatch(#"(\d{1,2}(?::\d{2})?\s?(?:am|pm))"#, in: u) ?? firstMatch(#"(\d{1,2}時半?)"#, in: u)
    }

    static func day(_ u: String) -> String? {
        let lower = " " + TextMatching.asciiTokens(u).joined(separator: " ") + " "
        if let d = enDays.first(where: { lower.contains(" \($0) ") }) { return d }
        return jaDays.first { u.contains($0) }
    }

    static func stripWrappers(_ u: String) -> String {
        var s = u
        for w in enWrappers where s.lowercased().hasPrefix(w) { s = String(s.dropFirst(w.count)) }
        for w in jaPrefixes where s.hasPrefix(w) { s = String(s.dropFirst(w.count)) }
        for w in jaSuffixes where s.hasSuffix(w) { s = String(s.dropLast(w.count)) }
        for w in [", thanks", " の予定"] where s.hasSuffix(w) { s = String(s.dropLast(w.count)) }
        return s
    }

    static func location(_ u: String) -> String? {
        let s = stripWrappers(u)
        if let l = firstMatch(#"\d(?::\d{2})?\s?(?:am|pm) at (.+)$"#, in: s) { return l }
        return firstMatch(#"、場所は(.+)$"#, in: s)
    }

    static func calendarMention(_ u: String) -> String? {
        firstMatch(#"\bto my (\w+) calendar\b"#, in: u) ?? firstMatch(#"^(?:.*?、)?(.+?)のカレンダーに"#, in: u)
    }

    static func title(_ u: String) -> String? {
        var s = stripWrappers(u)
        // "Add X to my Work calendar on …" → "Add X on …"; "…、場所は…" is a location, not part of the title.
        if let r = s.range(of: #" to my \w+ calendar"#, options: [.regularExpression, .caseInsensitive]) { s.removeSubrange(r) }
        if let r = s.range(of: "、場所は") { s = String(s[..<r.lowerBound]) }
        let day = #"(?:tomorrow|next \w+|\w+day)"#
        if let t = firstMatch(#"^(?:add|schedule|put|create an event called)\s+(.+?)\s+(?:on my calendar for|on|for)\s+"# + day + #"\b"#, in: s) { return t }
        if let t = firstMatch(#",\s*add\s+(.+)$"#, in: s) { return t }
        if let t = firstMatch(#"(?:時半|時)(?:に|から|で)(.+?)(?:の予定を作って|を入れて|をaddして)"#, in: s) { return t }
        if let t = firstMatch(#"^入れて、.+?(?:時半|時)に(.+)$"#, in: s) { return t }
        if let t = firstMatch(#"^(.+?)を.+?で追加して"#, in: s) { return t }
        return nil
    }

    static func invitee(_ u: String) -> String? {
        // Name directly before さん, without the particles that join it to the event (を, に, の, and the
        // IME slip お for を); prefer the one followed by 「に共有」/「にshare」.
        if let p = firstMatch(#"([^\sをにへのとお、]+さん)に(?:共有|share)"#, in: u) { return p }
        if let p = firstMatch(#"([^\sをにへのとお、]+さん)"#, in: u) { return p }
        if let p = firstMatch(#"\bwith\s+([A-Za-z]+)"#, in: u) { return p }
        return firstMatch(#"を\s*([A-Za-z]+)\s*に"#, in: u)
    }

    // MARK: dates for real runs

    /// Reference "today" for relative days: Sunday 2026-11-01 (UTC). Deterministic by design.
    static let referenceDay = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"), year: 2026, month: 11, day: 1)

    /// ISO-8601 start for a (day, time) pair; `fallbackDate` (yyyy-MM-dd) is used when no day is given.
    public static func startISO(day: String?, time: String?, fallbackDate: String?) -> String? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let ref = cal.date(from: referenceDay) else { return nil }
        var date: Date?
        if let day = day.map(normalize) {
            let weekdays = ["sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, "thursday": 5, "friday": 6, "saturday": 7,
                            "日曜": 1, "月曜": 2, "火曜": 3, "水曜": 4, "木曜": 5, "金曜": 6, "土曜": 7]
            if day == "tomorrow" || day == "明日" {
                date = cal.date(byAdding: .day, value: 1, to: ref)
            } else if day == "next monday" || day == "来週の月曜" {
                date = cal.date(byAdding: .day, value: 8, to: ref)
            } else if let wd = weekdays[day] {
                date = cal.date(byAdding: .day, value: (wd - 1 + 7) % 7 == 0 ? 7 : (wd - 1), to: ref)
            }
        } else if let f = fallbackDate {
            let parts = f.split(separator: "-").compactMap { Int($0) }
            if parts.count == 3 { date = cal.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) }
        }
        guard let base = date, let (h, m) = time.flatMap(hourMinute) else { return nil }
        guard let start = cal.date(bySettingHour: h, minute: m, second: 0, of: base) else { return nil }
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "UTC")
        return f.string(from: start)
    }

    static func hourMinute(_ time: String) -> (Int, Int)? {
        let t = normalize(time).replacingOccurrences(of: " ", with: "")
        if let m = SourceScanner.matches(#"^(\d{1,2})(?::(\d{2}))?(am|pm)$"#, in: t).first {
            var h = Int(m.groups[1]!)! % 12
            if m.groups[3] == "pm" { h += 12 }
            return (h, Int(m.groups[2] ?? "0") ?? 0)
        }
        if let m = SourceScanner.matches(#"^(\d{1,2})時(半)?$"#, in: t).first {
            return (Int(m.groups[1]!)!, m.groups[2] == nil ? 0 : 30)
        }
        return nil
    }
}
