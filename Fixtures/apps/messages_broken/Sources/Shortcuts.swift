// Synthetic fixture for SiriReady Bench ("Relay"). Not compiled in Phase 1.
import AppIntents

struct RelayShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenConversationIntent(),
            phrases: ["Open \(\.$target) in \(.applicationName)"],
            shortTitle: "Open Conversation",
            systemImageName: "bubble.left.and.bubble.right"
        )
    }
}
