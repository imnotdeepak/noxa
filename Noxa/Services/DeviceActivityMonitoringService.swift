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
    static let pomodoroWorkActivityPrefix = "noxa.pomodoro.work"
    static let dailyLimitActivityName = DeviceActivityName("noxa.daily.limits")
    static let scheduleActivityPrefix = "noxa.schedule"
    static let dailyLimitReachedEventsKey = "noxa.dailyLimitReachedEvents"
    static let dailyLimitResetDayKey = "noxa.dailyLimitResetDay"
    static let scheduleRelaxationActivityPrefix = "noxa.schedule.relax"
    static let minimumFocusSessionMinutes = 15
    static let maximumFocusSessionMinutes = 480
    static let maximumStrictFocusSessionMinutes = 240

    static func dailyLimitEventName(for id: UUID) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("noxa.daily.limit.\(id.uuidString.lowercased())")
    }

    static func scheduleActivityName(for id: UUID, segment: String) -> DeviceActivityName {
        DeviceActivityName("\(scheduleActivityPrefix).\(segment).\(id.uuidString.lowercased())")
    }

    static func pomodoroWorkActivityName(cycleID: UUID, round: Int) -> DeviceActivityName {
        DeviceActivityName("\(pomodoroWorkActivityPrefix).\(cycleID.uuidString.lowercased()).\(round)")
    }

    static func scheduleRelaxationActivityName(for id: UUID) -> DeviceActivityName {
        DeviceActivityName("\(scheduleRelaxationActivityPrefix).\(id.uuidString.lowercased())")
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
        ManagedSettingsStore(named: RestrictionStoreNames.legacy).clearAllSettings()
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
        reconcileDayBoundary()
    }

    var enabledCount: Int {
        configurations.filter(\.isEnabled).count
    }

    func add(selection: FamilyActivitySelection, minutes: Int) {
        errorMessage = nil
        guard !selection.applicationTokens.isEmpty else {
            errorMessage = "Select at least one app for a daily limit."
            return
        }
        let existingSelection = configurations.reduce(into: FamilyActivitySelection()) { combined, configuration in
            combined.applicationTokens.formUnion(configuration.selection.applicationTokens)
            combined.categoryTokens.formUnion(configuration.selection.categoryTokens)
            combined.webDomainTokens.formUnion(configuration.selection.webDomainTokens)
        }
        guard selection.applicationTokens.isDisjoint(with: existingSelection.applicationTokens),
              selection.categoryTokens.isDisjoint(with: existingSelection.categoryTokens),
              selection.webDomainTokens.isDisjoint(with: existingSelection.webDomainTokens) else {
            errorMessage = "One or more selected apps already has a daily limit."
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
        configurations.removeAll { $0.id == configuration.id }
        persistAndRestartIfNeeded()
    }

    func setEnabled(_ enabled: Bool, for configuration: DailyLimitConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index].isEnabled = enabled
        persistAndRestartIfNeeded()
    }

    func updateMinutes(_ minutes: Int, for configuration: DailyLimitConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index].dailyLimitMinutes = min(max(minutes, 5), 240)
        persistAndRestartIfNeeded()
    }

    func startMonitoring() {
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
                dailyLimitEvent(for: configuration)
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
            isMonitoring = true
            errorMessage = nil
            logger.info("Started daily limit monitor for \(active.count) configuration(s)")
        } catch {
            isMonitoring = false
            errorMessage = "Could not start daily limits: \(error.localizedDescription)"
            logger.error("Daily limit monitor failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func stopMonitoring() {
        center.stopMonitoring([NoxaDeviceActivityConfiguration.dailyLimitActivityName])
        settingsStore.clearAllSettings()
        let defaults = UserDefaults(suiteName: AppGroupStore.suiteName)
        defaults?.removeObject(forKey: NoxaDeviceActivityConfiguration.dailyLimitReachedEventsKey)
        defaults?.removeObject(forKey: NoxaDeviceActivityConfiguration.dailyLimitResetDayKey)
        isMonitoring = false
        isShieldActive = false
        errorMessage = nil
        logger.info("Stopped daily limit monitor")
    }

    func clearConfigurations() {
        stopMonitoring()
        configurations = []
        store.clearDailyLimitConfigurations()
        if var snapshot = try? store.loadSnapshot() {
            snapshot.dailyLimits = []
            try? store.saveSnapshot(snapshot)
        }
    }

    /// Re-registers an existing monitor after an app update while preserving
    /// any limits already reached today. This also upgrades older events to
    /// include activity recorded before Noxa started monitoring.
    func rescheduleActiveMonitoring() {
        reconcileDayBoundary()
        guard isMonitoring, configurations.contains(where: \.isEnabled) else { return }
        // Re-registering an already-running monitor is maintenance, not a new
        // user commitment. Do not renew yesterday's hard lock on app launch.
        startMonitoring(resetReachedState: false)
    }

    /// Clears yesterday's reached-limit state when the app crosses local
    /// midnight. The repeating DeviceActivity monitor remains registered, so
    /// today's usage begins counting again without relocking configuration.
    func reconcileDayBoundary(now: Date = Date()) {
        guard isMonitoring else { return }

        let defaults = UserDefaults(suiteName: AppGroupStore.suiteName)
        let today = NoxaDeviceActivityConfiguration.dailyLimitDayStamp(for: now)
        guard defaults?.string(
            forKey: NoxaDeviceActivityConfiguration.dailyLimitResetDayKey
        ) != today else {
            isShieldActive = settingsStore.shield.applications != nil
                || settingsStore.shield.applicationCategories != nil
                || settingsStore.shield.webDomains != nil
            return
        }

        settingsStore.clearAllSettings()
        defaults?.removeObject(forKey: NoxaDeviceActivityConfiguration.dailyLimitReachedEventsKey)
        defaults?.set(today, forKey: NoxaDeviceActivityConfiguration.dailyLimitResetDayKey)
        isShieldActive = false
        logger.info("Reset daily limit state at the local day boundary")
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

    private func dailyLimitEvent(for configuration: DailyLimitConfiguration) -> DeviceActivityEvent {
        if #available(iOS 17.4, *) {
            return DeviceActivityEvent(
                applications: configuration.selection.applicationTokens,
                categories: configuration.selection.categoryTokens,
                webDomains: configuration.selection.webDomainTokens,
                threshold: DateComponents(minute: configuration.dailyLimitMinutes),
                includesPastActivity: true
            )
        }

        return DeviceActivityEvent(
            applications: configuration.selection.applicationTokens,
            categories: configuration.selection.categoryTokens,
            webDomains: configuration.selection.webDomainTokens,
            threshold: DateComponents(minute: configuration.dailyLimitMinutes)
        )
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

/// Previous daily-window implementation retained while the versioned schedule
/// migration is validated on a physical device. The app uses
/// RestrictionScheduleService in RestrictionScheduleServiceV2.swift.
@MainActor
final class LegacyRestrictionScheduleService: ObservableObject {
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

    var nextPendingRelaxationDate: Date? {
        configurations.compactMap(\.pendingRelaxation?.effectiveAt).min()
    }

    func clearError() {
        errorMessage = nil
    }

    func rename(_ configuration: RestrictionScheduleConfiguration, to name: String) {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Give this schedule a name."
            return
        }
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index].name = trimmedName
        do {
            try store.saveRestrictionSchedules(configurations)
        } catch {
            errorMessage = "Could not rename the schedule: \(error.localizedDescription)"
        }
    }

    func add(name: String, selection: FamilyActivitySelection, allowedStart: Date, allowedEnd: Date) {
        errorMessage = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Give this schedule a name."
            return
        }
        guard !selection.applicationTokens.isEmpty
                || !selection.categoryTokens.isEmpty
                || !selection.webDomainTokens.isEmpty else {
            errorMessage = "Select an app, category, or website for this schedule."
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
                name: trimmedName,
                selection: selection,
                allowedStartMinutes: start,
                allowedEndMinutes: end
            )
        )
        persistAndReschedule()
    }

    func setEnabled(_ enabled: Bool, for configuration: RestrictionScheduleConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index].isEnabled = enabled
        configurations[index].pendingRelaxation = nil
        persistAndReschedule()
    }

    func remove(_ configuration: RestrictionScheduleConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        stop(configuration)
        configurations.remove(at: index)
        persistAndReschedule()
    }

    func cancelPendingRelaxation(for configuration: RestrictionScheduleConfiguration) {
        guard let index = configurations.firstIndex(where: { $0.id == configuration.id }) else { return }
        configurations[index].pendingRelaxation = nil
        persistAndReschedule()
    }

    func requestDisableAll() {
        var didChange = false
        for index in configurations.indices
        where configurations[index].isEnabled {
            configurations[index].isEnabled = false
            configurations[index].pendingRelaxation = nil
            didChange = true
        }
        guard didChange else { return }
        persistAndReschedule()
    }

    func rescheduleAll() {
        errorMessage = nil
        applyMaturedRelaxations()
        removeOrphanedActivities()
        for configuration in configurations {
            stop(configuration)
            guard configuration.isEnabled else { continue }
            do {
                try start(configuration)
                applyCurrentShield(for: configuration)
                do {
                    try startRelaxationMonitor(for: configuration)
                } catch {
                    logger.error("Pending schedule change monitor failed: \(error.localizedDescription, privacy: .public)")
                }
            } catch {
                stop(configuration)
                errorMessage = "Could not start a schedule: \(error.localizedDescription)"
                logger.error("Schedule start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func reconcile() {
        do {
            configurations = try store.loadRestrictionSchedules()
            rescheduleAll()
        } catch {
            errorMessage = "Could not load schedules: \(error.localizedDescription)"
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

    private func startRelaxationMonitor(for configuration: RestrictionScheduleConfiguration) throws {
        guard let pending = configuration.pendingRelaxation,
              pending.effectiveAt > Date() else { return }
        let calendar = Calendar.autoupdatingCurrent
        let intervalEnd = calendar.date(
            byAdding: .minute,
            value: 15,
            to: pending.effectiveAt
        ) ?? pending.effectiveAt.addingTimeInterval(15 * 60)
        let relaxationName = NoxaDeviceActivityConfiguration.scheduleRelaxationActivityName(
            for: configuration.id
        )
        try center.startMonitoring(
            relaxationName,
            during: DeviceActivitySchedule(
                intervalStart: Self.dateComponents(for: pending.effectiveAt, calendar: calendar),
                intervalEnd: Self.dateComponents(for: intervalEnd, calendar: calendar),
                repeats: false
            )
        )
    }

    private func stop(_ configuration: RestrictionScheduleConfiguration) {
        let names = [
            NoxaDeviceActivityConfiguration.scheduleActivityName(for: configuration.id, segment: "before"),
            NoxaDeviceActivityConfiguration.scheduleActivityName(for: configuration.id, segment: "after"),
            NoxaDeviceActivityConfiguration.scheduleRelaxationActivityName(for: configuration.id)
        ]
        center.stopMonitoring(names)
        for name in names {
            ManagedSettingsStore(named: ManagedSettingsStore.Name(name.rawValue)).clearAllSettings()
        }
    }

    private func applyCurrentShield(for configuration: RestrictionScheduleConfiguration) {
        if let pending = configuration.pendingRelaxation,
           pending.effectiveAt <= Date() {
            return
        }
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
        settings.shield.applications = configuration.selection.applicationTokens.isEmpty
            ? nil
            : configuration.selection.applicationTokens
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

    private static func dateComponents(for date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    }

    private func applyMaturedRelaxations(now: Date = Date()) {
        var changed = false
        configurations = configurations.compactMap { configuration in
            guard let pending = configuration.pendingRelaxation,
                  pending.effectiveAt <= now else {
                return configuration
            }

            changed = true
            switch pending.action {
            case .remove:
                stop(configuration)
                return nil
            case .disable:
                var updated = configuration
                updated.isEnabled = false
                updated.pendingRelaxation = nil
                return updated
            }
        }

        guard changed else { return }
        do {
            try store.saveRestrictionSchedules(configurations)
        } catch {
            errorMessage = "A pending schedule change could not be saved: \(error.localizedDescription)"
        }
    }

    private func removeOrphanedActivities() {
        let expectedNames = Set(configurations.flatMap { configuration in
            [
                NoxaDeviceActivityConfiguration.scheduleActivityName(for: configuration.id, segment: "before"),
                NoxaDeviceActivityConfiguration.scheduleActivityName(for: configuration.id, segment: "after"),
                NoxaDeviceActivityConfiguration.scheduleRelaxationActivityName(for: configuration.id)
            ]
        })
        let staleNames = center.activities.filter { activity in
            activity.rawValue.hasPrefix(NoxaDeviceActivityConfiguration.scheduleActivityPrefix)
                && !expectedNames.contains(activity)
        }
        guard !staleNames.isEmpty else { return }
        center.stopMonitoring(staleNames)
        for name in staleNames {
            ManagedSettingsStore(named: ManagedSettingsStore.Name(name.rawValue)).clearAllSettings()
        }
    }
}
