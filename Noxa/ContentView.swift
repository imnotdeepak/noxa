//
//  ContentView.swift
//  Noxa
//

import FamilyControls
import SafariServices
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private enum MainTab: Hashable {
        case dailyLimits
        case blocklist
        case home
        case stats
        case account
    }

    private enum StatsRange: Int, CaseIterable {
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

    @EnvironmentObject private var authentication: AuthenticationService
    @EnvironmentObject private var analytics: AnalyticsService
    @EnvironmentObject private var subscriptions: SubscriptionService
    @EnvironmentObject private var focusSession: FocusSessionService
    @EnvironmentObject private var restrictions: ScreenTimeRestrictionService
    @EnvironmentObject private var monitoring: DeviceActivityMonitoringService
    @EnvironmentObject private var dailyLimits: DailyLimitService
    @EnvironmentObject private var schedules: RestrictionScheduleService
    @EnvironmentObject private var cloudSync: CloudSyncService
    @EnvironmentObject private var websites: WebsiteBlocklistService
    @EnvironmentObject private var notifications: FocusNotificationService
    @EnvironmentObject private var onboarding: OnboardingService
    @EnvironmentObject private var focusLaunchRouter: FocusLaunchRouter
    @StateObject private var authorization = FamilyControlsAuthorizationService()
    @State private var selectedDurationMinutes = 30
    @State private var isRequestingAuthorization = false
    @State private var newDomain = ""
    @State private var instagramSiteMode = AppGroupStore.shared.instagramSiteMode
    @State private var instagramAppBlockEnabled = AppGroupStore.shared.instagramAppBlockEnabled
    @State private var instagramAppBlockMessage: String?
    @State private var safariExtensionEnabled: Bool?
    @State private var safariFilterLastSeenAt = AppGroupStore.shared.safariFilterLastSeenAt
    @State private var instagramAppSelection = (try? AppGroupStore.shared.loadInstagramAppSelection()) ?? nil
    @State private var instagramPickerSelection = FamilyActivitySelection()
    @State private var isInstagramAppPickerPresented = false
    @State private var restrictionPickerSelection = FamilyActivitySelection()
    @State private var isDailyLimitPickerPresented = false
    @State private var isChoosingDailyLimitDuration = false
    @State private var dailyLimitSelection = FamilyActivitySelection()
    @State private var selectedDailyLimitMinutes = 30
    @State private var isSchedulePickerPresented = false
    @State private var isFocusStartReviewPresented = false
    @State private var firstFocusReviewPending = false
    @State private var scheduleName = ""
    @State private var scheduleToEdit: ScheduleRule?
    @State private var scheduleToRename: ScheduleRule?
    @State private var renamedScheduleName = ""
    @State private var scheduleMode: ScheduleRule.Mode = .allowedHours
    @State private var scheduleWeekdays: Set<Int> = Set(1...7)
    @State private var scheduleNotifyAtStart = false
    @State private var scheduleNotifyAtEnd = false
    @State private var scheduleCustomDomains = ""
    @State private var scheduleSelection = FamilyActivitySelection()
    @State private var scheduleAllowedStart = Calendar.current.date(from: DateComponents(hour: 21)) ?? Date()
    @State private var scheduleAllowedEnd = Calendar.current.date(from: DateComponents(hour: 22)) ?? Date()
    @State private var pomodoroWorkMinutes = 25
    @State private var pomodoroBreakMinutes = 5
    @State private var isCustomPomodoro = false
    @State private var isPaywallPresented = false
    @State private var isDeleteAccountConfirmationPresented = false
    @State private var isCustomDuration = false
    @State private var customDurationText = "30"
    @State private var isEndRitualPresented = false
    @State private var isStrictModeIntroductionPresented = false
    @State private var isStrictStartConfirmationPresented = false
    @State private var isPomodoroCompletionPresented = false
    @State private var isScheduleSuggestionPresented = false
    @State private var isWidgetSetupAlertPresented = false
    @State private var strictStartIsPomodoro = false
    @State private var isNotificationPromptPresented = false
    @State private var selectedTab = MainTab.home
    @State private var selectedStatsRange = StatsRange.week
    @State private var statsReferenceDate = Date()
    @State private var isHomeBlocklistExpanded = false
    @State private var didRepairRestrictions = false
    @FocusState private var isCustomDurationFieldFocused: Bool

    private var hasFocusRestrictions: Bool {
        restrictions.hasSelection || !websites.domains.isEmpty
    }

    private var focusRestrictionCount: Int {
        restrictions.selectedItemCount + websites.domains.count
    }

    private var existingDailyLimitSelection: FamilyActivitySelection {
        combinedSelection(from: dailyLimits.configurations.map(\.selection))
    }

    private var newDailyLimitSelection: FamilyActivitySelection {
        dailyLimitSelection.removing(existingDailyLimitSelection)
    }

    private var newDailyLimitAppCount: Int {
        newDailyLimitSelection.applicationTokens.count
    }

    private var newDailyLimitSelectionDescription: String {
        let noun = newDailyLimitAppCount == 1 ? "app" : "apps"
        return "\(newDailyLimitAppCount) new \(noun) selected"
    }

    private var hasActiveDailyLimits: Bool {
        dailyLimits.isMonitoring || dailyLimits.isShieldActive
    }

    private var dailyFocusMinutes: Int {
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
            if !focusSession.hasOfferedStrictMode {
                focusSession.markStrictModeOffered()
                isStrictModeIntroductionPresented = true
            }
            firstFocusReviewPending = onboarding.progress.isComplete
                && !onboarding.progress.hasSeenFirstFocusReview
            presentFirstFocusReviewIfReady()
            presentScheduleSuggestionIfReady()
            presentWidgetStartIfReady()
            presentWidgetHomeIfReady()
        }
        .onChange(of: isStrictModeIntroductionPresented) { isPresented in
            if !isPresented { presentFirstFocusReviewIfReady() }
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
        .alert("Try Strict Mode?", isPresented: $isStrictModeIntroductionPresented) {
            Button("Keep Off", role: .cancel) {}
            Button("Turn On") { focusSession.setStrictModeEnabled(true) }
        } message: {
            Text("Strict Mode makes future focus work sessions impossible to end early in Noxa. You can turn it off in Settings for future sessions. Strict sessions last at most 4 hours.")
        }
        .alert("Start Strict Focus?", isPresented: $isStrictStartConfirmationPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Start Strict Session") {
                if strictStartIsPomodoro {
                    beginPomodoro()
                } else {
                    beginFocusSession(intention: "")
                }
            }
        } message: {
            Text("If you start now, this work session ends at \(strictEndTimeDescription). You cannot end it early in Noxa. During a Pomodoro break, you can stop before the next work session.")
        }
        .alert("Four rounds complete", isPresented: $isPomodoroCompletionPresented) {
            Button("Later", role: .cancel) {
                focusSession.acknowledgePomodoroCompletion()
            }
            Button("Start Another") {
                focusSession.acknowledgePomodoroCompletion()
                if focusSession.strictModeEnabled {
                    strictStartIsPomodoro = true
                    isStrictStartConfirmationPresented = true
                } else {
                    beginPomodoro()
                }
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

    private var mainTabs: some View {
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
                Label("Stats", systemImage: "chart.bar")
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

    private var restrictionPickerSheet: some View {
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

    private var dailyLimitPickerSheet: some View {
        NavigationStack {
            Group {
                if isChoosingDailyLimitDuration {
                    dailyLimitDurationStep
                } else {
                    FamilyActivityPicker(
                        selection: selectionBinding(
                            $dailyLimitSelection,
                            keeping: existingDailyLimitSelection
                        )
                    )
                }
            }
            .navigationTitle(isChoosingDailyLimitDuration ? "Set Time" : "Choose App")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isChoosingDailyLimitDuration ? "Back" : "Cancel") {
                        if isChoosingDailyLimitDuration {
                            isChoosingDailyLimitDuration = false
                        } else {
                            isDailyLimitPickerPresented = false
                        }
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    if isChoosingDailyLimitDuration {
                        Button("Add Limit") {
                            dailyLimits.add(
                                selection: newDailyLimitSelection,
                                minutes: selectedDailyLimitMinutes
                            )
                            if dailyLimits.errorMessage == nil {
                                dailyLimitSelection = FamilyActivitySelection()
                                isChoosingDailyLimitDuration = false
                                isDailyLimitPickerPresented = false
                            }
                        }
                    } else {
                        Button("Next") {
                            isChoosingDailyLimitDuration = true
                        }
                        .disabled(newDailyLimitSelection.applicationTokens.isEmpty)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var dailyLimitDurationStep: some View {
        VStack(alignment: .leading, spacing: NoxaTheme.Spacing.section) {
            NoxaScreenHeader(
                title: "Choose a daily allowance",
                subtitle: "The selected app will be blocked after this much total use today."
            )

            LazyVGrid(
                columns: durationGridColumns(regularCount: 2, spacing: 10),
                spacing: 10
            ) {
                ForEach([10, 15, 30, 45, 60, 120], id: \.self) { minutes in
                    Button(Self.durationLabel(minutes: minutes)) {
                        selectedDailyLimitMinutes = minutes
                    }
                    .buttonStyle(
                        NoxaDurationButtonStyle(isSelected: selectedDailyLimitMinutes == minutes)
                    )
                }
            }

            Label(newDailyLimitSelectionDescription, systemImage: "app.badge.checkmark")
                .font(NoxaType.subheadlineSemibold)
                .foregroundStyle(NoxaTheme.accent)

            if let errorMessage = dailyLimits.errorMessage {
                Text(errorMessage)
                    .font(NoxaType.footnote)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(NoxaTheme.Spacing.screen)
        .noxaScreenBackground()
    }

    private var schedulePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Schedule name", text: $scheduleName)
                    .textFieldStyle(NoxaTextFieldStyle())
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, NoxaTheme.Spacing.screen)
                scheduleTimingControls
                    .padding(.horizontal, NoxaTheme.Spacing.screen)
                TextField("Websites, separated by commas (optional)", text: $scheduleCustomDomains)
                    .textFieldStyle(NoxaTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, NoxaTheme.Spacing.screen)
                if let errorMessage = schedules.errorMessage {
                    Text(errorMessage)
                        .font(NoxaType.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, NoxaTheme.Spacing.screen)
                }
                FamilyActivityPicker(selection: $scheduleSelection)
            }
            .navigationTitle(scheduleToEdit == nil ? "New schedule" : "Edit schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isSchedulePickerPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if var rule = scheduleToEdit {
                            rule.name = scheduleName
                            rule.mode = scheduleMode
                            rule.selection = scheduleSelection
                            rule.websiteDomains = Self.domains(from: scheduleCustomDomains)
                            rule.weekdays = scheduleWeekdays
                            rule.startMinutes = Self.minutesSinceMidnight(scheduleAllowedStart)
                            rule.endMinutes = Self.minutesSinceMidnight(scheduleAllowedEnd)
                            rule.notifyAtStart = scheduleNotifyAtStart
                            rule.notifyAtEnd = scheduleNotifyAtEnd
                            rule.pendingLegacyRelaxation = nil
                            schedules.update(rule)
                        } else {
                            schedules.add(
                                name: scheduleName,
                                mode: scheduleMode,
                                selection: scheduleSelection,
                                websiteDomains: Self.domains(from: scheduleCustomDomains),
                                weekdays: scheduleWeekdays,
                                start: scheduleAllowedStart,
                                end: scheduleAllowedEnd,
                                notifyAtStart: scheduleNotifyAtStart,
                                notifyAtEnd: scheduleNotifyAtEnd
                            )
                        }
                        if schedules.errorMessage == nil {
                            isSchedulePickerPresented = false
                        }
                    }
                    .disabled(
                        scheduleName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || scheduleWeekdays.isEmpty
                            || (scheduleSelection.applicationTokens.isEmpty
                            && scheduleSelection.categoryTokens.isEmpty
                            && scheduleSelection.webDomainTokens.isEmpty
                            && Self.domains(from: scheduleCustomDomains).isEmpty)
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var scheduleTimingControls: some View {
        VStack(spacing: 12) {
            Picker("Schedule mode", selection: $scheduleMode) {
                Text("Blocked hours").tag(ScheduleRule.Mode.blockedHours)
                Text("Allowed hours").tag(ScheduleRule.Mode.allowedHours)
            }
            .pickerStyle(.segmented)

            HStack(spacing: 5) {
                ForEach(1...7, id: \.self) { weekday in
                    Button(Self.weekdayName(weekday)) {
                        if scheduleWeekdays.contains(weekday) {
                            scheduleWeekdays.remove(weekday)
                        } else {
                            scheduleWeekdays.insert(weekday)
                        }
                    }
                    .font(NoxaType.captionSemibold)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background(
                        scheduleWeekdays.contains(weekday) ? NoxaTheme.accent : Color.white.opacity(0.08),
                        in: Capsule()
                    )
                    .foregroundStyle(scheduleWeekdays.contains(weekday) ? .black : NoxaTheme.primaryText)
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(scheduleMode == .allowedHours ? "AVAILABLE FROM" : "BLOCK FROM")
                        .font(NoxaType.caption2Bold)
                        .foregroundStyle(NoxaTheme.secondaryText)
                    DatePicker("From", selection: $scheduleAllowedStart, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    Text("UNTIL")
                        .font(NoxaType.caption2Bold)
                        .foregroundStyle(NoxaTheme.secondaryText)
                    DatePicker("Until", selection: $scheduleAllowedEnd, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Toggle("Remind me when this schedule starts", isOn: $scheduleNotifyAtStart)
                .tint(NoxaTheme.accent)
            Toggle("Remind me when this schedule ends", isOn: $scheduleNotifyAtEnd)
                .tint(NoxaTheme.accent)
            Text("Reminders need notification permission and may arrive late if iOS delays a schedule callback. Blocking does not depend on reminders.")
                .font(NoxaType.caption)
                .foregroundStyle(NoxaTheme.secondaryText)
        }
    }

    private var safariFilterRecentlyConnected: Bool {
        guard let safariFilterLastSeenAt else { return false }
        return safariExtensionEnabled != false
            && (0..<5 * 60).contains(Date().timeIntervalSince(safariFilterLastSeenAt))
    }

    private var safariFilterStatusMessage: String {
        if safariExtensionEnabled == false {
            return "Turn on Noxa Instagram Filter in Settings → Apps → Safari → Extensions, then allow access to instagram.com. You can also block Instagram with a schedule or your blocklist."
        }
        if safariFilterRecentlyConnected {
            return "Noxa recently connected to Instagram in Safari. Check Reels and Explore there; this connection alone cannot confirm that every page element was hidden."
        }
        return "Noxa has not recently connected to Instagram in Safari. Open the site, allow extension access, and refresh it. If filtering stays unavailable, block Instagram with a schedule or your blocklist."
    }

    private func refreshSafariExtensionStatus() async {
        safariFilterLastSeenAt = AppGroupStore.shared.safariFilterLastSeenAt
        if #available(iOS 26.2, *) {
            let state = try? await SFSafariExtensionManager.stateOfExtension(
                withIdentifier: "LycheeCorp.Noxa.SafariFilter"
            )
            safariExtensionEnabled = state?.isEnabled
        }
    }

    private static func minutesSinceMidnight(_ date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private static func dateForScheduleMinute(_ minute: Int) -> Date {
        Calendar.current.date(from: DateComponents(
            year: 2001, month: 1, day: 1,
            hour: minute / 60, minute: minute % 60
        )) ?? Date()
    }

    private static func domains(from input: String) -> [String] {
        input.split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    nonisolated private static func weekdayName(_ weekday: Int) -> String {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        return (1...7).contains(weekday) ? names[weekday - 1] : ""
    }

    nonisolated private static func weekdaySummary(_ weekdays: Set<Int>) -> String {
        if weekdays == Set(1...7) { return "Every day" }
        return weekdays.sorted().map(weekdayName).joined(separator: ", ")
    }

    private var homeContent: some View {
        ScrollView {
            VStack(spacing: NoxaTheme.Spacing.section) {
                hero

                if !authorization.state.isApproved {
                    permissionCard
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }

                focusSessionCard
                if instagramSiteMode == .distractionFree && instagramAppBlockEnabled {
                    Button(action: openInstagramInSafari) {
                        Label("Open Instagram in Safari", systemImage: "safari")
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                    .noxaCard()
                }
                homeActiveRulesCard
                if schedules.enabledCount > 0 {
                    homeScheduleCard
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
                quickSetupCard
            }
            .noxaAnimation(value: authorization.state.isApproved)
            .noxaAnimation(value: schedules.enabledCount)
            .noxaAnimation(value: focusSession.isActive)
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
    }

    private var focusStartReviewSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoxaTheme.Spacing.section) {
                    NoxaScreenHeader(
                        title: "Ready to focus?",
                        subtitle: "Noxa will block these selected distractions for \(Self.durationLabel(minutes: chosenDurationMinutes))."
                    )

                    VStack(alignment: .leading, spacing: NoxaTheme.Spacing.row) {
                        NoxaCardHeader(title: "Duration", systemImage: "timer")

                        Stepper(
                            "Duration: \(Self.durationLabel(minutes: chosenDurationMinutes))",
                            value: $selectedDurationMinutes,
                            in: NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes...maximumFocusMinutes,
                            step: 5
                        )
                        .font(NoxaType.subheadlineMedium)
                        .onChange(of: selectedDurationMinutes) { _ in isCustomDuration = false }

                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Label(
                                "Ends at \(context.date.addingTimeInterval(TimeInterval(chosenDurationMinutes * 60)).formatted(date: .abbreviated, time: .shortened))",
                                systemImage: "clock"
                            )
                            .font(NoxaType.subheadline)
                            .foregroundStyle(NoxaTheme.secondaryText)
                        }
                    }
                    .noxaCard()

                    VStack(alignment: .leading, spacing: NoxaTheme.Spacing.row) {
                        NoxaCardHeader(title: "Will be blocked", systemImage: "shield.lefthalf.filled")

                        tokenRows(for: restrictions.selection)
                        ForEach(websites.domains, id: \.self) { domain in
                            Label(domain, systemImage: "globe")
                                .font(NoxaType.subheadline)
                                .accessibilityLabel("Website \(domain)")
                        }
                    }
                    .noxaCard()

                    if focusSession.strictModeEnabled {
                        Label(
                            "Strict Mode is on. You cannot end this session early in Noxa. It lasts at most four hours.",
                            systemImage: "lock.fill"
                        )
                        .font(NoxaType.subheadlineSemibold)
                        .foregroundStyle(NoxaTheme.warning)
                    }
                }
                .padding(.horizontal, NoxaTheme.Spacing.screen)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                Button("Start Focus") {
                    isFocusStartReviewPresented = false
                    beginFocusSession(intention: "")
                }
                .buttonStyle(NoxaPrimaryButtonStyle())
                .disabled(
                    !authorization.state.isApproved
                        || !hasFocusRestrictions
                        || focusSession.isActive
                        || !subscriptions.canEnterApp(for: authentication.userID)
                )
                .padding(.horizontal, NoxaTheme.Spacing.screen)
                .padding(.vertical, 12)
                .background(NoxaTheme.background.opacity(0.96))
            }
            .noxaScreenBackground()
            .navigationTitle("Review Focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isFocusStartReviewPresented = false }
                }
            }
        }
        .tint(NoxaTheme.accent)
        .font(NoxaType.body)
        .preferredColorScheme(.dark)
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Text("FOCUS TIME")
                .font(NoxaTheme.font(12, weight: .bold, relativeTo: .caption))
                .tracking(1.6)
                .foregroundStyle(NoxaTheme.accent)

            Text("\(dailyFocusMinutes)")
                .font(NoxaTheme.font(68, weight: .medium, relativeTo: .largeTitle))
                .monospacedDigit()
                .tracking(-1.5)
                .contentTransition(.numericText())
                .noxaAnimation(NoxaMotion.spring, value: dailyFocusMinutes)

            Text("\(dailyFocusMinutes == 1 ? "minute" : "minutes") focused today")
                .font(NoxaTheme.font(16, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(NoxaTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
    }

    private var homeScheduleCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 12) {
                NoxaCardHeader(title: "Schedules", systemImage: "calendar.badge.clock")

                ForEach(schedules.configurations.filter(\.isEnabled)) { configuration in
                    let isBlocking = ScheduleRuleEvaluator.isBlocking(
                        configuration,
                        at: context.date,
                        calendar: .autoupdatingCurrent
                    )
                    DisclosureGroup {
                        tokenRows(for: configuration.selection)
                        ForEach(configuration.websiteDomains, id: \.self) { domain in
                            Label(domain, systemImage: "globe")
                                .font(NoxaType.subheadline)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(configuration.name)
                                .font(NoxaType.subheadlineSemibold)
                            Text(isBlocking
                                 ? "This schedule blocks selected targets"
                                 : "This schedule is not blocking now")
                                .font(NoxaType.caption)
                                .foregroundStyle(isBlocking ? NoxaTheme.warning : NoxaTheme.accent)
                            if !isBlocking {
                                Text("Another rule may still block a selection.")
                                    .font(NoxaType.caption)
                                    .foregroundStyle(NoxaTheme.secondaryText)
                            }
                            if let nextChange = ScheduleRuleEvaluator.nextChange(
                                for: configuration,
                                after: context.date,
                                calendar: .autoupdatingCurrent
                            ) {
                                Text("Changes at \(nextChange.formatted(date: .abbreviated, time: .shortened))")
                                    .font(NoxaType.caption)
                                    .foregroundStyle(NoxaTheme.secondaryText)
                            }
                        }
                    }
                }
            }
            .noxaCard()
        }
    }

    private var homeActiveRulesCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let plan = activeRestrictionPlan(at: context.date)
            if !plan.activeRuleIDs.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    NoxaCardHeader(title: "Active blocking rules", systemImage: "shield.lefthalf.filled")
                    Text("\(plan.activeRuleIDs.count) \(plan.activeRuleIDs.count == 1 ? "rule requests" : "rules request") blocking for \(plan.blockedTargets.count) selected \(plan.blockedTargets.count == 1 ? "item" : "items").")
                        .font(NoxaType.subheadline)
                    Text("Saved rules show what Noxa requested. Open a selected app or site to verify its shield.")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                .noxaCard()
            }
        }
    }

    private func activeRestrictionPlan(at date: Date) -> EffectiveRestrictions<RestrictionTarget> {
        let localStore = AppGroupStore.shared
        let focus: RestrictionOwnershipPlan.Focus?
        if let session = focusSession.activeSession,
           session.outcome == .active,
           let configuration = try? localStore.loadFocusSessionRestrictions() {
            focus = RestrictionOwnershipPlan.Focus(
                id: session.id,
                plannedEndAt: session.plannedEndAt,
                isPomodoro: focusSession.hasPomodoroCycle,
                restrictions: configuration
            )
        } else {
            focus = nil
        }

        return RestrictionOwnershipPlan.evaluate(
            .init(
                focus: focus,
                schedules: schedules.configurations,
                dailyLimits: dailyLimits.configurations,
                reachedDailyEventNames: localStore.reachedDailyLimitEventNames(at: date),
                isDailyMonitoring: dailyLimits.isMonitoring,
                manualShield: try? localStore.loadManualShield(),
                blockedWebsiteDomains: websites.isBlocklistActive ? websites.domains : [],
                instagramAppBlock: InstagramSiteProtectionService.shouldApplyAppBlock(
                    mode: localStore.instagramSiteMode,
                    isEnabled: localStore.instagramAppBlockEnabled,
                    allowedUntil: localStore.safariFilterAllowedUntil,
                    appSelection: instagramAppSelection,
                    now: date
                ) ? instagramAppSelection : nil
            ),
            at: date,
            calendar: .autoupdatingCurrent
        )
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            NoxaCardHeader(title: "Screen Time access required", systemImage: "hourglass")

            Text(authorization.statusDescription)
                .foregroundStyle(NoxaTheme.secondaryText)

            Button {
                isRequestingAuthorization = true
                Task { @MainActor in
                    await authorization.requestAuthorization()
                    isRequestingAuthorization = false
                }
            } label: {
                HStack(spacing: 8) {
                    if isRequestingAuthorization {
                        ProgressView()
                            .tint(.black)
                    }
                    Text(isRequestingAuthorization ? "Requesting…" : "Enable Screen Time Access")
                }
            }
            .buttonStyle(NoxaPrimaryButtonStyle())
            .disabled(isRequestingAuthorization)

            if let errorMessage = authorization.errorMessage {
                Text(errorMessage)
                    .font(NoxaType.footnote)
                    .foregroundStyle(.red)
            }
        }
        .noxaCard()
    }

    private var focusSessionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: focusSession.isActive || focusSession.hasPomodoroCycle ? .leading : .center, spacing: 4) {
                    Text(focusSession.pomodoroBreakEndsAt != nil
                         ? "Pomodoro break"
                         : (focusSession.isActive ? "Stay focused" : "Start a focus"))
                        .font(NoxaType.title2)
                    Text(focusSession.pomodoroBreakEndsAt != nil
                         ? "The next work round starts automatically."
                         : (focusSession.isActive ? "Your focus session is running." : "Choose a duration and begin."))
                        .font(NoxaType.subheadline)
                        .foregroundStyle(NoxaTheme.secondaryText)
                        .multilineTextAlignment(focusSession.isActive || focusSession.hasPomodoroCycle ? .leading : .center)
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: focusSession.isActive || focusSession.hasPomodoroCycle ? .leading : .center
                )
                if focusSession.isActive {
                    Text("FOCUS")
                        .font(NoxaType.captionBold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(NoxaTheme.accent, in: Capsule())
                } else if focusSession.pomodoroBreakEndsAt != nil {
                    Text("BREAK")
                        .font(NoxaType.captionBold)
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(NoxaTheme.accent, in: Capsule())
                }
            }

            if focusSession.isPausedForScreenTimeAccess {
                screenTimePauseNotice
            }

            if let activeSession = focusSession.activeSession {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, activeSession.plannedEndAt.timeIntervalSince(context.date))
                    let progress = min(max(remaining / Double(activeSession.plannedDurationSeconds), 0), 1)
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .stroke(Color.white.opacity(0.08), lineWidth: 10)
                            Circle()
                                .trim(from: 0, to: progress)
                                .stroke(
                                    NoxaTheme.accent,
                                    style: StrokeStyle(lineWidth: 10, lineCap: .round)
                                )
                                .rotationEffect(.degrees(-90))

                            VStack(spacing: 3) {
                                Text(Self.durationString(seconds: Int(remaining)))
                                    .font(NoxaTheme.font(38, weight: .medium, relativeTo: .largeTitle))
                                    .monospacedDigit()
                                    .tracking(-1.5)
                                Text("remaining")
                                    .font(NoxaType.caption)
                                    .foregroundStyle(NoxaTheme.secondaryText)
                            }
                        }
                        .frame(width: 190, height: 190)

                        Text("Session ends at \(activeSession.plannedEndAt.formatted(date: .omitted, time: .shortened))")
                            .font(NoxaType.subheadlineMedium)
                            .foregroundStyle(NoxaTheme.secondaryText)

                        if focusSession.monitorReceipt(for: activeSession) != nil {
                            Label("Screen Time monitor applied your block settings.", systemImage: "checkmark.shield.fill")
                                .font(NoxaType.caption)
                                .foregroundStyle(NoxaTheme.secondaryText)
                        } else {
                            Label("Block settings requested; waiting for the Screen Time monitor.", systemImage: "clock.arrow.circlepath")
                                .font(NoxaType.caption)
                                .foregroundStyle(NoxaTheme.secondaryText)
                            if context.date.timeIntervalSince(activeSession.startedAt) > 30 {
                                Text("If selected apps are still available, check Screen Time access in Settings.")
                                    .font(NoxaType.caption)
                                    .foregroundStyle(NoxaTheme.secondaryText)
                            }
                        }

                        if let round = focusSession.pomodoroRoundDescription {
                            Text(round)
                                .font(NoxaType.subheadlineSemibold)
                        }

                        if let intention = focusSession.activeIntention, !intention.isEmpty {
                            Label(intention, systemImage: "scope")
                                .font(NoxaType.subheadlineMedium)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if activeSession.isStrict {
                    Label("Strict Focus · Ends at \(activeSession.plannedEndAt.formatted(date: .omitted, time: .shortened))", systemImage: "lock.fill")
                        .font(NoxaType.subheadlineSemibold)
                        .foregroundStyle(NoxaTheme.secondaryText)
                } else {
                    Button("End Session Early") {
                        isEndRitualPresented = true
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                }
            } else if let breakEndsAt = focusSession.pomodoroBreakEndsAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack(spacing: 10) {
                        Text(Self.durationString(seconds: Int(max(0, breakEndsAt.timeIntervalSince(context.date)))))
                            .font(NoxaTheme.font(42, weight: .medium, relativeTo: .largeTitle))
                            .monospacedDigit()
                        Text("Break ends at \(breakEndsAt.formatted(date: .omitted, time: .shortened))")
                            .font(NoxaType.subheadline)
                            .foregroundStyle(NoxaTheme.secondaryText)
                        if let round = focusSession.pomodoroRoundDescription {
                            Text(round).font(NoxaType.subheadlineSemibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                Button("Stop Pomodoro") {
                    if let cycle = focusSession.pomodoroCycle {
                        notifications.cancelPomodoroCycle(cycle.id)
                    }
                    focusSession.stopPomodoroDuringBreak()
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
            } else {
                VStack(spacing: 2) {
                    Text(Self.durationLabel(minutes: chosenDurationMinutes))
                        .font(NoxaTheme.font(58, weight: .medium, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .tracking(-2)
                        .contentTransition(.numericText())
                        .noxaAnimation(NoxaMotion.spring, value: chosenDurationMinutes)
                    Text("focus session")
                        .font(NoxaType.subheadline)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                LazyVGrid(columns: durationGridColumns(regularCount: 3, spacing: 9), spacing: 9) {
                    ForEach([30, 45, 60, 120, 180], id: \.self) { minutes in
                        durationButton(title: Self.durationLabel(minutes: minutes), minutes: minutes)
                    }

                    Button("Custom") {
                        customDurationText = String(selectedDurationMinutes)
                        isCustomDuration = true
                        isCustomDurationFieldFocused = true
                    }
                    .buttonStyle(NoxaDurationButtonStyle(isSelected: isCustomDuration))
                }

                if isCustomDuration {
                    VStack(spacing: 18) {
                        HStack(spacing: 10) {
                            Button {
                                adjustCustomDuration(by: -5)
                            } label: {
                                Image(systemName: "minus")
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(.plain)
                            .background(Color.white.opacity(0.08), in: Circle())

                            TextField("Minutes", text: $customDurationText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.center)
                                .font(NoxaTheme.font(22, weight: .semibold, relativeTo: .title3))
                                .padding(.horizontal, 14)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color.white.opacity(0.06), in: Capsule())
                                .overlay { Capsule().stroke(NoxaTheme.subtleBorder, lineWidth: 1) }
                                .focused($isCustomDurationFieldFocused)
                                .onChange(of: customDurationText) { value in
                                    customDurationText = String(value.filter(\.isNumber).prefix(3))
                                }

                            Button {
                                adjustCustomDuration(by: 5)
                            } label: {
                                Image(systemName: "plus")
                                    .frame(width: 42, height: 42)
                            }
                            .buttonStyle(.plain)
                            .background(Color.white.opacity(0.08), in: Circle())
                        }

                        Text("Enter \(NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes)–\(maximumFocusMinutes) minutes.")
                            .font(NoxaType.footnote)
                            .foregroundStyle(NoxaTheme.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)

                        Button {
                            commitCustomDuration()
                            isCustomDurationFieldFocused = false
                        } label: {
                            Label("Done Entering Time", systemImage: "keyboard.chevron.compact.down")
                        }
                        .buttonStyle(NoxaSecondaryButtonStyle())
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }

                if hasFocusRestrictions {
                    Label("\(focusRestrictionCount) selected distraction\(focusRestrictionCount == 1 ? "" : "s") will be blocked", systemImage: "checkmark.shield.fill")
                        .font(NoxaType.footnoteMedium)
                        .foregroundStyle(NoxaTheme.accent)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Button {
                        selectedTab = .blocklist
                    } label: {
                        Label("Choose distractions first", systemImage: "plus")
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                }

                Button("Start \(Self.durationLabel(minutes: chosenDurationMinutes)) Focus") {
                    commitCustomDuration()
                    isCustomDurationFieldFocused = false
                    isFocusStartReviewPresented = true
                }
                .buttonStyle(NoxaPrimaryButtonStyle())
                .disabled(
                    !authorization.state.isApproved
                        || !hasFocusRestrictions
                        || restrictions.isShieldActive
                        || monitoring.isMonitoring
                )
            }

            if let errorMessage = focusSession.errorMessage {
                Text(errorMessage)
                    .font(NoxaType.footnote)
                    .foregroundStyle(.red)
            }
        }
        .noxaAnimation(value: isCustomDuration)
        .noxaCard()
    }

    private var screenTimePauseNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Blocks are paused because Screen Time access is off.", systemImage: "pause.circle.fill")
                .font(NoxaType.subheadlineSemibold)
                .foregroundStyle(NoxaTheme.warning)
            Text(screenTimePauseDetail)
                .font(NoxaType.footnote)
                .foregroundStyle(NoxaTheme.secondaryText)
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
            .buttonStyle(NoxaSecondaryButtonStyle())
        }
        .padding(14)
        .background(
            NoxaTheme.warning.opacity(0.08),
            in: RoundedRectangle(cornerRadius: NoxaTheme.Radius.field, style: .continuous)
        )
    }

    private var screenTimePauseDetail: String {
        let end = (focusSession.activeSession?.plannedEndAt ?? focusSession.pomodoroBreakEndsAt)
            .map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        return "Turn it back on in Settings → Screen Time → Apps with Screen Time Access to resume\(end). This session won't count as completed."
    }

    private var quickSetupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    withAnimation(NoxaMotion.spring) {
                        NoxaHaptics.selection()
                        isHomeBlocklistExpanded.toggle()
                    }
                } label: {
                    HStack {
                        NoxaCardHeader(title: "Your blocklist", systemImage: "checklist")
                        Spacer()
                        Text("\(focusRestrictionCount)")
                            .font(NoxaType.caption.monospacedDigit())
                            .foregroundStyle(NoxaTheme.secondaryText)
                        Image(systemName: "chevron.down")
                            .font(NoxaType.captionBold)
                            .foregroundStyle(NoxaTheme.secondaryText)
                            .rotationEffect(.degrees(isHomeBlocklistExpanded ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Your blocklist, \(focusRestrictionCount) item\(focusRestrictionCount == 1 ? "" : "s")")
                .accessibilityValue(isHomeBlocklistExpanded ? "Expanded" : "Collapsed")
                .accessibilityAddTraits(.isButton)

                Button(focusSession.isActive ? "Add" : "Edit") {
                    presentRestrictionPicker()
                }
                .accessibilityLabel(focusSession.isActive ? "Add to blocklist" : "Edit blocklist")
                .font(NoxaType.subheadlineSemibold)
                .foregroundStyle(NoxaTheme.accent)
                .disabled(focusSession.hasPomodoroCycle && !focusSession.isActive)
            }

            Text(hasFocusRestrictions
                 ? "\(focusRestrictionCount) private selection\(focusRestrictionCount == 1 ? "" : "s") saved on this device."
                 : "Nothing selected yet.")
                .font(NoxaType.subheadline)
                .foregroundStyle(NoxaTheme.secondaryText)

            if isHomeBlocklistExpanded && hasFocusRestrictions {
                Divider()
                    .transition(.opacity)

                tokenRows(for: restrictions.selection)

                ForEach(websites.domains, id: \.self) { domain in
                    Label(domain, systemImage: "globe")
                        .font(NoxaType.subheadline)
                        .accessibilityLabel("Website \(domain)")
                }
            }

            if !hasFocusRestrictions {
                Button("Choose Apps and Websites") {
                    presentRestrictionPicker()
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
                .disabled(!authorization.state.isApproved)
            }
        }
        .noxaCard()
    }

    private var blocklistContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoxaTheme.Spacing.section) {
                Text("Apps and websites stay organized separately and remain private on this device.")
                    .font(NoxaType.body)
                    .foregroundStyle(NoxaTheme.secondaryText)

                if focusSession.isActive {
                    Label("You can add distractions now, but existing ones stay locked until the session ends", systemImage: "lock.fill")
                        .font(NoxaType.footnoteSemibold)
                        .foregroundStyle(.orange)
                } else if focusSession.hasPomodoroCycle {
                    Label("Blocklist changes resume after you stop the Pomodoro during a break or finish all four rounds", systemImage: "lock.fill")
                        .font(NoxaType.footnoteSemibold)
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        NoxaCardHeader(title: "Apps", systemImage: "square.grid.2x2")
                        Spacer()
                        let appCount = restrictions.selection.applicationTokens.count
                            + restrictions.selection.categoryTokens.count
                        Text("\(appCount)")
                            .font(NoxaType.caption.monospacedDigit())
                            .foregroundStyle(NoxaTheme.secondaryText)
                            .accessibilityLabel("\(appCount) apps and categories selected")
                    }

                    if restrictions.selection.applicationTokens.isEmpty,
                       restrictions.selection.categoryTokens.isEmpty {
                        Text("No apps or categories selected.")
                            .font(NoxaType.subheadline)
                            .foregroundStyle(NoxaTheme.secondaryText)
                    } else {
                        tokenRows(for: restrictions.selection, includeWebDomains: false)
                    }

                    Button(focusSession.isActive ? "Add Apps" : (restrictions.hasSelection ? "Edit Apps" : "Choose Apps")) {
                        presentRestrictionPicker()
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                    .disabled(!authorization.state.isApproved || (focusSession.hasPomodoroCycle && !focusSession.isActive))
                }
                .noxaCard()

                websiteCard
                pomodoroCard

            }
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
    }

    private var dailyLimitsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoxaTheme.Spacing.section) {
                Text("Set a daily allowance for distracting apps. Noxa applies each limit locally using Screen Time.")
                    .font(NoxaType.body)
                    .foregroundStyle(NoxaTheme.secondaryText)

                dailyLimitsCard
                scheduleCard
            }
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
    }

    private var websiteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                NoxaCardHeader(title: "Website blocklist", systemImage: "globe")
                Spacer()
                Text("\(websites.domains.count)/\(WebsiteBlocklistService.maximumDomains)")
                    .font(NoxaType.caption.monospacedDigit())
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .accessibilityLabel("\(websites.domains.count) of \(WebsiteBlocklistService.maximumDomains) websites")
            }

            Text("Add domains such as reddit.com or news.ycombinator.com. Noxa normalizes them and applies them locally during a focus session.")
                .font(NoxaType.subheadline)
                .foregroundStyle(NoxaTheme.secondaryText)

            HStack(spacing: 10) {
                TextField("reddit.com", text: $newDomain)
                    .accessibilityLabel("Website to block")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(NoxaTextFieldStyle())

                Button("Add Website") {
                    if websites.addDomain(newDomain) {
                        newDomain = ""
                        NoxaHaptics.tap()
                    }
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
                .fixedSize()
                .disabled(
                    websites.domains.count >= WebsiteBlocklistService.maximumDomains
                        || (focusSession.hasPomodoroCycle && !focusSession.isActive)
                )
            }

            if websites.domains.isEmpty {
                if restrictions.selection.webDomainTokens.isEmpty {
                    Text("No websites added.")
                        .font(NoxaType.subheadline)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
            } else {
                ForEach(websites.domains, id: \.self) { domain in
                    HStack {
                        Text(domain)
                            .font(NoxaType.subheadline.monospaced())
                            .accessibilityLabel("Website \(domain)")
                        Spacer()
                        Button {
                            websites.removeDomain(domain)
                            NoxaHaptics.selection()
                        } label: {
                            Text("Remove")
                                .font(NoxaType.captionSemibold)
                                .foregroundStyle(NoxaTheme.secondaryText)
                                .frame(minWidth: 70, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(domain)")
                        .disabled(focusSession.isActive || focusSession.hasPomodoroCycle)
                    }
                }
            }

            ForEach(Array(restrictions.selection.webDomainTokens), id: \.self) { token in
                Label(token)
                    .labelStyle(.titleAndIcon)
                    .font(NoxaType.subheadline)
            }

            if let errorMessage = websites.errorMessage {
                Text(errorMessage)
                    .font(NoxaType.footnote)
                    .foregroundStyle(.red)
            }
        }
        .noxaCard()
    }

    private var pomodoroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                NoxaCardHeader(title: "Pomodoro", systemImage: "timer.circle")
                Spacer()
                Text("\(pomodoroWorkMinutes)/\(pomodoroBreakMinutes)")
                    .font(NoxaType.captionSemibold.monospacedDigit())
                    .foregroundStyle(NoxaTheme.accent)
                    .accessibilityLabel("\(pomodoroWorkMinutes) minutes focus, \(pomodoroBreakMinutes) minutes break")
            }

            Text("Four work rounds start automatically, with a break between each. Noxa releases the focus blocklist during breaks and reminds you before work resumes.")
                .font(NoxaType.subheadline)
                .foregroundStyle(NoxaTheme.secondaryText)

            LazyVGrid(columns: durationGridColumns(regularCount: 4, spacing: 8), spacing: 8) {
                ForEach([(25, 5), (50, 10), (90, 15)], id: \.0) { preset in
                    Button("\(preset.0)/\(preset.1)") {
                        pomodoroWorkMinutes = preset.0
                        pomodoroBreakMinutes = preset.1
                        isCustomPomodoro = false
                    }
                    .accessibilityLabel("\(preset.0) minutes focus, \(preset.1) minutes break")
                    .buttonStyle(
                        NoxaDurationButtonStyle(
                            isSelected: pomodoroWorkMinutes == preset.0
                                && pomodoroBreakMinutes == preset.1
                                && !isCustomPomodoro
                        )
                    )
                }

                Button("Custom") {
                    isCustomPomodoro = true
                }
                .buttonStyle(NoxaDurationButtonStyle(isSelected: isCustomPomodoro))
            }

            if isCustomPomodoro {
                VStack(spacing: 10) {
                    Stepper(value: $pomodoroWorkMinutes, in: 15...240, step: 5) {
                        HStack {
                            Text("Focus time")
                            Spacer()
                            Text(Self.durationLabel(minutes: pomodoroWorkMinutes))
                                .monospacedDigit()
                                .foregroundStyle(NoxaTheme.accent)
                        }
                    }
                    Stepper(value: $pomodoroBreakMinutes, in: 5...60, step: 5) {
                        HStack {
                            Text("Break time")
                            Spacer()
                            Text(Self.durationLabel(minutes: pomodoroBreakMinutes))
                                .monospacedDigit()
                                .foregroundStyle(NoxaTheme.accent)
                        }
                    }
                }
                .font(NoxaType.subheadlineMedium)
                .padding(14)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if hasFocusRestrictions {
                Button("Start \(pomodoroWorkMinutes)-minute Pomodoro") {
                    if focusSession.strictModeEnabled {
                        strictStartIsPomodoro = true
                        isStrictStartConfirmationPresented = true
                    } else {
                        beginPomodoro()
                    }
                }
                .buttonStyle(NoxaPrimaryButtonStyle())
                .disabled(
                    !authorization.state.isApproved
                        || focusSession.isActive
                        || focusSession.hasPomodoroCycle
                        || restrictions.isShieldActive
                        || monitoring.isMonitoring
                )
            } else {
                Button("Choose Apps and Websites First") {
                    presentRestrictionPicker()
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
                .disabled(!authorization.state.isApproved)
            }
        }
        .noxaCard()
    }

    private var dailyLimitsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                NoxaCardHeader(title: "Daily limits", systemImage: "hourglass.bottomhalf.fill")
                Spacer()
                Text("\(dailyLimits.configurations.count)/\(DailyLimitService.maximumConfigurations)")
                    .font(NoxaType.caption.monospacedDigit())
                    .foregroundStyle(NoxaTheme.secondaryText)
            }

            Text("Give selected apps a daily allowance. Usage from earlier today counts. You can edit or stop limits at any time; other active blocks still apply.")
                .font(NoxaType.subheadline)
                .foregroundStyle(NoxaTheme.secondaryText)

            Text(notifications.canSchedule
                 ? "Noxa requests an alert about five minutes before a limit is reached. iOS may deliver it late."
                 : "Enable notifications for approaching-limit alerts. Daily limits still work without alerts.")
                .font(NoxaType.footnote)
                .foregroundStyle(NoxaTheme.secondaryText)

            Button("Add App Limit") {
                dailyLimitSelection = existingDailyLimitSelection
                selectedDailyLimitMinutes = 30
                isChoosingDailyLimitDuration = false
                isDailyLimitPickerPresented = true
            }
            .buttonStyle(NoxaSecondaryButtonStyle())
            .disabled(
                !authorization.state.isApproved
                    || dailyLimits.configurations.count >= DailyLimitService.maximumConfigurations
            )

            if dailyLimits.configurations.isEmpty {
                Text("No daily limits configured.")
                    .font(NoxaType.subheadline)
                    .foregroundStyle(NoxaTheme.secondaryText)
            } else {
                ForEach(dailyLimits.configurations) { configuration in
                    HStack(spacing: 12) {
                        Button {
                            dailyLimits.setEnabled(!configuration.isEnabled, for: configuration)
                        } label: {
                            Image(systemName: configuration.isEnabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(configuration.isEnabled ? .white : .secondary)
                                .font(.system(size: 22))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(configuration.isEnabled ? "Turn off daily limit" : "Turn on daily limit")

                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(configuration.selection.applicationTokens), id: \.self) { token in
                                Label(token)
                                    .labelStyle(.titleAndIcon)
                                    .font(NoxaType.subheadlineSemibold)
                            }
                            if configuration.selection.applicationTokens.isEmpty {
                                Text("App selection")
                                    .font(NoxaType.subheadlineSemibold)
                            }
                            Menu {
                                ForEach([10, 15, 30, 45, 60, 90, 120, 180, 240], id: \.self) { minutes in
                                    Button(Self.durationLabel(minutes: minutes)) {
                                        dailyLimits.updateMinutes(minutes, for: configuration)
                                    }
                                }
                            } label: {
                                Text("\(configuration.dailyLimitMinutes) min/day")
                                    .font(NoxaType.captionSemibold)
                                    .foregroundStyle(NoxaTheme.accent)
                                    .frame(minWidth: 96, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                        Spacer()
                        Button {
                            dailyLimits.remove(configuration)
                        } label: {
                            Text("Remove")
                                .font(NoxaType.captionSemibold)
                                .foregroundStyle(NoxaTheme.secondaryText)
                                .frame(minWidth: 70, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text(hasActiveDailyLimits ? "Daily limits active" : "Daily limits are off")
                    .font(NoxaType.subheadline)
                    .foregroundStyle(NoxaTheme.secondaryText)
                Spacer()
                Button {
                    if hasActiveDailyLimits {
                        dailyLimits.stopMonitoring()
                    } else {
                        dailyLimits.startMonitoring()
                    }
                } label: {
                    Text(hasActiveDailyLimits ? "Stop" : "Start Limits")
                        .font(NoxaType.subheadlineSemibold)
                        .foregroundStyle(NoxaTheme.accent)
                        .frame(minWidth: 100, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(
                    dailyLimits.configurations.filter(\.isEnabled).isEmpty
                        || (!hasActiveDailyLimits && !authorization.state.isApproved)
                )
            }

            if let errorMessage = dailyLimits.errorMessage {
                Text(errorMessage)
                    .font(NoxaType.footnote)
                    .foregroundStyle(.red)
            }
        }
        .noxaCard()
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                NoxaCardHeader(title: "Schedules", systemImage: "calendar.badge.clock")
                Spacer()
                Text("\(schedules.configurations.count)/\(RestrictionScheduleService.maximumConfigurations)")
                    .font(NoxaType.caption.monospacedDigit())
                    .foregroundStyle(NoxaTheme.secondaryText)
            }

            Text("Choose blocked or allowed hours, the days they apply, and the apps, categories, or websites. Changes take effect immediately.")
                .font(NoxaType.subheadline)
                .foregroundStyle(NoxaTheme.secondaryText)

            Button("Add Schedule") {
                schedules.clearError()
                scheduleToEdit = nil
                scheduleName = ""
                scheduleCustomDomains = ""
                scheduleSelection = FamilyActivitySelection()
                scheduleMode = .allowedHours
                scheduleWeekdays = Set(1...7)
                scheduleNotifyAtStart = false
                scheduleNotifyAtEnd = false
                scheduleAllowedStart = Self.dateForScheduleMinute(21 * 60)
                scheduleAllowedEnd = Self.dateForScheduleMinute(22 * 60)
                isSchedulePickerPresented = true
            }
            .buttonStyle(NoxaSecondaryButtonStyle())
            .disabled(
                !authorization.state.isApproved
                    || schedules.configurations.count >= RestrictionScheduleService.maximumConfigurations
            )

            if schedules.configurations.isEmpty {
                Text("No schedules configured.")
                    .font(NoxaType.subheadline)
                    .foregroundStyle(NoxaTheme.secondaryText)
            } else {
                ForEach(schedules.configurations) { configuration in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Button {
                                schedules.setEnabled(!configuration.isEnabled, for: configuration)
                            } label: {
                                Image(systemName: configuration.isEnabled ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(configuration.isEnabled ? NoxaTheme.accent : .secondary)
                            }
                            .buttonStyle(.plain)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(configuration.name)
                                    .font(NoxaType.subheadlineSemibold)
                                Text("\(configuration.mode == .allowedHours ? "Available" : "Blocked") \(Self.timeLabel(minutes: configuration.startMinutes))–\(Self.timeLabel(minutes: configuration.endMinutes))")
                                    .font(NoxaType.caption)
                                Text(Self.weekdaySummary(configuration.weekdays))
                                    .font(NoxaType.caption)
                                    .foregroundStyle(NoxaTheme.secondaryText)
                            }
                            Spacer()
                            Button("Edit") {
                                schedules.clearError()
                                scheduleToEdit = configuration
                                scheduleName = configuration.name
                                scheduleMode = configuration.mode
                                scheduleWeekdays = configuration.weekdays
                                scheduleNotifyAtStart = configuration.notifyAtStart
                                scheduleNotifyAtEnd = configuration.notifyAtEnd
                                scheduleAllowedStart = Self.dateForScheduleMinute(configuration.startMinutes)
                                scheduleAllowedEnd = Self.dateForScheduleMinute(configuration.endMinutes)
                                scheduleSelection = configuration.selection
                                scheduleCustomDomains = configuration.websiteDomains.joined(separator: ", ")
                                isSchedulePickerPresented = true
                            }
                            .font(NoxaType.captionSemibold)
                            .foregroundStyle(NoxaTheme.accent)
                            Button("Rename") {
                                scheduleToRename = configuration
                                renamedScheduleName = configuration.name
                            }
                            .font(NoxaType.captionSemibold)
                            .foregroundStyle(NoxaTheme.secondaryText)
                            Button("Remove") {
                                schedules.remove(configuration)
                            }
                            .font(NoxaType.captionSemibold)
                            .foregroundStyle(NoxaTheme.secondaryText)
                        }

                        tokenRows(for: configuration.selection)
                        ForEach(configuration.websiteDomains, id: \.self) { domain in
                            Label(domain, systemImage: "globe")
                                .font(NoxaType.subheadline)
                        }

                        if let pending = configuration.pendingLegacyRelaxation {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Label(
                                        pending.action == .remove ? "Removal pending" : "Disable pending",
                                        systemImage: "clock.badge.exclamationmark"
                                    )
                                    .font(NoxaType.captionSemibold)
                                    .foregroundStyle(NoxaTheme.warning)

                                    Text("Takes effect \(pending.effectiveAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(NoxaType.caption2)
                                        .foregroundStyle(NoxaTheme.secondaryText)
                                }

                                Spacer()

                                Button("Cancel Change") {
                                    schedules.cancelPendingRelaxation(for: configuration)
                                }
                                .font(NoxaType.captionSemibold)
                                .foregroundStyle(NoxaTheme.accent)
                            }
                            .padding(12)
                            .background(
                                NoxaTheme.warning.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            if let errorMessage = schedules.errorMessage {
                Text(errorMessage)
                    .font(NoxaType.footnote)
                    .foregroundStyle(.red)
            }
        }
        .noxaCard()
        .alert(
            "Rename schedule",
            isPresented: Binding(
                get: { scheduleToRename != nil },
                set: { if !$0 { scheduleToRename = nil } }
            )
        ) {
            TextField("Schedule name", text: $renamedScheduleName)
            Button("Save") {
                if let scheduleToRename {
                    schedules.rename(scheduleToRename, to: renamedScheduleName)
                }
                scheduleToRename = nil
            }
            Button("Cancel", role: .cancel) { scheduleToRename = nil }
        }
    }

    @ViewBuilder
    private func tokenRows(
        for selection: FamilyActivitySelection,
        includeWebDomains: Bool = true
    ) -> some View {
        ForEach(Array(selection.applicationTokens), id: \.self) { token in
            Label(token)
                .labelStyle(.titleAndIcon)
                .font(NoxaType.subheadline)
        }
        ForEach(Array(selection.categoryTokens), id: \.self) { token in
            Label(token)
                .labelStyle(.titleAndIcon)
                .font(NoxaType.subheadline)
        }
        if includeWebDomains {
            ForEach(Array(selection.webDomainTokens), id: \.self) { token in
                Label(token)
                    .labelStyle(.titleAndIcon)
                    .font(NoxaType.subheadline)
            }
        }
    }

    private var statsContent: some View {
        let statistics = FocusStatistics(
            history: focusSession.history,
            now: statsReferenceDate,
            calendar: .autoupdatingCurrent
        )
        let period = FocusStatistics.period(
            history: focusSession.history,
            days: selectedStatsRange.rawValue,
            now: statsReferenceDate,
            calendar: .autoupdatingCurrent
        )
        let scheduleCommitment = ScheduleCommitmentEvaluator.lastSevenDays(
            events: schedules.commitmentEvents,
            now: statsReferenceDate,
            calendar: .autoupdatingCurrent
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: NoxaTheme.Spacing.section) {
                VStack(spacing: 8) {
                    Text("FOCUS TIME")
                        .font(NoxaTheme.font(12, weight: .bold, relativeTo: .caption))
                        .tracking(1.6)
                        .foregroundStyle(NoxaTheme.accent)
                    Text(Self.focusTimeLabel(minutes: statistics.totalFocusMinutes))
                        .font(NoxaTheme.font(48, weight: .bold, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                    Text("since you started using Noxa")
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                .frame(maxWidth: .infinity)
                .noxaStatsCard()

                LazyVGrid(columns: durationGridColumns(regularCount: 4, spacing: 8), spacing: 8) {
                    ForEach(StatsRange.allCases, id: \.self) { range in
                        Button(range.title) {
                            selectedStatsRange = range
                        }
                        .buttonStyle(NoxaDurationButtonStyle(isSelected: selectedStatsRange == range))
                    }
                }

                HStack(spacing: 12) {
                    statCard(title: "Focus time", value: Self.compactFocusTime(minutes: period.focusMinutes))
                    statCard(title: "Completed", value: "\(period.completedSessions)")
                }

                HStack(spacing: 12) {
                    statCard(title: "Completion", value: "\(period.completionRate)%")
                    statCard(title: "Days focused", value: "\(period.focusedDays)")
                }

                VStack(alignment: .leading, spacing: 10) {
                    NoxaCardHeader(title: "Follow-through", systemImage: "chart.line.uptrend.xyaxis")
                    Text("\(period.completionRate)% completion rate")
                        .font(NoxaType.title2)
                    Text("\(period.completedSessions) completed · \(period.abandonedSessions) ended early")
                        .font(NoxaType.subheadline)
                        .foregroundStyle(NoxaTheme.secondaryText)
                    Text("\(statistics.currentStreak)-day current streak · \(statistics.longestStreak)-day best")
                        .font(NoxaType.caption)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                .noxaStatsCard()

                VStack(alignment: .leading, spacing: 10) {
                    NoxaCardHeader(title: "Schedule follow-through · last 7 days", systemImage: "calendar.badge.checkmark")
                    if scheduleCommitment.totalWindows == 0 {
                        Text("Tracking starts with the next full schedule window.")
                            .font(NoxaType.subheadline)
                            .foregroundStyle(NoxaTheme.secondaryText)
                    } else {
                        Text("\(scheduleCommitment.percentage)% kept")
                            .font(NoxaType.title2)
                        Text("\(scheduleCommitment.keptWindows) kept · \(scheduleCommitment.interruptedWindows) changed or stopped early")
                            .font(NoxaType.subheadline)
                            .foregroundStyle(NoxaTheme.secondaryText)
                    }
                    Text("Based on whether schedules stayed enabled through their planned windows, not measured app use or proof of blocking.")
                        .font(NoxaType.caption)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                .noxaStatsCard()

                recentSessionsCard
            }
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
    }

    private var recentSessionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            NoxaCardHeader(title: "Recent sessions", systemImage: "clock.arrow.circlepath")

            if focusSession.history.isEmpty {
                Text("Complete a focus session and it will appear here.")
                    .foregroundStyle(NoxaTheme.secondaryText)
            } else {
                ForEach(focusSession.history.prefix(8)) { session in
                    HStack(spacing: 12) {
                        Image(systemName: session.outcome == .completed ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                            .foregroundStyle(session.outcome == .completed ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.outcome.displayName)
                                .font(NoxaType.subheadlineSemibold)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(NoxaType.caption)
                                .foregroundStyle(NoxaTheme.secondaryText)
                        }
                        Spacer()
                        Text(Self.durationLabel(
                            minutes: (session.actualDurationSeconds ?? session.plannedDurationSeconds) / 60
                        ))
                            .font(NoxaType.subheadline.monospacedDigit())
                            .foregroundStyle(NoxaTheme.secondaryText)
                    }
                    if session.id != focusSession.history.prefix(8).last?.id {
                        Divider()
                            .overlay(Color.white.opacity(0.12))
                    }
                }
            }

            Text(cloudSync.historyStatusDescription)
                .font(NoxaType.footnote)
                .foregroundStyle(NoxaTheme.secondaryText)
        }
        .noxaStatsCard()
    }

    private var accountContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoxaTheme.Spacing.section) {
                settingsSectionTitle("Account")

                VStack(alignment: .leading, spacing: 12) {
                    NoxaCardHeader(title: "Signed in", systemImage: "checkmark.shield.fill")
                    if let displayName = authentication.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(NoxaTheme.font(22, weight: .semibold, relativeTo: .title3))
                    }
                    Text(authentication.userEmail ?? "Apple account")
                        .foregroundStyle(NoxaTheme.secondaryText)
                        .accessibilityLabel("Signed in as \(authentication.userEmail ?? "Apple account")")
                    Text("Screen Time selections and active shields stay on this device. Focus history and website domains sync securely when you’re online.")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                .noxaCard()

                VStack(alignment: .leading, spacing: 12) {
                    Label("Noxa subscription", systemImage: subscriptions.hasAccess ? "checkmark.seal.fill" : "creditcard")
                        .font(NoxaType.headline)
                    Text(subscriptions.hasAccess
                         ? "\(subscriptions.activePlanDisplayName) is active."
                         : "A subscription is required to use Noxa.")
                        .font(NoxaType.subheadline)
                        .foregroundStyle(NoxaTheme.secondaryText)
                    Button(subscriptions.hasAccess ? "View Subscription" : "See Subscription Plans") {
                        isPaywallPresented = true
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                }
                .noxaCard()

                settingsSectionTitle("Preferences")

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Strict Mode", isOn: Binding(
                        get: { focusSession.strictModeEnabled },
                        set: {
                            focusSession.setStrictModeEnabled($0)
                            NoxaHaptics.selection()
                        }
                    ))
                        .font(NoxaType.headline)
                        .tint(NoxaTheme.accent)
                    Text("Applies only to future focus sessions. Strict work sessions cannot be ended early in Noxa and are limited to 4 hours. Pomodoro sessions can be stopped during breaks.")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                    Divider()
                    Toggle("Share usage analytics", isOn: $analytics.isEnabled)
                        .font(NoxaType.headline)
                        .tint(NoxaTheme.accent)
                    Text("Helps improve Noxa using feature events and coarse counts. Noxa never sends your email, name, selected apps or websites, typed intentions, or screen recordings.")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                .noxaCard()

                settingsSectionTitle("Instagram website")

                VStack(alignment: .leading, spacing: 12) {
                    Picker("Instagram website", selection: $instagramSiteMode) {
                        Text("Off").tag(InstagramSiteMode.off)
                        Text("Hide Reels and Explore").tag(InstagramSiteMode.distractionFree)
                    }
                        .font(NoxaType.headline)
                        .onChange(of: instagramSiteMode) { mode in
                            AppGroupStore.shared.setInstagramSiteMode(mode)
                            if mode != .distractionFree {
                                instagramAppBlockEnabled = false
                                instagramAppBlockMessage = nil
                            }
                            InstagramSiteProtectionService.reconcile()
                        }
                    if instagramSiteMode == .distractionFree {
                        Text("Experimental Safari filter: aims to hide Reels and Explore while keeping the feed available. Embedded Reels may still appear.")
                            .font(NoxaType.footnote)
                            .foregroundStyle(NoxaTheme.secondaryText)
                        instagramAppBlockControls
                        Text(safariFilterStatusMessage)
                            .font(NoxaType.footnote)
                            .foregroundStyle(safariFilterRecentlyConnected ? Color.secondary : Color.orange)
                        if websites.domains.contains(where: { $0 == "instagram.com" || $0 == "www.instagram.com" }) {
                            Text("Instagram is also in your website blocklist. Remove that independent block to keep the feed available.")
                                .font(NoxaType.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                    Link("Report a filter problem", destination: NoxaWebLinks.support)
                        .font(NoxaType.subheadlineSemibold)
                }
                .noxaCard()
                .task {
                    await refreshSafariExtensionStatus()
                }

                settingsSectionTitle("Support & Legal")

                VStack(alignment: .leading, spacing: 10) {
                    NoxaCardHeader(title: "Blocking looks wrong?", systemImage: "arrow.clockwise")
                    Text("Refresh your active rules if something stays blocked after its rule ends, or if a selected app is not blocked.")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                    Button("Refresh Blocking") {
                        authorization.refresh()
                        focusSession.reconcile()
                        restrictions.reconcile()
                        websites.reconcile()
                        dailyLimits.reconcileDayBoundary()
                        schedules.reconcile()
                        InstagramSiteProtectionService.reconcile()
                        didRepairRestrictions = true
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                    if didRepairRestrictions {
                        Text("Rules refreshed. Open the affected app or site to check its shield. If the problem remains, contact support.")
                            .font(NoxaType.footnote)
                            .foregroundStyle(NoxaTheme.secondaryText)
                    }
                }
                .noxaCard()

                SettingsSupportLinksView()

                settingsSectionTitle("Data & Sync")

                cloudSyncStatusCard

                Button("Sign Out") {
                    Task {
                        await authentication.signOut()
                        if !authentication.isAuthenticated {
                            focusSession.discardScheduleSuggestion()
                        }
                    }
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
                .disabled(authentication.isBusy || focusSession.isActive || focusSession.hasPomodoroCycle)

                Button("Delete Account", role: .destructive) {
                    isDeleteAccountConfirmationPresented = true
                }
                .font(NoxaType.subheadlineSemibold)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .disabled(authentication.isBusy || focusSession.isActive || focusSession.hasPomodoroCycle)

                if focusSession.isActive || focusSession.hasPomodoroCycle {
                    Text("Wait until the active focus session ends before signing out or deleting your account.")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }

                if let message = authentication.message {
                    Text(message)
                        .font(NoxaType.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
        .sheet(isPresented: $isPaywallPresented) {
            PaywallView()
                .environmentObject(subscriptions)
        }
    }

    private func openInstagramInSafari() {
        InstagramSiteProtectionService.openInSafari()
    }

    @ViewBuilder
    private var instagramAppBlockControls: some View {
        Toggle("Block Instagram app", isOn: $instagramAppBlockEnabled)
            .tint(NoxaTheme.accent)
            .onChange(of: instagramAppBlockEnabled) { enabled in
                guard enabled else {
                    AppGroupStore.shared.setInstagramAppBlockEnabled(false)
                    InstagramSiteProtectionService.reconcile()
                    return
                }
                guard safariFilterRecentlyConnected else {
                    instagramAppBlockEnabled = false
                    instagramAppBlockMessage = "First open Instagram in Safari, refresh the page, then return here. Noxa must connect to the filter before blocking the app."
                    return
                }
                guard authorization.state.isApproved else {
                    instagramAppBlockEnabled = false
                    instagramAppBlockMessage = "Allow Screen Time access before blocking Instagram."
                    return
                }
                guard instagramAppSelection?.applicationTokens.count == 1 else {
                    presentInstagramAppPicker()
                    return
                }
                AppGroupStore.shared.setInstagramAppBlockEnabled(true)
                InstagramSiteProtectionService.reconcile()
                instagramAppBlockMessage = InstagramSiteProtectionService.isAppBlockApplied
                    ? nil : "Noxa could not activate the app block. Try again after reopening Noxa."
            }
        Text("When on, iOS prevents the selected Instagram app from opening. Use Noxa's Open Instagram in Safari button to continue on the filtered website.")
            .font(NoxaType.footnote)
            .foregroundStyle(NoxaTheme.secondaryText)
        if let selection = instagramAppSelection, !selection.applicationTokens.isEmpty {
            HStack(spacing: 10) {
                ForEach(Array(selection.applicationTokens), id: \.self) { token in
                    Label(token)
                        .labelStyle(.titleAndIcon)
                        .font(NoxaType.subheadlineSemibold)
                }
                Spacer()
                Text(instagramAppBlockEnabled && InstagramSiteProtectionService.isAppBlockApplied ? "Blocked" : "Selected")
                    .font(NoxaType.captionSemibold)
                    .foregroundStyle(NoxaTheme.accent)
                Button("Change") { presentInstagramAppPicker() }
                    .font(NoxaType.captionSemibold)
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .disabled(!authorization.state.isApproved)
            }
        } else {
            Text("Choose only Instagram in Apple's app picker.")
                .font(NoxaType.footnote)
                .foregroundStyle(NoxaTheme.secondaryText)
            Button("Choose Instagram App") { presentInstagramAppPicker() }
                .buttonStyle(NoxaSecondaryButtonStyle())
                .disabled(!authorization.state.isApproved)
        }
        if let instagramAppBlockMessage {
            Text(instagramAppBlockMessage)
                .font(NoxaType.footnote)
                .foregroundStyle(.orange)
        }
        Button {
            InstagramSiteProtectionService.openInSafari()
        } label: {
            Label("Open Instagram in Safari", systemImage: "safari")
        }
        .buttonStyle(NoxaSecondaryButtonStyle())
    }

    private var instagramAppPickerSheet: some View {
        NavigationStack {
            FamilyActivityPicker(selection: $instagramPickerSelection)
                .navigationTitle("Choose Instagram")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isInstagramAppPickerPresented = false
                            instagramAppBlockEnabled = AppGroupStore.shared.instagramAppBlockEnabled
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { saveInstagramAppSelection() }
                            .disabled(instagramPickerSelection.applicationTokens.count != 1)
                    }
                }
        }
        .tint(NoxaTheme.accent)
        .preferredColorScheme(.dark)
    }

    private func presentInstagramAppPicker() {
        instagramPickerSelection = instagramAppSelection ?? FamilyActivitySelection()
        isInstagramAppPickerPresented = true
    }

    /// Keeps only the app itself. Categories would block unrelated apps, and
    /// Instagram's website stays reachable through the Safari filter.
    private func saveInstagramAppSelection() {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = instagramPickerSelection.applicationTokens
        do {
            try AppGroupStore.shared.saveInstagramAppSelection(selection)
            instagramAppSelection = selection
            AppGroupStore.shared.setInstagramAppBlockEnabled(instagramAppBlockEnabled)
            InstagramSiteProtectionService.reconcile()
            instagramAppBlockMessage = instagramAppBlockEnabled && !InstagramSiteProtectionService.isAppBlockApplied
                ? "Noxa could not activate the app block. Try again after reopening Noxa." : nil
            isInstagramAppPickerPresented = false
        } catch {
            instagramAppBlockEnabled = false
            instagramAppBlockMessage = "Noxa could not save the Instagram app selection. Please try again."
            isInstagramAppPickerPresented = false
        }
    }

    private func settingsSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(NoxaTheme.font(18, weight: .semibold, relativeTo: .headline))
            .foregroundStyle(NoxaTheme.primaryText)
            .padding(.top, 8)
            .padding(.horizontal, 4)
    }

    private var cloudSyncStatusCard: some View {
        HStack(spacing: 12) {
            Image(systemName: cloudSync.status.iconName)
                .foregroundStyle(cloudSync.status == .failed ? .orange : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(cloudSync.status.title)
                    .font(NoxaType.subheadlineSemibold)
                if let lastSync = cloudSync.lastSuccessfulSyncAt {
                    Text("Last synced \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                } else if let errorMessage = cloudSync.errorMessage {
                    Text(errorMessage)
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                if cloudSync.hasPendingWork {
                    Button("Retry now") {
                        Task { @MainActor in
                            if let result = await cloudSync.sync(
                                history: focusSession.history,
                                websiteDomains: websites.domains
                            ) {
                                websites.replaceDomains(result.websiteDomains)
                                focusSession.replaceHistory(result.focusHistory)
                            }
                        }
                    }
                    .font(NoxaType.footnoteSemibold)
                    .foregroundStyle(.white)
                }
            }
            Spacer()
        }
        .noxaCard()
    }

    private func deleteAccountAndLocalData() async {
        guard !focusSession.isActive && !focusSession.hasPomodoroCycle else { return }
        guard await authentication.deleteAccount() else { return }
        LocalDataCleanupService.clear(
            focusSession: focusSession,
            restrictions: restrictions,
            monitoring: monitoring,
            dailyLimits: dailyLimits,
            schedules: schedules,
            websites: websites,
            cloudSync: cloudSync,
            onboarding: onboarding
        )
    }

    private var chosenDurationMinutes: Int {
        guard isCustomDuration else { return min(selectedDurationMinutes, maximumFocusMinutes) }
        return normalizedCustomDuration
    }

    private var strictEndTimeDescription: String {
        let minutes = strictStartIsPomodoro ? pomodoroWorkMinutes : chosenDurationMinutes
        return Date().addingTimeInterval(TimeInterval(minutes * 60))
            .formatted(date: .omitted, time: .shortened)
    }

    private var maximumFocusMinutes: Int {
        focusSession.strictModeEnabled
            ? NoxaDeviceActivityConfiguration.maximumStrictFocusSessionMinutes
            : NoxaDeviceActivityConfiguration.maximumFocusSessionMinutes
    }

    private var normalizedCustomDuration: Int {
        let value = Int(customDurationText) ?? NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes
        return min(
            max(value, NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes),
            maximumFocusMinutes
        )
    }

    private func commitCustomDuration() {
        customDurationText = String(normalizedCustomDuration)
    }

    private func adjustCustomDuration(by amount: Int) {
        let current = Int(customDurationText) ?? selectedDurationMinutes
        let adjusted = min(
            max(current + amount, NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes),
            maximumFocusMinutes
        )
        customDurationText = String(adjusted)
    }

    private func presentRestrictionPicker() {
        guard !focusSession.hasPomodoroCycle || focusSession.isActive else { return }
        // Existing choices stay visibly checked. During an active session the
        // binding below also prevents those locked choices from being removed.
        restrictionPickerSelection = restrictions.selection
        restrictions.isPickerPresented = true
    }

    private func finishRestrictionPicker() {
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

    private func combinedSelection(
        from selections: [FamilyActivitySelection]
    ) -> FamilyActivitySelection {
        selections.reduce(into: FamilyActivitySelection()) { combined, selection in
            combined.applicationTokens.formUnion(selection.applicationTokens)
            combined.categoryTokens.formUnion(selection.categoryTokens)
            combined.webDomainTokens.formUnion(selection.webDomainTokens)
        }
    }

    private func selectionBinding(
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

    private func durationButton(title: String, minutes: Int) -> some View {
        Button(title) {
            selectedDurationMinutes = minutes
            isCustomDuration = false
            isCustomDurationFieldFocused = false
        }
        .buttonStyle(
            NoxaDurationButtonStyle(
                isSelected: !isCustomDuration && selectedDurationMinutes == minutes
            )
        )
    }

    private func beginFocusSession(intention: String) {
        restrictions.persistSelection()
        focusSession.start(
            selection: restrictions.selection,
            websiteDomains: websites.domains,
            durationMinutes: chosenDurationMinutes,
            intention: intention
        )
        guard let session = focusSession.activeSession else { return }
        Task {
            await notifications.refreshAuthorizationStatus()
            if notifications.canSchedule {
                await notifications.schedule(for: session)
            } else if notifications.authorizationStatus == .notDetermined {
                isNotificationPromptPresented = true
            }
        }
    }

    private func presentFirstFocusReviewIfReady() {
        guard firstFocusReviewPending,
              !isStrictModeIntroductionPresented,
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

    private func presentWidgetStartIfReady() {
        guard focusLaunchRouter.hasPendingStart,
              subscriptions.canEnterApp(for: authentication.userID) else { return }
        focusLaunchRouter.consumeStart()
        selectedTab = .home
        guard !focusSession.isActive, !focusSession.hasPomodoroCycle else { return }
        selectedDurationMinutes = 60
        isCustomDuration = false
        if hasFocusRestrictions && authorization.state.isApproved {
            isFocusStartReviewPresented = true
        } else {
            isWidgetSetupAlertPresented = true
        }
    }

    private func presentWidgetHomeIfReady() {
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

    private func presentScheduleSuggestionIfReady() {
        guard onboarding.progress.isComplete,
              subscriptions.canEnterApp(for: authentication.userID),
              authorization.state.isApproved,
              schedules.configurations.count < RestrictionScheduleService.maximumConfigurations,
              focusSession.completedSessionCount > 0,
              !focusSession.isActive,
              !focusSession.hasPomodoroCycle,
              !isPomodoroCompletionPresented,
              !isStrictModeIntroductionPresented,
              !isFocusStartReviewPresented,
              !isNotificationPromptPresented,
              focusSession.pendingScheduleSuggestion != nil else { return }
        isScheduleSuggestionPresented = true
    }

    private func beginPomodoro() {
        restrictions.persistSelection()
        focusSession.startPomodoro(
            selection: restrictions.selection,
            websiteDomains: websites.domains,
            workMinutes: pomodoroWorkMinutes,
            breakMinutes: pomodoroBreakMinutes
        )
        guard let cycle = focusSession.pomodoroCycle else { return }
        Task {
            await notifications.refreshAuthorizationStatus()
            if notifications.canSchedule {
                await notifications.schedulePomodoroCycle(cycle)
            } else if notifications.authorizationStatus == .notDetermined {
                isNotificationPromptPresented = true
            }
        }
    }

    private func enableNotificationsForActiveSession() async {
        guard await notifications.requestAuthorization(),
              let session = focusSession.activeSession else { return }
        if let cycle = focusSession.pomodoroCycle {
            await notifications.schedulePomodoroCycle(cycle)
        } else {
            await notifications.schedule(for: session)
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(NoxaTheme.font(30, weight: .semibold, relativeTo: .title))
            Text(title)
                .font(NoxaType.subheadline)
                .foregroundStyle(NoxaTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .noxaStatsCard()
    }

    private static func durationLabel(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        return remainingMinutes == 0 ? "\(hours)h" : "\(hours)h \(remainingMinutes)m"
    }

    private func durationGridColumns(regularCount: Int, spacing: CGFloat) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: spacing),
              count: dynamicTypeSize.isAccessibilitySize ? 1 : regularCount)
    }

    private static func durationString(seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private static func compactFocusTime(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    private static func focusTimeLabel(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }

    private static func timeLabel(minutes: Int) -> String {
        let calendar = Calendar.autoupdatingCurrent
        let date = calendar.date(from: DateComponents(hour: minutes / 60, minute: minutes % 60)) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }
}

private struct NoxaDurationButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(NoxaTheme.font(15, weight: .semibold, relativeTo: .subheadline))
            .foregroundStyle(isSelected ? .black : NoxaTheme.primaryText)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(
                isSelected ? NoxaTheme.accent : NoxaTheme.elevated,
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .stroke(isSelected ? NoxaTheme.accent : NoxaTheme.border, lineWidth: 1)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .noxaAnimation(NoxaMotion.snappy, value: configuration.isPressed)
            .noxaAnimation(NoxaMotion.snappy, value: isSelected)
            .onChange(of: configuration.isPressed) { isPressed in
                if isPressed { NoxaHaptics.selection() }
            }
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension FamilyControlsAuthorizationService {
    var statusDescription: String {
        switch state {
        case .unknown:
            return "Checking Screen Time access."
        case .notDetermined:
            return "Noxa needs Screen Time access before it can block distractions."
        case .denied:
            return "Access is denied. Re-enable it in Settings to use blocking."
        case .approved, .approvedWithDataAccess:
            return "Screen Time access is ready."
        }
    }
}

private extension ScreenTimeAuthorizationState {
    var isApproved: Bool {
        self == .approved || self == .approvedWithDataAccess
    }
}

private extension FamilyActivitySelection {
    func removing(_ existingSelection: FamilyActivitySelection) -> FamilyActivitySelection {
        var result = self
        result.applicationTokens.subtract(existingSelection.applicationTokens)
        result.categoryTokens.subtract(existingSelection.categoryTokens)
        result.webDomainTokens.subtract(existingSelection.webDomainTokens)
        return result
    }
}

private extension SessionOutcome {
    var displayName: String {
        switch self {
        case .completed:
            return "Completed"
        case .endedEarly:
            return "Ended early"
        case .recoveredStale:
            return "Recovered after restart"
        case .failedToStart:
            return "Failed to start"
        case .interrupted:
            return "Interrupted"
        case .startPending:
            return "Starting"
        case .active:
            return "Active"
        }
    }
}

private extension CloudSyncStatus {
    var title: String {
        switch self {
        case .idle:
            return "Cloud sync is ready"
        case .syncing:
            return "Syncing your Noxa data…"
        case .synced:
            return "Cloud sync is up to date"
        case .pending:
            return "Cloud sync is pending"
        case .failed:
            return "Cloud sync will retry"
        }
    }

    var iconName: String {
        switch self {
        case .idle:
            return "icloud"
        case .syncing:
            return "arrow.triangle.2.circlepath.icloud"
        case .synced:
            return "checkmark.icloud"
        case .pending:
            return "clock.badge.checkmark"
        case .failed:
            return "exclamationmark.icloud"
        }
    }
}

private extension CloudSyncService {
    var historyStatusDescription: String {
        switch status {
        case .synced:
            return "History is stored locally and synced securely to your Noxa account."
        case .syncing:
            return "History is stored locally and is syncing securely to your Noxa account."
        case .pending, .failed:
            return "History is safe on this device. Cloud sync will retry when you’re back online."
        case .idle:
            return "History is stored locally first and syncs securely after you sign in."
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AuthenticationService())
        .environmentObject(AnalyticsService.shared)
        .environmentObject(SubscriptionService())
        .environmentObject(FocusSessionService())
        .environmentObject(ScreenTimeRestrictionService())
        .environmentObject(DeviceActivityMonitoringService())
        .environmentObject(DailyLimitService())
        .environmentObject(RestrictionScheduleService())
        .environmentObject(WebsiteBlocklistService())
        .environmentObject(CloudSyncService())
        .environmentObject(FocusNotificationService())
        .environmentObject(OnboardingService())
        .environmentObject(FocusLaunchRouter())
}
