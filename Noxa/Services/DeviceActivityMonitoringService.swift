//
//  DeviceActivityMonitoringService.swift
//  Noxa
//

import DeviceActivity
import FamilyControls
import Combine
import Foundation
import ManagedSettings
import os

enum NoxaDeviceActivityConfiguration {
    static let activityName = DeviceActivityName("noxa.validation.activity")
    static let thresholdEvent = DeviceActivityEvent.Name("noxa.validation.threshold")
    static let focusActivityName = DeviceActivityName("noxa.focus.session")
    static let dailyLimitActivityName = DeviceActivityName("noxa.daily.limits")
    static let scheduleActivityPrefix = "noxa.schedule"
    static let dailyLimitReachedEventsKey = "noxa.dailyLimitReachedEvents"
    static let dailyLimitResetDayKey = "noxa.dailyLimitResetDay"
    static let dailyLimitHardLockDayKey = "noxa.dailyLimitHardLockDay"
    static let minimumFocusSessionMinutes = 15
    static let maximumFocusSessionMinutes = 480

    static func dailyLimitEventName(for id: UUID) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("noxa.daily.limit.\(id.uuidString.lowercased())")
    }

    static func scheduleActivityName(for id: UUID, segment: String) -> DeviceActivityName {
        DeviceActivityName("\(scheduleActivityPrefix).\(segment).\(id.uuidString.lowercased())")
    }

    static func dailyLimitDayStamp(for date: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> String {
        let components = calendar.dateComponents([.era, .year, .month, .day], from: date)
        return "\(components.era ?? 0)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
    }

    static func retainedDailyLimitEventNames(
        configurations: [DailyLimitConfiguration],
        reachedEventNames: Set<String>
    ) -> Set<String> {
        let enabledEventNames = Set(
            configurations
                .filter(\.isEnabled)
                .map { dailyLimitEventName(for: $0.id).rawValue }
        )
        return reachedEventNames.intersection(enabledEventNames)
    }
}

/// Starts a short, repeatable monitor for the DeviceActivity validation spike.
@MainActor
final class DeviceActivityMonitoringService: ObservableObject {
    @Published private(set) var isMonitoring = false
    @Published private(set) var errorMessage: String?

    private let center = DeviceActivityCenter()
    private let logger = Logger(subsystem: "LycheeCorp.Noxa", category: "monitoring")

    init() {
        isMonitoring = center.activities.contains(NoxaDeviceActivityConfiguration.activityName)
    }

    func start(selection: FamilyActivitySelection, thresholdMinutes: Int = 1) {
        guard !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty else {
            errorMessage = "Choose something to monitor before starting."
            return
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: max(1, thresholdMinutes))
        )

        do {
            // Restarting the named activity resets this validation run so a
            // previous threshold cannot affect the next attempt.
            center.stopMonitoring([NoxaDeviceActivityConfiguration.activityName])
            try center.startMonitoring(
                NoxaDeviceActivityConfiguration.activityName,
                during: schedule,
                events: [NoxaDeviceActivityConfiguration.thresholdEvent: event]
            )
            errorMessage = nil
            isMonitoring = true
            logger.info("Started DeviceActivity validation monitor")
        } catch {
            errorMessage = "Could not start monitoring: \(error.localizedDescription)"
            logger.error("Monitoring start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stop() {
        center.stopMonitoring([NoxaDeviceActivityConfiguration.activityName])
        isMonitoring = false
        errorMessage = nil
        logger.info("Stopped DeviceActivity validation monitor")
    }
}

/// Schedules all configured daily allowances in one repeating DeviceActivity
/// interval. Apple resets threshold accounting at the next interval boundary.
@MainActor
final class DailyLimitService: ObservableObject {
    static let maximumConfigurations = 20

    @Published private(set) var configurations: [DailyLimitConfiguration]
    @Published private(set) var isMonitoring = false
    @Published private(set) var isShieldActive = false
    @Published private(set) var errorMessage: String?

    private let store: AppGroupStore
    private let center = DeviceActivityCenter()
    private let settingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("noxa.daily-limits"))
    private let logger = Logger(subsystem: "LycheeCorp.Noxa", category: "daily-limits")

    init(store: AppGroupStore? = nil) {
        self.store = store ?? AppGroupStore.shared
        configurations = (try? self.store.loadDailyLimitConfigurations())
            ?? ((try? self.store.loadSnapshot())?.dailyLimits ?? [])
        isMonitoring = center.activities.contains(NoxaDeviceActivityConfiguration.dailyLimitActivityName)
        isShieldActive = settingsStore.shield.applications != nil
            || settingsStore.shield.applicationCategories != nil
            || settingsStore.shield.webDomains != nil
    }

