// CalendarOK (reference app "Orbit Calendar"), SiriReady Bench Phase 2.
import AppIntents
import Foundation

@AppIntent(schema: .calendar.createEvent)
struct CreateEventIntent: AppIntent {
    var title: String
    var startDate: Date
    var endDate: Date?
    var isAllDay: Bool
    var location: EventLocation?
    var note: String?
    var recurrence: Calendar.RecurrenceRule?
    var attendees: [AttendeeEntity]
    var calendar: CalendarEntity

    func perform() async throws -> some IntentResult & ReturnsValue<EventEntity> {
        // Location text is stored as typed; nothing leaves the device.
        var recorded = ["title": title, "start": isoFormatter.string(from: startDate), "calendar": calendar.id]
        if case .text(let text)? = location { recorded["location"] = text }
        EventStore.shared.record("CreateEventIntent", target: nil, params: recorded)
        let seed = SeedEvent(id: "new", title: title, aliases: [], readings: [], phonetic: [], start: isoFormatter.string(from: startDate), calendar: calendar.id)
        return .result(value: EventEntity(seed: seed))
    }
}

@AppIntent(schema: .calendar.updateEvent)
struct UpdateEventIntent: AppIntent {
    var event: EventEntity
    var span: EventSpan?
    var title: String?
    var startDate: Date?
    var endDate: Date?
    var isAllDay: Bool?
    var location: EventLocation?
    var note: String?
    var recurrence: Calendar.RecurrenceRule?
    var attendees: [AttendeeEntity]?
    var calendar: CalendarEntity?

    func perform() async throws -> some IntentResult & ReturnsValue<EventEntity> {
        let target = try await EventDisambiguator.pick(event) { try await $event.requestDisambiguation(among: $0, dialog: "Which event?") }
        EventStore.shared.record("UpdateEventIntent", target: target.id, params: ["start": startDate.map(isoFormatter.string(from:)) ?? ""])
        return .result(value: target)
    }
}

@AppIntent(schema: .calendar.deleteEvent)
struct DeleteEventIntent: AppIntent {
    var entity: EventEntity
    var span: EventSpan?

    func perform() async throws -> some IntentResult {
        let target = try await EventDisambiguator.pick(entity) { try await $entity.requestDisambiguation(among: $0, dialog: "Which event?") }
        EventStore.shared.record("DeleteEventIntent", target: target.id)
        return .result()
    }
}

struct OpenEventIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Event"

    @Parameter(title: "Event")
    var target: EventEntity

    func perform() async throws -> some IntentResult {
        let event = try await EventDisambiguator.pick(target) { try await $target.requestDisambiguation(among: $0, dialog: "Which event?") }
        EventStore.shared.record("OpenEventIntent", target: event.id)
        return .result()
    }
}

struct ShareEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Share Event"

    @Parameter(title: "Event")
    var target: EventEntity

    @Parameter(title: "Invitee")
    var invitee: String

    func perform() async throws -> some IntentResult {
        let event = try await EventDisambiguator.pick(target) { try await $target.requestDisambiguation(among: $0, dialog: "Which event?") }
        // Declared cloud_allowed in siriready.yaml: invitations go through the app server.
        var request = URLRequest(url: URL(string: "https://invites.orbit.example/v1/share")!)
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(["event": event.id, "invitee": invitee])
        _ = try await URLSession.shared.data(for: request)
        EventStore.shared.record("ShareEventIntent", target: event.id, params: ["invitee": invitee])
        return .result()
    }
}

enum EventDisambiguator {
    // Events often share a title ("Team Sync" every week); ask instead of guessing.
    static func pick(_ event: EventEntity, ask: ([EventEntity]) async throws -> EventEntity) async throws -> EventEntity {
        guard let seed = EventStore.shared.event(event.id) else { return event }
        let sameTitle = EventStore.shared.events(titledLike: seed)
        guard sameTitle.count > 1 else { return event }
        return try await ask(sameTitle.map(EventEntity.init(seed:)))
    }
}
