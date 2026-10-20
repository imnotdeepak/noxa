//
//  NoxaMonitor.swift
//  NoxaMonitor
//

import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import os
import UserNotifications

private enum NoxaMonitorActivity {
    static let focusActivityName = DeviceActivityName("noxa.focus.session")
    static let dailyLimitActivityName = DeviceActivityName("noxa.daily.limits")
    static let dailyLimitReachedEventsKey = "noxa.dailyLimitReachedEvents"
    static let dailyLimitResetDayKey = "noxa.dailyLimitResetDay"
    static let scheduleActivityPrefix = "noxa.schedule."
    static let scheduleV2WakePrefix = "noxa.schedule.v2.wake."
    static let scheduleV2RelaxationPrefix = "noxa.schedule.v2.relax."
    static let scheduleV2ShieldPrefix = "noxa.schedule.v2.shield."
    static let scheduleRelaxationActivityPrefix = "noxa.schedule.relax."
    static let pomodoroWorkActivityPrefix = "noxa.pomodoro.work."

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

private struct PersistedPomodoroPlan: Codable {
    let startedAt: Date
    let workMinutes: Int
    let breakMinutes: Int

    func workInterval(round: Int) -> DateInterval? {
        guard (2...4).contains(round) else { return nil }
        let work = TimeInterval(workMinutes * 60)
        let breakTime = TimeInterval(breakMinutes * 60)
        let start = startedAt.addingTimeInterval(TimeInterval(round - 1) * (work + breakTime))
        return DateInterval(start: start, duration: work)
    }
}

private struct PersistedPomodoroCycle: Codable {
    let id: UUID
    let plan: PersistedPomodoroPlan
    let selection: FamilyActivitySelection
    let websiteDomains: [String]
    let roundSessionIDs: [UUID]
}

private struct PersistedSessionStatus: Codable {
    let activeSession: ActiveStatus?

    struct ActiveStatus: Codable {
        let id: UUID
        let plannedEndAt: Date
        let outcome: String
    }
}

private struct PersistedFocusMonitorReceipt: Codable {
    let sessionID: UUID
    let appliedAt: Date
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

private struct PersistedScheduleRuleArchive: Codable {
    let version: Int
    let rules: [PersistedScheduleRule]
}

private struct PersistedScheduleRule: Codable {
    enum Mode: String, Codable {
        case blockedHours
        case allowedHours
    }

    let id: UUID
    let name: String?
    let mode: Mode
    let selection: FamilyActivitySelection
    let websiteDomains: [String]
    let weekdays: Set<Int>
    let startMinutes: Int
    let endMinutes: Int
    let isEnabled: Bool
    let notifyAtStart: Bool?
    let notifyAtEnd: Bool?
    let pendingLegacyRelaxation: PersistedScheduleRelaxation?

