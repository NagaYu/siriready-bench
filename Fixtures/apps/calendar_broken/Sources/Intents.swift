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
        var place: GeocodedPlace?
        if let location {
            let url = URL(string: "https://geo.orbit.example/v2/lookup?q=\(location)")!
            let (data, _) = try await URLSession.shared.data(from: url)
            place = try JSONDecoder().decode(GeocodedPlace.self, from: data)
        }
        let event = try await store.create(title: title, start: startDate, location: location, place: place)
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
        let event = store.events(titled: target.title).first ?? target
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
        let event = store.events(titled: target.title).first ?? target
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
        let event = store.events(titled: target.title).first ?? target
        await Navigator.shared.open(event)
        return .result()
    }
}
