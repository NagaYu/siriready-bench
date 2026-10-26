// Synthetic fixture for SiriReady Bench ("Orbit Calendar"). Not compiled in Phase 1.
// Legacy SiriKit Intents extension that was never migrated to App Intents.
import Intents

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
        InviteService.shared.share(eventID: intent.eventIdentifier, with: intent.invitee) { ok in
            completion(ShareEventIntentResponse(code: ok ? .success : .failure, userActivity: nil))
        }
    }

    func resolveInvitee(for intent: ShareEventIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        completion(.success(with: intent.invitee ?? ""))
    }
}
