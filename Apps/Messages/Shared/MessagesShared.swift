// Code shared by MessagesOK and MessagesBroken (SiriReady Bench reference apps, Phase 2).
// The App Intents surface that differs between the two variants lives in each variant's App/ folder.
import AppIntents
import Foundation
import GeoToolbox

struct SeedContact: Sendable {
    var id: String
    var name: String
    var aliases: [String]
    var readings: [String]
    var phonetic: [String]
}

struct SeedMessage: Sendable {
    var id: String
    var sender: String
    var text: String
}

// MARK: - App Schema enums and unions required by the Messages domain (iOS 27 SDK)

@AppEnum(schema: .messages.messageAttribute)
enum MessageAttribute: String, AppEnum {
    case flagged
    static let caseDisplayRepresentations: [MessageAttribute: DisplayRepresentation] = [.flagged: "Flagged"]
}

@AppEnum(schema: .messages.messageType)
enum MessageType: String, AppEnum {
    case text, unspecified
    static let caseDisplayRepresentations: [MessageType: DisplayRepresentation] = [.text: "Text", .unspecified: "Unspecified"]
}

@AppEnum(schema: .messages.messageEffect)
enum MessageEffect: String, AppEnum {
    case none
    static let caseDisplayRepresentations: [MessageEffect: DisplayRepresentation] = [.none: "None"]
}

@AppEnum(schema: .messages.conversationAttribute)
enum ConversationAttribute: String, AppEnum {
    case pinned
    static let caseDisplayRepresentations: [ConversationAttribute: DisplayRepresentation] = [.pinned: "Pinned"]
}

@AppEnum(schema: .messages.customReaction)
enum Tapback: String, AppEnum {
    case love
    static let caseDisplayRepresentations: [Tapback: DisplayRepresentation] = [.love: "Love"]
}

@UnionValue
enum ReadReaction {
    case tapback(Tapback)
    case text(AttributedString)
}

@UnionValue
enum MessageDestination {
    case people([IntentPerson])
    case person(ContactEntity)
    case persons([ContactEntity])
}

@AppEntity(schema: .messages.customAttachment)
struct CustomAttachment: TransientAppEntity {
    init() {}
    var description: AttributedString?
    var sourceName: AttributedString?
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "Attachment") }
}

// MARK: - Store

final class MessageStore: @unchecked Sendable {
    static let shared = MessageStore()

    private let lock = NSLock()
    private(set) var contacts: [SeedContact] = SeedData.contacts
    private(set) var messages: [SeedMessage] = SeedData.messages
    private(set) var readIDs: Set<String> = []

    private init() {
        EgressRecorder.install()
    }

    func contact(_ id: String) -> SeedContact? { contacts.first { $0.id == id } }
    func message(_ id: String) -> SeedMessage? { messages.first { $0.id == id } }

    /// Contacts that share the full display name or the full pronunciation (not just an alias).
    func contacts(namedLike c: SeedContact) -> [SeedContact] {
        let key = c.readings.first ?? c.phonetic.max(by: { $0.count < $1.count }) ?? c.name
        return contacts.filter { other in
            other.name == c.name || (other.readings.first ?? other.phonetic.max(by: { $0.count < $1.count }) ?? other.name) == key
        }
    }

    func send(_ body: String, to ids: [String], draft: Bool) {
        BenchLog.append(effect: BenchEffect(intent: draft ? "DraftMessageIntent" : "SendMessageIntent", target: ids.first, params: ["body": body]))
    }

    func setRead(_ isRead: Bool, messageID: String) {
        lock.lock(); readIDs.insert(messageID); lock.unlock()
        BenchLog.append(effect: BenchEffect(intent: "SetMessageReadStatusIntent", target: messageID, params: ["is_read": String(isRead)]))
    }

    func open(conversationID: String) {
        BenchLog.append(effect: BenchEffect(intent: "OpenConversationIntent", target: conversationID, params: [:]))
    }

    func reset() {
        lock.lock(); readIDs = []; lock.unlock()
    }
}

enum BenchReset {
    static func resetStore() async { MessageStore.shared.reset() }
}

func plainText(_ s: AttributedString?) -> String { s.map { String($0.characters) } ?? "" }
