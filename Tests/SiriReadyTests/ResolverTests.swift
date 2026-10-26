import XCTest
@testable import SiriReadyCore

final class ResolverTests: XCTestCase {
    // Bench runs are deterministic and pure; compute each fixture once.
    nonisolated(unsafe) static var cache: [String: BenchResult] = [:]

    func result(_ name: String) throws -> BenchResult {
        if let r = Self.cache[name] { return r }
        let r = try Repo.bench(name)
        Self.cache[name] = r
        return r
    }

    func outcomes(_ name: String, where predicate: (BenchCase) -> Bool) throws -> [CaseOutcome] {
        try result(name).outcomes.filter { predicate($0.benchCase) }
    }

    func testOkFixturesScoreHighWithoutFailures() throws {
        for name in ["messages_ok", "calendar_ok"] {
            let r = try result(name)
            XCTAssertEqual(r.conditions.caseCount, name == "messages_ok" ? 624 : 648)
            XCTAssertGreaterThanOrEqual(r.score.overall, 95, name)
            // Only the documented MOCK limits remain (lexicon collision F2, unread ASR / reading variants F3).
            XCTAssertTrue(r.outcomes.compactMap(\.failure).allSatisfy { [.f2, .f3].contains($0) }, "\(name) unexpected failures")
        }
    }

    func testBrokenFixturesScoreClearlyLower() throws {
        XCTAssertLessThan(try result("messages_broken").score.overall, try result("messages_ok").score.overall - 20)
        XCTAssertLessThan(try result("calendar_broken").score.overall, try result("calendar_ok").score.overall - 10)
    }

    // messages_broken (a): no draftMessage companion → every draft request is F1.
    func testMissingDraftCompanionSurfacesAsF1() throws {
        let drafts = try outcomes("messages_broken") { $0.expected.intent == "DraftMessageIntent" }
        XCTAssertFalse(drafts.isEmpty)
        XCTAssertTrue(drafts.allSatisfy { $0.failure == .f1 })
        XCTAssertTrue(drafts.allSatisfy { $0.result.notes == [.noIntentForConcept] })
        XCTAssertTrue(try outcomes("messages_ok") { $0.expected.intent == "DraftMessageIntent" }.allSatisfy { $0.failure != .f1 })
    }

    // messages_broken (b): contacts not indexed → named recipients are F4.
    func testUnindexedContactsSurfaceAsF4() throws {
        let named = try outcomes("messages_broken") { $0.expected.intent == "SendMessageIntent" && $0.referenceKind == .name }
        XCTAssertGreaterThan(named.count, 20)
        // Two requests to "Mark Ellison" are caught by the MOCK's "mark (as read)" keyword first (F2, documented).
        XCTAssertEqual(named.filter { $0.failure == .f2 }.count, 2)
        XCTAssertTrue(named.filter { $0.failure != .f2 }.allSatisfy { $0.failure == .f4 }, "\(named.filter { $0.failure != .f4 }.map(\.benchCase.caseId))")
        // Context carry-over does not need the index: multi-turn sends still work.
        let carried = try outcomes("messages_broken") { $0.expected.intent == "SendMessageIntent" && $0.referenceKind == .priorTurn }
        XCTAssertTrue(carried.allSatisfy { $0.failure == nil })
    }

    // messages_broken (c): MessageDetailView not annotated → "mark this as read" / "reply to this" are F6.
    func testMissingAnnotationSurfacesAsF6() throws {
        let detail = try outcomes("messages_broken") { $0.state.screen == "message_detail" }
        XCTAssertEqual(detail.count, 30)
        XCTAssertTrue(detail.allSatisfy { $0.failure == .f6 })
        let otherScreens = try outcomes("messages_broken") {
            $0.state.screen == "contact_list" && $0.expected.intent == "SendMessageIntent"
        }
        XCTAssertTrue(otherScreens.allSatisfy { $0.failure == nil }, "annotated screens keep working")
    }

    // calendar_broken (a): no disambiguation → ambiguous same-title / homophone requests are F5.
    func testMissingDisambiguationSurfacesAsF5() throws {
        let ambiguous = try outcomes("calendar_broken") {
            $0.expected.resolution == "disambiguate" && $0.expected.intent != "ShareEventIntent"
        }
        XCTAssertEqual(ambiguous.count, 60)
        XCTAssertTrue(ambiguous.allSatisfy { $0.failure == .f5 })
        XCTAssertTrue(ambiguous.allSatisfy { $0.result.notes.contains(.pickedFirstWithoutDisambiguation) })
        // A qualifier ("Thursday's Team Sync") still resolves without asking.
        let qualified = try outcomes("calendar_broken") { $0.tags.contains("same_name_qualified") && $0.expected.intent != "ShareEventIntent" }
        XCTAssertTrue(qualified.allSatisfy { $0.failure == nil })
    }

