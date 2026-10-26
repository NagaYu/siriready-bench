// CalendarBroken (reference app "Orbit Calendar", INTENTIONALLY BROKEN), SiriReady Bench Phase 2.
import AppIntents
import SwiftUI

@main
struct OrbitApp: App {
    init() {
        _ = EventStore.shared
        Task { try? await SpotlightIndexer.reindexAll() }
    }

    var body: some Scene {
        WindowGroup { RootView() }
    }
}

struct RootView: View {
    var body: some View {
        let store = EventStore.shared
        let ids = LaunchScreen.ids
        switch LaunchScreen.screen {
        case "event_detail":
            if let e = ids.first.flatMap(store.event) { EventDetailView(event: e) }
        case "day_view":
            DayView(events: ids.compactMap(store.event))
        default:
            DayView(events: Array(store.events.prefix(6)))
        }
    }
}

struct DayView: View {
    let events: [SeedEvent]

    var body: some View {
        List(events, id: \.id) { event in
            Text(event.title)
                .appEntityIdentifier(EntityIdentifier(for: EventEntity.self, identifier: event.id))
        }
    }
}

struct EventDetailView: View {
    let event: SeedEvent

    var body: some View {
        VStack(alignment: .leading) {
            Text(event.title).font(.title)
            Text(event.start)
        }
        // Use the event's id, not its calendar's id.
        .appEntityIdentifier(EntityIdentifier(for: EventEntity.self, identifier: event.id))
    }
}
