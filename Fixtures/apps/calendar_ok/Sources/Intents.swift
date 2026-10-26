// Synthetic fixture for SiriReady Bench ("Orbit Calendar"). Not compiled in Phase 1.
import AppIntents

@AppIntent(schema: .calendar.createEvent)
struct CreateEventIntent: AppIntent {
    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Start")
    var startDate: Date

    @Parameter(title: "Location")
    var location: String?

    @Dependency
    var store: EventStore

    func perform() async throws -> some ReturnsValue<EventEntity> {
        // Location text is stored as typed; nothing leaves the device.
        let event = try await store.create(title: title, start: startDate, location: location)
        return .result(value: event.entity)
    }
}

@AppIntent(schema: .calendar.updateEvent)
struct UpdateEventIntent: AppIntent {
    @Parameter(title: "Event")
    var target: EventEntity

    @Parameter(title: "New start")
    var startDate: Date

    @Dependency
    var store: EventStore

    func perform() async throws -> some IntentResult {
        let event = try await EventDisambiguator.pick($target, store: store)
        try await store.move(event, to: startDate)
        return .result()
    }
}

@AppIntent(schema: .calendar.deleteEvent)
struct DeleteEventIntent: AppIntent {
    @Parameter(title: "Event")
    var target: EventEntity

    @Dependency
    var store: EventStore

    func perform() async throws -> some IntentResult {
        let event = try await EventDisambiguator.pick($target, store: store)
        try await requestConfirmation(actionName: .delete)
        try await store.delete(event)
        return .result()
    }
}

struct OpenEventIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Event"

    @Parameter(title: "Event")
    var target: EventEntity

    @Dependency
    var store: EventStore

    func perform() async throws -> some IntentResult {
        let event = try await EventDisambiguator.pick($target, store: store)
        await Navigator.shared.open(event)
        return .result()
    }
}

struct ShareEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Share Event"

    @Parameter(title: "Event")
    var target: EventEntity

    @Parameter(title: "Invitee")
    var invitee: String

    @Dependency
    var store: EventStore

    func perform() async throws -> some IntentResult {
        let event = try await EventDisambiguator.pick($target, store: store)
        // Declared cloud_allowed in siriready.yaml: invitations go through the app server.
        var request = URLRequest(url: URL(string: "https://invites.orbit.example/v1/share")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(InvitePayload(eventID: event.id, invitee: invitee))
        _ = try await URLSession.shared.data(for: request)
        return .result()
    }
}

enum EventDisambiguator {
    // Events often share a title ("Team Sync" every week); ask instead of guessing.
    static func pick(_ target: IntentParameter<EventEntity>, store: EventStore) async throws -> EventEntity {
        let sameTitle = store.events(titled: target.wrappedValue.title)
        guard sameTitle.count > 1 else { return target.wrappedValue }
        return try await target.requestDisambiguation(among: sameTitle, dialog: "Which \(target.wrappedValue.title)?")
    }
}
