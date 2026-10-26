// Synthetic fixture for SiriReady Bench ("Relay", a fictional messages app).
// Source fixture only: it is parsed as text and is not compiled in Phase 1.
import AppIntents
import CoreSpotlight

@AppEntity(schema: .messages.messagePerson)
struct ContactEntity: AppEntity {
    static let defaultQuery = ContactQuery()

    var id: String

    @Property
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct ContactQuery: EntityQuery {
    func entities(for identifiers: [ContactEntity.ID]) async throws -> [ContactEntity] {
        ContactStore.shared.contacts(ids: identifiers)
    }

    func suggestedEntities() async throws -> [ContactEntity] {
        ContactStore.shared.recent
    }
}

@AppEntity(schema: .messages.conversation)
struct ConversationEntity: IndexedEntity {
    static let defaultQuery = ConversationQuery()

    var id: String

    @Property(indexingKey: \.title)
    var title: String

    @Property
    var participant: ContactEntity

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }
}

struct ConversationQuery: EntityStringQuery {
    func entities(for identifiers: [ConversationEntity.ID]) async throws -> [ConversationEntity] {
        ConversationStore.shared.conversations(ids: identifiers)
    }

    func entities(matching string: String) async throws -> [ConversationEntity] {
        ConversationStore.shared.all.filter { $0.title.localizedCaseInsensitiveContains(string) }
    }
}

@AppEntity(schema: .messages.message)
struct MessageEntity: IndexedEntity {
    static let defaultQuery = MessageQuery()

    var id: String

    // The text content of the message
    @Property(indexingKey: \.textContent)
    var body: AttributedString?

    @Property
    var sender: ContactEntity

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Message from \(sender.name)")
    }
}

struct MessageQuery: EntityQuery {
    func entities(for identifiers: [MessageEntity.ID]) async throws -> [MessageEntity] {
        MessageStore.shared.messages(ids: identifiers)
    }
}
