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

    var countsTowardProtectedTime: Bool {
        switch self {
        case .completed, .recoveredStale, .endedEarly:
            return true
        case .startPending, .active, .failedToStart, .interrupted:
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
    let isStrict: Bool
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
        isStrict: Bool = false,
        actualDurationSeconds: Int? = nil,
        lastRestrictionApplicationAt: Date? = nil,
        lastCleanupAttemptAt: Date? = nil
    ) {
        self.id = id
        self.startedAt = startedAt
        self.plannedEndAt = plannedEndAt
        self.plannedDurationSeconds = plannedDurationSeconds
        self.outcome = outcome
        self.isStrict = isStrict
        self.actualDurationSeconds = actualDurationSeconds
        self.lastRestrictionApplicationAt = lastRestrictionApplicationAt
        self.lastCleanupAttemptAt = lastCleanupAttemptAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, startedAt, plannedEndAt, plannedDurationSeconds, outcome
        case isStrict, actualDurationSeconds, lastRestrictionApplicationAt, lastCleanupAttemptAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        plannedEndAt = try container.decode(Date.self, forKey: .plannedEndAt)
        plannedDurationSeconds = try container.decode(Int.self, forKey: .plannedDurationSeconds)
        outcome = try container.decode(SessionOutcome.self, forKey: .outcome)
        isStrict = try container.decodeIfPresent(Bool.self, forKey: .isStrict) ?? false
        actualDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .actualDurationSeconds)
        lastRestrictionApplicationAt = try container.decodeIfPresent(Date.self, forKey: .lastRestrictionApplicationAt)
        lastCleanupAttemptAt = try container.decodeIfPresent(Date.self, forKey: .lastCleanupAttemptAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(startedAt, forKey: .startedAt)
        try container.encode(plannedEndAt, forKey: .plannedEndAt)
        try container.encode(plannedDurationSeconds, forKey: .plannedDurationSeconds)
        try container.encode(outcome, forKey: .outcome)
        try container.encode(isStrict, forKey: .isStrict)
        try container.encodeIfPresent(actualDurationSeconds, forKey: .actualDurationSeconds)
        try container.encodeIfPresent(lastRestrictionApplicationAt, forKey: .lastRestrictionApplicationAt)
        try container.encodeIfPresent(lastCleanupAttemptAt, forKey: .lastCleanupAttemptAt)
    }
}

/// A stretch of time when Noxa had no Screen Time access. iOS lifts every
/// block while access is off, so overlapping sessions count as interrupted.
struct ScreenTimeAccessPause: Codable, Equatable, Sendable {
    let startedAt: Date
    var endedAt: Date?

    static func overlaps(
        _ interval: DateInterval,
        _ pauses: [ScreenTimeAccessPause],
        now: Date = Date()
    ) -> Bool {
        pauses.contains { pause in
            pause.startedAt < interval.end && (pause.endedAt ?? now) > interval.start
        }
    }

    /// The first instant a pause cut into the interval, for measured duration.
    static func firstOverlap(
        with interval: DateInterval,
        _ pauses: [ScreenTimeAccessPause],
        now: Date = Date()
    ) -> Date? {
        pauses
            .filter { $0.startedAt < interval.end && ($0.endedAt ?? now) > interval.start }
            .map { max($0.startedAt, interval.start) }
            .min()
    }
}

/// A device-local copy of the first completed session's targets, retained
/// only until the user accepts or dismisses the recurring-schedule offer.
struct PendingScheduleSuggestion: Codable, Equatable {
    let selection: FamilyActivitySelection
    let websiteDomains: [String]
    let startedAt: Date
    let plannedEndAt: Date
}

/// Receipt that the separate Screen Time monitor process reached the shield
/// application path. It is not proof that a target was visibly blocked.
struct FocusMonitorReceipt: Codable, Equatable {
    let sessionID: UUID
    let appliedAt: Date
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

/// The explicit shield is separate from the editable selection. Saving this
/// snapshot lets reconciliation preserve a manually enabled block after a
/// focus session or process restart.
struct ManualShieldConfiguration: Codable, Equatable, Sendable {
    let selection: FamilyActivitySelection
    let websiteDomains: [String]
}

/// A daily allowance associated with an opaque Screen Time selection. The
/// selection is kept local and is never converted to bundle identifiers.
struct DailyLimitConfiguration: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    /// The Noxa account that created this limit. Nil only for pre-migration data.
    var ownerUserID: UUID?
    var selection: FamilyActivitySelection
    var dailyLimitMinutes: Int
    var createdAt: Date
    var isEnabled: Bool
    /// Start of the weekly lock cycle. Nil for limits saved before weekly
    /// locks, which stay unlocked until their allowance is next changed.
    var lockAnchor: Date?

