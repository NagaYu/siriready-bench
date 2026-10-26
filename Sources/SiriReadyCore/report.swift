import Foundation

public enum ReportRenderer {
    static let mockBanner = """
    > **MOCK result.** Scores and failure classes come from SiriReady's deterministic, rule-based MOCK resolver \
    applied to the app's *source declarations* and a synthetic dataset. They are **not** measurements of Siri, \
    Apple Intelligence or Spotlight, and not an absolute, OS-independent value. Measuring the real system \
    (AppIntentsTesting on iOS 27, Spotlight queries, device spot checks) is Phase 2.
    """

    static func fmt(_ v: Double?) -> String { v.map { String(format: "%.1f", $0) } ?? "n/a" }

    static func location(_ l: SourceLocation?) -> String { l.map { "`\($0.file):\($0.line)`" } ?? "`siriready.yaml`" }

    static func escape(_ s: String) -> String { s.replacingOccurrences(of: "|", with: "\\|") }

    // MARK: audit

    public static func auditMarkdown(_ audit: AuditReport, heading: String = "##") -> String {
        var out = ""
        out += "\(heading) Static audit (C1–C5) — \(audit.findings.count) finding(s)\n\n"
        out += String(format: "IndexedEntity coverage (C2): **%.0f%%** · View Annotations coverage (C3): **%.0f%%**\n\n",
                      audit.indexCoverage * 100, audit.annotationCoverage * 100)
        if audit.findings.isEmpty {
            out += "No findings.\n"
            return out
        }
        out += "Ordered by impact on discoverability (severity, then check). Suggestions are text only; SiriReady never edits the app.\n\n"
        for (i, f) in audit.findings.enumerated() {
            out += "\(i + 1). **[\(f.check.rawValue) \(f.check.title) · \(f.severity.rawValue)]** \(location(f.location))"
            if let rf = f.relatedFailure { out += " → expected to surface as \(rf)" }
            out += "\n   - Reason: \(f.reason)\n   - Suggestion: \(f.suggestion)\n"
        }
        return out
    }

    // MARK: bench

    public static func markdown(_ r: BenchResult) -> String {
        let c = r.conditions
        var out = "# SiriReady Bench report — \(c.appDisplayName) [`\(c.appFixture)`] (MOCK)\n\n"
        out += mockBanner + "\n\n"
        out += String(format: "## Siri Visibility Score (MOCK): **%.1f / 100**\n\n", r.score.overall)
        out += "| Component | Weight | Score | Passed / Total | Source | How it is computed |\n|---|---:|---:|---:|---|---|\n"
        for comp in r.score.components {
            out += "| \(comp.component.rawValue) | \(Int(comp.weight * 100))% | \(fmt(comp.value)) | \(comp.passed) / \(comp.total) | \(v1Source(comp.component)) | \(escape(comp.note)) |\n"
        }
        out += "\nComponents without applicable cases show `n/a` and their weight is redistributed.\n\n"
        if let v2 = r.scoreV2 {
            out += v2Markdown(v2, title: "Siri Visibility Score v2 (MOCK, adds Parameter Accuracy)")
        }

        out += "## Failures by class (\(r.outcomes.count) cases, \(r.outcomes.filter { $0.failure == nil }.count) passed)\n\n"
        out += "| Class | Name | Count | Representative cases |\n|---|---|---:|---|\n"
        for f in FailureClass.allCases {
            let hits = r.outcomes.filter { $0.failure == f }
            let examples = hits.prefix(2).map { o -> String in
                // The routing line explains F8; for every other class the last step is the one that failed.
                let why = f == .f8 ? o.result.trace.first { $0.contains("on_device_only") } : o.result.trace.last
                return "`\(o.benchCase.caseId)` “\(escape(o.benchCase.utterance))” — \(escape(why ?? ""))"
            }
            out += "| \(f.rawValue) | \(f.title) | \(hits.count) | \(examples.joined(separator: "<br>")) |\n"
        }
        out += "\n<details><summary>F1–F8 definitions</summary>\n\n"
        for f in FailureClass.allCases { out += "- **\(f.rawValue) \(f.title)**: \(f.definition)\n" }
        out += "\n</details>\n\n"

        out += "## Pass rate by slice\n\n| Slice | Passed / Total | Rate |\n|---|---:|---:|\n"
        for (label, key) in slices(r) {
            let subset = r.outcomes.filter(key)
            guard !subset.isEmpty else { continue }
            let passed = subset.filter { $0.failure == nil }.count
            out += String(format: "| %@ | %d / %d | %.0f%% |\n", label, passed, subset.count, 100 * Double(passed) / Double(subset.count))
        }
        out += "\n"

        out += auditMarkdown(r.audit) + "\n"
        if let s = r.spotcheck { out += spotcheckMarkdown(s) }

        out += "## Measurement conditions\n\n| Field | Value |\n|---|---|\n"
        let rows: [(String, String)] = [
            ("Mode", "**\(c.mode)** (resolver `\(c.resolver)`, bench \(c.benchVersion))"),
            ("Target app fixture", "`\(c.appFixture)` (app_id `\(c.appId)`)"),
            ("Cases", "\(c.caseCount) from `\(c.casesFile)` (fingerprint `\(c.casesFingerprint)`)\(c.skippedCases > 0 ? "; \(c.skippedCases) case(s) of other apps skipped" : "")"),
            ("Locales", c.locales.keys.sorted().map { "\($0): \(c.locales[$0]!)" }.joined(separator: ", ")),
            ("Entity catalog", "`\(c.catalogFile)` (fingerprint `\(c.catalogFingerprint)`, dataset \(c.datasetVersion), synthetic)"),
            ("Target OS", c.targetOS),
            ("Target SDK", c.targetSDK),
            ("Host", c.hostOS),
            ("Index Recall", String(format: "Phase 1 stand-in: C2 coverage %.0f%% and simulated lexical/phonetic recall %.0f%% (%d/%d probes); not a Spotlight measurement",
                                    r.index.coverage * 100, r.index.simulatedRecall * 100, r.index.hits, r.index.queries)),
        ]
        for (k, v) in rows { out += "| \(k) | \(escape(v)) |\n" }
        out += "\n**Reproduced by the MOCK:** " + c.reproduces.joined(separator: "; ") + ".\n\n"
        out += "**Not reproduced:** " + c.doesNotReproduce.joined(separator: "; ") + ".\n"
        return out
    }

