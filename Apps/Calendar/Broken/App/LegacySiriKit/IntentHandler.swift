// CalendarBroken (reference app "Orbit Calendar", INTENTIONALLY BROKEN), SiriReady Bench Phase 2.
// Legacy SiriKit code that was never migrated to App Intents. The intent classes are written by
// hand (instead of being generated from an .intentdefinition) so the app builds; none of this is
// reachable from App Intents or the new Siri.
import Foundation
import Intents

class ShareEventIntent: INIntent {
    @NSManaged var eventIdentifier: String?
    @NSManaged var invitee: String?
}

class ShareEventIntentResponse: INIntentResponse {}

@objc protocol ShareEventIntentHandling: NSObjectProtocol {
    func handle(intent: ShareEventIntent, completion: @escaping (ShareEventIntentResponse) -> Void)
}

class IntentHandler: INExtension {
    override func handler(for intent: INIntent) -> Any {
        if intent is ShareEventIntent {
            return ShareEventIntentHandler()
        }
        return self
    }
}

class ShareEventIntentHandler: NSObject, ShareEventIntentHandling {
    func handle(intent: ShareEventIntent, completion: @escaping (ShareEventIntentResponse) -> Void) {
        EventStore.shared.record("ShareEventIntent(SiriKit)", target: intent.eventIdentifier, params: ["invitee": intent.invitee ?? ""])
        completion(ShareEventIntentResponse())
    }
}