    var enabledCount: Int {
        configurations.filter(\.isEnabled).count
    }

    var isLockedForFocusSession: Bool {
        store.hasActiveFocusSession()
    }

    var isHardLimitLocked: Bool {
        guard isMonitoring else { return false }
        let defaults = UserDefaults(suiteName: AppGroupStore.suiteName)
        return defaults?.string(forKey: NoxaDeviceActivityConfiguration.dailyLimitHardLockDayKey)
            == NoxaDeviceActivityConfiguration.dailyLimitDayStamp()
    }

    func add(selection: FamilyActivitySelection, minutes: Int) {
        errorMessage = nil
        guard canModifyLimits() else { return }
        guard !selection.applicationTokens.isEmpty else {
            errorMessage = "Select at least one app for a daily limit."
            return
        }
        guard configurations.count < Self.maximumConfigurations else {
            errorMessage = "You can configure up to \(Self.maximumConfigurations) daily limits."
            return
        }

        let configuration = DailyLimitConfiguration(
            selection: selection,
            dailyLimitMinutes: minutes
        )
        configurations.append(configuration)
        persistAndRestartIfNeeded()
    }

    func remove(_ configuration: DailyLimitConfiguration) {
        guard canModifyLimits() else { return }
        configurations.removeAll { $0.id == configuration.id }
        persistAndRestartIfNeeded()
    }

