// Synthetic fixture for SiriReady Bench ("Relay"). Not compiled in Phase 1.
import SwiftUI
import AppIntents

struct ContactListView: View {
    let contacts: [Contact]

    var body: some View {
        List(contacts) { contact in
            ContactRow(contact: contact)
                .appEntityIdentifier(EntityIdentifier(for: ContactEntity.self, identifier: contact.id))
        }
    }
}

struct ContactDetailView: View {
    let contact: Contact

    var body: some View {
        VStack(alignment: .leading) {
            Text(contact.name).font(.title)
            Text(contact.phoneticName ?? "")
        }
        .appEntityIdentifier(EntityIdentifier(for: ContactEntity.self, identifier: contact.id))
    }
}

struct ConversationListView: View {
    let conversations: [Conversation]

    var body: some View {
        List(conversations) { conversation in
            ConversationRow(conversation: conversation)
                .appEntityIdentifier(EntityIdentifier(for: ConversationEntity.self, identifier: conversation.id))
        }
    }
}

struct MessageDetailView: View {
    let message: Message

    var body: some View {
        ScrollView {
            Text(message.senderName).font(.headline)
            Text(message.body)
        }
        .appEntityIdentifier(EntityIdentifier(for: MessageEntity.self, identifier: message.id))
    }
}
