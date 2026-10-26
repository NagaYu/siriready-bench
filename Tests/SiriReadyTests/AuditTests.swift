import XCTest
@testable import SiriReadyCore

final class AuditTests: XCTestCase {
    func checks(_ report: AuditReport) -> [CheckID] { report.findings.map(\.check) }

    func testOkFixturesHaveNoFindings() throws {
        for name in ["messages_ok", "calendar_ok"] {
            let report = Auditor.audit(try Repo.model(name))
            XCTAssertEqual(report.findings, [], "\(name) should be clean: \(report.findings.map(\.reason))")
            XCTAssertEqual(report.indexCoverage, 1)
            XCTAssertEqual(report.annotationCoverage, 1)
        }
    }

    func testMessagesBrokenDetectsC1C2C3Only() throws {
        let report = Auditor.audit(try Repo.model("messages_broken"))
        XCTAssertEqual(Set(checks(report)), [.c1, .c2, .c3])

        let c1 = try XCTUnwrap(report.findings.first { $0.check == .c1 })
        XCTAssertEqual(c1.severity, .high)
        XCTAssertTrue(c1.reason.contains("messages.draftMessage"))
        XCTAssertEqual(c1.location?.file, "Sources/Intents.swift")
        XCTAssertEqual(c1.relatedFailure, "F1")

        let c2 = try XCTUnwrap(report.findings.first { $0.check == .c2 })
        XCTAssertEqual(c2.severity, .high, "ContactEntity is promised in indexed_entities")
        XCTAssertTrue(c2.reason.contains("ContactEntity"))
        XCTAssertEqual(report.indexCoverage, 2.0 / 3.0, accuracy: 1e-9)

        let c3 = try XCTUnwrap(report.findings.first { $0.check == .c3 })
        XCTAssertTrue(c3.reason.contains("MessageDetailView"))
        XCTAssertEqual(report.annotationCoverage, 0.75)
    }

    func testCalendarBrokenDetectsC4C5Only() throws {
        let report = Auditor.audit(try Repo.model("calendar_broken"))
        XCTAssertEqual(Set(checks(report)), [.c4, .c5])

        let c5 = report.findings.filter { $0.check == .c5 }
        XCTAssertTrue(c5.contains { $0.severity == .high && $0.reason.contains("ShareEventIntent has no App Intent counterpart") })
        XCTAssertTrue(c5.contains { $0.reason.contains("Intents.intentdefinition") })

        let c4 = try XCTUnwrap(report.findings.first { $0.check == .c4 && $0.severity == .high })
        XCTAssertTrue(c4.reason.contains("CreateEventIntent"))
        XCTAssertTrue(c4.reason.contains("URLSession"))
        XCTAssertEqual(c4.relatedFailure, "F8")
    }

    func testCloudAllowedIntentWithNetworkIsNotFlagged() throws {
        let model = try Repo.model("calendar_ok")
        XCTAssertFalse(try XCTUnwrap(model.intent(named: "ShareEventIntent")).networkEvidence.isEmpty)
        XCTAssertTrue(Auditor.checkPrivacy(model).isEmpty)
    }

    func testFindingsAreOrderedBySeverityThenDiscoverabilityImpact() throws {
        let report = Auditor.audit(try Repo.model("calendar_broken"))
        let severities = report.findings.map(\.severity)
        XCTAssertEqual(severities, severities.sorted())
        XCTAssertEqual(report.findings.first?.check, .c5, "a high SiriKit remnant outranks a high privacy mismatch")
        XCTAssertEqual(report.findings.last?.severity, .low)
    }

    func testModelExtraction() throws {
        let model = try Repo.model("messages_ok")
        let send = try XCTUnwrap(model.intent(named: "SendMessageIntent"))
        XCTAssertEqual(send.schema, "messages.sendMessage")
        XCTAssertTrue(send.hasDisambiguation, "found through the RecipientResolver helper")
        XCTAssertEqual(model.targetEntityType(of: send), "ContactEntity")
        XCTAssertEqual(model.appShortcutIntents, ["OpenConversationIntent"])
        XCTAssertEqual(model.indexedEntityTypes, ["ContactEntity", "ConversationEntity", "MessageEntity"])
        XCTAssertTrue(try XCTUnwrap(model.entity(named: "ContactEntity")).hasStringQuery)

        let broken = try Repo.model("calendar_broken")
        XCTAssertFalse(broken.intents.contains { $0.hasDisambiguation })
        XCTAssertEqual(broken.legacySiriKitIntents, ["ShareEventIntent"])
    }