    static func slices(_ r: BenchResult) -> [(String, (CaseOutcome) -> Bool)] {
        var result: [(String, (CaseOutcome) -> Bool)] = []
        for locale in Set(r.outcomes.map(\.benchCase.locale)).sorted() { result.append(("locale \(locale)", { $0.benchCase.locale == locale })) }
        result.append(("adversarial", { $0.benchCase.adversarial }))
        result.append(("non-adversarial", { !$0.benchCase.adversarial }))
        for noise in Set(r.outcomes.map(\.benchCase.noise)).sorted() { result.append(("noise \(noise)", { $0.benchCase.noise == noise })) }
        for tag in Set(r.outcomes.flatMap(\.benchCase.tags)).sorted() { result.append(("tag \(tag)", { $0.benchCase.tags.contains(tag) })) }
        return result
    }

    // MARK: comparison

    public static func comparisonMarkdown(_ a: BenchResult, _ b: BenchResult) -> String {
        var out = "# SiriReady Bench comparison (MOCK): `\(a.conditions.appFixture)` vs `\(b.conditions.appFixture)`\n\n"
        out += mockBanner + "\n\n"
        if a.conditions.casesFingerprint != b.conditions.casesFingerprint || a.conditions.resolver != b.conditions.resolver {
            out += "> ⚠️ The two runs used different cases or resolver versions; the scores are not comparable.\n\n"
        }
        out += "| | `\(a.conditions.appFixture)` | `\(b.conditions.appFixture)` | Δ |\n|---|---:|---:|---:|\n"
        out += String(format: "| **Siri Visibility Score (MOCK)** | **%.1f** | **%.1f** | **%+.1f** |\n", a.score.overall, b.score.overall, b.score.overall - a.score.overall)
        for (ca, cb) in zip(a.score.components, b.score.components) {
            let delta = (ca.value != nil && cb.value != nil) ? String(format: "%+.1f", cb.value! - ca.value!) : "n/a"
            out += "| \(ca.component.rawValue) | \(fmt(ca.value)) | \(fmt(cb.value)) | \(delta) |\n"
        }
        if let x = a.scoreV2, let y = b.scoreV2 {
            out += String(format: "| Siri Visibility Score v2 (MOCK) | %.1f | %.1f | %+.1f |\n", x.overall, y.overall, y.overall - x.overall)
        }
        out += "| Audit findings | \(a.audit.findings.count) | \(b.audit.findings.count) | \(b.audit.findings.count - a.audit.findings.count) |\n"
        for f in FailureClass.allCases {
            let x = a.failureCounts[f.rawValue] ?? 0, y = b.failureCounts[f.rawValue] ?? 0
            out += "| \(f.rawValue) \(f.title) | \(x) | \(y) | \(y - x >= 0 ? "+" : "")\(y - x) |\n"
        }
        out += "\nCases: \(a.conditions.caseCount) (`\(a.conditions.casesFile)`, fingerprint `\(a.conditions.casesFingerprint)`).\n"
        return out
    }
}
