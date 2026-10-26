// MessagesOK (reference app "Relay"), SiriReady Bench Phase 2.
import AppIntents
import CoreSpotlight

enum SpotlightIndexer {
    static func reindexAll() async throws {
        let index = CSSearchableIndex.default()
        let store = MessageStore.shared
        try await index.indexAppEntities(store.contacts.map(ContactEntity.init(seed:)))
        try await index.indexAppEntities(store.contacts.map(ConversationEntity.init(contact:)))
        try await index.indexAppEntities(store.messages.compactMap(MessageEntity.init(seed:)))
    }
}
