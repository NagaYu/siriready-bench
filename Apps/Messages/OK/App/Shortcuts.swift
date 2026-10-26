// MessagesOK (reference app "Relay"), SiriReady Bench Phase 2.
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
