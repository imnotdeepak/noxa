#if DEBUG
import SwiftUI

/// Debug-only entry point, selected by the `-NoxaUIPreview` launch argument.
/// It skips sign-in and the paywall so every main screen can be reviewed, and
/// never contacts Supabase, RevenueCat, or analytics. Compiled out of Release.
struct NoxaUIPreviewApp: App {
    @StateObject private var authentication = AuthenticationService()
    @StateObject private var subscriptions = SubscriptionService()
    @StateObject private var focusSession = FocusSessionService()
    @StateObject private var onboarding = OnboardingService()
    @StateObject private var restrictions = ScreenTimeRestrictionService()
    @StateObject private var monitoring = DeviceActivityMonitoringService()
    @StateObject private var dailyLimits = DailyLimitService()
    @StateObject private var schedules = RestrictionScheduleService()
    @StateObject private var websites = WebsiteBlocklistService()
    @StateObject private var cloudSync = CloudSyncService()
    @StateObject private var notifications = FocusNotificationService()

    var body: some Scene {
        WindowGroup {
            previewRoot
                .environmentObject(authentication)
                .environmentObject(AnalyticsService.shared)
                .environmentObject(subscriptions)
                .environmentObject(focusSession)
                .environmentObject(onboarding)
                .environmentObject(restrictions)
                .environmentObject(monitoring)
                .environmentObject(dailyLimits)
                .environmentObject(schedules)
                .environmentObject(websites)
                .environmentObject(cloudSync)
                .environmentObject(notifications)
                .environmentObject(FocusLaunchRouter.shared)
                .task { seed() }
        }
    }

    /// `-NoxaOnboardingStep N` shows onboarding step N (0 is Welcome) with
    /// its routing guards off, so each screen can be reviewed directly.
    @ViewBuilder
    private var previewRoot: some View {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "-NoxaOnboardingStep"),
           arguments.indices.contains(index + 1),
           let number = Int(arguments[index + 1]) {
            if number == 0 {
                OnboardingWelcomeView()
            } else {
                OnboardingView(previewStep: OnboardingStep(rawValue: number - 1) ?? .goals)
            }
        } else {
            ContentView()
        }
    }

    @MainActor
    private func seed() {
        authentication.applyUIPreview()
        if let userID = authentication.userID {
            subscriptions.applyUIPreview(userID: userID)
        }
        if focusSession.history.isEmpty {
            let now = Date()
            let day: TimeInterval = 86_400
            let records = (0..<28).map { index -> ActiveSessionRecord in
                let minutes = [25, 45, 60, 90, 30][index % 5]
                let start = now.addingTimeInterval(-Double(index) * day * 1.1 - 3_600 * Double(8 + index % 9))
                let end = start.addingTimeInterval(Double(minutes) * 60)
                let early = index % 6 == 5
                return ActiveSessionRecord(
                    startedAt: start,
                    plannedEndAt: end,
                    plannedDurationSeconds: minutes * 60,
                    outcome: early ? .endedEarly : .completed,
                    isStrict: index % 4 == 0,
                    actualDurationSeconds: early ? minutes * 30 : nil
                )
            }
            focusSession.replaceHistory(records)
        }
        if websites.domains.isEmpty {
            websites.replaceDomains(["reddit.com", "youtube.com", "x.com"])
        }
    }
}
#endif
