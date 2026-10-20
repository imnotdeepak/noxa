import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

/// Moves shields written by older builds out of the shared validation store.
/// It runs before app reconciliation so the new owners can restore their own
/// settings without one owner clearing another's block.
@MainActor
enum RestrictionStoreMigration {
    struct Plan {
        let copyLegacyToManual: Bool
        let copyLegacyToFocusFallback: Bool
        let clearLegacy: Bool
    }

    static func plan(hasActiveFocus: Bool, validationMonitorIsRunning: Bool) -> Plan {
        Plan(
            copyLegacyToManual: !hasActiveFocus && !validationMonitorIsRunning,
            copyLegacyToFocusFallback: hasActiveFocus,
            clearLegacy: !validationMonitorIsRunning
        )
    }

    struct Stores {
        let legacy: ManagedSettingsStore
        let focus: ManagedSettingsStore
        let manual: ManagedSettingsStore
        let websites: ManagedSettingsStore

        static var production: Stores {
            Stores(
                legacy: ManagedSettingsStore(named: RestrictionStoreNames.legacy),
                focus: ManagedSettingsStore(named: RestrictionStoreNames.focus),
                manual: ManagedSettingsStore(named: RestrictionStoreNames.manual),
                websites: ManagedSettingsStore(named: RestrictionStoreNames.websites)
            )
        }
    }

    static func migrateIfNeeded(
        store: AppGroupStore? = nil,
        stores: Stores? = nil,
        validationMonitorIsRunning: Bool? = nil
    ) {
        let store = store ?? .shared
        guard !store.hasMigratedRestrictionStores else { return }

        let stores = stores ?? .production
        let legacy = stores.legacy
        let focus = stores.focus
        let manual = stores.manual
        let websites = stores.websites
        let validationMonitorIsRunning = validationMonitorIsRunning ?? DeviceActivityCenter().activities.contains(
            NoxaDeviceActivityConfiguration.activityName
        )
        let migrationPlan = plan(
            hasActiveFocus: store.hasActiveFocusSession(),
            validationMonitorIsRunning: validationMonitorIsRunning
        )

        if migrationPlan.copyLegacyToFocusFallback {
            if let configuration = (try? store.loadFocusSessionRestrictions()) ?? nil {
                focus.shield.applications = configuration.selection.applicationTokens.isEmpty
                    ? nil : configuration.selection.applicationTokens
                focus.shield.applicationCategories = configuration.selection.categoryTokens.isEmpty
                    ? nil : .specific(configuration.selection.categoryTokens)
                focus.shield.webDomains = configuration.selection.webDomainTokens.isEmpty
                    ? nil : configuration.selection.webDomainTokens
                focus.webContent.blockedByFilter = configuration.websiteDomains.isEmpty
                    ? nil : .specific(Set(configuration.websiteDomains.map(WebDomain.init(domain:))))
            } else {
                // Preserve a legacy active session even if its restriction
                // snapshot is unavailable; FocusSessionService will recover it.
                copyShield(from: legacy, to: focus)
                focus.webContent.blockedByFilter = legacy.webContent.blockedByFilter
            }
        } else if migrationPlan.copyLegacyToManual, (try? store.loadManualShield()) == nil {
            copyShield(from: legacy, to: manual)
            manual.webContent.blockedByFilter = legacy.webContent.blockedByFilter
        }

        if let configuration = (try? store.loadManualShield()) ?? nil {
            manual.shield.applications = configuration.selection.applicationTokens.isEmpty
                ? nil : configuration.selection.applicationTokens
            manual.shield.applicationCategories = configuration.selection.categoryTokens.isEmpty
                ? nil : .specific(configuration.selection.categoryTokens)
            manual.shield.webDomains = configuration.selection.webDomainTokens.isEmpty
                ? nil : configuration.selection.webDomainTokens
            manual.webContent.blockedByFilter = configuration.websiteDomains.isEmpty
                ? nil : .specific(Set(configuration.websiteDomains.map(WebDomain.init(domain:))))
        }

        if store.isWebsiteShieldActive,
           let domains = try? store.loadWebsiteBlocklist(), !domains.isEmpty {
            websites.webContent.blockedByFilter = .specific(Set(domains.map(WebDomain.init(domain:))))
        }

        // A running validation monitor still owns its legacy store. Its stop
        // path clears that store; moving its shield to a manual store would
        // make a temporary threshold block permanent.
        if migrationPlan.clearLegacy {
            legacy.clearAllSettings()
        }
        store.hasMigratedRestrictionStores = true
    }

    private static func copyShield(from source: ManagedSettingsStore, to target: ManagedSettingsStore) {
        target.shield.applications = source.shield.applications
        target.shield.applicationCategories = source.shield.applicationCategories
        target.shield.webDomains = source.shield.webDomains
    }
}
