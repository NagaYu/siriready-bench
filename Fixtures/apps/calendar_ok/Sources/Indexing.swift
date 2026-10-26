// Synthetic fixture for SiriReady Bench ("Orbit Calendar"). Not compiled in Phase 1.
import AppIntents
import CoreSpotlight

enum SpotlightIndexer {
    static func reindexAll() async throws {
        let index = CSSearchableIndex.default()
        try await index.indexAppEntities(EventStore.shared.allEventEntities())
        try await index.indexAppEntities(EventStore.shared.allCalendarEntities())
    }
}
