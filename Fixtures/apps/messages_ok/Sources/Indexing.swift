// Synthetic fixture for SiriReady Bench ("Relay"). Not compiled in Phase 1.
import AppIntents
import CoreSpotlight

enum SpotlightIndexer {
    static func reindexAll() async throws {
        let index = CSSearchableIndex.default()
        try await index.indexAppEntities(ContactStore.shared.allEntities())
        try await index.indexAppEntities(ConversationStore.shared.allEntities())
        try await index.indexAppEntities(MessageStore.shared.allEntities())
    }
}