    init(
        id: UUID = UUID(),
        ownerUserID: UUID? = nil,
        selection: FamilyActivitySelection,
        dailyLimitMinutes: Int,
        createdAt: Date = Date(),
        isEnabled: Bool = true,
        lockAnchor: Date? = nil
    ) {
        self.id = id
        self.ownerUserID = ownerUserID
        self.selection = selection
        self.dailyLimitMinutes = min(max(dailyLimitMinutes, 5), 240)
        self.createdAt = createdAt
        self.isEnabled = isEnabled
        self.lockAnchor = lockAnchor
    }
}

/// A daily window during which the selected apps are available. Noxa shields
/// them before and after this window using independent DeviceActivity stores.
struct PendingScheduleRelaxation: Codable, Equatable, Sendable {
    enum Action: String, Codable, Sendable {
        case disable
        case remove
    }

    let action: Action
    let requestedAt: Date
    let effectiveAt: Date
}

struct RestrictionScheduleConfiguration: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String?
    var selection: FamilyActivitySelection
    var allowedStartMinutes: Int
    var allowedEndMinutes: Int
    var createdAt: Date
    var isEnabled: Bool
    var pendingRelaxation: PendingScheduleRelaxation?

    init(
        id: UUID = UUID(),
        name: String? = nil,
        selection: FamilyActivitySelection,
        allowedStartMinutes: Int,
        allowedEndMinutes: Int,
        createdAt: Date = Date(),
        isEnabled: Bool = true,
        pendingRelaxation: PendingScheduleRelaxation? = nil
    ) {
        self.id = id
        self.name = name
        self.selection = selection
        self.allowedStartMinutes = min(max(allowedStartMinutes, 15), 1_425)
        self.allowedEndMinutes = min(max(allowedEndMinutes, 15), 1_425)
        self.createdAt = createdAt
        self.isEnabled = isEnabled
        self.pendingRelaxation = pendingRelaxation
    }
}

/// Progress and draft data used to resume onboarding safely after interruption.
struct OnboardingProgress: Codable, Equatable, Sendable {
    private static let currentFlowVersion = 6

    var flowVersion = currentFlowVersion
    var ownerUserID: UUID?
    var hasSeenWelcome = false
    var hasCompletedName = false
    var hasCompletedGoals = false
    var hasCompletedDistractions = false
    var hasCompletedProblemTimes = false
    var hasCompletedMotivation = false
    var hasSeenCapabilitiesExplainer = false
    var hasSeenValueOverview = false
    var hasSeenPricingPreview = false
    var hasSeenNotificationExplainer = false
    var hasCompletedInitialSetup = false
    var hasSeenFirstSessionPrompt = false
    var hasSeenFirstFocusReview = false
    // Flow version 6: the redesigned narrative before account creation.
    var hasCompletedEstimate = false
    var hasSeenProjection = false
    var hasSeenInsight = false
    var hasSeenProductDemo = false
    var pactStatus: PactStatus?
    /// Allow or Skip on the analytics question; the answer itself lives
    /// with AnalyticsService.
    var hasAnsweredAnalyticsConsent = false
    var draftPersonalizationAnswers: [String] = []
    var draftSetupConfiguration: [String: String] = [:]

    var isComplete: Bool {
        hasCompletedInitialSetup && hasSeenFirstSessionPrompt
    }

    var selectedGoals: Set<OnboardingGoal> {
        Set(draftPersonalizationAnswers.compactMap(OnboardingGoal.init(rawValue:)))
    }

    var selectedDistractions: Set<OnboardingDistraction> {
        Set((draftSetupConfiguration["distractions"] ?? "")
            .split(separator: "|")
            .compactMap { OnboardingDistraction(rawValue: String($0)) })
    }

    /// Self-reported distracting minutes per day; nil when the user isn't
    /// sure or hasn't answered. Never measured usage.
    var estimatedDistractingMinutesPerDay: Int? {
        draftSetupConfiguration["estimatedMinutes"].flatMap(Int.init)
    }

