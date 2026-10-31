import Foundation

/// The new-user journey, in its approved order. Welcome and Home sit outside
/// this enum: Welcome is its own root view and Home is the main app.
enum OnboardingStep: Int, CaseIterable, Sendable {
    case estimate
    case projection
    case goals
    case categories
    case insight
    case productDemo
    case account
    case screenTime
    case selection
    case notifications
    case analyticsConsent
    case subscription
    case pact

    /// Steps that ask the user about themselves, for the small "1 of 3" label.
    static let questionnaire: [OnboardingStep] = [.estimate, .goals, .categories]

    /// Where to resume. Saved milestones cover the narrative; account,
    /// Screen Time, selection and subscription are rechecked live every time,
    /// so a revoked permission or lost entitlement is never treated as done.
    static func resume(
        progress: OnboardingProgress,
        isAuthenticated: Bool,
        isScreenTimeApproved: Bool,
        hasSelection: Bool,
        hasSubscription: Bool
    ) -> OnboardingStep {
        if !progress.hasCompletedEstimate { return .estimate }
        if !progress.hasSeenProjection { return .projection }
        if !progress.hasCompletedGoals { return .goals }
        if !progress.hasCompletedDistractions { return .categories }
        if !progress.hasSeenInsight { return .insight }
        if !progress.hasSeenProductDemo { return .productDemo }
        if !isAuthenticated { return .account }
        if !isScreenTimeApproved { return .screenTime }
        if !hasSelection { return .selection }
        if !progress.hasSeenNotificationExplainer { return .notifications }
        if !progress.hasAnsweredAnalyticsConsent { return .analyticsConsent }
        if !hasSubscription { return .subscription }
        return .pact
    }

    /// The step a Back button returns to, or nil where going back would
    /// undo something external (an account, a permission, a purchase).
    var previous: OnboardingStep? {
        switch self {
        case .estimate, .account, .screenTime, .subscription, .pact: nil
        case .projection: .estimate
        case .goals: .projection
        case .categories: .goals
        case .insight: .categories
        case .productDemo: .insight
        case .selection: .screenTime
        case .notifications: .selection
        case .analyticsConsent: .notifications
        }
    }
}

enum OnboardingGoal: String, Codable, CaseIterable, Sendable {
    case studying = "Studying"
    case work = "Work"
    case betterSleep = "Better sleep"
    case timeForMyself = "Time for myself"
    case beingPresent = "Being present"
    case betterHabits = "Building better habits"
    case hobbies = "Hobbies"

    var symbol: String {
        switch self {
        case .studying: "book"
        case .work: "briefcase"
        case .betterSleep: "moon"
        case .timeForMyself: "sparkles"
        case .beingPresent: "person.2"
        case .betterHabits: "repeat"
        case .hobbies: "paintpalette"
        }
    }
}

enum OnboardingDistraction: String, Codable, CaseIterable, Sendable {
    case shortVideos = "Short videos"
    case socialMedia = "Social media"
    case streaming = "Streaming & video"
    case games = "Games"
    case browsing = "Browsing"
    case other = "Other"

    var symbol: String {
        switch self {
        case .shortVideos: "play.rectangle.on.rectangle"
        case .socialMedia: "bubble.left.and.bubble.right"
        case .streaming: "tv"
        case .games: "gamecontroller"
        case .browsing: "safari"
        case .other: "ellipsis.circle"
        }
    }
}

/// A voluntary commitment, stored apart from purchase and permission state.
enum PactStatus: String, Codable, Sendable {
    case completed
    case skipped
}

/// One calculator for every projection number, so the hero figure and the
/// week/month/year comparisons can never disagree.
struct TimeProjection: Equatable, Sendable {
    /// Presets offered on the estimate step, in minutes per day.
    static let presets = [30, 60, 120, 180, 240, 300, 360]
    /// The largest estimate accepted; "6h+" maps here.
    static let maximumMinutesPerDay = 360
    /// Used only for an older draft saved without an estimate.
    static let exampleMinutesPerDay = 180
    /// Slider granularity on the estimate step.
    static let sliderStep = 15

    let minutesPerDay: Int

    init(minutesPerDay: Int) {
        self.minutesPerDay = min(max(minutesPerDay, 0), Self.maximumMinutesPerDay)
    }

    var weekHours: Double { Double(minutesPerDay * 7) / 60 }
    var annualHours: Double { Double(minutesPerDay * 365) / 60 }
    var averageMonthHours: Double { annualHours / 12 }
    /// Continuous 24-hour days, not waking days.
    var annualFullDays: Double { annualHours / 24 }

    static func label(minutes: Int) -> String {
        if minutes >= maximumMinutesPerDay { return "6h+" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    static func spokenLabel(minutes: Int) -> String {
        if minutes >= maximumMinutesPerDay { return "6 hours or more" }
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        let remainder = minutes % 60
        let hourText = "\(hours) hour\(hours == 1 ? "" : "s")"
        return remainder == 0 ? hourText : "\(hourText) \(remainder) minutes"
    }

    static func format(_ value: Double, maximumFractionDigits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(0...maximumFractionDigits)))
    }
}
