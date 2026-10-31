//
//  ScreenTimeRestrictionService.swift
//  Noxa
//

import Combine
import FamilyControls
import Foundation
import ManagedSettings
import os

/// Owns the app-side selection and the explicit shield used by Spike B.
///
/// The selection contains opaque Apple-managed tokens. It is persisted in the
/// App Group so a future Screen Time extension can enforce the same selection
/// after Noxa is terminated.
@MainActor
final class ScreenTimeRestrictionService: ObservableObject {
    @Published var selection: FamilyActivitySelection
    @Published var isPickerPresented = false
    @Published private(set) var isShieldActive = false
    @Published private(set) var errorMessage: String?

    private let store: AppGroupStore
    private let settingsStore = ManagedSettingsStore(named: RestrictionStoreNames.manual)
    private let focusSettingsStore = ManagedSettingsStore(named: RestrictionStoreNames.focus)
    private let logger = Logger(subsystem: "LycheeCorp.Noxa", category: "shielding")

    init(store: AppGroupStore? = nil) {
        let store = store ?? AppGroupStore.shared
        self.store = store
        self.selection = (try? store.loadFamilyActivitySelection()) ?? nil
            ?? FamilyActivitySelection()
        self.isShieldActive = settingsStore.shield.applications != nil
            || settingsStore.shield.applicationCategories != nil
            || settingsStore.shield.webDomains != nil
            || settingsStore.webContent.blockedByFilter != nil
    }

    var selectedItemCount: Int {
        selection.applicationTokens.count
            + selection.categoryTokens.count
            + selection.webDomainTokens.count
    }

    var hasSelection: Bool {
        selectedItemCount > 0
    }

    func reloadSelectionForAccount() {
        selection = (try? store.loadFamilyActivitySelection()) ?? nil
            ?? FamilyActivitySelection()
        errorMessage = nil
    }

    /// Selection edits are locked while a focus session is pending or active.
    /// The persisted check protects the invariant even after app relaunch.
    var isLockedForFocusSession: Bool {
        store.hasActiveFocusSession() || store.hasActivePomodoroCycle()
    }

    func persistSelection() {
        errorMessage = nil
        guard !isLockedForFocusSession else {
            restoreActiveSessionSelection()
            errorMessage = "Blocklist changes are locked until the focus session ends."
            return
        }
        do {
            try store.saveFamilyActivitySelection(selection)
            AnalyticsService.shared.capture(.focusBlocklistSaved(
                apps: selection.applicationTokens.count,
                categories: selection.categoryTokens.count,
                websites: selection.webDomainTokens.count
            ))
        } catch {
            errorMessage = "Could not save the selection: \(error.localizedDescription)"
            logger.error("Selection persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Adds new restrictions to the immutable snapshot owned by an active
    /// focus session. Existing tokens are always retained, so this operation
    /// can strengthen a running session but can never weaken it.
    @discardableResult
    func addToActiveSession(_ additions: FamilyActivitySelection) -> Bool {
        errorMessage = nil
        guard isLockedForFocusSession else {
            errorMessage = "There is no active focus session to update."
            return false
        }

        do {
            guard let current = try store.loadFocusSessionRestrictions() else {
                errorMessage = "The active focus session could not be updated."
                return false
            }

            var mergedSelection = current.selection
            mergedSelection.applicationTokens.formUnion(additions.applicationTokens)
            mergedSelection.categoryTokens.formUnion(additions.categoryTokens)
            mergedSelection.webDomainTokens.formUnion(additions.webDomainTokens)

            let updated = FocusSessionRestrictionConfiguration(
                selection: mergedSelection,
                websiteDomains: current.websiteDomains,
                intention: current.intention
            )
            try store.saveFocusSessionRestrictions(updated)
            if var cycle = try store.loadPomodoroCycle() {
                cycle.selection = mergedSelection
                try store.savePomodoroCycle(cycle)
            }
            try store.saveFamilyActivitySelection(mergedSelection)
            selection = mergedSelection
            applyShieldConfiguration(
                mergedSelection,
                customDomains: current.websiteDomains,
                to: focusSettingsStore
            )
            logger.info("Added restrictions to the active focus session")
            return true
        } catch {
            restoreActiveSessionSelection()
            errorMessage = "Could not add to the active blocklist: \(error.localizedDescription)"
            logger.error("Active-session addition failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Applies a shield immediately. This is intentionally callable from the
    /// main app for the first physical-device spike; the monitor extension
    /// applies the same shield when its callbacks arrive.
    func applyShield(customDomains: [String] = []) {
        guard !isLockedForFocusSession else {
            restoreActiveSessionSelection()
            errorMessage = "Blocklist changes are locked until the focus session ends."
            return
        }
        guard hasSelection || !customDomains.isEmpty else {
            errorMessage = "Choose at least one app, category, or website first."
            return
        }

        errorMessage = nil
        do {
            try store.saveManualShield(ManualShieldConfiguration(
                selection: selection,
                websiteDomains: customDomains
            ))
        } catch {
            errorMessage = "Could not save the active shield: \(error.localizedDescription)"
            return
        }
        applyShieldConfiguration(selection, customDomains: customDomains)
        logger.info("Applied local shield for \(self.selectedItemCount) selected item(s)")
    }

    private func applyShieldConfiguration(
        _ selection: FamilyActivitySelection,
        customDomains: [String],
        to targetStore: ManagedSettingsStore? = nil
    ) {
        let targetStore = targetStore ?? settingsStore
        RestrictionStoreWriter.apply(
            selection: selection,
            websiteDomains: customDomains,
            to: targetStore
        )
        if targetStore === settingsStore { isShieldActive = true }
    }

    func reconcile() {
        if let configuration = (try? store.loadManualShield()) ?? nil {
            applyShieldConfiguration(
                configuration.selection,
                customDomains: configuration.websiteDomains
            )
        } else {
            isShieldActive = settingsStore.shield.applications != nil
                || settingsStore.shield.applicationCategories != nil
                || settingsStore.shield.webDomains != nil
                || settingsStore.webContent.blockedByFilter != nil
        }
    }

    func removeShield(force: Bool = false) {
        guard force || !isLockedForFocusSession else {
            errorMessage = "Blocklist changes are locked until the focus session ends."
            return
        }
        errorMessage = nil
        settingsStore.clearAllSettings()
        store.clearManualShield()
        isShieldActive = false
        logger.info("Removed all local Managed Settings restrictions")
    }

    func clearSelection(force: Bool = false) {
        guard force || !isLockedForFocusSession else {
            restoreActiveSessionSelection()
            errorMessage = "Blocklist changes are locked until the focus session ends."
            return
        }
        selection = FamilyActivitySelection()
        store.clearFamilyActivitySelection()
        removeShield(force: true)
    }

    /// Restores the immutable selection captured when the active session began.
    /// This is used if a picker was already open when a session became active.
    func restoreActiveSessionSelection() {
        do {
            if let configuration = try store.loadFocusSessionRestrictions() {
                selection = configuration.selection
            }
        } catch {
            logger.error("Could not restore active-session selection: \(error.localizedDescription, privacy: .public)")
        }
    }
}
