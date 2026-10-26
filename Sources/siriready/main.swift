import Foundation
import SiriReadyCore

let usage = """
siriready \(benchVersion) — SiriReady Bench, Phase 1 (offline; results are MOCK, not Siri measurements)

USAGE
  siriready audit  --app <fixture dir> [--json] [--out <file>]
  siriready bench  --app <fixture dir> --cases <jsonl> --out <dir> [--catalog <json>]
  siriready report --in <bench out dir> [--out <dir>]
  siriready report --compare <bench out dir A> <bench out dir B> [--out <file>]
  siriready plan   --app <fixture dir> --cases <jsonl> --bundle-id <id> --out <plan.json> [--catalog <json>]
  siriready ingest --app <fixture dir> --cases <jsonl> --plan <plan.json> --raw <raw.json> --out <dir>
                   [--catalog <json>] [--spotcheck <json>]
  siriready benchmarks --conditions <json> --out BENCHMARKS.md [--follow-up <json> ...] [--divergence-out <md>]

bench writes report.json (full result) and report.md into --out.
report re-renders report.md from report.json, or compares two runs.
plan / ingest bracket a real AppIntentsTesting run (scripts/real_run.sh): the MOCK decides what
reaches which intent (F1/F2), the harness observes the app, ingest scores with provenance tags.
"""

struct CLIError: Error, CustomStringConvertible {
    var description: String
}

struct Arguments {
    var options: [String: [String]] = [:]
    var flags: Set<String> = []

    init(_ args: ArraySlice<String>, flags known: Set<String>) {
        var i = args.startIndex
        while i < args.endIndex {
            let a = args[i]
            if a.hasPrefix("--") {
                let name = String(a.dropFirst(2))
                if known.contains(name) {
                    flags.insert(name)
                } else {
                    var values: [String] = []
                    while i + 1 < args.endIndex, !args[i + 1].hasPrefix("--") {
                        values.append(args[i + 1]); i += 1
                    }
                    options[name] = values
                }
            }
            i += 1
        }
    }

    func value(_ name: String) throws -> String {
        guard let v = options[name]?.first else { throw CLIError(description: "missing --\(name)\n\n\(usage)") }
        return v
    }
}

func url(_ path: String) -> URL { URL(fileURLWithPath: path).standardizedFileURL }

func write(_ data: Data, to path: URL) throws {
    try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: path)
}

func loadResult(_ dir: String) throws -> BenchResult {
    try JSONDecoder().decode(BenchResult.self, from: Data(contentsOf: url(dir).appendingPathComponent("report.json")))
}

