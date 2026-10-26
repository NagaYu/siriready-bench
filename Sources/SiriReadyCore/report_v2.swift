import Foundation

// Phase 2 report sections: provenance-tagged v2 score, mixed MOCK+REAL reports and spot checks.

extension ReportRenderer {
    static let mixedBanner = """
    > **MOCK + REAL result.** Components tagged `real` were measured against the built reference app with \
    AppIntentsTesting (entity queries, Spotlight, View Annotations, intent execution and its side effects). \
    Components tagged `mock` come from SiriReady's rule-based MOCK resolver — in particular F1/F2 \
    (does the utterance reach the intent?) is always MOCK, because AppIntentsTesting cannot observe Siri's \
    language understanding. `static` is the source audit. None of this is a measurement of Siri itself.
    """

    /// Source label for a Phase 1 (v1) component in a MOCK-only run.
    static func v1Source(_ c: ScoreComponent) -> String {
        switch c {
        case .indexRecall: return "static + mock"
        case .staticHealth: return "static + mock"
        default: return "mock"
        }
    }

    static func sourceLabel(_ shares: [ProvenanceShare]) -> String {
        shares.count == 1 ? shares[0].source.rawValue : ProvenanceShare.label(shares)
    }

    public static func v2Markdown(_ s: ScoreBreakdownV2, title: String) -> String {
        var out = String(format: "## %@: **%.1f / 100**\n\nSources: %@\n\n", title, s.overall, s.provenanceLabel)
        out += "| Component | Weight | Score | Passed / Total | Source | How it is computed |\n|---|---:|---:|---:|---|---|\n"
        for c in s.components {
            out += "| \(c.component.rawValue) | \(Int(c.weight * 100))% | \(fmt(c.value)) | \(c.passed) / \(c.total) | \(sourceLabel(c.provenance)) | \(escape(c.note)) |\n"
        }
        return out + "\n"
    }

    public static func spotcheckMarkdown(_ log: SpotcheckLog) -> String {
        var out = "## Spot checks (manual, provenance `spotcheck`; not part of any score)\n\n"
        if log.sample { out += "> ⚠️ **SAMPLE** — this log is an illustrative, fictional fill-in of the protocol, not an observation.\n\n" }
        let passed = log.results.filter(\.success).count
        out += "Device: \(log.device) · OS: \(log.os) · Locale: \(log.locale) · Siri: \(escape(log.siriSettings))\(log.recordedOn.map { " · Recorded: \($0)" } ?? "")\n\n"
        out += "\(passed) / \(log.results.count) succeeded (voice: \(log.results.filter { $0.inputMode == "voice" }.count), typed: \(log.results.filter { $0.inputMode == "typed" }.count)).\n\n"
        out += "| Case | Input | Reached intent | Resolved entity | Success | Notes |\n|---|---|---|---|:---:|---|\n"
        for r in log.results {
            out += "| `\(r.caseId)` | \(r.inputMode) | \(r.reachedIntent ?? "—") | \(r.resolvedEntity ?? "—") | \(r.success ? "✓" : "✗") | \(escape(r.notes)) |\n"
        }
        return out + "\n"
    }

