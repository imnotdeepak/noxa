//
//  NoxaState.swift
//  Noxa
//
//  Shared, Codable state primitives used by the main app and future extensions.
//

import FamilyControls
import Foundation

/// Describes what the local session engine is currently doing.
enum SessionEngineState: String, Codable, Equatable, Sendable {
    case idle
    case starting
    case active
    case ending
    case reconciling
}

/// Describes the durable outcome of a focus session.
enum SessionOutcome: String, Codable, Equatable, Sendable {
    case startPending = "start_pending"
    case active
    case completed
    case endedEarly = "ended_early"
    case failedToStart = "failed_to_start"
    case interrupted
    case recoveredStale = "recovered_stale"

    var countsTowardFocusStatistics: Bool {
        switch self {
        // A session only contributes to completed-session stats when it
        // reached its planned end. Ending early is retained in history but is
        // intentionally treated as abandoned work.
        case .completed, .recoveredStale:
            return true
        case .startPending, .active, .endedEarly, .failedToStart, .interrupted:
            return false
        }
    }
}

/// The small amount of session metadata that must survive process termination.
/// Screen Time tokens are deliberately not represented here; they remain in
/// Apple-managed, device-local storage.
struct ActiveSessionRecord: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let startedAt: Date
    let plannedEndAt: Date
    let plannedDurationSeconds: Int
    var outcome: SessionOutcome
    /// Measured duration for sessions ended before their planned end.
    /// Completed sessions can use the planned duration when this is nil.
    var actualDurationSeconds: Int?
    var lastRestrictionApplicationAt: Date?
    var lastCleanupAttemptAt: Date?

    init(
        id: UUID = UUID(),
        startedAt: Date = Date(),
        plannedEndAt: Date,
        plannedDurationSeconds: Int,
        outcome: SessionOutcome = .startPending,
        actualDurationSeconds: Int? = nil,
        lastRestrictionApplicationAt: Date? = nil,
        lastCleanupAttemptAt: Date? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.plannedEndAt = plannedEndAt
        self.plannedDurationSeconds = plannedDurationSeconds
        self.outcome = outcome
        self.actualDurationSeconds = actualDurationSeconds
        self.lastRestrictionApplicationAt = lastRestrictionApplicationAt
        self.lastCleanupAttemptAt = lastCleanupAttemptAt
    }
}

/// The device-local restriction snapshot owned by an active focus session.
/// Screen Time selections are opaque Apple-managed tokens and never leave the
/// device. This configuration is separate from the user's editable blocklist
/// so changing settings cannot weaken an active session.
struct FocusSessionRestrictionConfiguration: Codable, Equatable, Sendable {
    let selection: FamilyActivitySelection
    let websiteDomains: [String]
    let intention: String?

    init(
        selection: FamilyActivitySelection,
        websiteDomains: [String] = [],
        intention: String? = nil
    ) {
        self.selection = selection
        self.websiteDomains = websiteDomains
        self.intention = intention
    }

    private enum CodingKeys: String, CodingKey {
        case selection
        case websiteDomains
        case intention
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selection = try container.decode(FamilyActivitySelection.self, forKey: .selection)
        websiteDomains = try container.decodeIfPresent([String].self, forKey: .websiteDomains) ?? []
        intention = try container.decodeIfPresent(String.self, forKey: .intention)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(selection, forKey: .selection)
        try container.encode(websiteDomains, forKey: .websiteDomains)
        try container.encodeIfPresent(intention, forKey: .intention)
    }
}

/// A daily allowance associated with an opaque Screen Time selection. The
/// selection is kept local and is never converted to bundle identifiers.
struct DailyLimitConfiguration: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var selection: FamilyActivitySelection
    var dailyLimitMinutes: Int
    var createdAt: Date
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        selection: FamilyActivitySelection,
        dailyLimitMinutes: Int,
        createdAt: Date = Date(),
        isEnabled: Bool = true
    ) {
        self.id = id
        self.selection = selection
        self.dailyLimitMinutes = min(max(dailyLimitMinutes, 5), 240)
        self.createdAt = createdAt
        self.isEnabled = isEnabled
    }
}

/// Progress and draft data used to resume onboarding safely after interruption.
struct OnboardingProgress: Codable, Equatable, Sendable {
    var hasSeenWelcome = false
    var hasCompletedGoals = false
    var hasCompletedDistractions = false
    var hasSeenCapabilitiesExplainer = false
    var hasCompletedInitialSetup = false
    var hasSeenFirstSessionPrompt = false
    var draftPersonalizationAnswers: [String] = []
    var draftSetupConfiguration: [String: String] = [:]
}

/// The app-level snapshot needed for launch reconciliation.
struct NoxaLocalSnapshot: Codable, Equatable, Sendable {
    var sessionEngineState: SessionEngineState = .idle
    var activeSession: ActiveSessionRecord?
    var onboarding: OnboardingProgress = OnboardingProgress()
    var sessionHistory: [ActiveSessionRecord] = []
    var dailyLimits: [DailyLimitConfiguration] = []

    private enum CodingKeys: String, CodingKey {
        case sessionEngineState
        case activeSession
        case onboarding
        case sessionHistory
        case dailyLimits
    }

    init(
        sessionEngineState: SessionEngineState = .idle,
        activeSession: ActiveSessionRecord? = nil,
        onboarding: OnboardingProgress = OnboardingProgress(),
        sessionHistory: [ActiveSessionRecord] = [],
        dailyLimits: [DailyLimitConfiguration] = []
    ) {
        self.sessionEngineState = sessionEngineState
        self.activeSession = activeSession
        self.onboarding = onboarding
        self.sessionHistory = sessionHistory
        self.dailyLimits = dailyLimits
    }

    /// Defaults the history field when reading snapshots written before the
    /// local history feature existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionEngineState = try container.decodeIfPresent(SessionEngineState.self, forKey: .sessionEngineState) ?? .idle
        activeSession = try container.decodeIfPresent(ActiveSessionRecord.self, forKey: .activeSession)
        onboarding = try container.decodeIfPresent(OnboardingProgress.self, forKey: .onboarding) ?? OnboardingProgress()
        sessionHistory = try container.decodeIfPresent([ActiveSessionRecord].self, forKey: .sessionHistory) ?? []
        dailyLimits = try container.decodeIfPresent([DailyLimitConfiguration].self, forKey: .dailyLimits) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionEngineState, forKey: .sessionEngineState)
        try container.encodeIfPresent(activeSession, forKey: .activeSession)
        try container.encode(onboarding, forKey: .onboarding)
        try container.encode(sessionHistory, forKey: .sessionHistory)
        try container.encode(dailyLimits, forKey: .dailyLimits)
    }
}
