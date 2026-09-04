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
    private let settingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("noxa.validation"))
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

    func persistSelection() {
        errorMessage = nil
        do {
            try store.saveFamilyActivitySelection(selection)
        } catch {
            errorMessage = "Could not save the selection: \(error.localizedDescription)"
            logger.error("Selection persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Applies a shield immediately. This is intentionally callable from the
    /// main app for the first physical-device spike; the monitor extension
    /// applies the same shield when its callbacks arrive.
    func applyShield(customDomains: [String] = []) {
        guard hasSelection || !customDomains.isEmpty else {
            errorMessage = "Choose at least one app, category, or website first."
            return
        }

        errorMessage = nil
        settingsStore.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        settingsStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        settingsStore.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
        settingsStore.webContent.blockedByFilter = customDomains.isEmpty
            ? nil
            : .specific(Set(customDomains.map(WebDomain.init(domain:))))
        isShieldActive = true
        logger.info("Applied local shield for \(self.selectedItemCount) selected item(s)")
    }

    func removeShield() {
        errorMessage = nil
        settingsStore.clearAllSettings()
        isShieldActive = false
        logger.info("Removed all local Managed Settings restrictions")
    }

    func clearSelection() {
        selection = FamilyActivitySelection()
        store.clearFamilyActivitySelection()
        removeShield()
    }
}
