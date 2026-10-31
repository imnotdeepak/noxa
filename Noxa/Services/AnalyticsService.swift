import Combine
import Foundation
import PostHog

@MainActor
final class AnalyticsService: ObservableObject {
    static let shared = AnalyticsService()

    @Published private(set) var isConfigured = false
    @Published var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: Self.consentKey)
            guard isConfigured else { return }
            if isEnabled {
                PostHogSDK.shared.optIn()
                if let currentUserID {
                    PostHogSDK.shared.identify(currentUserID)
                    identifiedUserID = currentUserID
                }
            } else {
                PostHogSDK.shared.optOut()
            }
        }
    }

    private static let consentKey = "analyticsConsentEnabled"
    private let defaults: UserDefaults
    private var currentUserID: String?
    private var identifiedUserID: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Off until the user agrees, during onboarding or in Settings.
        isEnabled = defaults.bool(forKey: Self.consentKey)
    }

    func configure() {
        guard !isConfigured, let token = AppConfiguration.postHogProjectToken else { return }

        let config = PostHogConfig(projectToken: token, host: AppConfiguration.postHogAPIHost)
        // App opened, backgrounded, installed and updated.
        config.captureApplicationLifecycleEvents = true
        config.captureScreenViews = false
        config.captureElementInteractions = false
        config.captureSwiftUIElementInteractions = false
        config.captureAutocaptureElementText = false
        config.sessionReplay = false
        config.preloadFeatureFlags = false
        config.sendFeatureFlagEvent = false
        config.personProfiles = .identifiedOnly
        config.optOut = !isEnabled
        PostHogSDK.shared.setup(config)
        isConfigured = true
    }

    func identify(userID: UUID) {
        let identifier = userID.uuidString.lowercased()
        currentUserID = identifier
        guard isConfigured, isEnabled else { return }
        guard identifiedUserID != identifier else { return }
        PostHogSDK.shared.identify(identifier)
        identifiedUserID = identifier
    }

    func reset() {
        currentUserID = nil
        identifiedUserID = nil
        guard isConfigured else { return }
        PostHogSDK.shared.reset()
        if !isEnabled {
            PostHogSDK.shared.optOut()
        }
    }

    func capture(_ event: AnalyticsEvent) {
        guard isConfigured, isEnabled, identifiedUserID != nil else { return }
        PostHogSDK.shared.capture(event.name, properties: event.properties)
    }

    /// Named screens, sent by hand: SwiftUI's hosting controllers would
    /// otherwise all report the same meaningless UIKit class name.
    func screen(_ name: String) {
        guard isConfigured, isEnabled, identifiedUserID != nil else { return }
        PostHogSDK.shared.screen(name)
    }
}

struct AnalyticsEvent {
    let name: String
    let properties: [String: Any]

    init(_ name: String, properties: [String: Any] = [:]) {
        self.name = name
        self.properties = properties
    }

    static func focusStarted(durationMinutes: Int, selectionCount: Int) -> Self {
        .init("focus_session_started", properties: [
            "duration_bucket": durationBucket(durationMinutes),
            "selection_count": selectionCount
        ])
    }

    static func focusEndedEarly(elapsedMinutes: Int) -> Self {
        .init("focus_session_ended_early", properties: [
            "elapsed_minutes_bucket": durationBucket(elapsedMinutes)
        ])
    }

    static func focusCompleted(durationMinutes: Int) -> Self {
        .init("focus_session_completed", properties: [
            "duration_bucket": durationBucket(durationMinutes)
        ])
    }

    static func purchaseStarted(productID: String) -> Self {
        .init("subscription_purchase_started", properties: ["product_id": productID])
    }

    static func paywallViewed(context: String) -> Self {
        .init("paywall_viewed", properties: ["context": context])
    }

    static func purchaseCompleted(productID: String) -> Self {
        .init("subscription_purchase_completed", properties: ["product_id": productID])
    }

    static func purchaseCancelled(productID: String) -> Self {
        .init("subscription_purchase_cancelled", properties: ["product_id": productID])
    }

