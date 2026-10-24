import FamilyControls
import ManagedSettings

/// Writes one rule owner's selection to its own Managed Settings store.
/// Callers decide whether that owner is active and clear only their store.
enum RestrictionStoreWriter {
    nonisolated static func combinedSelection(
        _ selections: [FamilyActivitySelection]
    ) -> FamilyActivitySelection {
        selections.reduce(into: FamilyActivitySelection()) { combined, selection in
            combined.applicationTokens.formUnion(selection.applicationTokens)
            combined.categoryTokens.formUnion(selection.categoryTokens)
            combined.webDomainTokens.formUnion(selection.webDomainTokens)
        }
    }

    nonisolated static func apply(
        selection: FamilyActivitySelection,
        websiteDomains: [String],
        to store: ManagedSettingsStore
    ) {
        store.shield.applications = selection.applicationTokens.isEmpty
            ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil : selection.webDomainTokens
        store.webContent.blockedByFilter = websiteDomains.isEmpty
            ? nil : .specific(Set(websiteDomains.map(WebDomain.init(domain:))))
    }
}
