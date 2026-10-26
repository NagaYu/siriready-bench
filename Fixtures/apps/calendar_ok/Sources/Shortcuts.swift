// Synthetic fixture for SiriReady Bench ("Orbit Calendar"). Not compiled in Phase 1.
import AppIntents

struct OrbitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenEventIntent(),
            phrases: ["Open \(\.$target) in \(.applicationName)"],
            shortTitle: "Open Event",
            systemImageName: "calendar"
        )
        AppShortcut(
            intent: ShareEventIntent(),
            phrases: ["Share \(\.$target) with \(.applicationName)"],
            shortTitle: "Share Event",
            systemImageName: "person.badge.plus"
        )
    }
}