    private enum CodingKeys: String, CodingKey {
        case flowVersion
        case ownerUserID
        case hasSeenWelcome
        case hasCompletedName
        case hasCompletedGoals
        case hasCompletedDistractions
        case hasCompletedProblemTimes
        case hasCompletedMotivation
        case hasSeenCapabilitiesExplainer
        case hasSeenValueOverview
        case hasSeenPricingPreview
        case hasSeenNotificationExplainer
        case hasCompletedInitialSetup
        case hasSeenFirstSessionPrompt
        case hasSeenFirstFocusReview
        case hasCompletedEstimate
        case hasSeenProjection
        case hasSeenInsight
        case hasSeenProductDemo
        case pactStatus
        case hasAnsweredAnalyticsConsent
        case draftPersonalizationAnswers
        case draftSetupConfiguration
    }

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        flowVersion = try container.decodeIfPresent(Int.self, forKey: .flowVersion) ?? 1
        ownerUserID = try container.decodeIfPresent(UUID.self, forKey: .ownerUserID)
        hasSeenWelcome = try container.decodeIfPresent(Bool.self, forKey: .hasSeenWelcome) ?? false
        hasCompletedName = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedName) ?? false
        hasCompletedGoals = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedGoals) ?? false
        hasCompletedDistractions = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedDistractions) ?? false
        hasCompletedProblemTimes = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedProblemTimes) ?? false
        hasCompletedMotivation = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedMotivation) ?? false
        hasSeenCapabilitiesExplainer = try container.decodeIfPresent(Bool.self, forKey: .hasSeenCapabilitiesExplainer) ?? false
        // Build 8 completed onboarding at the capabilities step. Treat those
        // existing users as complete rather than routing them backwards after
        // the pricing preview was introduced in Build 9.
        hasSeenPricingPreview = try container.decodeIfPresent(Bool.self, forKey: .hasSeenPricingPreview)
            ?? hasSeenCapabilitiesExplainer
        hasSeenValueOverview = try container.decodeIfPresent(Bool.self, forKey: .hasSeenValueOverview)
            ?? (flowVersion < 3 && hasSeenPricingPreview)
        hasSeenNotificationExplainer = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasSeenNotificationExplainer
        ) ?? false
        let storedInitialSetup = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedInitialSetup) ?? false
        let storedFirstSessionPrompt = try container.decodeIfPresent(Bool.self, forKey: .hasSeenFirstSessionPrompt) ?? false
        // Builds before flow version 2 ended onboarding at the pricing preview.
        // Preserve those users' completed state instead of sending them backward.
        hasCompletedInitialSetup = storedInitialSetup || (flowVersion < 2 && hasSeenPricingPreview)
        hasSeenFirstSessionPrompt = storedFirstSessionPrompt || (flowVersion < 2 && hasSeenPricingPreview)
        hasSeenFirstFocusReview = try container.decodeIfPresent(Bool.self, forKey: .hasSeenFirstFocusReview)
            ?? (flowVersion < 5 && hasSeenFirstSessionPrompt)
        // Earlier flows asked for a name right before account creation, so
        // anyone past that step has already seen the old narrative.
        let passedLegacyNarrative = flowVersion < 6 && hasCompletedName
        hasCompletedEstimate = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedEstimate)
            ?? passedLegacyNarrative
        hasSeenProjection = try container.decodeIfPresent(Bool.self, forKey: .hasSeenProjection)
            ?? passedLegacyNarrative
        hasSeenInsight = try container.decodeIfPresent(Bool.self, forKey: .hasSeenInsight)
            ?? passedLegacyNarrative
        hasSeenProductDemo = try container.decodeIfPresent(Bool.self, forKey: .hasSeenProductDemo)
            ?? passedLegacyNarrative
        pactStatus = try container.decodeIfPresent(PactStatus.self, forKey: .pactStatus)
        hasAnsweredAnalyticsConsent = try container.decodeIfPresent(
            Bool.self, forKey: .hasAnsweredAnalyticsConsent
        ) ?? false
        draftPersonalizationAnswers = try container.decodeIfPresent([String].self, forKey: .draftPersonalizationAnswers) ?? []
        draftSetupConfiguration = try container.decodeIfPresent([String: String].self, forKey: .draftSetupConfiguration) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentFlowVersion, forKey: .flowVersion)
        try container.encodeIfPresent(ownerUserID, forKey: .ownerUserID)
        try container.encode(hasSeenWelcome, forKey: .hasSeenWelcome)
        try container.encode(hasCompletedName, forKey: .hasCompletedName)
        try container.encode(hasCompletedGoals, forKey: .hasCompletedGoals)
        try container.encode(hasCompletedDistractions, forKey: .hasCompletedDistractions)
        try container.encode(hasCompletedProblemTimes, forKey: .hasCompletedProblemTimes)
        try container.encode(hasCompletedMotivation, forKey: .hasCompletedMotivation)
        try container.encode(hasSeenCapabilitiesExplainer, forKey: .hasSeenCapabilitiesExplainer)
        try container.encode(hasSeenValueOverview, forKey: .hasSeenValueOverview)
        try container.encode(hasSeenPricingPreview, forKey: .hasSeenPricingPreview)
        try container.encode(hasSeenNotificationExplainer, forKey: .hasSeenNotificationExplainer)
        try container.encode(hasCompletedInitialSetup, forKey: .hasCompletedInitialSetup)
        try container.encode(hasSeenFirstSessionPrompt, forKey: .hasSeenFirstSessionPrompt)
        try container.encode(hasSeenFirstFocusReview, forKey: .hasSeenFirstFocusReview)
        try container.encode(hasCompletedEstimate, forKey: .hasCompletedEstimate)
        try container.encode(hasSeenProjection, forKey: .hasSeenProjection)
        try container.encode(hasSeenInsight, forKey: .hasSeenInsight)
        try container.encode(hasSeenProductDemo, forKey: .hasSeenProductDemo)
        try container.encodeIfPresent(pactStatus, forKey: .pactStatus)
        try container.encode(hasAnsweredAnalyticsConsent, forKey: .hasAnsweredAnalyticsConsent)
        try container.encode(draftPersonalizationAnswers, forKey: .draftPersonalizationAnswers)
        try container.encode(draftSetupConfiguration, forKey: .draftSetupConfiguration)
    }
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
