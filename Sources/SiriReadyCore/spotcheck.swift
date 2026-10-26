import Foundation

/// Manual Siri spot checks recorded by docs/spotcheck-protocol.md (Track C).
///
/// Spot checks are shown in reports as their own section with provenance `spotcheck`; they never
/// feed the automatic scores.
public struct SpotcheckLog: Codable, Sendable {
    public var protocolVersion: String
    /// True for the illustrative sample shipped in docs/ (fictional results).
    public var sample: Bool
    public var device: String
    public var os: String
    public var locale: String
    public var siriSettings: String
    public var recordedOn: String?
    public var results: [SpotcheckEntry]

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol_version", sample, device, os, locale, siriSettings = "siri_settings"
        case recordedOn = "recorded_on", results
    }

    public static func load(_ url: URL) throws -> SpotcheckLog {
        try JSONDecoder().decode(SpotcheckLog.self, from: Data(contentsOf: url))
    }

    /// Problems that make a log unusable (wrong protocol, unknown modes, duplicate cases).
    public func problems(knownCaseIDs: Set<String>? = nil) -> [String] {
        var out: [String] = []
        if protocolVersion != "spotcheck-v1" { out.append("protocol_version must be spotcheck-v1") }
        var seen = Set<String>()
        for r in results {
            if !["voice", "typed"].contains(r.inputMode) { out.append("\(r.caseId): input_mode must be voice or typed") }
            if !seen.insert(r.caseId).inserted { out.append("\(r.caseId): recorded twice") }
            if let known = knownCaseIDs, !known.contains(r.caseId) { out.append("\(r.caseId): not in the dataset") }
        }
        return out
    }
}

public struct SpotcheckEntry: Codable, Sendable {
    public var caseId: String
    public var inputMode: String
    public var reachedIntent: String?
    public var resolvedEntity: String?
    public var success: Bool
    public var notes: String

    enum CodingKeys: String, CodingKey {
        case caseId = "case_id", inputMode = "input_mode", reachedIntent = "reached_intent"
        case resolvedEntity = "resolved_entity", success, notes
    }
}
