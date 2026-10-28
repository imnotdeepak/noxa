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
    enum MainTab: Hashable {
        case dailyLimits
        case blocklist
        case home
        case stats
        case account
    }

    enum StatsRange: Int, CaseIterable {
        case day = 1
        case week = 7
        case month = 30
        case year = 365

        var title: String {
            switch self {
            case .day: "Today"
            case .week: "Week"
            case .month: "Month"
            case .year: "Year"
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
    @State var selectedDurationMinutes = 30
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
    @State var scheduleMode: ScheduleRule.Mode = .allowedHours
    @State var scheduleWeekdays: Set<Int> = Set(1...7)
    @State var scheduleNotifyAtStart = false
    @State var scheduleNotifyAtEnd = false
    @State var scheduleLockWhileActive = false
    @State var isScheduleLockConfirmationPresented = false
    @State var scheduleCustomDomains = ""
    @State var scheduleSelection = FamilyActivitySelection()
    @State var scheduleAllowedStart = Calendar.current.date(from: DateComponents(hour: 21)) ?? Date()
    @State var scheduleAllowedEnd = Calendar.current.date(from: DateComponents(hour: 22)) ?? Date()
    @State var pomodoroWorkMinutes = 25
    @State var pomodoroBreakMinutes = 5
    @State var isCustomPomodoro = false
    @State var isPaywallPresented = false
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
    @State var statsReferenceDate = Date()
    @State var isHomeBlocklistExpanded = false
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
        .tint(NoxaTheme.accent)
        .font(NoxaType.body)
        .preferredColorScheme(.dark)
        .font(NoxaTheme.font(17))
        .toolbarBackground(NoxaTheme.background.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(NoxaBackground())
        .sheet(isPresented: $restrictions.isPickerPresented) {
            restrictionPickerSheet
        }
        .sheet(isPresented: $isDailyLimitPickerPresented) {
            dailyLimitPickerSheet
        }
        .sheet(isPresented: $isSchedulePickerPresented) {
            schedulePickerSheet
        }
        .sheet(isPresented: $isFocusStartReviewPresented) {
            focusStartReviewSheet
        }
        .sheet(isPresented: $isInstagramAppPickerPresented) {
            instagramAppPickerSheet
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
            if focusSession.completedPomodoroCycleID != nil {
                isPomodoroCompletionPresented = true
            }
            firstFocusReviewPending = onboarding.progress.isComplete
                && !onboarding.progress.hasSeenFirstFocusReview
            presentFirstFocusReviewIfReady()
            presentScheduleSuggestionIfReady()
            presentWidgetStartIfReady()
            presentWidgetHomeIfReady()
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            statsReferenceDate = Date()
            instagramSiteMode = AppGroupStore.shared.instagramSiteMode
            instagramAppBlockEnabled = AppGroupStore.shared.instagramAppBlockEnabled
            safariFilterLastSeenAt = AppGroupStore.shared.safariFilterLastSeenAt
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
            Text("Noxa can notify you when focus sessions and Pomodoro breaks are complete.")
        }
        return accountAlerts
        .alert("Start Pomodoro?", isPresented: $isPomodoroStartConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Start Pomodoro") { beginPomodoro() }
        } message: {
            Text("Your selected distractions will be blocked until \(pomodoroFirstRoundEndDescription), when your first break starts. You can't end a work round early in Noxa, but you can stop the cycle during a break. iOS Screen Time permissions can still be changed in Settings.")
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
            Text("Your Pomodoro cycle is over. Would you like to start another one?")
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
                scheduleLockWhileActive = false
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
            Text("Use the apps and websites from your first completed focus session. You can choose the days and hours before saving.")
        }
        .alert("Set up Focus first", isPresented: $isWidgetSetupAlertPresented) {
            Button("Choose Distractions") { selectedTab = .blocklist }
            Button("Later", role: .cancel) {}
        } message: {
            Text("Allow Screen Time and choose at least one app or website before starting from a widget.")
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

    var mainTabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                dailyLimitsContent
                    .navigationTitle("Daily Limits")
            }
            .tabItem {
                Label("Limits", systemImage: "hourglass")
            }
            .tag(MainTab.dailyLimits)

            NavigationStack {
                blocklistContent
                    .navigationTitle("Blocklist")
            }
            .tabItem {
                Label("Blocklist", systemImage: "hand.raised.slash")
            }
            .tag(MainTab.blocklist)

            NavigationStack {
                homeContent
                    .toolbar(.hidden, for: .navigationBar)
            }
            .tabItem {
                Label("Home", systemImage: "circle.circle.fill")
            }
            .tag(MainTab.home)

            NavigationStack {
                statsContent
                    .navigationTitle("Stats")
            }
            .tabItem {
                Label("Insights", systemImage: "chart.bar")
            }
            .tag(MainTab.stats)

            NavigationStack {
                accountContent
                    .navigationTitle("Settings")
            }
            .tabItem {
                Label("Account", systemImage: "person.crop.circle")
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
        isFocusStartReviewPresented = true
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
        selectedDurationMinutes = 60
        isCustomDuration = false
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