    func isBlocking(at date: Date, calendar: Calendar) -> Bool {
        ScheduleWindow.isBlocking(
            mode: mode.rawValue,
            weekdays: weekdays,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            isEnabled: isEnabled,
            pendingRelaxationAt: pendingLegacyRelaxation?.effectiveAt,
            at: date,
            calendar: calendar
        )
    }
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
        } else if activity.rawValue.hasPrefix(NoxaMonitorActivity.pomodoroWorkActivityPrefix) {
            applyPomodoroShield(for: activity)
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
        } else if activity.rawValue.hasPrefix(NoxaMonitorActivity.scheduleV2WakePrefix)
                    || activity.rawValue.hasPrefix(NoxaMonitorActivity.scheduleV2RelaxationPrefix) {
            applyV2ScheduleShield(for: activity)
            if activity.rawValue.hasPrefix(NoxaMonitorActivity.scheduleV2WakePrefix) {
                sendScheduleReminder(for: activity)
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

    override func eventWillReachThresholdWarning(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventWillReachThresholdWarning(event, activity: activity)
        guard activity == NoxaMonitorActivity.dailyLimitActivityName else { return }
        sendDailyLimitWarning(for: event)
    }

    private func sendDailyLimitWarning(for event: DeviceActivityEvent.Name) {
        guard let idText = event.rawValue.split(separator: ".").last,
              let id = UUID(uuidString: String(idText)),
              let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.dailyLimits"),
              let configurations = try? JSONDecoder().decode(
                [PersistedDailyLimitConfiguration].self, from: data
              ),
              let limit = configurations.first(where: { $0.id == id && $0.isEnabled }),
              limit.dailyLimitMinutes > 5 else { return }

        let today = NoxaMonitorActivity.dailyLimitDayStamp()
        let identifier = "noxa.daily.warning.\(id.uuidString.lowercased()).\(today)"
        guard !defaults.bool(forKey: identifier),
              !(defaults.stringArray(forKey: NoxaMonitorActivity.dailyLimitReachedEventsKey) ?? [])
                .contains(event.rawValue) else { return }
        defaults.set(true, forKey: identifier)

        let content = UNMutableNotificationContent()
        content.title = "Daily limit almost reached"
        content.body = "About 5 minutes remain for one of your daily limits."
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.error("Daily limit warning failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        if activity == NoxaMonitorActivity.focusActivityName {
            if let cycle = loadPomodoroCycle() {
                reconcilePomodoroShield(cycle)
            } else if hasUnexpiredFocusSession() {
                applyPersistedFocusShield(reason: "reconciled late focus-end callback")
            } else {
                focusSettingsStore.clearAllSettings()
                UserDefaults(suiteName: "group.LycheeCorp.Noxa")?.removeObject(
                    forKey: "noxa.focusSessionRestrictions"
                )
                UserDefaults(suiteName: "group.LycheeCorp.Noxa")?.removeObject(
                    forKey: "noxa.focusMonitorReceipt"
                )
            }
            let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa")
            if defaults?.bool(forKey: "noxa.restrictionStoresMigrated") != true {
                settingsStore.clearAllSettings()
            }
            logger.info("Removed focus shield when session ended")
        } else if activity.rawValue.hasPrefix(NoxaMonitorActivity.pomodoroWorkActivityPrefix) {
            reconcilePomodoroShield(for: activity)
        } else if activity.rawValue.hasPrefix(NoxaMonitorActivity.scheduleV2WakePrefix)
                    || activity.rawValue.hasPrefix(NoxaMonitorActivity.scheduleV2RelaxationPrefix) {
            applyV2ScheduleShield(for: activity)
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
        if let snapshotData = defaults.data(forKey: "noxa.localSnapshot"),
           let snapshot = try? JSONDecoder().decode(PersistedSessionStatus.self, from: snapshotData),
           let session = snapshot.activeSession,
           ["active", "start_pending"].contains(session.outcome),
           session.plannedEndAt > Date() {
            saveFocusMonitorReceipt(sessionID: session.id, defaults: defaults)
        }
    }

    private func saveFocusMonitorReceipt(sessionID: UUID, defaults: UserDefaults) {
        let receipt = PersistedFocusMonitorReceipt(sessionID: sessionID, appliedAt: Date())
        if let data = try? JSONEncoder().encode(receipt) {
            defaults.set(data, forKey: "noxa.focusMonitorReceipt")
        }
    }

    private func loadPomodoroCycle() -> PersistedPomodoroCycle? {
        guard let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.pomodoroCycle") else { return nil }
        return try? JSONDecoder().decode(PersistedPomodoroCycle.self, from: data)
    }

    private func hasUnexpiredFocusSession() -> Bool {
        guard let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.localSnapshot"),
              let snapshot = try? JSONDecoder().decode(PersistedSessionStatus.self, from: data),
              let session = snapshot.activeSession else { return false }
        return session.outcome == "active" && session.plannedEndAt > Date()
    }

    private func applyPomodoroShield(for activity: DeviceActivityName) {
        reconcilePomodoroShield(for: activity)
    }

    private func reconcilePomodoroShield(for activity: DeviceActivityName) {
        let parts = activity.rawValue.split(separator: ".")
        guard let idText = parts.dropLast().last,
              let id = UUID(uuidString: String(idText)),
              let cycle = loadPomodoroCycle(),
              cycle.id == id else {
            logger.error("Skipped stale Pomodoro callback for \(activity.rawValue, privacy: .public)")
            return
        }
        reconcilePomodoroShield(cycle)
    }

    private func reconcilePomodoroShield(_ cycle: PersistedPomodoroCycle) {
        let now = Date()
        for round in 2...4 {
            if cycle.plan.workInterval(round: round)?.contains(now) == true {
                if let data = try? JSONEncoder().encode(PersistedFocusSessionConfiguration(
                    selection: cycle.selection,
                    websiteDomains: cycle.websiteDomains
                )) {
                    UserDefaults(suiteName: "group.LycheeCorp.Noxa")?.set(
                        data, forKey: "noxa.focusSessionRestrictions"
                    )
                }
                applyShield(
                    selection: cycle.selection,
                    websiteDomains: cycle.websiteDomains,
                    reason: "Pomodoro round \(round) active",
                    to: focusSettingsStore
                )
                let enforcementKey = "noxa.pomodoro.enforced.\(cycle.id.uuidString.lowercased()).\(round)"
                let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa")
                if defaults?.object(forKey: enforcementKey) == nil {
                    defaults?.set(now, forKey: enforcementKey)
                }
                if cycle.roundSessionIDs.indices.contains(round - 1), let defaults {
                    saveFocusMonitorReceipt(
                        sessionID: cycle.roundSessionIDs[round - 1],
                        defaults: defaults
                    )
                }
                return
            }
        }
        focusSettingsStore.clearAllSettings()
        UserDefaults(suiteName: "group.LycheeCorp.Noxa")?.removeObject(
            forKey: "noxa.focusSessionRestrictions"
        )
        UserDefaults(suiteName: "group.LycheeCorp.Noxa")?.removeObject(
            forKey: "noxa.focusMonitorReceipt"
        )
        logger.info("Removed Pomodoro work shield during break or after completion")
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

    private func applyV2ScheduleShield(for activity: DeviceActivityName) {
        guard let idText = activity.rawValue.split(separator: ".").last,
              let id = UUID(uuidString: String(idText)) else { return }
        let name = "\(NoxaMonitorActivity.scheduleV2ShieldPrefix)\(id.uuidString.lowercased())"
        let ruleStore = ManagedSettingsStore(named: ManagedSettingsStore.Name(name))
        guard let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.scheduleRules.v2"),
              let archive = try? JSONDecoder().decode(PersistedScheduleRuleArchive.self, from: data),
              archive.version == 2,
              let rule = archive.rules.first(where: { $0.id == id }) else {
            ruleStore.clearAllSettings()
            logger.error("Missing v2 schedule for \(activity.rawValue, privacy: .public)")
            return
        }
        if rule.isBlocking(at: Date(), calendar: .autoupdatingCurrent) {
            applyShield(
                selection: rule.selection,
                websiteDomains: rule.websiteDomains,
                reason: "schedule \(id.uuidString)",
                to: ruleStore
            )
        } else {
            ruleStore.clearAllSettings()
        }
    }

    private func sendScheduleReminder(for activity: DeviceActivityName) {
        let parts = activity.rawValue.split(separator: ".")
        guard parts.count >= 2,
              let id = UUID(uuidString: String(parts[parts.count - 1])),
              let wakeMinute = Int(parts[parts.count - 2]),
              let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.scheduleRules.v2"),
              let archive = try? JSONDecoder().decode(PersistedScheduleRuleArchive.self, from: data),
              archive.version == 2,
              let rule = archive.rules.first(where: { $0.id == id && $0.isEnabled }) else { return }

        let now = Date()
        let calendar = Calendar.autoupdatingCurrent
        let components = calendar.dateComponents([.hour, .minute], from: now)
        let currentMinute = (components.hour ?? -1) * 60 + (components.minute ?? -1)
        // A late Device Activity callback must not announce an old boundary.
        guard (0...3).contains((currentMinute - wakeMinute + 1_440) % 1_440),
              rule.isBlocking(at: now.addingTimeInterval(-240), calendar: calendar)
                != rule.isBlocking(at: now, calendar: calendar) else { return }

        let kind: String
        if wakeMinute == rule.startMinutes, rule.notifyAtStart == true {
            kind = "start"
        } else if wakeMinute == rule.endMinutes, rule.notifyAtEnd == true {
            kind = "end"
        } else {
            return
        }

        let day = calendar.dateComponents([.era, .year, .month, .day], from: now)
        let identifier = "noxa.schedule.reminder.\(id.uuidString).\(kind).\(day.era ?? 0)-\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
        guard defaults.bool(forKey: identifier) == false else { return }
        defaults.set(true, forKey: identifier)

        let content = UNMutableNotificationContent()
        content.title = kind == "start" ? "Schedule started" : "Schedule ended"
        let name = rule.name.flatMap { $0.isEmpty ? nil : $0 } ?? "Your schedule"
        content.body = "\(name) \(kind == "start" ? "has started" : "has ended")."
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [logger] error in
            if let error {
                logger.error("Schedule reminder failed: \(error.localizedDescription, privacy: .public)")
            }
        }
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
