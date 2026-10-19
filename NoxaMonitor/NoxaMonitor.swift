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
    static let scheduleActivityPrefix = "noxa.schedule."
    static let scheduleRelaxationActivityPrefix = "noxa.schedule.relax."

    static func dailyLimitEventPrefix() -> String {
        "noxa.daily.limit."
    }

    static func dailyLimitDayStamp(for date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> String {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(components.era ?? 0)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }
}

/// Mirrors the main app's device-local focus-session restriction snapshot.
/// This type intentionally lives in the extension target so Screen Time tokens
/// remain local and the extension can enforce the immutable session state.
private struct PersistedFocusSessionConfiguration: Codable {
    let selection: FamilyActivitySelection
    let websiteDomains: [String]
}

private struct PersistedDailyLimitConfiguration: Codable {
    let id: UUID
    let selection: FamilyActivitySelection
    let dailyLimitMinutes: Int
    let createdAt: Date
    let isEnabled: Bool
}

private struct PersistedRestrictionScheduleConfiguration: Codable {
    let id: UUID
    let selection: FamilyActivitySelection
    let allowedStartMinutes: Int
    let allowedEndMinutes: Int
    let createdAt: Date
    var isEnabled: Bool
    var pendingRelaxation: PersistedScheduleRelaxation?
}

private struct PersistedScheduleRelaxation: Codable {
    enum Action: String, Codable {
        case disable
        case remove
    }

    let action: Action
    let requestedAt: Date
    let effectiveAt: Date
}

