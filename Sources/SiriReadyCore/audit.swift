import Foundation

// MARK: - siriready.yaml

public enum PrivacyRouting: String, Codable, Sendable {
    case onDeviceOnly = "on_device_only"
    case cloudAllowed = "cloud_allowed"
}

public struct ScreenDeclaration: Codable, Equatable, Sendable {
    public var view: String
    public var entities: [String]
}

/// Typed form of `siriready.yaml`: declarations the source alone cannot express.
public struct AppManifest: Sendable {
    public var appId: String
    public var domain: String
    public var displayName: String
    public var indexedEntities: [String]
    public var annotatedViews: [String]
    /// Intent name → intended routing, in file order.
    public var privacy: [(intent: String, routing: PrivacyRouting)]
    /// Screen name → view and displayed entity types, in file order.
    public var screens: [(name: String, declaration: ScreenDeclaration)]

    public func routing(for intent: String) -> PrivacyRouting? {
        privacy.first { $0.intent == intent }?.routing
    }

    public func screen(named name: String) -> ScreenDeclaration? {
        screens.first { $0.name == name }?.declaration
    }

    public static func load(_ url: URL) throws -> AppManifest {
        let root = try YAML.parse(String(contentsOf: url, encoding: .utf8))
        guard let appId = root["app_id"]?.string, !appId.isEmpty else {
            throw AuditError.invalidManifest("app_id is required")
        }
        var privacy: [(String, PrivacyRouting)] = []
        for entry in root["privacy"]?.entries ?? [] {
            guard let raw = entry.value.string, let routing = PrivacyRouting(rawValue: raw) else {
                throw AuditError.invalidManifest("privacy.\(entry.key) must be on_device_only or cloud_allowed")
            }
            privacy.append((entry.key, routing))
        }
        var screens: [(String, ScreenDeclaration)] = []
        for entry in root["screens"]?.entries ?? [] {
            guard let view = entry.value["view"]?.string else {
                throw AuditError.invalidManifest("screens.\(entry.key).view is required")
            }
            screens.append((entry.key, ScreenDeclaration(view: view, entities: entry.value["entities"]?.stringList ?? [])))
        }
        return AppManifest(
            appId: appId,
            domain: root["domain"]?.string ?? appId,
            displayName: root["display_name"]?.string ?? appId,
            indexedEntities: root["indexed_entities"]?.stringList ?? [],
            annotatedViews: root["annotated_views"]?.stringList ?? [],
            privacy: privacy,
            screens: screens
        )
    }
}

public enum AuditError: Error, CustomStringConvertible {
    case invalidManifest(String)
    case missingManifest(String)

    public var description: String {
        switch self {
        case .invalidManifest(let m): return "invalid siriready.yaml: \(m)"
        case .missingManifest(let p): return "siriready.yaml not found in \(p)"
        }
    }
}

// MARK: - Extracted app model

public struct SourceLocation: Codable, Equatable, Sendable {
    public var file: String
    public var line: Int
}

public struct ParameterInfo: Codable, Equatable, Sendable {
    public var name: String
    public var type: String
}

public struct IntentInfo: Codable, Equatable, Sendable {
    public var name: String
    /// App Schema identifier without the leading dot, e.g. `messages.sendMessage`.
    public var schema: String?
    public var location: SourceLocation
    public var parameters: [ParameterInfo]
    /// `requestDisambiguation(` in the intent body or in a helper type the body references.
    public var hasDisambiguation: Bool
    /// Source evidence of off-device transmission (URLSession, URLRequest, remote URLs, ...).
    public var networkEvidence: [String]
}

public struct EntityInfo: Codable, Equatable, Sendable {
    public var name: String
    public var schema: String?
    public var location: SourceLocation
    public var conformsToIndexedEntity: Bool
    public var queryType: String?
    public var hasStringQuery: Bool
}

public struct ViewInfo: Codable, Equatable, Sendable {
    public var name: String
    public var location: SourceLocation
    /// Entity types referenced by `EntityIdentifier(for: X.self, ...)` inside the view.
    public var annotatedEntityTypes: [String]
    public var usesAnnotationModifier: Bool
}

public struct SiriKitRemnant: Codable, Equatable, Sendable {
    public var location: SourceLocation
    public var kind: String
    public var snippet: String
}

