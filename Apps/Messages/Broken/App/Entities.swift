// MessagesBroken (reference app "Relay", INTENTIONALLY BROKEN), SiriReady Bench Phase 2. Synthetic data only.
import AppIntents
import CoreSpotlight
import Foundation
import GeoToolbox
import LinkPresentation

@AppEntity(schema: .messages.messagePerson)
struct ContactEntity: AppEntity {
    static let defaultQuery = ContactQuery()

    var id: String
    var person: IntentPerson

    @Property
    var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }

    init(seed: SeedContact) {
        id = seed.id
        person = IntentPerson(identifier: .applicationDefined(seed.id), name: .displayName(seed.name), handle: nil)
        name = seed.name
    }
}

// Xcode 27.1 rejects a sendMessage destination entity that is neither indexed nor string-queryable
// (halting AppIntents metadata error), so the buildable broken variant keeps a name-only string
// query. Contacts are still not IndexedEntity and never reach the semantic index.
struct ContactQuery: EntityStringQuery {
    func entities(for identifiers: [ContactEntity.ID]) async throws -> [ContactEntity] {
        identifiers.compactMap { MessageStore.shared.contact($0) }.map(ContactEntity.init(seed:))
    }

    func entities(matching string: String) async throws -> [ContactEntity] {
        MessageStore.shared.contacts.filter { $0.name.localizedCaseInsensitiveContains(string) }.map(ContactEntity.init(seed:))
    }

    func suggestedEntities() async throws -> [ContactEntity] {
        Array(MessageStore.shared.contacts.prefix(5)).map(ContactEntity.init(seed:))
    }
}

@AppEntity(schema: .messages.conversation)
struct ConversationEntity: IndexedEntity {
    static let defaultQuery = ConversationQuery()

    var id: String

    @Property(indexingKey: \.displayName)
    var displayName: String

    @Property(indexingKey: \.alternateNames)
    var aliases: [String]

    var attributes: Set<ConversationAttribute>
    var conversationName: String?
    var dateLastActive: Date?
    var isRead: Bool
    var previewText: AttributedString
    var recipients: [ContactEntity]

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(displayName)") }

    init(contact: SeedContact) {
        id = "conv_" + contact.id
        displayName = contact.name
        aliases = contact.aliases
        attributes = []
        conversationName = nil
        dateLastActive = nil
        isRead = true
        previewText = AttributedString("")
        recipients = [ContactEntity(seed: contact)]
    }
}

struct ConversationQuery: EntityStringQuery {
    func entities(for identifiers: [ConversationEntity.ID]) async throws -> [ConversationEntity] {
        identifiers.compactMap { id in MessageStore.shared.contact(String(id.dropFirst("conv_".count))) }.map(ConversationEntity.init(contact:))
    }

    func entities(matching string: String) async throws -> [ConversationEntity] {
        MessageStore.shared.contacts.filter { $0.name.localizedCaseInsensitiveContains(string) }.map(ConversationEntity.init(contact:))
    }
}

@AppEntity(schema: .messages.message)
struct MessageEntity: IndexedEntity {
    static let defaultQuery = MessageQuery()

    var id: String

    // The text content of the message
    @Property(indexingKey: \.textContent)
    var body: AttributedString?

    var attachments: [IntentFile]
    var attributes: Set<MessageAttribute>
    var audioMessage: IntentFile?
    var author: ContactEntity
    var conversation: ConversationEntity
    var customAttachments: [CustomAttachment]
    var date: Date
    var isRead: Bool
    var links: [LinkPresentation.LinkMetadata]
    var locations: [GeoToolbox.PlaceDescriptor]
    var messageEffect: MessageEffect?
    var messageType: MessageType
    var notificationIdentifier: String?
    var reaction: ReadReaction?
    var referencedMessage: MessageEntity?
    var subject: AttributedString?

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(plainText(body))") }

    init?(seed: SeedMessage) {
        guard let sender = MessageStore.shared.contact(seed.sender) else { return nil }
        id = seed.id
        body = AttributedString(seed.text)
        attachments = []
        attributes = []
        audioMessage = nil
        author = ContactEntity(seed: sender)
        conversation = ConversationEntity(contact: sender)
        customAttachments = []
        date = Date(timeIntervalSince1970: 1_793_000_000)
        isRead = MessageStore.shared.readIDs.contains(seed.id)
        links = []
        locations = []
        messageEffect = nil
        messageType = .text
        notificationIdentifier = nil
        reaction = nil
        referencedMessage = nil
        subject = nil
    }
}

struct MessageQuery: EntityQuery {
    func entities(for identifiers: [MessageEntity.ID]) async throws -> [MessageEntity] {
        identifiers.compactMap { MessageStore.shared.message($0) }.compactMap(MessageEntity.init(seed:))
    }
}
