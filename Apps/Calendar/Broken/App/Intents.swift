// CalendarBroken (reference app "Orbit Calendar", INTENTIONALLY BROKEN), SiriReady Bench Phase 2.
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
        if let location, case .text(let text) = location {
            let url = URL(string: "https://geo.orbit.example/v2/lookup?q=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!
            _ = try await URLSession.shared.data(from: url)
        }
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
        let target = EventStore.shared.event(event.id).flatMap { EventStore.shared.events(titledLike: $0).first }.map(EventEntity.init(seed:)) ?? event
        EventStore.shared.record("UpdateEventIntent", target: target.id, params: ["start": startDate.map(isoFormatter.string(from:)) ?? ""])
        return .result(value: target)
    }
}

@AppIntent(schema: .calendar.deleteEvent)
struct DeleteEventIntent: AppIntent {
    var entity: EventEntity
    var span: EventSpan?

    func perform() async throws -> some IntentResult {
        let target = EventStore.shared.event(entity.id).flatMap { EventStore.shared.events(titledLike: $0).first }.map(EventEntity.init(seed:)) ?? entity
        EventStore.shared.record("DeleteEventIntent", target: target.id)
        return .result()
    }
}

struct OpenEventIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Event"

    @Parameter(title: "Event")
    var target: EventEntity

    func perform() async throws -> some IntentResult {
        let event = EventStore.shared.event(target.id).flatMap { EventStore.shared.events(titledLike: $0).first }.map(EventEntity.init(seed:)) ?? target
        EventStore.shared.record("OpenEventIntent", target: event.id)
        return .result()
    }
}