/// Everything the audit and the MOCK resolver know about an app, from text analysis only.
public struct AppModel: Sendable {
    public var root: URL
    public var manifest: AppManifest
    public var sourceFiles: [String]
    public var intents: [IntentInfo]
    public var entities: [EntityInfo]
    public var views: [ViewInfo]
    /// Intents registered through `AppShortcut(intent: X(), ...)`.
    public var appShortcutIntents: [String]
    /// Whether `indexAppEntities(` is called anywhere.
    public var callsIndexAppEntities: Bool
    public var siriKitRemnants: [SiriKitRemnant]
    /// SiriKit intents still handled through `XIntentHandling` (e.g. `ShareEventIntent`).
    public var legacySiriKitIntents: [String]

    public func intent(named name: String) -> IntentInfo? { intents.first { $0.name == name } }
    public func entity(named name: String) -> EntityInfo? { entities.first { $0.name == name } }
    public func view(named name: String) -> ViewInfo? { views.first { $0.name == name } }

    /// Entity types whose instances reach the semantic index (IndexedEntity + an indexing call).
    public var indexedEntityTypes: Set<String> {
        guard callsIndexAppEntities else { return [] }
        return Set(entities.filter(\.conformsToIndexedEntity).map(\.name))
    }

    /// The parameter an intent acts on: the first parameter typed as one of the app's entities.
    public func targetEntityType(of intent: IntentInfo) -> String? {
        intent.parameters.first { entity(named: $0.type) != nil }?.type
    }
}

public enum AppModelLoader {
    static let intentProtocols: Set<String> = [
        "AppIntent", "OpenIntent", "DeleteIntent", "AudioPlaybackIntent", "AudioRecordingIntent",
        "ForegroundContinuableIntent", "LiveActivityIntent", "SetValueIntent", "URLRepresentableIntent",
        "ShowInAppSearchResultsIntent", "SnippetIntent",
    ]
    static let entityProtocols: Set<String> = ["AppEntity", "IndexedEntity", "TransientAppEntity", "FileEntity", "URLRepresentableEntity"]