    public static func mixedMarkdown(_ m: MixedResult) -> String {
        let c = m.conditions
        var out = "# SiriReady Bench report — \(c.appDisplayName) [`\(c.appFixture)`] (MOCK + REAL)\n\n"
        out += mixedBanner + "\n\n"
        out += v2Markdown(m.score, title: "Siri Visibility Score v2 (MOCK + REAL)")
        if let mockV2 = m.mock.scoreV2 {
            out += String(format: "For comparison, the MOCK-only v2 score for the same cases is **%.1f** (%@); the Phase 1 (v1, five components) MOCK score is %.1f.\n\n",
                          mockV2.overall, mockV2.provenanceLabel, m.mock.score.overall)
        }

        let measured = m.real.filter { !$0.notMeasured && $0.decidedBy != .mock }
        let stoppedAtMock = m.real.filter { $0.decidedBy == .mock }.count
        out += "## Failures by class (\(m.real.count) cases; \(measured.count) executed against the app, \(stoppedAtMock) stopped at MOCK F1/F2, \(m.real.filter(\.notMeasured).count) not measured)\n\n"
        out += "| Class | Name | MOCK only | MOCK + REAL | decided by real | Representative real cases |\n|---|---|---:|---:|---:|---|\n"
        let mockByCase = Dictionary(uniqueKeysWithValues: m.mock.outcomes.map { ($0.benchCase.caseId, $0) })
        for f in FailureClass.allCases {
            let real = m.real.filter { $0.failure == f }
            let byReal = real.filter { $0.decidedBy == .real }
            let examples = byReal.prefix(2).map { "`\($0.caseId)` “\(escape(mockByCase[$0.caseId]?.benchCase.utterance ?? ""))” — \(escape($0.trace.last ?? ""))" }
            out += "| \(f.rawValue) | \(f.title) | \(m.mock.failureCounts[f.rawValue] ?? 0) | \(real.count) | \(byReal.count) | \(examples.joined(separator: "<br>")) |\n"
        }
        out += "\n"

        let disagreements = m.real.filter { r in !r.notMeasured && r.decidedBy != .mock && mockByCase[r.caseId]?.failure != r.failure }
        out += "## Where the real run disagrees with the MOCK (\(disagreements.count) cases)\n\n"
        if disagreements.isEmpty {
            out += "None.\n\n"
        } else {
            var groups: [String: [RealCaseOutcome]] = [:]
            for d in disagreements {
                groups["\(mockByCase[d.caseId]?.failure?.rawValue ?? "pass") → \(d.failure?.rawValue ?? "pass")", default: []].append(d)
            }
            out += "| MOCK → REAL | Cases | Examples |\n|---|---:|---|\n"
            for key in groups.keys.sorted() {
                let g = groups[key]!
                let ex = g.prefix(3).map { "`\($0.caseId)` “\(escape(mockByCase[$0.caseId]?.benchCase.utterance ?? ""))” — \(escape($0.trace.last ?? ""))" }
                out += "| \(key) | \(g.count) | \(ex.joined(separator: "<br>")) |\n"
            }
            out += "\n"
        }

        let errors = m.real.filter { $0.executionError != nil }
        if !errors.isEmpty {
            out += "## Execution errors (run() threw for a reason other than disambiguation; \(errors.count) cases)\n\n"
            for e in errors.prefix(10) { out += "- `\(e.caseId)`: \(escape(e.executionError ?? ""))\n" }
            out += "\n"
        }

        let extraction = m.params.filter(\.extractionCorrect).count
        let execution = m.params.filter { $0.executionCorrect == true }.count
        out += "## Parameters\n\n"
        out += "\(m.params.count) executed cases expect parameters (cases stopped at entity resolution or by a disambiguation request are not counted twice). MOCK slot filling matched expected.params in \(extraction); the app persisted the expected values in \(execution) (observed effect, real).\n\n"

        out += "## Index\n\n"
        out += String(format: "Spotlight probes (real): %d / %d returned the probed entity (%.0f%%). Entity types with any hit: %@. C2 coverage (static): %.0f%%.\n\n",
                      m.index.hits, m.index.queries, m.realIndexRecall * 100, m.indexedTypesObserved.isEmpty ? "none" : m.indexedTypesObserved.joined(separator: ", "),
                      m.index.coverage * 100)

        if let s = m.spotcheck { out += spotcheckMarkdown(s) }

        out += auditMarkdown(m.mock.audit) + "\n"
        out += "## Measurement conditions\n\n| Field | Value |\n|---|---|\n"
        let rows: [(String, String)] = [
            ("Mode", "**MOCK + REAL** (resolver `\(c.resolver)`, bench \(c.benchVersion), harness protocol `\(harnessProtocolVersion)`)"),
            ("Real stages ran on", "\(m.device), \(m.osVersion) — reference app built from Apps/ (see Apps/README.md)"),
            ("MOCK stages used", "source fixture `\(c.appFixture)` (same declarations as the built app)"),
            ("Cases", "\(c.caseCount) from `\(c.casesFile)` (fingerprint `\(c.casesFingerprint)`)"),
            ("Entity catalog", "`\(c.catalogFile)` (fingerprint `\(c.catalogFingerprint)`, dataset \(c.datasetVersion), synthetic)"),
            ("Host", c.hostOS),
            ("Not measured", "Siri speech recognition / language understanding (F1/F2 are MOCK), system-level disambiguation UI, physical devices"),
        ]
        for (k, v) in rows { out += "| \(k) | \(escape(v)) |\n" }
        return out
    }
}
