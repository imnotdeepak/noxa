//
//  ContentView.swift
//  Noxa
//

import FamilyControls
import SafariServices
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    enum MainTab: Hashable {
        case dailyLimits
        case blocklist
        case home
        case stats
        case account
    }

    enum StatsRange: CaseIterable, Hashable {
        case day, week, month, year

        var title: String {
            switch self {
            case .day: "Day"
            case .week: "Week"
            case .month: "Month"
            case .year: "Year"
            }
        }

        var unit: FocusPeriodUnit {
            switch self {
            case .day: .day
            case .week: .week
            case .month: .month
            case .year: .year
            }
        }

        func emptyPhrase(isCurrent: Bool) -> String {
            switch self {
            case .day: isCurrent ? "today yet" : "on this day"
            case .week: isCurrent ? "this week yet" : "this week"
            case .month: isCurrent ? "this month yet" : "this month"
            case .year: isCurrent ? "this year yet" : "this year"
            }
        }
    }

    @EnvironmentObject var authentication: AuthenticationService
    @EnvironmentObject var analytics: AnalyticsService
    @EnvironmentObject var subscriptions: SubscriptionService
    @EnvironmentObject var focusSession: FocusSessionService
    @EnvironmentObject var restrictions: ScreenTimeRestrictionService
    @EnvironmentObject var monitoring: DeviceActivityMonitoringService
    @EnvironmentObject var dailyLimits: DailyLimitService
    @EnvironmentObject var schedules: RestrictionScheduleService
    @EnvironmentObject var cloudSync: CloudSyncService
    @EnvironmentObject var websites: WebsiteBlocklistService
    @EnvironmentObject var notifications: FocusNotificationService
    @EnvironmentObject var onboarding: OnboardingService
    @EnvironmentObject var focusLaunchRouter: FocusLaunchRouter
    @StateObject var authorization = FamilyControlsAuthorizationService()
    /// Remembered across launches so the last choice is ready next time.
    @AppStorage("noxa.home.focusDurationMinutes") var selectedDurationMinutes = 30
    @State var isRequestingAuthorization = false
    @State var newDomain = ""
    @State var instagramSiteMode = AppGroupStore.shared.instagramSiteMode
    @State var instagramAppBlockEnabled = AppGroupStore.shared.instagramAppBlockEnabled
    @State var instagramAppBlockMessage: String?
    @State var safariExtensionEnabled: Bool?
    @State var safariFilterLastSeenAt = AppGroupStore.shared.safariFilterLastSeenAt
    @State var instagramAppSelection = (try? AppGroupStore.shared.loadInstagramAppSelection()) ?? nil
    @State var instagramPickerSelection = FamilyActivitySelection()
    @State var isInstagramAppPickerPresented = false
    @State var youtubeShortsHidden = AppGroupStore.shared.youtubeShortsHidden
    @State var youtubeAppBlockEnabled = AppGroupStore.shared.youtubeAppBlockEnabled
    @State var youtubeAppBlockMessage: String?
    @State var youtubeFilterLastSeenAt = AppGroupStore.shared.youtubeFilterLastSeenAt
    @State var youtubeAppSelection = (try? AppGroupStore.shared.loadYouTubeAppSelection()) ?? nil
    @State var youtubePickerSelection = FamilyActivitySelection()
    @State var isYouTubeAppPickerPresented = false
    @State var pendingFilterLock: ShortVideoFilter?
    @State var filterSetupGuide: ShortVideoFilter?
    @State var restrictionPickerSelection = FamilyActivitySelection()
    @State var isDailyLimitPickerPresented = false
    @State var isChoosingDailyLimitDuration = false
    @State var dailyLimitSelection = FamilyActivitySelection()
    @State var selectedDailyLimitMinutes = 30
    @State var isSchedulePickerPresented = false
    @State var isFocusStartReviewPresented = false
    @State var firstFocusReviewPending = false
    @State var scheduleName = ""
    @State var scheduleToEdit: ScheduleRule?
    @State var scheduleToRename: ScheduleRule?
    @State var renamedScheduleName = ""
    @State var scheduleMode: ScheduleRule.Mode = .blockedHours
    @State var scheduleWeekdays: Set<Int> = Set(1...7)
    @State var scheduleNotifyAtStart = false
    @State var scheduleNotifyAtEnd = false
    @State var isScheduleLockConfirmationPresented = false
    @State var expandedScheduleIDs: Set<UUID> = []
    @State var isScheduleAppPickerPresented = false
    @State var isDailyLimitLockConfirmationPresented = false
    @State var dailyLimitToEdit: DailyLimitConfiguration?
    @State var scheduleCustomDomains = ""
    @State var scheduleSelection = FamilyActivitySelection()
    @State var scheduleAllowedStart = Calendar.current.date(from: DateComponents(hour: 21)) ?? Date()
    @State var scheduleAllowedEnd = Calendar.current.date(from: DateComponents(hour: 22)) ?? Date()
    @State var pomodoroWorkMinutes = 25
    @State var pomodoroBreakMinutes = 5
    @State var isCustomPomodoro = false
    @State var isPaywallPresented = false
    @State var isOnboardingReplayPresented = false
    @State var isDeleteAccountConfirmationPresented = false
    @State var isCustomDuration = false
    @State var customDurationText = "30"
    @State var isEndRitualPresented = false
    @State var isPomodoroStartConfirmationPresented = false
    @State var isPomodoroCompletionPresented = false
    @State var isScheduleSuggestionPresented = false
    @State var isWidgetSetupAlertPresented = false
    @State var isNotificationPromptPresented = false
    @State var selectedTab = MainTab.home
    @State var selectedStatsRange = StatsRange.week
    @State var selectedFocusBucket: FocusBucket?
    @State var statsAnchorDate = Date()
    @State var statsReferenceDate = Date()
    @State var isHomeBlocklistExpanded = false
    @State var homeMode: HomeFocusMode = .focus
    @State var lastHomeSessionID: UUID?
    @State var lastCompletedSessionID: UUID?
    @State var toastMessage: String?
    @State var didRepairRestrictions = false
    @FocusState var isCustomDurationFieldFocused: Bool

    var hasFocusRestrictions: Bool {
        restrictions.hasSelection || !websites.domains.isEmpty
    }

    var focusRestrictionCount: Int {
        restrictions.selectedItemCount + websites.domains.count
    }

    var existingDailyLimitSelection: FamilyActivitySelection {
        combinedSelection(from: dailyLimits.configurations.map(\.selection))
    }

    var newDailyLimitSelection: FamilyActivitySelection {
        dailyLimitSelection.removing(existingDailyLimitSelection)
    }

    var newDailyLimitAppCount: Int {
        newDailyLimitSelection.applicationTokens.count
    }

    var newDailyLimitSelectionDescription: String {
        let noun = newDailyLimitAppCount == 1 ? "app" : "apps"
        return "\(newDailyLimitAppCount) new \(noun) selected"
    }

    var hasActiveDailyLimits: Bool {
        dailyLimits.isMonitoring || dailyLimits.isShieldActive
    }

    var dailyFocusMinutes: Int {
        FocusStatistics(
            history: focusSession.history,
            now: statsReferenceDate,
            calendar: .autoupdatingCurrent
        ).dailyFocusMinutes
    }

    var body: some View {
        let presentedTabs = mainTabs
        .overlay(alignment: .top) { AnyView(toastView) }
        .tint(NoxaTheme.accent)
        .font(NoxaType.body)
        .preferredColorScheme(.dark)
        .font(NoxaTheme.font(17))
        .toolbarBackground(NoxaTheme.background.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(NoxaBackground())
        .sheet(isPresented: $restrictions.isPickerPresented) {
            AnyView(restrictionPickerSheet)
        }
        .sheet(isPresented: $isDailyLimitPickerPresented) {
            AnyView(dailyLimitPickerSheet)
        }
        .sheet(item: $dailyLimitToEdit) { configuration in
            AnyView(dailyLimitDetailSheet(configuration))
        }
        .sheet(isPresented: $isSchedulePickerPresented) {
            AnyView(schedulePickerSheet)
        }
        .sheet(isPresented: $isFocusStartReviewPresented) {
            AnyView(focusStartReviewSheet)
        }
        .sheet(isPresented: $isInstagramAppPickerPresented) {
            AnyView(instagramAppPickerSheet)
        }
        .sheet(isPresented: $isYouTubeAppPickerPresented) {
            AnyView(youtubeAppPickerSheet)
        }
        .fullScreenCover(isPresented: $isEndRitualPresented) {
            EndSessionRitualView {
                guard !focusSession.isActiveSessionStrict else { return }
                if let cycle = focusSession.pomodoroCycle {
                    notifications.cancelPomodoroCycle(cycle.id)
                }
                if let sessionID = focusSession.activeSession?.id {
                    notifications.cancel(for: sessionID)
                }
                focusSession.endEarly()
            }
        }
        let observedTabs = presentedTabs
        .task {
            authorization.refresh()
            AppGroupStore.shared.startMissingFilterLocks()
            restoreInstagramAppBlockIfNeeded()
            restoreYouTubeAppBlockIfNeeded()
            if focusSession.completedPomodoroCycleID != nil {
                isPomodoroCompletionPresented = true
            }
            firstFocusReviewPending = onboarding.progress.isComplete
                && !onboarding.progress.hasSeenFirstFocusReview
            presentFirstFocusReviewIfReady()
            presentScheduleSuggestionIfReady()
            presentWidgetStartIfReady()
            presentWidgetHomeIfReady()
            #if DEBUG
            // `-NoxaFilterSetupPreview` opens the Reels setup guide for review.
            if CommandLine.arguments.contains("-NoxaFilterSetupPreview") {
                selectedTab = .dailyLimits
                filterSetupGuide = .instagram
            }
            #endif
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            statsReferenceDate = Date()
            restoreInstagramAppBlockIfNeeded()
            instagramSiteMode = AppGroupStore.shared.instagramSiteMode
            instagramAppBlockEnabled = AppGroupStore.shared.instagramAppBlockEnabled
            safariFilterLastSeenAt = AppGroupStore.shared.safariFilterLastSeenAt
            restoreYouTubeAppBlockIfNeeded()
            youtubeShortsHidden = AppGroupStore.shared.youtubeShortsHidden
            youtubeAppBlockEnabled = AppGroupStore.shared.youtubeAppBlockEnabled
            youtubeFilterLastSeenAt = AppGroupStore.shared.youtubeFilterLastSeenAt
            Task { await refreshSafariExtensionStatus() }
            Task { await notifications.refreshAuthorizationStatus() }
        }
        .onChange(of: selectedTab) { _ in
            NoxaHaptics.selection()
        }
        .onChange(of: authorization.state) { _ in
            // Pause or resume a running session as soon as access changes.
            focusSession.reconcile()
        }
        .onChange(of: focusSession.activeSession?.id) { sessionID in
            if sessionID != nil {
                NoxaHaptics.success()
            } else {
                switch focusSession.history.first?.outcome {
                case .completed: NoxaHaptics.success()
                case .endedEarly: NoxaHaptics.warning()
                default: break
                }
            }
        }
        .onChange(of: focusSession.completedPomodoroCycleID) { completedID in
            isPomodoroCompletionPresented = completedID != nil
            if completedID == nil { presentScheduleSuggestionIfReady() }
        }
        .onChange(of: focusSession.history) { _ in
            presentScheduleSuggestionIfReady()
        }
        .onChange(of: focusSession.pomodoroCycle?.id) { _ in
            presentScheduleSuggestionIfReady()
        }
        .onChange(of: focusLaunchRouter.hasPendingStart) { _ in
            presentWidgetStartIfReady()
        }
        .onChange(of: focusLaunchRouter.hasPendingHome) { _ in
            presentWidgetHomeIfReady()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            statsReferenceDate = Date()
        }
        let accountAlerts = observedTabs
        .alert("Delete your Noxa account?", isPresented: $isDeleteAccountConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task { @MainActor in
                    await deleteAccountAndLocalData()
                }
            }
        } message: {
            Text("This permanently deletes your cloud account and Noxa data. Your App Store subscription must be cancelled separately in Apple settings.")
        }
        .alert("Get focus notifications?", isPresented: $isNotificationPromptPresented) {
            Button("Not Now", role: .cancel) {}
            Button("Allow Notifications") {
                Task { await enableNotificationsForActiveSession() }
            }
        } message: {
            Text("Get told when sessions and breaks finish.")
        }
        return accountAlerts
        .alert("Start Pomodoro?", isPresented: $isPomodoroStartConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Start Pomodoro") { beginPomodoro() }
        } message: {
            Text("Blocked until your first break at \(pomodoroFirstRoundEndDescription). Work rounds can't be ended early; you can stop during a break.")
        }
        .alert("Four rounds complete", isPresented: $isPomodoroCompletionPresented) {
            Button("Later", role: .cancel) {
                focusSession.acknowledgePomodoroCompletion()
            }
            Button("Start Another") {
                focusSession.acknowledgePomodoroCompletion()
                isPomodoroStartConfirmationPresented = true
            }
        } message: {
            Text("Start another cycle?")
        }
        .alert("Make this a recurring schedule?", isPresented: $isScheduleSuggestionPresented) {
            Button("Not Now", role: .cancel) {
                focusSession.acknowledgeScheduleSuggestion()
            }
            Button("Create Schedule") {
                guard let suggestion = focusSession.pendingScheduleSuggestion else { return }
                focusSession.acknowledgeScheduleSuggestion()
                schedules.clearError()
                scheduleToEdit = nil
                scheduleName = ""
                scheduleMode = .blockedHours
                scheduleWeekdays = Set(1...7)
                scheduleNotifyAtStart = false
                scheduleNotifyAtEnd = false
                scheduleAllowedStart = Self.dateForScheduleMinute(
                    Self.minutesSinceMidnight(suggestion.startedAt)
                )
                scheduleAllowedEnd = Self.dateForScheduleMinute(
                    Self.minutesSinceMidnight(suggestion.plannedEndAt)
                )
                scheduleSelection = suggestion.selection
                scheduleCustomDomains = suggestion.websiteDomains.joined(separator: ", ")
                selectedTab = .dailyLimits
                Task { @MainActor in
                    await Task.yield()
                    isSchedulePickerPresented = true
                }
            }
        } message: {
            Text("Uses the same apps and sites. You pick the days and hours.")
        }
        .alert("Set up Focus first", isPresented: $isWidgetSetupAlertPresented) {
            Button("Choose Distractions") { selectedTab = .blocklist }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Allow Screen Time and choose at least one app or site.")
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    commitCustomDuration()
                    isCustomDurationFieldFocused = false
                }
            }
        }
    }

    // Each tab is type-erased: fully inlined, the five screens form one view
    // type deep enough to overflow the main-thread stack on device at launch.
    var mainTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                AnyView(dailyLimitsContent)
                    .navigationTitle("Limits & Schedules")
            }
            .tabItem {
                Label("Limits", systemImage: "hourglass")
            }
            .tag(MainTab.dailyLimits)

            NavigationStack {
                AnyView(blocklistContent)
                    .navigationTitle("Blocklist")
            }
            .tabItem {
                Label("Blocklist", systemImage: "hand.raised.slash")
            }
            .tag(MainTab.blocklist)

            NavigationStack {
                AnyView(homeContent)
                    .toolbar(.hidden, for: .navigationBar)
                    .noxaStatusBarScrim()
            }
            .tabItem {
                Label("Home", systemImage: "circle.circle.fill")
            }
            .tag(MainTab.home)

            NavigationStack {
                AnyView(statsContent)
                    .toolbar(.hidden, for: .navigationBar)
                    .noxaStatusBarScrim()
            }
            .tabItem {
                Label("Insights", systemImage: "chart.bar")
            }
            .tag(MainTab.stats)

            NavigationStack {
                AnyView(profileContent)
                    .toolbar(.hidden, for: .navigationBar)
                    .noxaStatusBarScrim()
            }
            .tabItem {
                Label("Profile", systemImage: "person.crop.circle")
            }
            .tag(MainTab.account)
        }
    }

    var restrictionPickerSheet: some View {
        NavigationStack {
            FamilyActivityPicker(
                selection: focusSession.isActive
                    ? selectionBinding($restrictionPickerSelection, keeping: restrictions.selection)
                    : $restrictionPickerSelection
            )
            .navigationTitle(focusSession.isActive ? "Add restrictions" : "Choose restrictions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        finishRestrictionPicker()
                    }
                }
            }
        }
        .tint(NoxaTheme.accent)
        .font(NoxaType.body)
        .preferredColorScheme(.dark)
    }

    static func minutesSinceMidnight(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    static func dateForScheduleMinute(_ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(
            year: 2001, month: 1, day: 1,
            hour: minute / 60, minute: minute % 60
        )) ?? Date()
    }

    static func domains(from input: String) -> [String] {
        input.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated static func weekdayName(_ weekday: Int) -> String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return (1...7).contains(weekday) ? names[weekday - 1] : ""
    }

    nonisolated static func weekdaySummary(_ weekdays: Set<Int>) -> String {
        if weekdays == Set(1...7) { return "Every day" }
        return weekdays.sorted().map(weekdayName).joined(separator: ", ")
    }

    func presentRestrictionPicker() {
        guard !focusSession.hasPomodoroCycle || focusSession.isActive else { return }
        // Existing choices stay visibly checked. During an active session the
        // binding below also prevents those locked choices from being removed.
        restrictionPickerSelection = restrictions.selection
        restrictions.isPickerPresented = true
    }

    func finishRestrictionPicker() {
        if focusSession.hasPomodoroCycle && !focusSession.isActive {
            restrictionPickerSelection = FamilyActivitySelection()
            restrictions.isPickerPresented = false
            return
        }
        if focusSession.isActive {
            guard restrictions.addToActiveSession(restrictionPickerSelection) else { return }
        } else {
            restrictions.selection = restrictionPickerSelection
            restrictions.persistSelection()
            guard restrictions.errorMessage == nil else { return }
        }

        restrictionPickerSelection = FamilyActivitySelection()
        restrictions.isPickerPresented = false
        showToast(focusSession.isActive ? "Added to this session" : "Blocklist saved")
    }

    /// Confirms a change only after it was stored; failures show their own
    /// error text where the change was made.
    func showToast(_ message: String, duration: TimeInterval = 2) {
        NoxaHaptics.tap(.light)
        withAnimation(reduceMotion ? nil : NoxaMotion.spring) { toastMessage = message }
        let shown = message
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard toastMessage == shown else { return }
            withAnimation(reduceMotion ? nil : NoxaMotion.spring) { toastMessage = nil }
        }
    }

    @ViewBuilder
    var toastView: some View {
        if let toastMessage {
            Label(toastMessage, systemImage: "checkmark.circle.fill")
                .font(NoxaType.subheadlineSemibold)
                .foregroundStyle(NoxaTheme.primaryText)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(NoxaTheme.elevated, in: Capsule())
                .overlay { Capsule().strokeBorder(NoxaTheme.border, lineWidth: 1) }
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityAddTraits(.updatesFrequently)
                .onAppear { UIAccessibility.post(notification: .announcement, argument: toastMessage) }
        }
    }

    func combinedSelection(
        from selections: [FamilyActivitySelection]
    ) -> FamilyActivitySelection {
        selections.reduce(into: FamilyActivitySelection()) { combined, selection in
            combined.applicationTokens.formUnion(selection.applicationTokens)
            combined.categoryTokens.formUnion(selection.categoryTokens)
            combined.webDomainTokens.formUnion(selection.webDomainTokens)
        }
    }

    func selectionBinding(
        _ selection: Binding<FamilyActivitySelection>,
        keeping lockedSelection: FamilyActivitySelection
    ) -> Binding<FamilyActivitySelection> {
        Binding(
            get: { selection.wrappedValue },
            set: { updatedSelection in
                var mergedSelection = updatedSelection
                mergedSelection.applicationTokens.formUnion(lockedSelection.applicationTokens)
                mergedSelection.categoryTokens.formUnion(lockedSelection.categoryTokens)
                mergedSelection.webDomainTokens.formUnion(lockedSelection.webDomainTokens)
                selection.wrappedValue = mergedSelection
            }
        )
    }

    func presentFirstFocusReviewIfReady() {
        guard firstFocusReviewPending,
              !focusSession.isActive,
              hasFocusRestrictions,
              subscriptions.canEnterApp(for: authentication.userID) else { return }
        guard onboarding.markFirstFocusReviewPresented() else { return }
        firstFocusReviewPending = false
        selectedDurationMinutes = 30
        isCustomDuration = false
        selectedTab = .home
        // A short nudge, never an automatic start or a second tutorial.
        showToast("Your first Focus is ready. Start whenever you are.", duration: 4)
    }

    func presentWidgetStartIfReady() {
        guard focusLaunchRouter.hasPendingStart,
              subscriptions.canEnterApp(for: authentication.userID) else { return }
        focusLaunchRouter.consumeStart()
        selectedTab = .home
        if let cycle = focusSession.pomodoroCycle,
           case .complete = cycle.plan.phase(at: Date()) {
            focusSession.reconcile()
        }
        guard !focusSession.isActive, !focusSession.hasPomodoroCycle else { return }
        // Starts with the duration last chosen on Home.
        if hasFocusRestrictions && authorization.state.isApproved {
            isFocusStartReviewPresented = true
        } else {
            isWidgetSetupAlertPresented = true
        }
    }

    func presentWidgetHomeIfReady() {
        guard focusLaunchRouter.hasPendingHome else { return }
        let duration = focusLaunchRouter.pendingHomeDurationMinutes
        focusLaunchRouter.consumeHome()
        selectedTab = .home
        if let duration {
            if let cycle = focusSession.pomodoroCycle,
               case .complete = cycle.plan.phase(at: Date()) {
                focusSession.reconcile()
            }
            guard !focusSession.isActive, !focusSession.hasPomodoroCycle else { return }
            selectedDurationMinutes = duration
            isCustomDuration = false
        }
    }

    func presentScheduleSuggestionIfReady() {
        guard onboarding.progress.isComplete,
              subscriptions.canEnterApp(for: authentication.userID),
              authorization.state.isApproved,
              schedules.configurations.count < RestrictionScheduleService.maximumConfigurations,
              focusSession.completedSessionCount > 0,
              !focusSession.isActive,
              !focusSession.hasPomodoroCycle,
              !isPomodoroCompletionPresented,
              !isFocusStartReviewPresented,
              !isNotificationPromptPresented,
              focusSession.pendingScheduleSuggestion != nil else { return }
        isScheduleSuggestionPresented = true
    }

    static func durationLabel(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }

    func durationGridColumns(regularCount: Int, spacing: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing),
              count: dynamicTypeSize.isAccessibilitySize ? 1 : regularCount)
    }

    static func durationString(seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    static func timeLabel(minutes: Int) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let date = calendar.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}
