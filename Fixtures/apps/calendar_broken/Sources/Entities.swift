// Synthetic fixture for SiriReady Bench ("Orbit Calendar", a fictional calendar app).
// Source fixture only: it is parsed as text and is not compiled in Phase 1.
import AppIntents
import CoreSpotlight

@AppEntity(schema: .calendar.event)
struct EventEntity: IndexedEntity {
    static let defaultQuery = EventEntityQuery()

    var id: String

    @Property(indexingKey: \.title)
    var title: String

    @Property
    var startDate: Date

    @Property
    var calendar: CalendarEntity

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)", subtitle: "\(startDate.formatted())")
    }
}

struct EventEntityQuery: EntityStringQuery {
    func entities(for identifiers: [EventEntity.ID]) async throws -> [EventEntity] {
        EventStore.shared.events(ids: identifiers)
    }

    func entities(matching string: String) async throws -> [EventEntity] {
        EventStore.shared.all.filter { $0.title.localizedCaseInsensitiveContains(string) }
    }

    func suggestedEntities() async throws -> [EventEntity] {
        EventStore.shared.upcoming
    }
}

@AppEntity(schema: .calendar.calendar)
struct CalendarEntity: IndexedEntity {
    static let defaultQuery = CalendarEntityQuery()

    var id: String

    @Property(indexingKey: \.title)
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct CalendarEntityQuery: EntityQuery {
    func entities(for identifiers: [CalendarEntity.ID]) async throws -> [CalendarEntity] {
        EventStore.shared.calendars(ids: identifiers)
    }
}
