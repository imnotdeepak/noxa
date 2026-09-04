//
//  FocusSessionService.swift
//  Noxa
//

import Combine
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import os

/// Coordinates a timed focus session between the main app and the monitor
/// extension. The extension owns the scheduled end so cleanup does not depend
/// on the SwiftUI process staying alive.
@MainActor
final class FocusSessionService: ObservableObject {
    @Published private(set) var activeSession: ActiveSessionRecord?
    @Published private(set) var history: [ActiveSessionRecord]
    @Published private(set) var errorMessage: String?

    private let store: AppGroupStore
    private let center = DeviceActivityCenter()
    private let settingsStore = ManagedSettingsStore(named: ManagedSettingsStore.Name("noxa.validation"))
    private let logger = Logger(subsystem: "LycheeCorp.Noxa", category: "session")
    private var reconciliationTask: Task<Void, Never>?

    init(store: AppGroupStore? = nil) {
        self.store = store ?? AppGroupStore.shared
        let snapshot = try? self.store.loadSnapshot()
        activeSession = snapshot?.activeSession
        history = snapshot?.sessionHistory ?? []
        if activeSession?.outcome != .active {
            activeSession = nil
        }
    }

    var isActive: Bool {
        activeSession != nil
    }

    var completedSessionCount: Int {
        history.filter { $0.outcome.countsTowardFocusStatistics }.count
    }

    var completedFocusMinutes: Int {
        history
            .filter { $0.outcome.countsTowardFocusStatistics }
            .reduce(0) { $0 + (($1.actualDurationSeconds ?? $1.plannedDurationSeconds) / 60) }
    }

    var endTimeDescription: String? {
        guard let activeSession else { return nil }
        return activeSession.plannedEndAt.formatted(date: .omitted, time: .shortened)
    }