    /// Text patterns that indicate data may leave the device. Heuristic; see README.
    static let networkPatterns: [(label: String, pattern: String)] = [
        ("URLSession", #"\bURLSession\b"#),
        ("URLRequest", #"\bURLRequest\b"#),
        ("NWConnection", #"\bNWConnection\b"#),
        ("remote URL literal", #"https?://"#),
    ]

    public static func load(appDirectory: URL) throws -> AppModel {
        let manifestURL = appDirectory.appendingPathComponent("siriready.yaml")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw AuditError.missingManifest(appDirectory.path)
        }
        let manifest = try AppManifest.load(manifestURL)

        var files: [SourceFile] = []
        var intentDefinitions: [String] = []
        let enumerator = FileManager.default.enumerator(at: appDirectory, includingPropertiesForKeys: nil)
        var urls: [URL] = []
        while let url = enumerator?.nextObject() as? URL { urls.append(url) }
        for url in urls.sorted(by: { $0.path < $1.path }) {
            let relative = String(url.standardizedFileURL.path.dropFirst(appDirectory.standardizedFileURL.path.count + 1))
            if url.pathExtension == "swift" {
                files.append(SourceFile(path: relative, text: try String(contentsOf: url, encoding: .utf8)))
            } else if url.pathExtension == "intentdefinition" {
                intentDefinitions.append(relative)
            }
        }

        let declarations = files.flatMap(SourceScanner.declarations(in:))
        var conformances: [String: Set<String>] = [:]
        for d in declarations { conformances[d.name, default: []].formUnion(d.conformances) }
        let typeBodies = Dictionary(declarations.filter { $0.kind != "extension" }.map { ($0.name, $0.body) }, uniquingKeysWith: { a, _ in a })

        func schema(in attributes: String, macro: String) -> String? {
            SourceScanner.matches(#"@"# + macro + #"\(\s*schema:\s*\.(\w+)\.(\w+)\s*\)"#, in: attributes).first.map { "\($0.groups[1]!).\($0.groups[2]!)" }
        }

        var intents: [IntentInfo] = []
        var entities: [EntityInfo] = []
        var views: [ViewInfo] = []
        for d in declarations where d.kind != "extension" && d.kind != "protocol" {
            let all = conformances[d.name] ?? []
            let location = SourceLocation(file: d.file, line: d.line)
            if !all.isDisjoint(with: intentProtocols) || d.attributes.contains("@AppIntent(") {
                let parameters = SourceScanner.matches(
                    #"@Parameter(?:\([^)]*\))?\s+var\s+(\w+)\s*:\s*\[?\s*(\w+)"#, in: d.maskedBody
                ).map { ParameterInfo(name: $0.groups[1]!, type: $0.groups[2]!) }
                var disambiguates = d.body.contains("requestDisambiguation(")
                if !disambiguates {
                    // One hop: helper types referenced from the intent body.
                    for (name, body) in typeBodies where name != d.name && body.contains("requestDisambiguation(") {
                        if !SourceScanner.matches(#"\b"# + NSRegularExpression.escapedPattern(for: name) + #"\b"#, in: d.maskedBody).isEmpty {
                            disambiguates = true
                        }
                    }
                }
                let evidence = networkPatterns.filter { !SourceScanner.matches($0.pattern, in: d.body).isEmpty }.map(\.label)
                intents.append(IntentInfo(
                    name: d.name, schema: schema(in: d.attributes, macro: "AppIntent"), location: location,
                    parameters: parameters, hasDisambiguation: disambiguates, networkEvidence: evidence))
            } else if !all.isDisjoint(with: entityProtocols) || d.attributes.contains("@AppEntity(") {
                let queryType = SourceScanner.matches(#"static\s+(?:let|var)\s+defaultQuery\s*=\s*(\w+)\s*\("#, in: d.maskedBody).first?.groups[1] ?? nil
                let queryConformances = queryType.flatMap { conformances[$0] } ?? []
                entities.append(EntityInfo(
                    name: d.name, schema: schema(in: d.attributes, macro: "AppEntity"), location: location,
                    conformsToIndexedEntity: all.contains("IndexedEntity"),
                    queryType: queryType,
                    hasStringQuery: queryConformances.contains("EntityStringQuery")))
            } else if all.contains("View") {
                let annotated = SourceScanner.matches(#"EntityIdentifier\(\s*for:\s*(\w+)\.self"#, in: d.maskedBody).compactMap { $0.groups[1] }
                let usesModifier = d.maskedBody.contains(".appEntityIdentifier(") || d.maskedBody.contains(".appEntityUIElements(")
                views.append(ViewInfo(
                    name: d.name, location: location,
                    annotatedEntityTypes: usesModifier ? Array(Set(annotated)).sorted() : [],
                    usesAnnotationModifier: usesModifier))
            }
        }

        var shortcutIntents: [String] = []
        var callsIndex = false
        var remnants: [SiriKitRemnant] = []
        var legacyIntents: [String] = []
        let siriKitPatterns: [(kind: String, pattern: String)] = [
            ("import Intents", #"(?m)^\s*import\s+Intents\s*$"#),
            ("INExtension", #"\bINExtension\b"#),
            ("INIntent", #"\bINIntent\b"#),
            ("SiriKit intent handling protocol", #"\b(\w+Intent)Handling\b"#),
            ("INInteraction", #"\bINInteraction\b"#),
            ("INVoiceShortcut", #"\bINVoiceShortcut\w*\b"#),
        ]
        for f in files {
            shortcutIntents += SourceScanner.matches(#"AppShortcut\(\s*intent:\s*(\w+)\s*\("#, in: f.masked).compactMap { $0.groups[1] }
            if f.masked.contains("indexAppEntities(") { callsIndex = true }
            for p in siriKitPatterns {
                for m in SourceScanner.matches(p.pattern, in: f.masked) {
                    let line = f.line(at: m.range.location)
                    let snippet = f.text.components(separatedBy: "\n")[line - 1].trimmingCharacters(in: .whitespaces)
                    remnants.append(SiriKitRemnant(location: SourceLocation(file: f.path, line: line), kind: p.kind, snippet: snippet))
                    if p.kind == "SiriKit intent handling protocol", let name = m.groups[1], !legacyIntents.contains(name) {
                        legacyIntents.append(name)
                    }
                }
            }
        }
        for path in intentDefinitions {
            remnants.append(SiriKitRemnant(location: SourceLocation(file: path, line: 1), kind: "SiriKit intent definition file", snippet: (path as NSString).lastPathComponent))
        }

        return AppModel(
            root: appDirectory, manifest: manifest, sourceFiles: files.map(\.path),
            intents: intents, entities: entities, views: views,
            appShortcutIntents: shortcutIntents, callsIndexAppEntities: callsIndex,
            siriKitRemnants: remnants, legacySiriKitIntents: legacyIntents)
    }
}