/// Runs outside the Noxa process so restrictions can be enforced after the
/// app is backgrounded or terminated by the operating system.
final class NoxaMonitorExtension: DeviceActivityMonitor {
    private let settingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("noxa.validation"))
    private let focusSettingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("noxa.focus"))
    private let dailyLimitSettingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("noxa.daily-limits"))
    private let logger = Logger(subsystem: "LycheeCorp.Noxa", category: "monitoring")

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        if activity == NoxaMonitorActivity.focusActivityName {
            applyPersistedFocusShield(reason: "focus session started")
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
        } else if activity.rawValue.hasPrefix(NoxaMonitorActivity.scheduleRelaxationActivityPrefix) {
            applyPendingScheduleRelaxation(for: activity)
        } else if activity.rawValue.hasPrefix(NoxaMonitorActivity.scheduleActivityPrefix) {
            applyScheduleShield(for: activity)
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
            focusSettingsStore.clearAllSettings()
            let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa")
            if defaults?.bool(forKey: "noxa.restrictionStoresMigrated") != true {
                settingsStore.clearAllSettings()
            }
            UserDefaults(suiteName: "group.LycheeCorp.Noxa")?.removeObject(
                forKey: "noxa.focusSessionRestrictions"
            )
            logger.info("Removed focus shield when session ended")
        } else if activity.rawValue.hasPrefix(NoxaMonitorActivity.scheduleRelaxationActivityPrefix) {
            logger.info("Pending schedule relaxation interval ended")
        } else if activity.rawValue.hasPrefix(NoxaMonitorActivity.scheduleActivityPrefix) {
            ManagedSettingsStore(named: ManagedSettingsStore.Name(activity.rawValue)).clearAllSettings()
            logger.info("Removed scheduled shield for \(activity.rawValue, privacy: .public)")
        }
    }

    private func applyPersistedFocusShield(reason: String) {
        guard let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.focusSessionRestrictions"),
              let configuration = try? JSONDecoder().decode(
                  PersistedFocusSessionConfiguration.self,
                  from: data
              )
        else {
            logger.error("Could not load the immutable focus-session restrictions")
            return
        }

        applyShield(
            selection: configuration.selection,
            websiteDomains: configuration.websiteDomains,
            reason: reason,
            to: focusSettingsStore
        )
    }

    private func applyPersistedShield(reason: String) {
        guard let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.familyActivitySelection"),
              let selection = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data)
        else {
            logger.error("Could not load a persisted selection for monitor callback")
            return
        }

        let websiteDomains: [String]
        if let blocklistData = defaults.data(forKey: "noxa.websiteBlocklist"),
           let domains = try? JSONDecoder().decode([String].self, from: blocklistData) {
            websiteDomains = domains
        } else {
            websiteDomains = []
        }

        applyShield(
            selection: selection,
            websiteDomains: websiteDomains,
            reason: reason
        )
    }

    private func applyShield(
        selection: FamilyActivitySelection,
        websiteDomains: [String],
        reason: String,
        to targetStore: ManagedSettingsStore? = nil
    ) {
        let targetStore = targetStore ?? settingsStore
        targetStore.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        targetStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        targetStore.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
        if !websiteDomains.isEmpty {
            targetStore.webContent.blockedByFilter = .specific(
                Set(websiteDomains.map(WebDomain.init(domain:)))
            )
        } else {
            targetStore.webContent.blockedByFilter = nil
        }
        logger.info("Applied monitor shield: \(reason, privacy: .public)")
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

    private func applyScheduleShield(for activity: DeviceActivityName) {
        let parts = activity.rawValue.split(separator: ".")
        guard let idText = parts.last,
              let id = UUID(uuidString: String(idText)),
              let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.restrictionSchedules"),
              let schedules = try? JSONDecoder().decode(
                  [PersistedRestrictionScheduleConfiguration].self,
                  from: data
              ),
              let schedule = schedules.first(where: { $0.id == id && $0.isEnabled })
        else {
            logger.error("Could not load schedule for \(activity.rawValue, privacy: .public)")
            return
        }

        if let pending = schedule.pendingRelaxation,
           pending.effectiveAt <= Date() {
            clearScheduleShields(for: id)
            logger.info("Skipped expired schedule \(activity.rawValue, privacy: .public)")
            return
        }

        let store = ManagedSettingsStore(named: ManagedSettingsStore.Name(activity.rawValue))
        store.shield.applications = schedule.selection.applicationTokens.isEmpty
            ? nil
            : schedule.selection.applicationTokens
        store.shield.applicationCategories = schedule.selection.categoryTokens.isEmpty
            ? nil
            : .specific(schedule.selection.categoryTokens)
        store.shield.webDomains = schedule.selection.webDomainTokens.isEmpty
            ? nil
            : schedule.selection.webDomainTokens
        logger.info("Applied scheduled shield for \(activity.rawValue, privacy: .public)")
    }

    private func applyPendingScheduleRelaxation(for activity: DeviceActivityName) {
        let parts = activity.rawValue.split(separator: ".")
        guard let idText = parts.last,
              let id = UUID(uuidString: String(idText)),
              let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.restrictionSchedules"),
              var schedules = try? JSONDecoder().decode(
                  [PersistedRestrictionScheduleConfiguration].self,
                  from: data
              ),
              let index = schedules.firstIndex(where: { $0.id == id }),
              let pending = schedules[index].pendingRelaxation,
              pending.effectiveAt <= Date()
        else {
            logger.error("Could not apply pending relaxation for \(activity.rawValue, privacy: .public)")
            return
        }

        switch pending.action {
        case .remove:
            schedules.remove(at: index)
        case .disable:
            schedules[index].isEnabled = false
            schedules[index].pendingRelaxation = nil
        }

        if let updatedData = try? JSONEncoder().encode(schedules) {
            defaults.set(updatedData, forKey: "noxa.restrictionSchedules")
        }
        clearScheduleShields(for: id)
        logger.info("Applied pending schedule relaxation for \(id.uuidString, privacy: .public)")
    }

    private func clearScheduleShields(for id: UUID) {
        for segment in ["before", "after"] {
            let name = DeviceActivityName(
                "\(NoxaMonitorActivity.scheduleActivityPrefix)\(segment).\(id.uuidString.lowercased())"
            )
            ManagedSettingsStore(named: ManagedSettingsStore.Name(name.rawValue)).clearAllSettings()
        }
    }
}