    /// Step names only: no answers, estimates or app selections.
    static func onboardingStepViewed(_ step: String) -> Self {
        .init("onboarding_step_viewed", properties: ["step": step])
    }

    static func onboardingScreenTimeResult(_ state: String) -> Self {
        .init("onboarding_screen_time_result", properties: ["state": state])
    }

    static func onboardingPaywallLoadFailed() -> Self {
        .init("onboarding_paywall_load_failed")
    }

    static func onboardingPactFinished(_ status: String) -> Self {
        .init("onboarding_pact_finished", properties: ["status": status])
    }

    // MARK: Limits, schedules and filters
    // Counts and buckets only: never app names, tokens or website domains.

    static func dailyLimitAdded(minutes: Int, appCount: Int) -> Self {
        .init("daily_limit_added", properties: [
            "allowance_bucket": durationBucket(minutes),
            "app_count": appCount
        ])
    }

    static func dailyLimitAllowanceChanged(lowered: Bool) -> Self {
        .init("daily_limit_allowance_changed", properties: ["direction": lowered ? "lower" : "higher"])
    }

    static func dailyLimitToggled(on: Bool, lockState: String) -> Self {
        .init("daily_limit_toggled", properties: ["on": on, "lock_state": lockState])
    }

    static func dailyLimitRemoved(lockState: String) -> Self {
        .init("daily_limit_removed", properties: ["lock_state": lockState])
    }

    static func dailyLimitsStopped() -> Self {
        .init("daily_limits_stopped")
    }

    static func scheduleCreated(blockMinutes: Int, dayCount: Int) -> Self {
        .init("schedule_created", properties: [
            "block_length_bucket": durationBucket(blockMinutes),
            "day_count": dayCount
        ])
    }

    static func scheduleEdited() -> Self {
        .init("schedule_edited")
    }

    static func scheduleToggled(on: Bool, lockState: String) -> Self {
        .init("schedule_toggled", properties: ["on": on, "lock_state": lockState])
    }

    static func scheduleRemoved(lockState: String) -> Self {
        .init("schedule_removed", properties: ["lock_state": lockState])
    }

    /// `site` is "instagram" or "youtube".
    static func shortVideoFilterChanged(site: String, on: Bool) -> Self {
        .init("short_video_filter_changed", properties: ["site": site, "on": on])
    }

    static func shortVideoFilterSetupOpened(site: String) -> Self {
        .init("short_video_filter_setup_opened", properties: ["site": site])
    }

    static func focusBlocklistSaved(apps: Int, categories: Int, websites: Int) -> Self {
        .init("focus_blocklist_saved", properties: [
            "app_count": apps,
            "category_count": categories,
            "website_token_count": websites
        ])
    }

    static func blockedWebsiteAdded(totalCount: Int) -> Self {
        .init("blocked_website_added", properties: ["total_count": totalCount])
    }

    static func blockedWebsiteRemoved(totalCount: Int) -> Self {
        .init("blocked_website_removed", properties: ["total_count": totalCount])
    }

    static func pomodoroStarted(workMinutes: Int, breakMinutes: Int) -> Self {
        .init("pomodoro_started", properties: ["work_minutes": workMinutes, "break_minutes": breakMinutes])
    }

    static func widgetOpened(destination: String) -> Self {
        .init("widget_opened", properties: ["destination": destination])
    }

    static func insightsRangeChanged(_ range: String) -> Self {
        .init("insights_range_changed", properties: ["range": range])
    }

    /// "locked", "change_window" or "unlocked", for weekly commitments.
    static func lockStateName(_ state: WeeklyCommitment.State) -> String {
        switch state {
        case .locked: "locked"
        case .changeWindow: "change_window"
        case .unlocked: "unlocked"
        }
    }

    private static func durationBucket(_ minutes: Int) -> String {
        switch minutes {
        case ..<15: return "under_15"
        case 15..<30: return "15_29"
        case 30..<60: return "30_59"
        case 60..<120: return "60_119"
        default: return "120_plus"
        }
    }
}