    // calendar_broken (b): ShareEvent only exists in SiriKit → share requests are F1.
    func testSiriKitOnlyIntentSurfacesAsF1() throws {
        let shares = try outcomes("calendar_broken") { $0.expected.intent == "ShareEventIntent" }
        XCTAssertFalse(shares.isEmpty)
        XCTAssertTrue(shares.allSatisfy { $0.failure == .f1 })
        // In the correct app only misspelled titles are missed (F3, a documented MOCK limit).
        XCTAssertTrue(try outcomes("calendar_ok") { $0.expected.intent == "ShareEventIntent" }.allSatisfy { $0.failure == nil || $0.failure == .f3 })
    }

    // calendar_broken (c): on_device_only CreateEventIntent calls a remote geocoder → F8.
    func testPrivacyMismatchSurfacesAsF8() throws {
        let creates = try outcomes("calendar_broken") { $0.expected.intent == "CreateEventIntent" }
        XCTAssertEqual(creates.count, 108)
        XCTAssertTrue(creates.allSatisfy { $0.failure == .f8 && $0.result.routing == "cloud" })
        XCTAssertTrue(try outcomes("calendar_ok") { $0.expected.intent == "CreateEventIntent" }.allSatisfy { $0.result.routing == "on_device" })
    }

    func testBenchIsDeterministic() throws {
        let a = try Bench.encode(try Repo.bench("calendar_broken"))
        let b = try Bench.encode(try Repo.bench("calendar_broken"))
        XCTAssertEqual(a, b)
    }

    func testConceptLexicon() throws {
        let messages = MockResolver(model: try Repo.model("messages_ok"),
                                    catalog: try DatasetLoader.loadCatalog(Repo.root.appendingPathComponent("dataset/v1.2/entities/messages.json")))
        XCTAssertEqual(messages.concept(for: "Start a message to Alex saying the slides are ready but don't send it"), "messages.draftMessage")
        XCTAssertEqual(messages.concept(for: "Text Alex saying the slides are ready"), "messages.sendMessage", "'ready' must not trigger 'read'")
        XCTAssertEqual(messages.concept(for: "高瀬美月宛てに「明日送る」の下書きを作って"), "messages.draftMessage")
        XCTAssertNil(messages.concept(for: "What's the weather"))
        XCTAssertEqual(MockResolver.derivedConcept("OpenEventIntent"), "open.event")
        XCTAssertEqual(MockResolver.derivedConcept("ShareEventIntent"), "share.event")
    }

    func testEntityMatcherHandlesNoiseAndSoundAlikes() throws {
        let catalog = try DatasetLoader.loadCatalog(Repo.root.appendingPathComponent("dataset/v1.2/entities/messages.json"))
        let contacts = catalog.entities.filter { $0.type == "ContactEntity" }
        func ids(_ text: String, semantic: Bool = true) -> [String] { EntityMatcher.search(text, in: contacts, semantic: semantic).map(\.id) }
        XCTAssertEqual(ids("Send Alex Rviera a note"), ["c_alex"], "typo")
        XCTAssertEqual(ids("Send Sean Patel a note"), ["c_shawn"], "ASR homophone")
        XCTAssertEqual(ids("Send John Parke a note"), ["c_jon_park", "c_john_parke"], "sound-alike names are ambiguous by voice")
        XCTAssertEqual(ids("Send John Parke from finance a note"), ["c_john_parke"], "qualifier")
        XCTAssertEqual(ids("鷹瀬美月に送って"), ["j_takase"], "full reading beats a partial exact alias")
        XCTAssertEqual(ids("みづきに送って"), ["j_takase", "j_mori"], "同音異義")
        XCTAssertEqual(ids("斎藤健に送って"), ["j_saito"], "表記ゆれ alias")
        XCTAssertEqual(ids("Send Alex Rviera a note", semantic: false), [], "string query fallback is exact only")
        XCTAssertEqual(ids("Send Alex Rivera a note", semantic: false), ["c_alex"])
    }

    func testTextPrimitives() {
        XCTAssertEqual(TextMatching.soundex("Robert"), "R163")
        XCTAssertEqual(TextMatching.soundex("Rupert"), "R163")
        XCTAssertEqual(TextMatching.soundex("Ashcraft"), "A261")
        XCTAssertEqual(TextMatching.soundex("Pfister"), "P236")
        XCTAssertEqual(TextMatching.soundex("Tymczak"), "T522")
        XCTAssertEqual(TextMatching.osaDistance("rivera", "rviera"), 1)
        XCTAssertEqual(TextMatching.osaDistance("kitten", "sitting"), 3)
        XCTAssertEqual(TextMatching.asciiTokens("Jon's Stand-up, don't"), ["jon", "standup", "dont"])
        XCTAssertEqual(TextMatching.japaneseNormalized("ヒロト ＭＴＧ"), "ひろとmtg")
        XCTAssertEqual(TextMatching.reading("在庫店卸"), "ざいこたなおろし")
        XCTAssertEqual(TextMatching.referenceSegment("Text Alex saying see you: soon"), "Text Alex")
        XCTAssertEqual(TextMatching.referenceSegment("光に「これ送って」って送って"), "光に って送って")
    }
}
