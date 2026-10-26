// CalendarBroken (reference app "Orbit Calendar", INTENTIONALLY BROKEN), SiriReady Bench Phase 2.
import AppIntents
import CoreSpotlight

enum SpotlightIndexer {
    static func reindexAll() async throws {
        let index = CSSearchableIndex.default()
        try await index.indexAppEntities(EventStore.shared.events.map(EventEntity.init(seed:)))
        try await index.indexAppEntities(EventStore.shared.calendars.map(CalendarEntity.init(seed:)))
    }
}
