import AppIntents

/// Opens the same duration-and-policy review as the widget. A shortcut never
/// begins enforcement before the user confirms the targets and end time.
struct StartFocusIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Focus"
    static var description = IntentDescription("Choose a duration and review your focus session in Noxa.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        FocusLaunchRouter.shared.requestStart()
        return .result()
    }
}

struct NoxaAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartFocusIntent(),
            phrases: ["Start focus with \(.applicationName)"],
            shortTitle: "Start Focus",
            systemImageName: "timer"
        )
    }
}
