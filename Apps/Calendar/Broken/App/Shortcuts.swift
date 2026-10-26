// CalendarBroken (reference app "Orbit Calendar", INTENTIONALLY BROKEN), SiriReady Bench Phase 2.
import AppIntents

struct OrbitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenEventIntent(),
            phrases: ["Open \(\.$target) in \(.applicationName)"],
            shortTitle: "Open Event",
            systemImageName: "calendar"
        )
    }
}
