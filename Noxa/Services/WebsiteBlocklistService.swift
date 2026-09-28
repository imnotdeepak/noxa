//
//  WebsiteBlocklistService.swift
//  Noxa
//

import Combine
import Foundation
import ManagedSettings
import os

/// Stores normalized custom domains and applies them through Apple's web
/// content filter. The domain strings are user configuration, not Screen Time
/// activity telemetry.
@MainActor
final class WebsiteBlocklistService: ObservableObject {
    static let maximumDomains = 50

    @Published private(set) var domains: [String]
    @Published private(set) var errorMessage: String?

    private let store: AppGroupStore
    private let settingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("noxa.validation"))
    private let logger = Logger(subsystem: "LycheeCorp.Noxa", category: "websites")

    init(store: AppGroupStore? = nil) {
        self.store = store ?? AppGroupStore.shared
        self.domains = (try? self.store.loadWebsiteBlocklist()) ?? []
    }

    var isLockedForFocusSession: Bool {
        store.hasActiveFocusSession()
    }

    @discardableResult
    func addDomain(_ input: String) -> Bool {
        guard let domain = Self.normalize(input) else {
            errorMessage = "Enter a valid domain such as reddit.com."
            return false
        }
        guard !domains.contains(domain) else {
            errorMessage = nil
            return true
        }
        guard domains.count < Self.maximumDomains else {
            errorMessage = "You can block up to \(Self.maximumDomains) custom domains at once."
            return false
        }

        if isLockedForFocusSession {
            return addDomainToActiveSession(domain)
        }

        domains.append(domain)
        domains.sort()
        persist()
        return true
    }

    /// Strengthens a running session without allowing any existing domain to
    /// be removed. The monitor extension reads the same updated snapshot.
    private func addDomainToActiveSession(_ domain: String) -> Bool {
        do {
            guard let current = try store.loadFocusSessionRestrictions() else {
                errorMessage = "The active focus session could not be updated."
                return false
            }

            let mergedDomains = Array(Set(current.websiteDomains + domains + [domain])).sorted()
            guard mergedDomains.count <= Self.maximumDomains else {
                errorMessage = "You can block up to \(Self.maximumDomains) custom domains at once."
                return false
            }

            let updated = FocusSessionRestrictionConfiguration(
                selection: current.selection,
                websiteDomains: mergedDomains,
                intention: current.intention
            )
            try store.saveFocusSessionRestrictions(updated)
            try store.saveWebsiteBlocklist(mergedDomains)
            domains = mergedDomains
            settingsStore.webContent.blockedByFilter = .specific(
                Set(mergedDomains.map(WebDomain.init(domain:)))
            )
            errorMessage = nil
            logger.info("Added a website restriction to the active focus session")
            return true
        } catch {
            errorMessage = "Could not add the website: \(error.localizedDescription)"
            logger.error("Active website addition failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    func removeDomain(_ domain: String) {
        guard !isLockedForFocusSession else {
            errorMessage = "Blocklist changes are locked until the focus session ends."
            return
        }
        domains.removeAll { $0 == domain }
        persist()
    }

    /// Replaces cloud-supported domains after account hydration or merging.
    /// Every value is normalized again before entering local enforcement state.
    func replaceDomains(_ newDomains: [String]) {
        guard !isLockedForFocusSession else {
            logger.info("Ignored cloud blocklist replacement while a focus session is active")
            return
        }
        let normalized = Array(Set(newDomains.compactMap(Self.normalize))).sorted()
        let bounded = Array(normalized.prefix(Self.maximumDomains))
        guard bounded != domains else { return }
        domains = bounded
        persist()
    }

    func persist() {
        errorMessage = nil
        do {
            try store.saveWebsiteBlocklist(domains)
        } catch {
            errorMessage = "Could not save the website list: \(error.localizedDescription)"
            logger.error("Website persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func applyBlocklist() {
        guard !isLockedForFocusSession else {
            errorMessage = "Blocklist changes are locked until the focus session ends."
            return
        }
        guard !domains.isEmpty else {
            settingsStore.webContent.blockedByFilter = nil
            return
        }
        settingsStore.webContent.blockedByFilter = .specific(Set(domains.map(WebDomain.init(domain:))))
        logger.info("Applied \(self.domains.count) custom website restriction(s)")
    }

    func clearBlocklist(force: Bool = false) {
        guard force || !isLockedForFocusSession else {
            errorMessage = "Blocklist changes are locked until the focus session ends."
            return
        }
        settingsStore.webContent.blockedByFilter = nil
    }

    func removeAllDomains(force: Bool = false) {
        guard force || !isLockedForFocusSession else {
            errorMessage = "Blocklist changes are locked until the focus session ends."
            return
        }
        domains = []
        store.clearWebsiteBlocklist()
        clearBlocklist(force: true)
        errorMessage = nil
    }

    static func normalize(_ input: String) -> String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }

        if !value.contains("://") {
            value = "https://\(value)"
        }
        guard let url = URL(string: value), let host = url.host else { return nil }

        var domain = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if domain.hasPrefix("www.") {
            domain = String(domain.dropFirst(4))
        }
        guard domain.contains("."),
              !domain.contains(" "),
              domain.count <= 253,
              domain.split(separator: ".").allSatisfy({ !$0.isEmpty }) else {
            return nil
        }
        return domain
    }
}
