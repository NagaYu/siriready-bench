// Synthetic fixture for SiriReady Bench ("Relay"). Not compiled in Phase 1.
import AppIntents

@AppIntent(schema: .messages.sendMessage)
struct SendMessageIntent: AppIntent {
    @Parameter(title: "Recipients")
    var recipients: [ContactEntity]

    @Parameter(title: "Message")
    var content: AttributedString?

    @Dependency
    var store: MessageStore

    func perform() async throws -> some IntentResult {
        let targets = try await RecipientResolver.resolve($recipients, store: store)
        try await store.send(content, to: targets)
        return .result()
    }
}

@AppIntent(schema: .messages.draftMessage)
struct DraftMessageIntent: AppIntent {
    @Parameter(title: "Recipients")
    var recipients: [ContactEntity]

    @Parameter(title: "Message")
    var content: AttributedString?

    @Dependency
    var store: MessageStore

    func perform() async throws -> some IntentResult {
        let targets = try await RecipientResolver.resolve($recipients, store: store)
        try await store.saveDraft(content, to: targets)
        return .result()
    }
}

@AppIntent(schema: .messages.setMessageReadStatus)
struct SetMessageReadStatusIntent: AppIntent {
    @Parameter(title: "Messages")
    var target: [MessageEntity]

    @Parameter(title: "Read")
    var isRead: Bool

    @Dependency
    var store: MessageStore

    func perform() async throws -> some IntentResult {
        try await store.setRead(isRead, for: target)
        return .result()
    }
}

struct OpenConversationIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Conversation"

    @Parameter(title: "Conversation")
    var target: ConversationEntity

    func perform() async throws -> some IntentResult {
        let sameTitle = ConversationStore.shared.conversations(titled: target.title)
        let chosen = sameTitle.count > 1
            ? try await $target.requestDisambiguation(among: sameTitle, dialog: "Which conversation?")
            : target
        await Navigator.shared.open(chosen)
        return .result()
    }
}

enum RecipientResolver {
    // When several contacts share a (spoken) name, ask instead of guessing.
    static func resolve(_ recipients: IntentParameter<[ContactEntity]>, store: MessageStore) async throws -> [ContactEntity] {
        var resolved: [ContactEntity] = []
        for contact in recipients.wrappedValue {
            let sameName = store.contacts(namedLike: contact.name)
            if sameName.count > 1 {
                resolved.append(try await recipients.requestDisambiguation(among: sameName, dialog: "Which \(contact.name)?"))
            } else {
                resolved.append(contact)
            }
        }
        return resolved
    }
}