func run() throws {
    let argv = CommandLine.arguments
    guard argv.count >= 2 else { print(usage); return }
    let args = Arguments(argv.dropFirst(2), flags: ["json", "help"])
    switch argv[1] {
    case "audit":
        let model = try AppModelLoader.load(appDirectory: url(try args.value("app")))
        let audit = Auditor.audit(model)
        let output = args.flags.contains("json")
            ? String(decoding: try Bench.encode(audit), as: UTF8.self) + "\n"
            : "# SiriReady audit — \(model.manifest.displayName) [`\(audit.appPath)`]\n\n" + ReportRenderer.auditMarkdown(audit)
        if let out = args.options["out"]?.first { try write(Data(output.utf8), to: url(out)) } else { print(output, terminator: "") }

    case "bench":
        var result = try Bench.run(
            appDirectory: url(try args.value("app")),
            casesURL: url(try args.value("cases")),
            catalogURL: args.options["catalog"]?.first.map(url))
        if let s = args.options["spotcheck"]?.first { result.spotcheck = try SpotcheckLog.load(url(s)) }
        let out = url(try args.value("out"))
        try write(try Bench.encode(result), to: out.appendingPathComponent("report.json"))
        try write(Data(ReportRenderer.markdown(result).utf8), to: out.appendingPathComponent("report.md"))
        let failures = FailureClass.allCases.compactMap { f in result.failureCounts[f.rawValue].flatMap { $0 > 0 ? "\(f.rawValue)=\($0)" : nil } }
        print(String(format: "[MOCK] %@: Siri Visibility Score %.1f/100 over %d cases; failures: %@; audit findings: %d",
                     result.conditions.appFixture, result.score.overall, result.conditions.caseCount,
                     failures.isEmpty ? "none" : failures.joined(separator: " "), result.audit.findings.count))

    case "report":
        if let pair = args.options["compare"], pair.count == 2 {
            let md = ReportRenderer.comparisonMarkdown(try loadResult(pair[0]), try loadResult(pair[1]))
            if let out = args.options["out"]?.first { try write(Data(md.utf8), to: url(out)) } else { print(md, terminator: "") }
        } else {
            let input = try args.value("in")
            let result = try loadResult(input)
            let out = url(args.options["out"]?.first ?? input)
            try write(try Bench.encode(result), to: out.appendingPathComponent("report.json"))
            try write(Data(ReportRenderer.markdown(result).utf8), to: out.appendingPathComponent("report.md"))
            print("wrote \(out.appendingPathComponent("report.md").path)")
        }

    case "plan":
        let model = try AppModelLoader.load(appDirectory: url(try args.value("app")))
        let casesURL = url(try args.value("cases"))
        let catalogURL = args.options["catalog"]?.first.map(url) ?? Bench.defaultCatalog(casesURL: casesURL, appId: model.manifest.appId)
        let plan = RunPlanner.plan(model: model, catalog: try DatasetLoader.loadCatalog(catalogURL), cases: try DatasetLoader.loadCases(casesURL),
                                   bundleIdentifier: try args.value("bundle-id"),
                                   casesFingerprint: DatasetLoader.fingerprint(try Data(contentsOf: casesURL)))
        try write(try Bench.encode(plan), to: url(try args.value("out")))
        let skipped = plan.cases.filter { $0.mockFailure != nil }.count
        print("plan: \(plan.cases.count) cases (\(skipped) stop at MOCK F1/F2), \(plan.indexProbes.count) index probes")

    case "ingest":
        let appURL = url(try args.value("app"))
        let casesURL = url(try args.value("cases"))
        let mock = try Bench.run(appDirectory: appURL, casesURL: casesURL, catalogURL: args.options["catalog"]?.first.map(url))
        let model = try AppModelLoader.load(appDirectory: appURL)
        let catalogURL = args.options["catalog"]?.first.map(url) ?? Bench.defaultCatalog(casesURL: casesURL, appId: model.manifest.appId)
        let decoder = JSONDecoder()
        let plan = try decoder.decode(RunPlan.self, from: Data(contentsOf: url(try args.value("plan"))))
        let raw = try decoder.decode(RawRun.self, from: Data(contentsOf: url(try args.value("raw"))))
        let spotcheck = try args.options["spotcheck"]?.first.map { try SpotcheckLog.load(url($0)) }
        let mixed = RealScorer.ingest(mock: mock, model: model, catalog: try DatasetLoader.loadCatalog(catalogURL), plan: plan, raw: raw,
                                      spotcheck: spotcheck)
        let out = url(try args.value("out"))
        try write(try Bench.encode(mixed), to: out.appendingPathComponent("mixed.json"))
        try write(Data(ReportRenderer.mixedMarkdown(mixed).utf8), to: out.appendingPathComponent("mixed.md"))
        print(String(format: "[MOCK+REAL] %@: Siri Visibility Score v2 %.1f/100 (%@) vs MOCK-only %.1f; %d cases measured",
                     mixed.conditions.appFixture, mixed.score.overall, mixed.score.provenanceLabel, mock.scoreV2?.overall ?? 0,
                     mixed.real.filter { !$0.notMeasured && $0.decidedBy != .mock }.count))

    case "benchmarks":
        let root = url(FileManager.default.currentDirectoryPath)
        let decoder = JSONDecoder()
        let primary = try decoder.decode(BenchmarkConditions.self, from: Data(contentsOf: url(try args.value("conditions"))))
        let runs = try Benchmarks.load(root: root, conditions: primary)
        var followUps: [(BenchmarkConditions, [BenchmarkRun])] = []
        for f in args.options["follow-up"] ?? [] {
            let c = try decoder.decode(BenchmarkConditions.self, from: Data(contentsOf: url(f)))
            followUps.append((c, try Benchmarks.load(root: root, conditions: c)))
        }
        try write(Data(Benchmarks.render(primary: primary, runs: runs, followUps: followUps).utf8), to: url(try args.value("out")))
        if let d = args.options["divergence-out"]?.first {
            try write(Data(Benchmarks.divergenceAppendix(runs, conditions: primary).utf8), to: url(d))
        }
        print("benchmarks: \(runs.count) apps, follow-ups: \(followUps.map { "\($0.0.dataset) (\($0.1.count))" }.joined(separator: ", "))")

    case "help", "--help", "-h":
        print(usage)

    default:
        throw CLIError(description: "unknown command \(argv[1])\n\n\(usage)")
    }
}

do {
    try run()
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
