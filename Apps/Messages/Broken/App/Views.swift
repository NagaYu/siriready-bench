// MessagesBroken (reference app "Relay", INTENTIONALLY BROKEN), SiriReady Bench Phase 2.
import AppIntents
import SwiftUI

@main
struct RelayApp: App {
    init() {
        _ = MessageStore.shared
        Task { try? await SpotlightIndexer.reindexAll() }
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    var body: some View {
        let store = MessageStore.shared
        let ids = LaunchScreen.ids
        switch LaunchScreen.screen {
        case "contact_detail":
            if let c = ids.first.flatMap(store.contact) { ContactDetailView(contact: c) }
        case "conversation_list":
            ConversationListView(contacts: ids.compactMap { store.contact(String($0.dropFirst("conv_".count))) })
        case "message_detail":
            if let m = ids.first.flatMap(store.message) { MessageDetailView(message: m) }
        case "contact_list":
            ContactListView(contacts: ids.compactMap(store.contact))
        default:
            ContactListView(contacts: Array(store.contacts.prefix(8)))
        }
    }
}

struct ContactListView: View {
    let contacts: [SeedContact]

    var body: some View {
        List(contacts, id: \.id) { contact in
            Text(contact.name)
                .appEntityIdentifier(EntityIdentifier(for: ContactEntity.self, identifier: contact.id))
        }
    }
}

struct ContactDetailView: View {
    let contact: SeedContact

    var body: some View {
        VStack(alignment: .leading) {
            Text(contact.name).font(.title)
            Text(contact.aliases.joined(separator: ", "))
        }
        .appEntityIdentifier(EntityIdentifier(for: ContactEntity.self, identifier: contact.id))
    }
}

struct ConversationListView: View {
    let contacts: [SeedContact]

    var body: some View {
        List(contacts, id: \.id) { contact in
            Text(contact.name)
                .appEntityIdentifier(EntityIdentifier(for: ConversationEntity.self, identifier: "conv_" + contact.id))
        }
    }
}

struct MessageDetailView: View {
    let message: SeedMessage

    var body: some View {
        ScrollView {
            Text(MessageStore.shared.contact(message.sender)?.name ?? "").font(.headline)
            Text(message.text)
        }
    }
}
