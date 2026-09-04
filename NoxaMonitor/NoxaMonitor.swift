//
//  NoxaMonitor.swift
//  NoxaMonitor
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import os

private enum NoxaMonitorActivity {
    static let focusActivityName = DeviceActivityName("noxa.focus.session")
    static let dailyLimitActivityName = DeviceActivityName("noxa.daily.limits")
    static let dailyLimitReachedEventsKey = "noxa.dailyLimitReachedEvents"
    static let dailyLimitResetDayKey = "noxa.dailyLimitResetDay"

    static func dailyLimitEventPrefix() -> String {
        "noxa.daily.limit."
    }

    static func dailyLimitDayStamp(for date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> String {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(components.era ?? 0)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

private struct PersistedDailyLimitConfiguration: Codable {
    let id: UUID
    let selection: FamilyActivitySelection
    let dailyLimitMinutes: Int
    let createdAt: Date
    let isEnabled: Bool
}

/// Runs outside the Noxa process so restrictions can be enforced after the
/// app is backgrounded or terminated by the operating system.
final class NoxaMonitorExtension: DeviceActivityMonitor {
    private let settingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("noxa.validation"))
    private let dailyLimitSettingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("noxa.daily-limits"))
    private let logger = Logger(subsystem: "LycheeCorp.Noxa", category: "monitoring")

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity == NoxaMonitorActivity.focusActivityName {
            applyPersistedShield(reason: "focus session started")
        } else if activity == NoxaMonitorActivity.dailyLimitActivityName {
            let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa")
            let today = NoxaMonitorActivity.dailyLimitDayStamp()
            if defaults?.string(forKey: NoxaMonitorActivity.dailyLimitResetDayKey) != today {
                dailyLimitSettingsStore.clearAllSettings()
                defaults?.removeObject(forKey: NoxaMonitorActivity.dailyLimitReachedEventsKey)
                defaults?.set(today, forKey: NoxaMonitorActivity.dailyLimitResetDayKey)
                logger.info("Reset daily limit shields for a new day")
            } else {
                logger.info("Restarted daily limit monitoring without resetting today's reached limits")
            }
        } else {
            logger.info("DeviceActivity validation interval started")
        }
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
        if activity == NoxaMonitorActivity.dailyLimitActivityName {
            applyDailyLimitShield(for: event)
        } else {
            applyPersistedShield(reason: "threshold reached")
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == NoxaMonitorActivity.focusActivityName {
            settingsStore.clearAllSettings()
            logger.info("Removed focus shield when session ended")
        }
    }

    private func applyPersistedShield(reason: String) {
        guard let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.familyActivitySelection"),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            logger.error("Could not load a persisted selection for monitor callback")
            return
        }

        settingsStore.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        settingsStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        settingsStore.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
        if let blocklistData = defaults.data(forKey: "noxa.websiteBlocklist"),
           let domains = try? JSONDecoder().decode([String].self, from: blocklistData),
           !domains.isEmpty {
            settingsStore.webContent.blockedByFilter = .specific(Set(domains.map(WebDomain.init(domain:))))
        } else {
            settingsStore.webContent.blockedByFilter = nil
        }
        logger.info("Applied persisted monitor shield: \(reason, privacy: .public)")
    }

    private func applyDailyLimitShield(for event: DeviceActivityEvent.Name) {
        guard let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.dailyLimits"),
              let configurations = try? JSONDecoder().decode([PersistedDailyLimitConfiguration].self, from: data) else {
            logger.error("Could not load a daily limit for monitor event \(event.rawValue, privacy: .public)")
            return
        }

        var reachedEvents = Set(defaults.stringArray(forKey: NoxaMonitorActivity.dailyLimitReachedEventsKey) ?? [])
        reachedEvents.insert(event.rawValue)
        defaults.set(Array(reachedEvents), forKey: NoxaMonitorActivity.dailyLimitReachedEventsKey)

        let reachedConfigurations = configurations.filter { configuration in
            configuration.isEnabled
                && reachedEvents.contains(
                    "\(NoxaMonitorActivity.dailyLimitEventPrefix())\(configuration.id.uuidString.lowercased())"
                )
        }

        guard !reachedConfigurations.isEmpty else {
            logger.error("Could not find an enabled daily limit for monitor event \(event.rawValue, privacy: .public)")
            return
        }

        var applications = Set<ApplicationToken>()
        var categories = Set<ActivityCategoryToken>()
        var webDomains = Set<WebDomainToken>()
        for configuration in reachedConfigurations {
            applications.formUnion(configuration.selection.applicationTokens)
            categories.formUnion(configuration.selection.categoryTokens)
            webDomains.formUnion(configuration.selection.webDomainTokens)
        }

        dailyLimitSettingsStore.shield.applications = applications.isEmpty ? nil : applications
        dailyLimitSettingsStore.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        dailyLimitSettingsStore.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        logger.info("Applied daily limit shields for \(reachedConfigurations.count) reached configuration(s)")
    }
}
