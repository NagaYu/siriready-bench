import Foundation

// BENCHMARKS.md and the MOCK-divergence appendix, regenerated from committed results
// (results/<phase>/<variant>/{plan,raw}.json) plus a conditions file. Deterministic: no host
// values, no timestamps — the measurement conditions come from the committed conditions JSON.

public struct BenchmarkConditions: Codable, Sendable {
    public var label: String
    public var resultsDir: String
    public var dataset: String
    public var measuredOn: String
    public var xcode: String
    public var sdk: String
    public var runtime: String
    public var device: String
    public var host: String
    public var signing: String
    public var harnessProtocol: String
    public var resolver: String
    /// Optional free text shown under the section heading.
    public var note: String?
    /// Results directory of an earlier follow-up to compare against (rename check).
    public var compareWith: String?

    enum CodingKeys: String, CodingKey {
        case label, resultsDir = "results_dir", dataset, measuredOn = "measured_on", xcode, sdk, runtime, device, host
        case signing, harnessProtocol = "harness_protocol", resolver, note, compareWith = "compare_with"
    }
}

public struct BenchmarkRun: Sendable {
    public var variant: String
    public var mixed: MixedResult
    public var raw: RawRun
}

public enum Benchmarks {
    public static let variants = ["messages_ok", "messages_broken", "calendar_ok", "calendar_broken"]

    public static func casesFile(variant: String, dataset: String) -> String {
        "dataset/\(dataset)/cases_\(variant.hasPrefix("messages") ? "dev" : "eval").jsonl"
    }

