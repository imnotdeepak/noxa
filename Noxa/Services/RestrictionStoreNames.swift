import ManagedSettings

enum RestrictionStoreNames {
    static let legacy = ManagedSettingsStore.Name("noxa.validation")
    static let focus = ManagedSettingsStore.Name("noxa.focus")
    static let manual = ManagedSettingsStore.Name("noxa.manual")
    static let websites = ManagedSettingsStore.Name("noxa.websites")
}
