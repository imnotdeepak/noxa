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
    /// True while a session or Pomodoro cycle is waiting for Screen Time
    /// access to return. iOS has lifted the blocks; the end time still runs.
    @Published private(set) var isPausedForScreenTimeAccess = false

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
        store.endScreenTimeAccessPause()
        isPausedForScreenTimeAccess = false
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
            stopFocusMonitors()
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
            // The app requests its initial shield before the cycle is saved.
            // Credit that round only after the monitor confirms it applied
            // the same session. A later monitor callback records the marker
            // itself if it arrives after the cycle was saved.
            if let receipt = monitorReceipt(for: firstSession) {
                store.markPomodoroRoundEnforced(
                    cycleID: cycle.id,
                    round: 1,
                    at: receipt.appliedAt
                )
            }
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

        stopFocusMonitors()
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
        // iOS lifts every block while access is off but keeps Noxa's saved
        // settings, and restores them if access returns. Keep the session so
        // opening Noxa can't turn a temporary bypass into a cancelled session.
        if !Self.isAuthorizationApproved(authorizationCenter.authorizationStatus) {
            if session.outcome == .active {
                guard session.plannedEndAt > Date() else {
                    finish(session: session, recovered: recoverStale)
                    return
                }
                store.beginScreenTimeAccessPause()
                isPausedForScreenTimeAccess = true
                activeSession = session
                activeIntention = ((try? store.loadFocusSessionRestrictions()) ?? nil)?.intention
                scheduleReconciliation(for: session)
                return
            } else if session.outcome == .startPending {
                failPendingSession(session)
            } else {
                activeSession = nil
            }
            return
        }

        store.endScreenTimeAccessPause()
        isPausedForScreenTimeAccess = false

        guard session.outcome == .active else {
            if session.outcome == .startPending {
                // A process termination can happen after the pending intent
                // is persisted but before DeviceActivity accepts the
                // schedule. Treat that half-start as failed and remove any
                // shield it may have applied so the lock cannot linger.
                stopFocusMonitors()
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
        } else if !center.activities.contains(NoxaDeviceActivityConfiguration.focusReleaseActivityName) {
            do {
                try scheduleFocusReleaseMonitor(for: session)
            } catch {
                logger.error("Could not restore focus release wake: \(error.localizedDescription, privacy: .public)")
            }
        }

        if let configuration = (try? store.loadFocusSessionRestrictions()) ?? nil {
            activeIntention = configuration.intention
            applyShield(configuration.selection, websiteDomains: configuration.websiteDomains)
        } else if let cycle = pomodoroCycle,
                  case .work(round: 1, _) = cycle.plan.phase(at: Date()) {
            // A delayed focus-end callback can remove the shared snapshot
            // while the first Pomodoro round is still active. Restore the
            // cycle's immutable targets before reapplying its shield.
            let configuration = FocusSessionRestrictionConfiguration(
                selection: cycle.selection,
                websiteDomains: cycle.websiteDomains,
                intention: "Pomodoro · \(cycle.plan.workMinutes)/\(cycle.plan.breakMinutes)"
            )
            do {
                try store.saveFocusSessionRestrictions(configuration)
                activeIntention = configuration.intention
                applyShield(configuration.selection, websiteDomains: configuration.websiteDomains)
            } catch {
                errorMessage = "The active Pomodoro blocklist could not be restored: \(error.localizedDescription)"
            }
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
        stopFocusMonitors()
        settingsStore.clearAllSettings()
        store.clearFocusSessionRestrictions()
        activeSession = nil
        activeIntention = nil
        history = []
        errorMessage = nil
        store.clearSnapshot()
        store.clearScreenTimeAccessPauses()
        isPausedForScreenTimeAccess = false
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
        // The first round's backup release wake can outlive the work interval.
        // Remove it before another cycle starts so a late callback cannot
        // clear the next session's shield.
        stopFocusMonitors()
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
        #if DEBUG
        let registeredBefore = Set(center.activities)
        let presence = (2...PomodoroCyclePlan.roundCount).map { round in
            let name = NoxaDeviceActivityConfiguration.pomodoroWorkActivityName(
                cycleID: cycle.id, round: round
            )
            return "\(round):\(registeredBefore.contains(name) ? 1 : 0)"
        }.joined(separator: ",")
        let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa")
        let key = "noxa.debug.pomodoroMonitorPresenceBeforeScheduling"
        var observations = defaults?.stringArray(forKey: key) ?? []
        observations.append("\(Date().timeIntervalSince1970)|\(cycle.id.uuidString.lowercased())|\(presence)")
        defaults?.set(Array(observations.suffix(20)), forKey: key)
        #endif
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
            // Warning callbacks are an additional chance to reconcile a work
            // boundary when the normal start/end callback is delayed.
            try center.startMonitoring(
                name,
                during: DeviceActivitySchedule(
                    intervalStart: start,
                    intervalEnd: end,
                    repeats: false,
                    warningTime: DateComponents(second: 1)
                )
            )
        }
        recordPomodoroMonitorSchedule(cycleID: cycle.id)
    }

    private func recordPomodoroMonitorSchedule(cycleID: UUID) {
        #if DEBUG
        let entries = (2...PomodoroCyclePlan.roundCount).map { round in
            let name = NoxaDeviceActivityConfiguration.pomodoroWorkActivityName(
                cycleID: cycleID, round: round
            )
            guard let schedule = center.schedule(for: name) else {
                return "\(round)|missing"
            }
            guard let interval = schedule.nextInterval else {
                return "\(round)|no-next-interval"
            }
            return "\(round)|\(interval.start.timeIntervalSince1970)|\(interval.end.timeIntervalSince1970)"
        }
        UserDefaults(suiteName: "group.LycheeCorp.Noxa")?.set(
            entries, forKey: "noxa.debug.pomodoroMonitorSchedules"
        )
        #endif
    }

    private func stopPomodoroMonitors(for cycle: PomodoroCycleRecord) {
        center.stopMonitoring((2...PomodoroCyclePlan.roundCount).map {
            NoxaDeviceActivityConfiguration.pomodoroWorkActivityName(
                cycleID: cycle.id, round: $0
            )
        })
    }

    private func reconcilePomodoro(_ cycle: PomodoroCycleRecord, now: Date = Date()) {
        if !Self.isAuthorizationApproved(authorizationCenter.authorizationStatus),
           cycle.plan.phase(at: now) != .complete {
            // Keep the cycle on its schedule. iOS restores the work block if
            // access returns during a work round; overlapping rounds are
            // recorded as interrupted once the cycle is reconciled again.
            store.beginScreenTimeAccessPause(at: now)
            isPausedForScreenTimeAccess = true
            pomodoroCycle = cycle
            switch cycle.plan.phase(at: now) {
            case let .work(round, endsAt):
                activeSession = cycle.session(for: round)
                activeIntention = "Pomodoro · \(cycle.plan.workMinutes)/\(cycle.plan.breakMinutes)"
                schedulePomodoroBoundaryReconciliation(for: endsAt)
            case let .breakTime(_, endsAt):
                activeSession = nil
                activeIntention = nil
                schedulePomodoroBoundaryReconciliation(for: endsAt)
            case let .scheduled(startsAt):
                schedulePomodoroBoundaryReconciliation(for: startsAt)
            case .complete:
                break
            }
            return
        }
        if Self.isAuthorizationApproved(authorizationCenter.authorizationStatus) {
            store.endScreenTimeAccessPause(at: now)
        }
        isPausedForScreenTimeAccess = false

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
        let accessPauses = store.loadScreenTimeAccessPauses()
        for completed in cycle.verifiedCompletedSessions(
            asOf: now,
            enforcedAt: { store.pomodoroRoundEnforcedAt(cycleID: cycle.id, round: $0) }
        )
        where !snapshot.sessionHistory.contains(where: { $0.id == completed.id }) {
            snapshot.sessionHistory.insert(
                Self.applyingAccessPauses(accessPauses, to: completed, now: now),
                at: 0
            )
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
        // Keep the original interval when restoring a missing monitor. A
        // fresh start-to-end interval can be shorter than DeviceActivity's
        // 15-minute minimum even while the saved session is still active.
        // DeviceActivity invokes intervalDidStart for the current interval.
        let start = record.startedAt
        guard record.plannedEndAt > Date() else {
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
            repeats: false,
            warningTime: DateComponents(second: 1)
        )
        try center.startMonitoring(
            NoxaDeviceActivityConfiguration.focusActivityName,
            during: schedule
        )
        try scheduleFocusReleaseMonitor(for: record)
    }

    private func scheduleFocusReleaseMonitor(for record: ActiveSessionRecord) throws {
        let calendar = Calendar.current
        // Keep this wake separate from the primary end boundary so a missed
        // intervalDidEnd has an independent later chance to clear the shield.
        let releaseAt = record.plannedEndAt.addingTimeInterval(60)
        let releaseStart = calendar.dateComponents(
            [.calendar, .year, .month, .day, .hour, .minute, .second],
            from: releaseAt
        )
        let releaseEnd = calendar.dateComponents(
            [.calendar, .year, .month, .day, .hour, .minute, .second],
            from: releaseAt.addingTimeInterval(15 * 60)
        )
        let releaseSchedule = DeviceActivitySchedule(
            intervalStart: releaseStart,
            intervalEnd: releaseEnd,
            repeats: false
        )
        try center.startMonitoring(
            NoxaDeviceActivityConfiguration.focusReleaseActivityName,
            during: releaseSchedule
        )
        #if DEBUG
        let next = center.schedule(for: NoxaDeviceActivityConfiguration.focusReleaseActivityName)?.nextInterval
        UserDefaults(suiteName: "group.LycheeCorp.Noxa")?.set(
            next.map { "\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)" }
                ?? "no-next-interval",
            forKey: "noxa.debug.focusReleaseNextInterval"
        )
        #endif
    }

    private func stopFocusMonitors() {
        center.stopMonitoring([
            NoxaDeviceActivityConfiguration.focusActivityName,
            NoxaDeviceActivityConfiguration.focusReleaseActivityName
        ])
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
        stopFocusMonitors()
        settingsStore.clearAllSettings()
        store.clearFocusSessionRestrictions()

        var completedRecord = session
        let interval = DateInterval(start: session.startedAt, end: max(session.startedAt, session.plannedEndAt))
        let pausedAt = ScreenTimeAccessPause.firstOverlap(with: interval, store.loadScreenTimeAccessPauses())
        if let pausedAt {
            completedRecord.outcome = .interrupted
            completedRecord.actualDurationSeconds = Self.measuredDurationSeconds(
                startedAt: session.startedAt,
                endedAt: pausedAt,
                plannedDurationSeconds: session.plannedDurationSeconds
            )
        } else {
            completedRecord.outcome = recovered ? .recoveredStale : .completed
            completedRecord.actualDurationSeconds = completedRecord.plannedDurationSeconds
        }
        completedRecord.lastCleanupAttemptAt = Date()
        if Self.isAuthorizationApproved(authorizationCenter.authorizationStatus) {
            store.endScreenTimeAccessPause()
        }
        isPausedForScreenTimeAccess = false
        do {
            try saveSnapshot(engineState: .idle, session: completedRecord)
            activeSession = nil
            activeIntention = nil
            history = (try? store.loadSnapshot())?.sessionHistory ?? history
            guard pausedAt == nil else {
                logger.info("Focus session \(completedRecord.id.uuidString, privacy: .public) ended after a Screen Time access pause")
                return
            }
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
        stopFocusMonitors()
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
        stopFocusMonitors()
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

    /// A Pomodoro round that overlapped a Screen Time access pause was not
    /// enforced throughout, so it is kept in history as interrupted.
    static func applyingAccessPauses(
        _ pauses: [ScreenTimeAccessPause],
        to round: ActiveSessionRecord,
        now: Date = Date()
    ) -> ActiveSessionRecord {
        let interval = DateInterval(start: round.startedAt, end: max(round.startedAt, round.plannedEndAt))
        guard let pausedAt = ScreenTimeAccessPause.firstOverlap(with: interval, pauses, now: now) else {
            return round
        }
        var interrupted = round
        interrupted.outcome = .interrupted
        interrupted.actualDurationSeconds = measuredDurationSeconds(
            startedAt: round.startedAt,
            endedAt: pausedAt,
            plannedDurationSeconds: round.plannedDurationSeconds
        )
        return interrupted
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
