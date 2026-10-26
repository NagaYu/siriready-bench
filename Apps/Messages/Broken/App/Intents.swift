// MessagesBroken (reference app "Relay", INTENTIONALLY BROKEN), SiriReady Bench Phase 2.
import AppIntents
import Foundation
import GeoToolbox

@AppIntent(schema: .messages.sendMessage)
struct SendMessageIntent: AppIntent {
    var attachments: [IntentFile]
    var audioMessage: IntentFile?
    var content: AttributedString?
    var destination: MessageDestination
    var links: [URL]
    var locations: [GeoToolbox.PlaceDescriptor]
    var scheduledDate: Date?
    var subject: AttributedString?

    func perform() async throws -> some ReturnsValue<[MessageEntity]> {
        let targets = try await RecipientResolver.resolve(destination) { try await $destination.requestDisambiguation(among: $0, dialog: "Which contact?") }
        MessageStore.shared.send(plainText(content), to: targets.map(\.id), draft: false)
        return .result(value: [])
    }
}

@AppIntent(schema: .messages.setMessageReadStatus)
struct SetMessageReadStatusIntent: AppIntent {
    var isRead: Bool
    var message: MessageEntity

    func perform() async throws -> some IntentResult {
        MessageStore.shared.setRead(isRead, messageID: message.id)
        return .result()
    }
}

struct OpenConversationIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Conversation"

    @Parameter(title: "Conversation")
    var target: ConversationEntity

    func perform() async throws -> some IntentResult {
        var chosen = target
        if let contact = MessageStore.shared.contact(String(target.id.dropFirst("conv_".count))) {
            let sameName = MessageStore.shared.contacts(namedLike: contact)
            if sameName.count > 1 {
                chosen = try await $target.requestDisambiguation(among: sameName.map(ConversationEntity.init(contact:)), dialog: "Which conversation?")
            }
        }
        MessageStore.shared.open(conversationID: chosen.id)
        return .result()
    }
}

enum RecipientResolver {
    // When several contacts share a (spoken) name, ask instead of guessing.
    static func resolve(_ value: MessageDestination, ask: ([MessageDestination]) async throws -> MessageDestination?) async throws -> [SeedContact] {
        let contacts: [ContactEntity]
        switch value {
        case .person(let c): contacts = [c]
        case .persons(let cs): contacts = cs
        case .people: contacts = []
        }
        var resolved: [SeedContact] = []
        for entity in contacts {
            guard let seed = MessageStore.shared.contact(entity.id) else { continue }
            let sameName = MessageStore.shared.contacts(namedLike: seed)
            if sameName.count > 1 {
                let choice = try await ask(sameName.map { MessageDestination.person(ContactEntity(seed: $0)) })
                if case .person(let picked)? = choice, let s = MessageStore.shared.contact(picked.id) { resolved.append(s) }
            } else {
                resolved.append(seed)
            }
        }
        return resolved
    }
}