    func setEnabled(_ enabled: Bool, for configuration: DailyLimitConfiguration) {
        guard canModifyLimits() else { return }
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index].isEnabled = enabled
        persistAndRestartIfNeeded()
    }

    func updateMinutes(_ minutes: Int, for configuration: DailyLimitConfiguration) {
        guard canModifyLimits() else { return }
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index].dailyLimitMinutes = min(max(minutes, 5), 240)
        persistAndRestartIfNeeded()
    }

    func startMonitoring() {
        guard canModifyLimits() else { return }
        startMonitoring(resetReachedState: true)
    }

    private func startMonitoring(resetReachedState: Bool) {
        let active = configurations.filter(\.isEnabled)
        guard !active.isEmpty else {
            errorMessage = "Add a daily limit before starting the monitor."
            return
        }

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: 0, minute: 0),
            intervalEnd: DateComponents(hour: 23, minute: 59),
            repeats: true
        )
        let events = Dictionary(uniqueKeysWithValues: active.map { configuration in
            (
                NoxaDeviceActivityConfiguration.dailyLimitEventName(for: configuration.id),
                DeviceActivityEvent(
                    applications: configuration.selection.applicationTokens,
                    categories: configuration.selection.categoryTokens,
                    webDomains: configuration.selection.webDomainTokens,
                    threshold: DateComponents(minute: configuration.dailyLimitMinutes)
                )
            )
        })

        do {
            let defaults = UserDefaults(suiteName: AppGroupStore.suiteName)
            let today = NoxaDeviceActivityConfiguration.dailyLimitDayStamp()
            let startsNewDay = defaults?.string(
                forKey: NoxaDeviceActivityConfiguration.dailyLimitResetDayKey
            ) != today
            let shouldResetReachedState = resetReachedState || startsNewDay

            center.stopMonitoring([NoxaDeviceActivityConfiguration.dailyLimitActivityName])
            if shouldResetReachedState {
                settingsStore.clearAllSettings()
                isShieldActive = false
                defaults?.removeObject(forKey: NoxaDeviceActivityConfiguration.dailyLimitReachedEventsKey)
            } else {
                let reachedEventNames = Set(
                    defaults?.stringArray(
                        forKey: NoxaDeviceActivityConfiguration.dailyLimitReachedEventsKey
                    ) ?? []
                )
                let retainedEventNames = NoxaDeviceActivityConfiguration.retainedDailyLimitEventNames(
                    configurations: active,
                    reachedEventNames: reachedEventNames
                )
                defaults?.set(
                    Array(retainedEventNames),
                    forKey: NoxaDeviceActivityConfiguration.dailyLimitReachedEventsKey
                )
                applyDailyLimitShields(
                    configurations: active,
                    reachedEventNames: retainedEventNames
                )
            }
            defaults?.set(today, forKey: NoxaDeviceActivityConfiguration.dailyLimitResetDayKey)
            try center.startMonitoring(
                NoxaDeviceActivityConfiguration.dailyLimitActivityName,
                during: schedule,
                events: events
            )
            defaults?.set(today, forKey: NoxaDeviceActivityConfiguration.dailyLimitHardLockDayKey)
            isMonitoring = true
            errorMessage = nil
            logger.info("Started daily limit monitor for \(active.count) configuration(s)")
        } catch {
            isMonitoring = false
            errorMessage = "Could not start daily limits: \(error.localizedDescription)"
            logger.error("Daily limit monitor failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopMonitoring(force: Bool = false) {
        if !force {
            guard canModifyLimits() else { return }
        }
        center.stopMonitoring([NoxaDeviceActivityConfiguration.dailyLimitActivityName])
        settingsStore.clearAllSettings()
        let defaults = UserDefaults(suiteName: AppGroupStore.suiteName)
        defaults?.removeObject(forKey: NoxaDeviceActivityConfiguration.dailyLimitReachedEventsKey)
        defaults?.removeObject(forKey: NoxaDeviceActivityConfiguration.dailyLimitResetDayKey)
        defaults?.removeObject(forKey: NoxaDeviceActivityConfiguration.dailyLimitHardLockDayKey)
        isMonitoring = false
        isShieldActive = false
        errorMessage = nil
        logger.info("Stopped daily limit monitor")
    }

    func clearConfigurations() {
        stopMonitoring(force: true)
        configurations = []
        store.clearDailyLimitConfigurations()
        if var snapshot = try? store.loadSnapshot() {
            snapshot.dailyLimits = []
            try? store.saveSnapshot(snapshot)
        }
    }

    private func persistAndRestartIfNeeded() {
        do {
            try store.saveDailyLimitConfigurations(configurations)
            var snapshot = (try store.loadSnapshot()) ?? NoxaLocalSnapshot()
            snapshot.dailyLimits = configurations
            try store.saveSnapshot(snapshot)
            if isMonitoring {
                if configurations.contains(where: \.isEnabled) {
                    startMonitoring(resetReachedState: false)
                } else {
                    stopMonitoring()
                }
            }
        } catch {
            errorMessage = "Could not save daily limits: \(error.localizedDescription)"
            logger.error("Daily limit persistence failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func canModifyLimits() -> Bool {
        if isLockedForFocusSession {
            errorMessage = "Daily limits cannot be changed during a focus session."
            return false
        }
        if isHardLimitLocked {
            errorMessage = "Hard daily limits are locked until tomorrow."
            return false
        }
        return true
    }

    private func applyDailyLimitShields(
        configurations: [DailyLimitConfiguration],
        reachedEventNames: Set<String>
    ) {
        let reachedConfigurations = configurations.filter { configuration in
            reachedEventNames.contains(
                NoxaDeviceActivityConfiguration.dailyLimitEventName(for: configuration.id).rawValue
            )
        }

        var applications = Set<ApplicationToken>()
        var categories = Set<ActivityCategoryToken>()
        var webDomains = Set<WebDomainToken>()
        for configuration in reachedConfigurations {
            applications.formUnion(configuration.selection.applicationTokens)
            categories.formUnion(configuration.selection.categoryTokens)
            webDomains.formUnion(configuration.selection.webDomainTokens)
        }

        settingsStore.shield.applications = applications.isEmpty ? nil : applications
        settingsStore.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        settingsStore.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        isShieldActive = !applications.isEmpty || !categories.isEmpty || !webDomains.isEmpty
    }
}

/// Keeps selected apps unavailable except during a user-defined daily window.
/// Each half of a schedule has its own ManagedSettings store so overlapping
/// schedules cannot accidentally clear one another's shields.
@MainActor
final class RestrictionScheduleService: ObservableObject {
    static let maximumConfigurations = 8

    @Published private(set) var configurations: [RestrictionScheduleConfiguration]
    @Published private(set) var errorMessage: String?

    private let store: AppGroupStore
    private let center = DeviceActivityCenter()
    private let logger = Logger(subsystem: "LycheeCorp.Noxa", category: "schedules")

    init(store: AppGroupStore? = nil) {
        self.store = store ?? AppGroupStore.shared
        configurations = (try? self.store.loadRestrictionSchedules()) ?? []
    }

    var enabledCount: Int {
        configurations.filter(\.isEnabled).count
    }

    func add(selection: FamilyActivitySelection, allowedStart: Date, allowedEnd: Date) {
        guard !store.hasActiveFocusSession() else {
            errorMessage = "Schedules cannot be changed during a focus session."
            return
        }
        guard !selection.applicationTokens.isEmpty else {
            errorMessage = "Select at least one app for this schedule."
            return
        }
        guard configurations.count < Self.maximumConfigurations else {
            errorMessage = "You can create up to \(Self.maximumConfigurations) schedules."
            return
        }

        let calendar = Calendar.autoupdatingCurrent
        let start = Self.minutesSinceMidnight(allowedStart, calendar: calendar)
        let end = Self.minutesSinceMidnight(allowedEnd, calendar: calendar)
        guard end - start >= 15 else {
            errorMessage = "The allowed window must be at least 15 minutes and end later the same day."
            return
        }

        configurations.append(
            RestrictionScheduleConfiguration(
                selection: selection,
                allowedStartMinutes: start,
                allowedEndMinutes: end
            )
        )
        persistAndReschedule()
    }

    func setEnabled(_ enabled: Bool, for configuration: RestrictionScheduleConfiguration) {
        guard !store.hasActiveFocusSession() else {
            errorMessage = "Schedules cannot be changed during a focus session."
            return
        }
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index].isEnabled = enabled
        persistAndReschedule()
    }

    func remove(_ configuration: RestrictionScheduleConfiguration) {
        guard !store.hasActiveFocusSession() else {
            errorMessage = "Schedules cannot be changed during a focus session."
            return
        }
        stop(configuration)
        configurations.removeAll { $0.id == configuration.id }
        persistAndReschedule()
    }

    func rescheduleAll() {
        errorMessage = nil
        for configuration in configurations {
            stop(configuration)
            guard configuration.isEnabled else { continue }
            do {
                try start(configuration)
                applyCurrentShield(for: configuration)
            } catch {
                stop(configuration)
                errorMessage = "Could not start a schedule: \(error.localizedDescription)"
                logger.error("Schedule start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func clearConfigurations() {
        configurations.forEach(stop)
        configurations = []
        store.clearRestrictionSchedules()
        errorMessage = nil
    }

    private func persistAndReschedule() {
        do {
            try store.saveRestrictionSchedules(configurations)
            rescheduleAll()
        } catch {
            errorMessage = "Could not save schedules: \(error.localizedDescription)"
        }
    }

    private func start(_ configuration: RestrictionScheduleConfiguration) throws {
        let beforeName = NoxaDeviceActivityConfiguration.scheduleActivityName(for: configuration.id, segment: "before")
        let afterName = NoxaDeviceActivityConfiguration.scheduleActivityName(for: configuration.id, segment: "after")
        let start = Self.components(for: configuration.allowedStartMinutes)
        let end = Self.components(for: configuration.allowedEndMinutes)

        try center.startMonitoring(
            beforeName,
            during: DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0),
                intervalEnd: start,
                repeats: true
            )
        )
        try center.startMonitoring(
            afterName,
            during: DeviceActivitySchedule(
                intervalStart: end,
                intervalEnd: DateComponents(hour: 23, minute: 59),
                repeats: true
            )
        )
    }

    private func stop(_ configuration: RestrictionScheduleConfiguration) {
        let names = [
            NoxaDeviceActivityConfiguration.scheduleActivityName(for: configuration.id, segment: "before"),
            NoxaDeviceActivityConfiguration.scheduleActivityName(for: configuration.id, segment: "after")
        ]
        center.stopMonitoring(names)
        for name in names {
            ManagedSettingsStore(named: ManagedSettingsStore.Name(name.rawValue)).clearAllSettings()
        }
    }

    private func applyCurrentShield(for configuration: RestrictionScheduleConfiguration) {
        let now = Self.minutesSinceMidnight(Date(), calendar: .autoupdatingCurrent)
        let segment: String?
        if now < configuration.allowedStartMinutes {
            segment = "before"
        } else if now >= configuration.allowedEndMinutes {
            segment = "after"
        } else {
            segment = nil
        }
        guard let segment else { return }
        let name = NoxaDeviceActivityConfiguration.scheduleActivityName(for: configuration.id, segment: segment)
        let settings = ManagedSettingsStore(named: ManagedSettingsStore.Name(name.rawValue))
        settings.shield.applications = configuration.selection.applicationTokens
        settings.shield.applicationCategories = configuration.selection.categoryTokens.isEmpty
            ? nil
            : .specific(configuration.selection.categoryTokens)
        settings.shield.webDomains = configuration.selection.webDomainTokens.isEmpty
            ? nil
            : configuration.selection.webDomainTokens
    }

    private static func minutesSinceMidnight(_ date: Date, calendar: Calendar) -> Int {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func components(for minutes: Int) -> DateComponents {
        DateComponents(hour: minutes / 60, minute: minutes % 60)
    }
}