    /// Re-ingests every variant found under `conditions.resultsDir` (paths relative to `root`).
    public static func load(root: URL, conditions: BenchmarkConditions) throws -> [BenchmarkRun] {
        var runs: [BenchmarkRun] = []
        let decoder = JSONDecoder()
        for v in variants {
            let dir = root.appendingPathComponent(conditions.resultsDir).appendingPathComponent(v)
            guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("raw.json").path) else { continue }
            let app = root.appendingPathComponent("Fixtures/apps/\(v)")
            let cases = root.appendingPathComponent(casesFile(variant: v, dataset: conditions.dataset))
            let mock = try Bench.run(appDirectory: app, casesURL: cases)
            let model = try AppModelLoader.load(appDirectory: app)
            let catalog = try DatasetLoader.loadCatalog(Bench.defaultCatalog(casesURL: cases, appId: model.manifest.appId))
            let plan = try decoder.decode(RunPlan.self, from: Data(contentsOf: dir.appendingPathComponent("plan.json")))
            let raw = try decoder.decode(RawRun.self, from: Data(contentsOf: dir.appendingPathComponent("raw.json")))
            runs.append(BenchmarkRun(variant: v, mixed: RealScorer.ingest(mock: mock, model: model, catalog: catalog, plan: plan, raw: raw), raw: raw))
        }
        return runs
    }

    static func f(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "n/a" }

    static func failures(_ counts: [String: Int]) -> String {
        let parts = FailureClass.allCases.compactMap { c in counts[c.rawValue].flatMap { $0 > 0 ? "\(c.rawValue)=\($0)" : nil } }
        return parts.isEmpty ? "none" : parts.joined(separator: ", ")
    }

    static func conditionsTable(_ c: BenchmarkConditions) -> String {
        var out = "| Condition | Value |\n|---|---|\n"
        for (k, v) in [("Dataset", c.dataset), ("Measured on", c.measuredOn), ("Xcode", c.xcode), ("Build SDK", c.sdk),
                       ("Run on", "\(c.runtime), \(c.device)"), ("Host", c.host), ("Signing", c.signing),
                       ("Harness protocol", c.harnessProtocol), ("MOCK resolver", c.resolver),
                       ("Raw observations", "`\(c.resultsDir)/<app>/raw.json` (plans: `plan.json`)")] {
            out += "| \(k) | \(v) |\n"
        }
        return out
    }

    static func scoreTable(_ runs: [BenchmarkRun]) -> String {
        var out = "| App | Run | v2 score | Sources | Discoverability | Entity Res. | Params | Index | On-screen & MT | Static | Failure classes |\n"
        out += "|---|---|---:|---|---:|---:|---:|---:|---:|---:|---|\n"
        for r in runs {
            let m = r.mixed
            for (label, s, counts) in [("MOCK only", m.mock.scoreV2, m.mock.failureCounts), ("MOCK + REAL", m.score, m.failureCounts)] {
                guard let s else { continue }
                let cells = s.components.map { f($0.value) }.joined(separator: " | ")
                out += "| \(r.variant) | \(label) | **\(f(s.overall))** | \(s.provenanceLabel) | \(cells) | \(failures(counts)) |\n"
            }
        }
        return out
    }

    struct Facts {
        var overAsked = 0, typoMissed = 0, wrongEntity: [String: Int] = [:]
        var mockF4 = 0, realF4 = 0, mockF8 = 0, realF8 = 0, locatedF8 = 0, located = 0, otherCreates = 0
        var possessiveMisses: [String] = [], missesByType: [String: [String]] = [:]
    }

    static func facts(_ runs: [BenchmarkRun]) -> Facts {
        var x = Facts()
        for r in runs {
            let mock = Dictionary(uniqueKeysWithValues: r.mixed.mock.outcomes.map { ($0.benchCase.caseId, $0) })
            for v in r.mixed.real where v.decidedBy == .real {
                let last = v.trace.last ?? ""
                if r.variant.hasSuffix("_ok"), last.contains("app asked although") { x.overAsked += 1 }
                if r.variant.hasSuffix("_ok"), v.failure == .f3, let o = mock[v.caseId], o.failure == nil,
                   ["typo", "asr_homophone"].contains(o.benchCase.noise) { x.typoMissed += 1 }
                if r.variant == "calendar_broken", last.hasPrefix("app acted on"), let c = v.failure { x.wrongEntity[c.rawValue, default: 0] += 1 }
            }
            if r.variant == "messages_broken" {
                x.mockF4 = r.mixed.mock.failureCounts["F4"] ?? 0
                x.realF4 = r.mixed.failureCounts["F4"] ?? 0
            }
            if r.variant == "calendar_broken" {
                x.mockF8 = r.mixed.mock.failureCounts["F8"] ?? 0
                x.realF8 = r.mixed.failureCounts["F8"] ?? 0
                let byCase = Dictionary(uniqueKeysWithValues: r.mixed.mock.outcomes.map { ($0.benchCase.caseId, $0.benchCase) })
                for v in r.mixed.real where byCase[v.caseId]?.expected.intent == "CreateEventIntent" && v.decidedBy != .mock {
                    if byCase[v.caseId]?.expected.params["location"] != nil {
                        x.located += 1
                        if v.failure == .f8 { x.locatedF8 += 1 }
                    } else { x.otherCreates += 1 }
                }
            }
            if r.variant.hasSuffix("_ok") {
                for p in r.raw.indexProbes where !p.ids.contains(p.entityId) {
                    if p.query.contains("'s") { x.possessiveMisses.append(p.query) } else { x.missesByType[p.entityType, default: []].append(p.query) }
                }
            }
        }
        x.possessiveMisses = Array(Set(x.possessiveMisses)).sorted()
        for k in x.missesByType.keys { x.missesByType[k] = Array(Set(x.missesByType[k]!)).sorted() }
        return x
    }

    public static func render(primary: BenchmarkConditions, runs: [BenchmarkRun], followUp: (BenchmarkConditions, [BenchmarkRun])? = nil) -> String {
        render(primary: primary, runs: runs, followUps: followUp.map { [$0] } ?? [])
    }

    /// Score and per-case comparison between two runs of the same apps (used for the v1.2 rename check).
    static func comparison(_ before: [BenchmarkRun], _ after: [BenchmarkRun], beforeLabel: String, afterLabel: String) -> String {
        var out = "| App | Run | \(beforeLabel) | \(afterLabel) | Δ |\n|---|---|---:|---:|---:|\n"
        var changed: [String] = []
        for a in after {
            guard let b = before.first(where: { $0.variant == a.variant }) else { continue }
            for (label, x, y) in [("MOCK only", b.mixed.mock.scoreV2?.overall, a.mixed.mock.scoreV2?.overall),
                                  ("MOCK + REAL", b.mixed.score.overall, a.mixed.score.overall)] {
                let delta = (x != nil && y != nil) ? String(format: "%+.1f", y! - x!) : "n/a"
                out += "| \(a.variant) | \(label) | \(f(x)) | \(f(y)) | \(delta) |\n"
            }
            let old = Dictionary(uniqueKeysWithValues: b.mixed.real.map { ($0.caseId, $0.failure) })
            for v in a.mixed.real where old[v.caseId] != nil && old[v.caseId]! != v.failure {
                changed.append("`\(v.caseId)` (\(a.variant)): \(old[v.caseId]!?.rawValue ?? "pass") → \(v.failure?.rawValue ?? "pass")")
            }
        }
        out += "\nCases whose real class changed: " + (changed.isEmpty ? "**none**." : "\(changed.count) — " + changed.joined(separator: "; ") + ".") + "\n"
        return out
    }

    public static func render(primary: BenchmarkConditions, runs: [BenchmarkRun], followUps: [(BenchmarkConditions, [BenchmarkRun])]) -> String {
        var out = "# SiriReady Bench — benchmark results\n\n"
        out += "<!-- Generated by `siriready benchmarks` from committed results; do not edit by hand. -->\n\n"
        out += """
        > **Read this first.** These numbers come from four *reference apps built for this benchmark* (two correct, two \
        intentionally broken), not from App Store apps. `real` components were measured with AppIntentsTesting on an iOS \
        simulator; `mock` components come from SiriReady's rule-based MOCK resolver — in particular **F1/F2 (does an \
        utterance reach the right intent?) is always MOCK**, because AppIntentsTesting does not exercise Siri's speech \
        recognition or language understanding. `static` is source analysis. No physical-device Siri run has been recorded \
        (the spot-check protocol exists but has not been executed). Scores depend on OS, SDK, device and locale; they are \
        not absolute values.


        """
        out += "## \(primary.label): Siri Visibility Score v2\n\n"
        let sources = runs.first.map { ProvenanceShare.label($0.mixed.score.provenance) } ?? ""
        out += "Every MOCK + REAL score below is composed of **\(sources)** (weighted by component). MOCK-only rows contain no real evidence.\n"
        out += "Component columns follow the v2 profile: Discoverability 20%, Entity Resolution 20%, Parameter Accuracy 10%, Index Recall 15%, On-screen & Multi-turn 15%, Static Health 20%.\n\n"
        out += scoreTable(runs) + "\n"
        out += "### Measurement conditions\n\n" + conditionsTable(primary) + "\n"

        let x = facts(runs)
        out += "## What the real runs showed that the MOCK did not\n\n"
        out += "1. **Over-asking in the correct apps (F5).** \(x.overAsked) requests that already named one entity (\"Thursday's Team Sync\", \"Sam Lee from work\") still triggered `requestDisambiguation` in the *ok* apps: `perform()` asks whenever a same-name or same-reading entity exists, even after the target was narrowed to one.\n"
        out += "2. **No fuzzy matching in Spotlight or the string queries.** \(x.typoMissed) typo / sound-alike requests (\"Ktaherine Osei\", \"Sean Patel\" for Shawn, \"Design Revue\") returned nothing from `spotlightQuery` or `entities(matching:)` in the ok apps. The MOCK assumed indexed entities could be matched fuzzily — too optimistic.\n"
        out += "3. **Index holes** (Spotlight probes that did not return the probed entity, ok apps). Possessive titles: \(x.possessiveMisses.isEmpty ? "none" : x.possessiveMisses.map { "\"\($0)\"" }.joined(separator: ", ")). "
        out += x.missesByType.keys.sorted().map { type in
            let qs = x.missesByType[type]!
            let note = type == "ConversationEntity" ? " — kana readings; the conversation entity indexes no readings"
                : type == "CalendarEntity" ? " — calendar aliases; the calendar entity indexes only its title" : ""
            return "\(type): \(qs.count) (\(qs.prefix(6).joined(separator: ", "))\(qs.count > 6 ? ", …" : ""))\(note)"
        }.joined(separator: ". ") + ".\n"
        let wrong = x.wrongEntity.values.reduce(0, +)
        out += "4. **Silent action on another event.** calendar_broken acted on a different event than the one requested in \(wrong) cases (e.g. updated the Tuesday \"Vendor Sync\" when Friday's was named): \(x.wrongEntity["F5"] ?? 0) were same-title siblings, which SiriReady classifies as F5 (a silent pick that should have been a question), and \(x.wrongEntity["F3"] ?? 0) were a different, sound-alike title (F3, e.g. Jon's vs John's Birthday Dinner).\n"
        out += "5. **The toolchain changed a broken app.** Xcode 27.1 refuses to build a `sendMessage` destination entity that is neither indexed nor string-queryable, so the buildable messages_broken keeps a name-only string query. That rescues exact-name requests: F4 fell from \(x.mockF4) (MOCK) to \(x.realF4) (real), and the broken app scores *higher* with real evidence than under the MOCK.\n"
        out += "6. **Static privacy findings are input-dependent.** calendar_broken's remote geocoder only runs when a location is given: real F8 (an attempted off-device call, intercepted inside the app) in \(x.locatedF8) of \(x.located) location-bearing creates and in none of the other \(x.otherCreates). The MOCK flags all \(x.mockF8) creates from source evidence; calendar_ok never attempts a call.\n\n"
        if runs.contains(where: { r in r.mixed.mock.outcomes.contains { $0.benchCase.tags.first?.hasPrefix("gap_") == true } }) {
            out += "### Cases added for the data gaps above\n\n" + gapSection(runs) + "\n"
        }

        for (cond, extra) in followUps where !extra.isEmpty {
            out += "## \(cond.label)\n\n"
            out += (cond.note ?? "Dataset \(cond.dataset). Same apps and harness.") + "\n\n"
            if let ref = cond.compareWith, let base = followUps.first(where: { $0.0.resultsDir == ref }) {
                out += scoreTable(extra) + "\n"
                out += "### Rename check: \(base.0.dataset) → \(cond.dataset)\n\n"
                out += comparison(base.1, extra, beforeLabel: base.0.dataset, afterLabel: cond.dataset) + "\n"
                out += "### Measurement conditions\n\n" + conditionsTable(cond) + "\n"
                continue
            }
            out += scoreTable(extra) + "\n"
            var gapRows = "Wrong parameter values (e.g. the wrong calendar) are not a failure class; they are counted under Parameter Accuracy.\n\n"
            gapRows += "| App | Gap tag | Cases | MOCK: no failure class | Real: no failure class | Real failure classes |\n|---|---|---:|---:|---:|---|\n"
            for r in extra {
                let mock = Dictionary(uniqueKeysWithValues: r.mixed.mock.outcomes.map { ($0.benchCase.caseId, $0) })
                var byTag: [String: [RealCaseOutcome]] = [:]
                for v in r.mixed.real {
                    if let tag = mock[v.caseId]?.benchCase.tags.first, tag.hasPrefix("gap_") { byTag[tag, default: []].append(v) }
                }
                for tag in byTag.keys.sorted() {
                    let vs = byTag[tag]!
                    var counts: [String: Int] = [:]
                    for v in vs { if let c = v.failure { counts[c.rawValue, default: 0] += 1 } }
                    let mockPass = vs.filter { mock[$0.caseId]?.failure == nil }.count
                    gapRows += "| \(r.variant) | \(tag) | \(vs.count) | \(mockPass) | \(vs.filter { $0.failure == nil && !$0.notMeasured }.count) | \(failures(counts)) |\n"
                }
            }
            out += gapRows + "\n"
            out += followUpNotes(extra) + "\n"
            out += "### Measurement conditions\n\n" + conditionsTable(cond) + "\n"
        }

        out += "## Reproduce\n\n```bash\nscripts/reingest.sh                 # rebuild per-app MOCK+REAL reports from the committed raw observations\nscripts/make_benchmarks.sh          # regenerate this file\nscripts/real_run.sh calendar_broken # re-measure one app on an iOS 27 simulator (8–10 min)\n```\n"
        return out
    }

    /// Gap-case table plus computed notes (cases added for gaps found by earlier real runs).
    static func gapSection(_ extra: [BenchmarkRun]) -> String {
        var gapRows = "Wrong parameter values (e.g. the wrong calendar) are not a failure class; they are counted under Parameter Accuracy.\n\n"
        gapRows += "| App | Gap tag | Cases | MOCK: no failure class | Real: no failure class | Real failure classes |\n|---|---|---:|---:|---:|---|\n"
        for r in extra {
            let mock = Dictionary(uniqueKeysWithValues: r.mixed.mock.outcomes.map { ($0.benchCase.caseId, $0) })
            var byTag: [String: [RealCaseOutcome]] = [:]
            for v in r.mixed.real {
                if let tag = mock[v.caseId]?.benchCase.tags.first, tag.hasPrefix("gap_") { byTag[tag, default: []].append(v) }
            }
            for tag in byTag.keys.sorted() {
                let vs = byTag[tag]!
                var counts: [String: Int] = [:]
                for v in vs { if let c = v.failure { counts[c.rawValue, default: 0] += 1 } }
                let mockPass = vs.filter { mock[$0.caseId]?.failure == nil }.count
                gapRows += "| \(r.variant) | \(tag) | \(vs.count) | \(mockPass) | \(vs.filter { $0.failure == nil && !$0.notMeasured }.count) | \(failures(counts)) |\n"
            }
        }
        return gapRows + "\n" + followUpNotes(extra)
    }

    /// Observations specific to the v1.1 gap cases, computed from the runs.
    static func followUpNotes(_ runs: [BenchmarkRun]) -> String {
        var lines: [String] = []
        for r in runs {
            let mock = Dictionary(uniqueKeysWithValues: r.mixed.mock.outcomes.map { ($0.benchCase.caseId, $0.benchCase) })
            let raw = Dictionary(uniqueKeysWithValues: r.raw.cases.map { ($0.caseId, $0) })
            let located = r.mixed.real.filter { mock[$0.caseId]?.expected.params["location"] != nil }
            if r.variant.hasPrefix("calendar"), !located.isEmpty {
                let f8 = located.filter { $0.failure == .f8 }.count
                let hosts = Set(located.flatMap { raw[$0.caseId]?.egress ?? [] }).sorted()
                lines.append("- **\(r.variant), location-bearing creates:** \(f8) / \(located.count) real F8; attempted hosts: \(hosts.isEmpty ? "none" : hosts.joined(separator: ", ")) (intercepted inside the app, never sent).")
            }
            if r.variant == "calendar_ok" {
                let alias = r.mixed.real.filter { mock[$0.caseId]?.tags.first == "gap_calendar_alias" }
                let wrong = alias.filter { v in
                    let expected = mock[v.caseId]?.expected.params["calendar"]?.description
                    return raw[v.caseId]?.effects.first.map { $0.params["calendar"] != expected } ?? false
                }
                let jaDefault = alias.filter { mock[$0.caseId]?.locale == "ja-JP" && mock[$0.caseId]?.expected.params["calendar"]?.description == "cal_work" }
                lines.append("- **Calendar aliases:** \(wrong.count) / \(alias.count) creates landed on the wrong calendar (\(wrong.map(\.caseId).joined(separator: ", "))): Spotlight does not return a calendar for its Japanese alias, and the harness then uses the app's default calendar (`cal_work`). The \(jaDefault.count) Japanese 仕事 (= `cal_work`) cases therefore pass only by that default; parameter accuracy is unaffected for them but should not be read as alias support.")
            }
            if r.variant == "messages_ok" {
                let byReading = r.mixed.real.filter { mock[$0.caseId]?.tags.first == "gap_conversation_index" && mock[$0.caseId]?.locale == "ja-JP" }
                let found = byReading.filter { $0.failure == nil }
                lines.append("- **Conversations by kana reading (ja-JP):** Spotlight returned the conversation for \(found.count) / \(byReading.count) readings (\(found.compactMap { mock[$0.caseId]?.mention }.joined(separator: ", "))) and nothing for the rest, although the conversation entity indexes no reading. Nicknames (en-US) are found through the indexed `alternateNames`.")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Per-case list of MOCK vs real disagreements (appendix of docs/mock-divergence.md).
    public static func divergenceAppendix(_ runs: [BenchmarkRun], conditions: BenchmarkConditions) -> String {
        var out = "# MOCK divergence — case list (\(conditions.label))\n\n"
        out += "<!-- Generated by `siriready benchmarks`; do not edit by hand. -->\n\n"
        out += "Cases whose class differs between the MOCK (`\(conditions.resolver)`) and the real run. A MOCK resolver version that adopted the real behaviour would reclassify exactly these cases. See docs/mock-divergence.md for the rules.\n\n"
        for r in runs {
            let mock = Dictionary(uniqueKeysWithValues: r.mixed.mock.outcomes.map { ($0.benchCase.caseId, $0) })
            var groups: [String: [String]] = [:]
            for v in r.mixed.real where !v.notMeasured && v.decidedBy != .mock {
                let m = mock[v.caseId]?.failure
                guard m != v.failure else { continue }
                let reason = (v.trace.last ?? "").replacingOccurrences(of: #"(c|conv_c|conv_j|j|ev|jev|msg)_[\w]+"#, with: "<id>", options: .regularExpression)
                groups["\(m?.rawValue ?? "pass") → \(v.failure?.rawValue ?? "pass") — \(reason)", default: []].append(v.caseId)
            }
            out += "## \(r.variant) (\(groups.values.reduce(0) { $0 + $1.count }) cases)\n\n"
            for key in groups.keys.sorted() {
                let ids = groups[key]!.sorted()
                out += "- **\(key)** (\(ids.count)): \(ids.map { "`\($0)`" }.joined(separator: " "))\n"
            }
            out += "\n"
        }
        return out
    }
}
