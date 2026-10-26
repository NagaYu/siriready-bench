// CalendarOK (reference app "Orbit Calendar"), SiriReady Bench Phase 2. Synthetic data only.
import AppIntents
import CoreSpotlight
import Foundation

@AppEntity(schema: .calendar.event)
struct EventEntity: IndexedEntity {
    static let defaultQuery = EventEntityQuery()

    var id: String

    @Property(indexingKey: \.title)
    var title: String

    // Abbreviations and orthographic variants (QBR, 打合せ) for the semantic index.
    @Property(indexingKey: \.alternateNames)
    var aliases: [String]

    // Kana readings for spoken variants (こうえん).
    @Property(indexingKey: \.keywords)
    var readings: [String]

    var alarms: [EventAlarm]
    var attendees: [AttendeeEntity]
    var calendar: CalendarEntity
    var endDate: Date
    var isAllDay: Bool
    var location: EventLocation?
    var note: AttributedString?
    var organizers: [IntentPerson]
    var recurrence: Calendar.RecurrenceRule?
    var startDate: Date
    var status: EventEntityStatus?
    var travelTime: Duration?
    var virtualLocation: URL?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(isoFormatter.string(from: startDate))")
    }

    init(seed: SeedEvent) {
        id = seed.id
        title = seed.title
        aliases = seed.aliases
        readings = seed.readings
        alarms = []
        attendees = []
        calendar = CalendarEntity(seed: EventStore.shared.calendar(seed.calendar) ?? EventStore.shared.calendars[0])
        startDate = isoFormatter.date(from: seed.start) ?? Date(timeIntervalSince1970: 0)
        endDate = startDate.addingTimeInterval(3600)
        isAllDay = false
        location = nil
        note = nil
        organizers = []
        recurrence = nil
        status = .confirmed
        travelTime = nil
        virtualLocation = nil
    }
}

struct EventEntityQuery: EntityStringQuery {
    func entities(for identifiers: [EventEntity.ID]) async throws -> [EventEntity] {
        identifiers.compactMap { EventStore.shared.event($0) }.map(EventEntity.init(seed:))
    }

    func entities(matching string: String) async throws -> [EventEntity] {
        EventStore.shared.events.filter { $0.title.localizedCaseInsensitiveContains(string) }.map(EventEntity.init(seed:))
    }

    func suggestedEntities() async throws -> [EventEntity] {
        Array(EventStore.shared.events.prefix(5)).map(EventEntity.init(seed:))
    }
}

@AppEntity(schema: .calendar.calendar)
struct CalendarEntity: IndexedEntity {
    static let defaultQuery = CalendarEntityQuery()

    var id: String

    @Property(indexingKey: \.title)
    var title: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }

    init(seed: SeedCalendar) {
        id = seed.id
        title = seed.title
    }
}

struct CalendarEntityQuery: EntityQuery {
    func entities(for identifiers: [CalendarEntity.ID]) async throws -> [CalendarEntity] {
        identifiers.compactMap { EventStore.shared.calendar($0) }.map(CalendarEntity.init(seed:))
    }
}