    /// Starts a session atomically from the product's point of view: a pending
    /// intent is persisted before restrictions are touched, and only a fully
    /// configured shield plus schedule becomes active. DeviceActivity requires
    /// a minimum 15-minute interval, so shorter requests are rejected by the
    /// platform and are clamped to that minimum here.
    func start(
        selection: FamilyActivitySelection,
        websiteDomains: [String] = [],
        durationMinutes: Int = 15
    ) {
        guard activeSession == nil else {
            errorMessage = "A focus session is already active."
            return
        }
        guard !selection.applicationTokens.isEmpty
            || !selection.categoryTokens.isEmpty
            || !selection.webDomainTokens.isEmpty
            || !websiteDomains.isEmpty else {
            errorMessage = "Choose something to restrict before starting a session."
            return
        }

        errorMessage = nil
        let startedAt = Date()
        let duration = max(
            NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes,
            durationMinutes
        ) * 60
        let record = ActiveSessionRecord(
            startedAt: startedAt,
            plannedEndAt: startedAt.addingTimeInterval(TimeInterval(duration)),
            plannedDurationSeconds: duration
        )

        do {
            try store.saveFamilyActivitySelection(selection)
            try saveSnapshot(engineState: .starting, session: record)
            applyShield(selection, websiteDomains: websiteDomains)
            try schedule(record: record)

            var activeRecord = record
            activeRecord.outcome = .active
            activeRecord.lastRestrictionApplicationAt = Date()
            try saveSnapshot(engineState: .active, session: activeRecord)
            activeSession = activeRecord
            scheduleReconciliation(for: activeRecord)
            logger.info("Started focus session \(activeRecord.id.uuidString, privacy: .public)")
        } catch {
            center.stopMonitoring([NoxaDeviceActivityConfiguration.focusActivityName])
            settingsStore.clearAllSettings()
            let failedRecord = record
            try? saveSnapshot(engineState: .idle, session: failedRecord, outcome: .failedToStart)
            errorMessage = "Could not start the focus session: \(error.localizedDescription)"
            logger.error("Focus session start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func endEarly() {
        guard let activeSession else { return }
        reconciliationTask?.cancel()
        errorMessage = nil
        let endedAt = Date()

        do {
            try saveSnapshot(engineState: .ending, session: activeSession)
        } catch {
            errorMessage = "Could not record the session ending: \(error.localizedDescription)"
        }

        center.stopMonitoring([NoxaDeviceActivityConfiguration.focusActivityName])
        settingsStore.clearAllSettings()

        var endedRecord = activeSession
        endedRecord.outcome = .endedEarly
        endedRecord.actualDurationSeconds = Self.measuredDurationSeconds(
            startedAt: endedRecord.startedAt,
            endedAt: endedAt,
            plannedDurationSeconds: endedRecord.plannedDurationSeconds
        )
        endedRecord.lastCleanupAttemptAt = endedAt
        do {
            try saveSnapshot(engineState: .idle, session: endedRecord)
            self.activeSession = nil
            logger.info("Ended focus session early \(endedRecord.id.uuidString, privacy: .public)")
        } catch {
            errorMessage = "Restrictions were removed, but session cleanup could not be recorded: \(error.localizedDescription)"
        }
    }

    /// Reconciles persisted intent with the current time and the system's
    /// scheduled activity. Call this at launch and after returning foreground.
    func reconcile(recoverStale: Bool = true) {
        guard let snapshot = try? store.loadSnapshot() else {
            activeSession = nil
            history = []
            return
        }
        history = snapshot.sessionHistory

        guard let session = snapshot.activeSession else {
            activeSession = nil
            return
        }

        guard session.outcome == .active else {
            activeSession = nil
            return
        }

        if session.plannedEndAt <= Date() {
            finish(session: session, recovered: recoverStale)
            return
        }

        activeSession = session
        if !center.activities.contains(NoxaDeviceActivityConfiguration.focusActivityName) {
            do {
                try schedule(record: session)
            } catch {
                errorMessage = "The active session needs attention: \(error.localizedDescription)"
                return
            }
        }

        if let selection = try? store.loadFamilyActivitySelection() {
            let domains = (try? store.loadWebsiteBlocklist()) ?? []
            applyShield(selection, websiteDomains: domains)
        }
        scheduleReconciliation(for: session)
    }

    /// Replaces account-scoped history after cloud hydration while preserving
    /// the active device-local session and enforcement state.
    func replaceHistory(_ records: [ActiveSessionRecord]) {
        var recordsByID: [UUID: ActiveSessionRecord] = [:]
        for record in records {
            recordsByID[record.id] = record
        }
        let normalized = Array(
            recordsByID.values.sorted { $0.startedAt > $1.startedAt }.prefix(100)
        )
        guard normalized != history else { return }

        do {
            var snapshot = (try store.loadSnapshot()) ?? NoxaLocalSnapshot()
            snapshot.sessionHistory = normalized
            try store.saveSnapshot(snapshot)
            history = normalized
        } catch {
            errorMessage = "Could not save synchronized focus history: \(error.localizedDescription)"
        }
    }

    func clearAllLocalData() {
        reconciliationTask?.cancel()
        center.stopMonitoring([NoxaDeviceActivityConfiguration.focusActivityName])
        settingsStore.clearAllSettings()
        activeSession = nil
        history = []
        errorMessage = nil
        store.clearSnapshot()
    }

    private func schedule(record: ActiveSessionRecord) throws {
        // DeviceActivity invokes intervalDidStart immediately when the
        // current date falls inside the scheduled interval. Starting at the
        // current wall-clock time lets the main app apply the shield now while
        // still giving the system a full 15-minute interval to schedule.
        let start = Date()
        guard record.plannedEndAt > start else {
            throw FocusSessionError.sessionEndInPast
        }

        let calendar = Calendar.current
        let startComponents = calendar.dateComponents(
            [.calendar, .year, .month, .day, .hour, .minute, .second],
            from: start
        )
        let endComponents = calendar.dateComponents(
            [.calendar, .year, .month, .day, .hour, .minute, .second],
            from: record.plannedEndAt
        )
        let schedule = DeviceActivitySchedule(
            intervalStart: startComponents,
            intervalEnd: endComponents,
            repeats: false
        )
        try center.startMonitoring(
            NoxaDeviceActivityConfiguration.focusActivityName,
            during: schedule
        )
    }

    private func applyShield(_ selection: FamilyActivitySelection, websiteDomains: [String]) {
        settingsStore.shield.applications = selection.applicationTokens.isEmpty
            ? nil
            : selection.applicationTokens
        settingsStore.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        settingsStore.shield.webDomains = selection.webDomainTokens.isEmpty
            ? nil
            : selection.webDomainTokens
        settingsStore.webContent.blockedByFilter = websiteDomains.isEmpty
            ? nil
            : .specific(Set(websiteDomains.map(WebDomain.init(domain:))))
    }

    private func scheduleReconciliation(for session: ActiveSessionRecord) {
        reconciliationTask?.cancel()
        reconciliationTask = Task { [weak self] in
            let interval = max(1, session.plannedEndAt.timeIntervalSinceNow)
            try? await Task.sleep(for: .seconds(interval))
            guard !Task.isCancelled else { return }
            self?.reconcile(recoverStale: false)
        }
    }

    private func finish(session: ActiveSessionRecord, recovered: Bool) {
        reconciliationTask?.cancel()
        center.stopMonitoring([NoxaDeviceActivityConfiguration.focusActivityName])
        settingsStore.clearAllSettings()

        var completedRecord = session
        completedRecord.outcome = recovered ? .recoveredStale : .completed
        completedRecord.actualDurationSeconds = completedRecord.plannedDurationSeconds
        completedRecord.lastCleanupAttemptAt = Date()
        do {
            try saveSnapshot(engineState: .idle, session: completedRecord)
            activeSession = nil
            history = (try? store.loadSnapshot())?.sessionHistory ?? history
            logger.info("Finished focus session \(completedRecord.id.uuidString, privacy: .public)")
        } catch {
            errorMessage = "Restrictions were removed, but session reconciliation failed: \(error.localizedDescription)"
        }
    }

    private func saveSnapshot(
        engineState: SessionEngineState,
        session: ActiveSessionRecord,
        outcome: SessionOutcome? = nil
    ) throws {
        var snapshot = (try store.loadSnapshot()) ?? NoxaLocalSnapshot()
        var savedSession = session
        if let outcome {
            savedSession.outcome = outcome
        }
        snapshot.sessionEngineState = engineState
        snapshot.activeSession = savedSession
        if [.completed, .endedEarly, .failedToStart, .interrupted, .recoveredStale].contains(savedSession.outcome) {
            snapshot.sessionHistory.removeAll { $0.id == savedSession.id }
            snapshot.sessionHistory.insert(savedSession, at: 0)
            snapshot.sessionHistory = Array(snapshot.sessionHistory.prefix(100))
        }
        try store.saveSnapshot(snapshot)
        history = snapshot.sessionHistory
    }

    static func measuredDurationSeconds(
        startedAt: Date,
        endedAt: Date,
        plannedDurationSeconds: Int
    ) -> Int {
        max(0, min(plannedDurationSeconds, Int(endedAt.timeIntervalSince(startedAt))))
    }
}

private enum FocusSessionError: LocalizedError {
    case sessionEndInPast

    var errorDescription: String? {
        "The requested session duration is too short to schedule."
    }
}
