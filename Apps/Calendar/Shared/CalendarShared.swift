// Code shared by CalendarOK and CalendarBroken (SiriReady Bench reference apps, Phase 2).
// The App Intents surface that differs between the two variants lives in each variant's App/ folder.
import AppIntents
import Foundation
import GeoToolbox

struct SeedCalendar: Sendable {
    var id: String
    var title: String
    var aliases: [String]
}

struct SeedEvent: Sendable {
    var id: String
    var title: String
    var aliases: [String]
    var readings: [String]
    var phonetic: [String]
    var start: String
    var calendar: String
}

// MARK: - App Schema enums, unions and transient entities required by the Calendar domain (iOS 27 SDK)

@AppEnum(schema: .calendar.eventStatus)
enum EventEntityStatus: String, AppEnum {
    case confirmed, cancelled, tentative
    static let caseDisplayRepresentations: [EventEntityStatus: DisplayRepresentation] = [.confirmed: "Confirmed", .cancelled: "Cancelled", .tentative: "Tentative"]
}

@AppEnum(schema: .calendar.attendeeStatus)
enum AttendeeStatus: String, AppEnum {
    case accepted, declined, tentative
    static let caseDisplayRepresentations: [AttendeeStatus: DisplayRepresentation] = [.accepted: "Accepted", .declined: "Declined", .tentative: "Tentative"]
}

@AppEnum(schema: .calendar.attendeeType)
enum AttendeeType: String, AppEnum {
    case person
    static let caseDisplayRepresentations: [AttendeeType: DisplayRepresentation] = [.person: "Person"]
}

@AppEnum(schema: .calendar.eventSpan)
enum EventSpan: String, AppEnum {
    case this, future, all
    static let caseDisplayRepresentations: [EventSpan: DisplayRepresentation] = [.this: "This event", .future: "Future events", .all: "All events"]
}

@UnionValue
enum EventAlarm {
    case relative(Duration)
    case absolute(Date)
}

@UnionValue
enum EventLocation {
    case place(GeoToolbox.PlaceDescriptor)
    case text(String)
}

@AppEntity(schema: .calendar.attendee)
struct AttendeeEntity: TransientAppEntity {
    init() {
        isAttendanceOptional = false
        person = IntentPerson(identifier: .unknown, name: .unknown, handle: nil)
    }
    var isAttendanceOptional: Bool
    var person: IntentPerson
    var status: AttendeeStatus?
    var type: AttendeeType?
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "Attendee") }
}

// MARK: - Store

final class EventStore: @unchecked Sendable {
    static let shared = EventStore()

    let calendars: [SeedCalendar] = SeedData.calendars
    let events: [SeedEvent] = SeedData.events

    private init() {
        EgressRecorder.install()
    }

    func event(_ id: String) -> SeedEvent? { events.first { $0.id == id } }
    func calendar(_ id: String) -> SeedCalendar? { calendars.first { $0.id == id } }

    /// Events that share the full title or its full pronunciation (e.g. 講演 / 公演).
    func events(titledLike e: SeedEvent) -> [SeedEvent] {
        let key = e.readings.first ?? e.phonetic.max(by: { $0.count < $1.count }) ?? e.title
        return events.filter { other in
            other.title == e.title || (other.readings.first ?? other.phonetic.max(by: { $0.count < $1.count }) ?? other.title) == key
        }
    }

    func record(_ intent: String, target: String?, params: [String: String] = [:]) {
        BenchLog.append(effect: BenchEffect(intent: intent, target: target, params: params))
    }
}

enum BenchReset {
    static func resetStore() async {}
}

let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(identifier: "UTC")
    return f
}()
