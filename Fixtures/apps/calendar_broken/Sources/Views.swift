// Synthetic fixture for SiriReady Bench ("Orbit Calendar"). Not compiled in Phase 1.
import SwiftUI
import AppIntents

struct DayView: View {
    let events: [Event]

    var body: some View {
        List(events) { event in
            EventRow(event: event)
                .appEntityIdentifier(EntityIdentifier(for: EventEntity.self, identifier: event.id))
        }
    }
}

struct EventDetailView: View {
    let event: Event

    var body: some View {
        VStack(alignment: .leading) {
            Text(event.title).font(.title)
            Text(event.startDate, style: .time)
        }
        // Use the event's id, not its calendar's id.
        .appEntityIdentifier(EntityIdentifier(for: EventEntity.self, identifier: event.id))
    }
}
