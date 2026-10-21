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
    @Published private(set) var activeIntention: String?
    @Published private(set) var strictModeEnabled: Bool
    @Published private(set) var hasOfferedStrictMode: Bool
    @Published private(set) var pomodoroCycle: PomodoroCycleRecord?
    @Published private(set) var completedPomodoroCycleID: UUID?

    private let store: AppGroupStore
    private let center = DeviceActivityCenter()
    private let authorizationCenter = AuthorizationCenter.shared
    private let settingsStore = ManagedSettingsStore(named: RestrictionStoreNames.focus)
    private let logger = Logger(subsystem: "LycheeCorp.Noxa", category: "session")
    private var reconciliationTask: Task<Void, Never>?

    init(store: AppGroupStore? = nil) {
        self.store = store ?? AppGroupStore.shared
        strictModeEnabled = self.store.isStrictModeEnabled
        hasOfferedStrictMode = self.store.hasOfferedStrictMode
        pomodoroCycle = (try? self.store.loadPomodoroCycle()) ?? nil
        completedPomodoroCycleID = self.store.pendingPomodoroCompletionID
        let snapshot = try? self.store.loadSnapshot()
        activeSession = snapshot?.activeSession
        history = snapshot?.sessionHistory ?? []
        activeIntention = ((try? self.store.loadFocusSessionRestrictions()) ?? nil)?.intention
        if activeSession?.outcome != .active {
            activeSession = nil
            activeIntention = nil
        }
    }

    var isActive: Bool {
        activeSession != nil
    }

    var isActiveSessionStrict: Bool {
        activeSession?.isStrict == true
    }

    func monitorReceipt(for session: ActiveSessionRecord) -> FocusMonitorReceipt? {
        guard let receipt = try? store.loadFocusMonitorReceipt(),
              receipt.sessionID == session.id else { return nil }
        return receipt
    }

    var hasPomodoroCycle: Bool { pomodoroCycle != nil }

    var pomodoroBreakEndsAt: Date? {
        guard let pomodoroCycle,
              case let .breakTime(_, endsAt) = pomodoroCycle.plan.phase(at: Date()) else {
            return nil
        }
        return endsAt
    }

    var pomodoroRoundDescription: String? {
        guard let pomodoroCycle else { return nil }
        switch pomodoroCycle.plan.phase(at: Date()) {
        case let .work(round, _): return "Round \(round) of 4"
        case let .breakTime(afterRound, _): return "Break after round \(afterRound)"
        case .scheduled: return "Starting soon"
        case .complete: return "Four rounds complete"
        }
    }

    func setStrictModeEnabled(_ enabled: Bool) {
        store.isStrictModeEnabled = enabled
        strictModeEnabled = enabled
    }

    func markStrictModeOffered() {
        store.hasOfferedStrictMode = true
        hasOfferedStrictMode = true
    }

    func acknowledgePomodoroCompletion() {
        store.pendingPomodoroCompletionID = nil
        completedPomodoroCycleID = nil
    }

    var completedSessionCount: Int {
        history.filter { $0.outcome.countsTowardFocusStatistics }.count
    }

    var pendingScheduleSuggestion: PendingScheduleSuggestion? {
        (try? store.loadPendingScheduleSuggestion()) ?? nil
    }

    func acknowledgeScheduleSuggestion() {
        store.hasOfferedScheduleSuggestion = true
        store.clearPendingScheduleSuggestion()
    }

    func discardScheduleSuggestion() {
        store.clearPendingScheduleSuggestion()
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
        durationMinutes: Int = 15,
        intention: String? = nil
    ) {
        guard Self.isAuthorizationApproved(authorizationCenter.authorizationStatus) else {
            errorMessage = "Screen Time access is required before starting a focus session."
            return
        }
        guard activeSession == nil else {
            errorMessage = "A focus session is already active."
            return
        }
        guard (try? store.loadPomodoroCycle()) == nil else {
            errorMessage = "Finish or stop the current Pomodoro before starting another session."
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
        let isStrict = strictModeEnabled
        let duration = Self.normalizedDurationMinutes(durationMinutes, strict: isStrict) * 60
        let record = ActiveSessionRecord(
            startedAt: startedAt,
            plannedEndAt: startedAt.addingTimeInterval(TimeInterval(duration)),
            plannedDurationSeconds: duration,
            isStrict: isStrict
        )
        let restrictionConfiguration = FocusSessionRestrictionConfiguration(
            selection: selection,
            websiteDomains: websiteDomains,
            intention: intention?.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        do {
            store.clearFocusMonitorReceipt()
            try store.saveFamilyActivitySelection(selection)
            try store.saveFocusSessionRestrictions(restrictionConfiguration)
            try saveSnapshot(engineState: .starting, session: record)
            applyShield(selection, websiteDomains: websiteDomains)
            try schedule(record: record)

            var activeRecord = record
            activeRecord.outcome = .active
            activeRecord.lastRestrictionApplicationAt = Date()
            try saveSnapshot(engineState: .active, session: activeRecord)
            activeSession = activeRecord
            activeIntention = restrictionConfiguration.intention
            if completedSessionCount == 0 && !store.hasOfferedScheduleSuggestion {
                try? store.savePendingScheduleSuggestion(PendingScheduleSuggestion(
                    selection: selection,
                    websiteDomains: websiteDomains,
                    startedAt: activeRecord.startedAt,
                    plannedEndAt: activeRecord.plannedEndAt
                ))
            }
            scheduleReconciliation(for: activeRecord)
            let selectionCount = selection.applicationTokens.count
                + selection.categoryTokens.count
                + selection.webDomainTokens.count
                + websiteDomains.count
            AnalyticsService.shared.capture(.focusStarted(
                durationMinutes: duration / 60,
                selectionCount: selectionCount
            ))
            logger.info("Started focus session \(activeRecord.id.uuidString, privacy: .public)")
        } catch {
            center.stopMonitoring([NoxaDeviceActivityConfiguration.focusActivityName])
            settingsStore.clearAllSettings()
            store.clearFocusSessionRestrictions()
            activeIntention = nil
            let failedRecord = record
            try? saveSnapshot(engineState: .idle, session: failedRecord, outcome: .failedToStart)
            errorMessage = "Could not start the focus session: \(error.localizedDescription)"
            logger.error("Focus session start failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func startPomodoro(
        selection: FamilyActivitySelection,
        websiteDomains: [String] = [],
        workMinutes: Int,
        breakMinutes: Int
    ) {
        guard pomodoroCycle == nil else {
            errorMessage = "A Pomodoro cycle is already in progress."
            return
        }
        let plan = PomodoroCyclePlan(
            startedAt: Date(),
            workMinutes: workMinutes,
            breakMinutes: breakMinutes
        )
        start(
            selection: selection,
            websiteDomains: websiteDomains,
            durationMinutes: plan.workMinutes,
            intention: "Pomodoro · \(plan.workMinutes)/\(plan.breakMinutes)"
        )
        guard let firstSession = activeSession else { return }

        let cycle = PomodoroCycleRecord(
            plan: PomodoroCyclePlan(
                startedAt: firstSession.startedAt,
                workMinutes: plan.workMinutes,
                breakMinutes: plan.breakMinutes
            ),
            selection: selection,
            websiteDomains: websiteDomains,
            isStrict: firstSession.isStrict,
            firstSessionID: firstSession.id
        )
        do {
            try store.savePomodoroCycle(cycle)
            try schedulePomodoroMonitors(for: cycle)
            store.markPomodoroRoundEnforced(
                cycleID: cycle.id,
                round: 1,
                at: firstSession.lastRestrictionApplicationAt ?? firstSession.startedAt
            )
            pomodoroCycle = cycle
            acknowledgePomodoroCompletion()
            schedulePomodoroBoundaryReconciliation(for: firstSession.plannedEndAt)
        } catch {
            stopPomodoroMonitors(for: cycle)
            store.clearPomodoroCycle()
            store.clearPomodoroRoundEnforcement(cycleID: cycle.id)
            pomodoroCycle = nil
            interrupt(
                session: firstSession,
                message: "The Pomodoro cycle could not be scheduled: \(error.localizedDescription)"
            )
        }
    }

    func endEarly() {
        guard let activeSession else { return }
        guard !activeSession.isStrict else {
            errorMessage = "Strict focus cannot end early. It ends at \(activeSession.plannedEndAt.formatted(date: .omitted, time: .shortened))."
            return
        }
        if let pomodoroCycle {
            stopPomodoroMonitors(for: pomodoroCycle)
            store.clearPomodoroCycle()
            store.clearPomodoroRoundEnforcement(cycleID: pomodoroCycle.id)
            self.pomodoroCycle = nil
        }
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
        store.clearFocusSessionRestrictions()
        if completedSessionCount == 0 { store.clearPendingScheduleSuggestion() }

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
            activeIntention = nil
            AnalyticsService.shared.capture(.focusEndedEarly(
                elapsedMinutes: (endedRecord.actualDurationSeconds ?? 0) / 60
            ))
            logger.info("Ended focus session early \(endedRecord.id.uuidString, privacy: .public)")
        } catch {
            errorMessage = "Restrictions were removed, but session cleanup could not be recorded: \(error.localizedDescription)"
        }
    }

    /// Reconciles persisted intent with the current time and the system's
    /// scheduled activity. Call this at launch and after returning foreground.
    func reconcile(recoverStale: Bool = true) {
        if let cycle = (try? store.loadPomodoroCycle()) ?? nil {
            pomodoroCycle = cycle
            if case .work(round: 1, _) = cycle.plan.phase(at: Date()) {
                // The first interval uses the existing focus activity and its
                // established recovery path below.
            } else {
                reconcilePomodoro(cycle)
                return
            }
        } else {
            pomodoroCycle = nil
        }
        guard let snapshot = try? store.loadSnapshot() else {
            activeSession = nil
            activeIntention = nil
            history = []
            return
        }
        history = snapshot.sessionHistory

        guard let session = snapshot.activeSession else {
            activeSession = nil
            activeIntention = nil
            return
        }

        // Authorization can be revoked in Settings while Noxa is suspended.
        // Apple's tokens are no longer enforceable after revocation, so do not
        // leave a persisted session looking active or keep the blocklist lock.
        if !Self.isAuthorizationApproved(authorizationCenter.authorizationStatus) {
            if session.outcome == .active {
                interrupt(
                    session: session,
                    message: "Screen Time access was revoked. Re-enable it to start another focus session."
                )
            } else if session.outcome == .startPending {
                failPendingSession(session)
            } else {
                activeSession = nil
            }
            return
        }

        guard session.outcome == .active else {
            if session.outcome == .startPending {
                // A process termination can happen after the pending intent
                // is persisted but before DeviceActivity accepts the
                // schedule. Treat that half-start as failed and remove any
                // shield it may have applied so the lock cannot linger.
                center.stopMonitoring([NoxaDeviceActivityConfiguration.focusActivityName])
                settingsStore.clearAllSettings()
                store.clearFocusSessionRestrictions()
                var failedSession = session
                failedSession.outcome = .failedToStart
                failedSession.lastCleanupAttemptAt = Date()
                try? saveSnapshot(engineState: .idle, session: failedSession)
            }
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
                interrupt(
                    session: session,
                    message: "The focus session could not be restored and was ended safely."
                )
                return
            }
        }

        if let configuration = (try? store.loadFocusSessionRestrictions()) ?? nil {
            activeIntention = configuration.intention
            applyShield(configuration.selection, websiteDomains: configuration.websiteDomains)
        } else if let selection = try? store.loadFamilyActivitySelection() {
            // Backward-compatible recovery for sessions created before the
            // immutable focus-session snapshot was introduced.
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
        if let pomodoroCycle {
            stopPomodoroMonitors(for: pomodoroCycle)
            store.clearPomodoroRoundEnforcement(cycleID: pomodoroCycle.id)
        }
        store.clearPomodoroCycle()
        store.pendingPomodoroCompletionID = nil
        pomodoroCycle = nil
        completedPomodoroCycleID = nil
        center.stopMonitoring([NoxaDeviceActivityConfiguration.focusActivityName])
        settingsStore.clearAllSettings()
        store.clearFocusSessionRestrictions()
        activeSession = nil
        activeIntention = nil
        history = []
        errorMessage = nil
        store.clearSnapshot()
        store.isStrictModeEnabled = false
        store.hasOfferedStrictMode = false
        store.hasOfferedScheduleSuggestion = false
        store.clearPendingScheduleSuggestion()
        strictModeEnabled = false
        hasOfferedStrictMode = false
    }

    func stopPomodoroDuringBreak() {
        guard let pomodoroCycle,
              case .breakTime = pomodoroCycle.plan.phase(at: Date()) else { return }
        reconciliationTask?.cancel()
        stopPomodoroMonitors(for: pomodoroCycle)
        store.clearPomodoroCycle()
        store.clearPomodoroRoundEnforcement(cycleID: pomodoroCycle.id)
        self.pomodoroCycle = nil
        settingsStore.clearAllSettings()
        store.clearFocusSessionRestrictions()
        if var snapshot = try? store.loadSnapshot() {
            snapshot.activeSession = nil
            snapshot.sessionEngineState = .idle
            try? store.saveSnapshot(snapshot)
        }
        activeSession = nil
        activeIntention = nil
        errorMessage = nil
    }

    private func schedulePomodoroMonitors(for cycle: PomodoroCycleRecord) throws {
        let calendar = Calendar.current
        for round in 2...PomodoroCyclePlan.roundCount {
            guard let interval = cycle.plan.workInterval(round: round),
                  interval.end > Date() else { continue }
            let name = NoxaDeviceActivityConfiguration.pomodoroWorkActivityName(
                cycleID: cycle.id, round: round
            )
            guard !center.activities.contains(name) else { continue }
            let start = calendar.dateComponents(
                [.calendar, .year, .month, .day, .hour, .minute, .second],
                from: interval.start
            )
            let end = calendar.dateComponents(
                [.calendar, .year, .month, .day, .hour, .minute, .second],
                from: interval.end
            )
            try center.startMonitoring(
                name,
                during: DeviceActivitySchedule(
                    intervalStart: start,
                    intervalEnd: end,
                    repeats: false
                )
            )
        }
    }

    private func stopPomodoroMonitors(for cycle: PomodoroCycleRecord) {
        center.stopMonitoring((2...PomodoroCyclePlan.roundCount).map {
            NoxaDeviceActivityConfiguration.pomodoroWorkActivityName(
                cycleID: cycle.id, round: $0
            )
        })
    }

    private func reconcilePomodoro(_ cycle: PomodoroCycleRecord, now: Date = Date()) {
        guard Self.isAuthorizationApproved(authorizationCenter.authorizationStatus) else {
            let message = "Screen Time access was revoked. The Pomodoro cycle was stopped."
            if let session = (try? store.loadSnapshot())?.activeSession,
               session.outcome == .active {
                interrupt(session: session, message: message)
                return
            }
            stopPomodoroMonitors(for: cycle)
            store.clearPomodoroCycle()
            pomodoroCycle = nil
            settingsStore.clearAllSettings()
            activeSession = nil
            activeIntention = nil
            errorMessage = message
            return
        }

        var snapshot = (try? store.loadSnapshot()) ?? NoxaLocalSnapshot()
        let hadCompletedSession = snapshot.sessionHistory.contains {
            $0.outcome.countsTowardFocusStatistics
        }
        if cycle.plan.phase(at: now) != .complete {
            do {
                try schedulePomodoroMonitors(for: cycle)
            } catch {
                errorMessage = "A Pomodoro work interval could not be restored: \(error.localizedDescription)"
            }
        }
        for completed in cycle.verifiedCompletedSessions(
            asOf: now,
            enforcedAt: { store.pomodoroRoundEnforcedAt(cycleID: cycle.id, round: $0) }
        )
        where !snapshot.sessionHistory.contains(where: { $0.id == completed.id }) {
            snapshot.sessionHistory.insert(completed, at: 0)
        }
        snapshot.sessionHistory = Array(snapshot.sessionHistory.prefix(100))
        let phase = cycle.plan.phase(at: now)
        switch phase {
        case .scheduled:
            return
        case let .work(round, endsAt):
            guard let session = cycle.session(for: round) else { return }
            snapshot.activeSession = session
            snapshot.sessionEngineState = .active
            do {
                try store.saveSnapshot(snapshot)
                try store.saveFocusSessionRestrictions(FocusSessionRestrictionConfiguration(
                    selection: cycle.selection,
                    websiteDomains: cycle.websiteDomains,
                    intention: "Pomodoro · \(cycle.plan.workMinutes)/\(cycle.plan.breakMinutes)"
                ))
                applyShield(cycle.selection, websiteDomains: cycle.websiteDomains)
                store.markPomodoroRoundEnforced(cycleID: cycle.id, round: round)
                var appliedSession = session
                appliedSession.lastRestrictionApplicationAt = Date()
                snapshot.activeSession = appliedSession
                try store.saveSnapshot(snapshot)
                activeSession = appliedSession
                activeIntention = "Pomodoro · \(cycle.plan.workMinutes)/\(cycle.plan.breakMinutes)"
                history = snapshot.sessionHistory
                schedulePomodoroBoundaryReconciliation(for: endsAt)
            } catch {
                errorMessage = "Could not restore the Pomodoro work interval: \(error.localizedDescription)"
            }
        case let .breakTime(_, endsAt):
            snapshot.activeSession = nil
            snapshot.sessionEngineState = .idle
            do {
                try store.saveSnapshot(snapshot)
                settingsStore.clearAllSettings()
                store.clearFocusSessionRestrictions()
                activeSession = nil
                activeIntention = nil
                history = snapshot.sessionHistory
                schedulePomodoroBoundaryReconciliation(for: endsAt)
            } catch {
                errorMessage = "Could not restore the Pomodoro break: \(error.localizedDescription)"
            }
        case .complete:
            snapshot.activeSession = nil
            snapshot.sessionEngineState = .idle
            do {
                try store.saveSnapshot(snapshot)
                if !hadCompletedSession,
                   let firstCompleted = snapshot.sessionHistory
                    .filter({ $0.outcome.countsTowardFocusStatistics })
                    .min(by: { $0.startedAt < $1.startedAt }) {
                    saveFirstScheduleSuggestion(
                        for: firstCompleted,
                        selection: cycle.selection,
                        websiteDomains: cycle.websiteDomains
                    )
                }
                settingsStore.clearAllSettings()
                store.clearFocusSessionRestrictions()
                stopPomodoroMonitors(for: cycle)
                store.clearPomodoroCycle()
                store.clearPomodoroRoundEnforcement(cycleID: cycle.id)
                store.pendingPomodoroCompletionID = cycle.id
                completedPomodoroCycleID = cycle.id
                pomodoroCycle = nil
                activeSession = nil
                activeIntention = nil
                history = snapshot.sessionHistory
            } catch {
                errorMessage = "Could not finish the Pomodoro cycle: \(error.localizedDescription)"
            }
        }
    }

    private func schedulePomodoroBoundaryReconciliation(for boundary: Date) {
        reconciliationTask?.cancel()
        reconciliationTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(1, boundary.timeIntervalSinceNow + 1)))
            guard !Task.isCancelled else { return }
            self?.reconcile(recoverStale: false)
        }
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
        RestrictionStoreWriter.apply(
            selection: selection,
            websiteDomains: websiteDomains,
            to: settingsStore
        )
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
        let sessionTargets = (try? store.loadFocusSessionRestrictions()) ?? nil
        let hadCompletedSession = history.contains { $0.outcome.countsTowardFocusStatistics }
        center.stopMonitoring([NoxaDeviceActivityConfiguration.focusActivityName])
        settingsStore.clearAllSettings()
        store.clearFocusSessionRestrictions()

        var completedRecord = session
        completedRecord.outcome = recovered ? .recoveredStale : .completed
        completedRecord.actualDurationSeconds = completedRecord.plannedDurationSeconds
        completedRecord.lastCleanupAttemptAt = Date()
        do {
            try saveSnapshot(engineState: .idle, session: completedRecord)
            activeSession = nil
            activeIntention = nil
            history = (try? store.loadSnapshot())?.sessionHistory ?? history
            if !hadCompletedSession, let sessionTargets {
                saveFirstScheduleSuggestion(
                    for: completedRecord,
                    selection: sessionTargets.selection,
                    websiteDomains: sessionTargets.websiteDomains
                )
            }
            AnalyticsService.shared.capture(.focusCompleted(
                durationMinutes: completedRecord.plannedDurationSeconds / 60
            ))
            logger.info("Finished focus session \(completedRecord.id.uuidString, privacy: .public)")
        } catch {
            errorMessage = "Restrictions were removed, but session reconciliation failed: \(error.localizedDescription)"
        }
    }

    private func saveFirstScheduleSuggestion(
        for session: ActiveSessionRecord,
        selection: FamilyActivitySelection,
        websiteDomains: [String]
    ) {
        guard !store.hasOfferedScheduleSuggestion,
              pendingScheduleSuggestion == nil else { return }
        do {
            try store.savePendingScheduleSuggestion(PendingScheduleSuggestion(
                selection: selection,
                websiteDomains: websiteDomains,
                startedAt: session.startedAt,
                plannedEndAt: session.plannedEndAt
            ))
        } catch {
            logger.error("Could not save the first-session schedule suggestion")
        }
    }

    private func failPendingSession(_ session: ActiveSessionRecord) {
        center.stopMonitoring([NoxaDeviceActivityConfiguration.focusActivityName])
        settingsStore.clearAllSettings()
        store.clearFocusSessionRestrictions()
        if completedSessionCount == 0 { store.clearPendingScheduleSuggestion() }
        var failedSession = session
        failedSession.outcome = .failedToStart
        failedSession.lastCleanupAttemptAt = Date()
        try? saveSnapshot(engineState: .idle, session: failedSession)
        activeSession = nil
        activeIntention = nil
    }

    private func interrupt(session: ActiveSessionRecord, message: String) {
        reconciliationTask?.cancel()
        if let pomodoroCycle {
            stopPomodoroMonitors(for: pomodoroCycle)
            store.clearPomodoroCycle()
            store.clearPomodoroRoundEnforcement(cycleID: pomodoroCycle.id)
            self.pomodoroCycle = nil
        }
        center.stopMonitoring([NoxaDeviceActivityConfiguration.focusActivityName])
        settingsStore.clearAllSettings()
        store.clearFocusSessionRestrictions()
        if completedSessionCount == 0 { store.clearPendingScheduleSuggestion() }

        var interruptedSession = session
        interruptedSession.outcome = .interrupted
        interruptedSession.actualDurationSeconds = Self.measuredDurationSeconds(
            startedAt: session.startedAt,
            endedAt: Date(),
            plannedDurationSeconds: session.plannedDurationSeconds
        )
        interruptedSession.lastCleanupAttemptAt = Date()
        try? saveSnapshot(engineState: .idle, session: interruptedSession)
        activeSession = nil
        activeIntention = nil
        errorMessage = message
        logger.error("Interrupted focus session \(session.id.uuidString, privacy: .public): \(message, privacy: .public)")
    }

    private static func isAuthorizationApproved(_ status: AuthorizationStatus) -> Bool {
        if status == .approved { return true }
        if #available(iOS 26.4, *) {
            return status == .approvedWithDataAccess
        }
        return false
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

    static func normalizedDurationMinutes(_ minutes: Int, strict: Bool = false) -> Int {
        min(
            max(minutes, NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes),
            strict
                ? NoxaDeviceActivityConfiguration.maximumStrictFocusSessionMinutes
                : NoxaDeviceActivityConfiguration.maximumFocusSessionMinutes
        )
    }
}

private enum FocusSessionError: LocalizedError {
    case sessionEndInPast

    var errorDescription: String? {
        "The requested session duration is too short to schedule."
    }
}