    func testIndexedEntityWithoutIndexingCallIsReported() throws {
        let dir = try makeFixture(yaml: """
            app_id: notes
            indexed_entities: [NoteEntity]
            privacy:
              OpenNoteIntent: on_device_only
            """, swift: """
            import AppIntents
            struct NoteEntity: IndexedEntity { static let defaultQuery = NoteQuery() }
            struct NoteQuery: EntityStringQuery {}
            struct OpenNoteIntent: OpenIntent { @Parameter(title: "Note") var target: NoteEntity }
            // indexAppEntities( is only mentioned in a comment, which does not count
            """)
        let report = Auditor.audit(try AppModelLoader.load(appDirectory: dir))
        XCTAssertTrue(report.findings.contains { $0.check == .c2 && $0.reason.contains("indexAppEntities") })
        XCTAssertEqual(report.indexCoverage, 0)
    }

    func testWrongAnnotationIdentifierIsReported() throws {
        let dir = try makeFixture(yaml: """
            app_id: calendar
            screens:
              event_detail:
                view: EventDetailView
                entities: [EventEntity]
            privacy:
              OpenEventIntent: on_device_only
            """, swift: """
            import SwiftUI
            struct EventEntity: AppEntity {}
            struct CalendarEntity: AppEntity {}
            struct OpenEventIntent: OpenIntent { @Parameter(title: "Event") var target: EventEntity }
            struct EventDetailView: View {
                var body: some View {
                    Text("{ not a brace }")
                        .appEntityIdentifier(EntityIdentifier(for: CalendarEntity.self, identifier: event.calendarID))
                }
            }
            """)
        let report = Auditor.audit(try AppModelLoader.load(appDirectory: dir))
        let c3 = try XCTUnwrap(report.findings.first { $0.check == .c3 })
        XCTAssertTrue(c3.reason.contains("annotates CalendarEntity instead"))
        XCTAssertEqual(c3.severity, .medium, "the view is not listed in annotated_views")
    }

    func testCompanionTableIsDeclarativeAndSourced() {
        XCTAssertTrue(companionRules.allSatisfy { !$0.basis.isEmpty })
        let documented = companionRules.filter { !$0.heuristic }
        XCTAssertEqual(documented.map(\.trigger), ["messages.sendMessage"])
        XCTAssertEqual(documented.map(\.requires), ["messages.draftMessage"])
    }
}

final class ParsingTests: XCTestCase {
    func testYAMLSubset() throws {
        let v = try YAML.parse("""
            # comment
            app_id: "messages"   # trailing comment
            list:
              - A
              - 'B # not a comment'
            inline: [X, Y]
            same_indent:
            - one
            nested:
              screen:
                view: V
                entities: []
            """)
        XCTAssertEqual(v["app_id"]?.string, "messages")
        XCTAssertEqual(v["list"]?.stringList, ["A", "B # not a comment"])
        XCTAssertEqual(v["inline"]?.stringList, ["X", "Y"])
        XCTAssertEqual(v["same_indent"]?.stringList, ["one"])
        XCTAssertEqual(v["nested"]?["screen"]?["view"]?.string, "V")
        XCTAssertEqual(v["nested"]?["screen"]?["entities"]?.stringList, [])
        XCTAssertThrowsError(try YAML.parse("list:\n  - a: b\n"))
    }

    func testScannerBlanksCommentsAndStringsButKeepsOffsets() {
        let text = """
            let a = "{ // not a comment }" // real comment
            /* block { /* nested */ } */ struct S: View { var body: some View { Text("}") } }
            """
        let file = SourceFile(path: "x.swift", text: text)
        XCTAssertEqual(file.code.utf16.count, text.utf16.count)
        XCTAssertEqual(file.masked.utf16.count, text.utf16.count)
        XCTAssertFalse(file.code.contains("real comment"))
        XCTAssertTrue(file.code.contains("not a comment"), "string contents stay in code")
        XCTAssertFalse(file.masked.contains("not a comment"))
        let decls = SourceScanner.declarations(in: file)
        XCTAssertEqual(decls.map(\.name), ["S"])
        XCTAssertEqual(decls.first?.conformances, ["View"])
        XCTAssertEqual(decls.first?.line, 2)
        XCTAssertTrue(decls.first?.body.contains("Text(\"}\")") ?? false)
    }

    func testConformanceParsing() {
        XCTAssertEqual(SourceScanner.parseConformances(": NSObject, ShareEventIntentHandling "), ["NSObject", "ShareEventIntentHandling"])
        XCTAssertEqual(SourceScanner.parseConformances(": Collection<Int> where Element: Equatable"), ["Collection"])
        XCTAssertEqual(SourceScanner.parseConformances(" "), [])
    }
}
