//
//  ContentView.swift
//  Noxa
//

import FamilyControls
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
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
    @StateObject private var authorization = FamilyControlsAuthorizationService()
    @State private var selectedDurationMinutes = 30
    @State private var isRequestingAuthorization = false
    @State private var newDomain = ""
    @State private var restrictionPickerSelection = FamilyActivitySelection()
    @State private var isDailyLimitPickerPresented = false
    @State private var isChoosingDailyLimitDuration = false
    @State private var dailyLimitSelection = FamilyActivitySelection()
    @State private var selectedDailyLimitMinutes = 30
    @State private var isHardLimitConfirmationPresented = false
    @State private var isSchedulePickerPresented = false
    @State private var scheduleSelection = FamilyActivitySelection()
    @State private var scheduleAllowedStart = Calendar.current.date(from: DateComponents(hour: 21)) ?? Date()
    @State private var scheduleAllowedEnd = Calendar.current.date(from: DateComponents(hour: 22)) ?? Date()
    @State private var pomodoroWorkMinutes = 25
    @State private var pomodoroBreakMinutes = 5
    @State private var isCustomPomodoro = false
    @State private var pendingPomodoroBreakMinutes: Int?
    @State private var isPaywallPresented = false
    @State private var isDeleteAccountConfirmationPresented = false
    @State private var isCustomDuration = false
    @State private var customDurationText = "30"
    @State private var isEndRitualPresented = false
    @State private var isNotificationPromptPresented = false
    @State private var selectedTab = MainTab.home
    @State private var selectedStatsRange = StatsRange.week
    @State private var statsReferenceDate = Date()
    @FocusState private var isCustomDurationFieldFocused: Bool

    private var hasConfiguredRestrictions: Bool {
        restrictions.hasSelection || !websites.domains.isEmpty || dailyLimits.enabledCount > 0
    }

    private var hasFocusRestrictions: Bool {
        restrictions.hasSelection || !websites.domains.isEmpty
    }

    private var focusRestrictionCount: Int {
        restrictions.selectedItemCount + websites.domains.count
    }

    private var configuredRestrictionCount: Int {
        restrictions.selectedItemCount + websites.domains.count + dailyLimits.enabledCount
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
        .tint(NoxaTheme.accent)
        .preferredColorScheme(.dark)
        .font(NoxaTheme.font(17))
        .toolbarBackground(NoxaTheme.background.opacity(0.96), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .background(NoxaBackground())
        .sheet(isPresented: $restrictions.isPickerPresented) {
            NavigationStack {
                FamilyActivityPicker(selection: $restrictionPickerSelection)
                    .navigationTitle(focusSession.isActive ? "Add restrictions" : "Choose restrictions")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                finishRestrictionPicker()
                            }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isDailyLimitPickerPresented) {
            NavigationStack {
                Group {
                    if isChoosingDailyLimitDuration {
                        VStack(alignment: .leading, spacing: 22) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Choose a daily allowance")
                                    .font(NoxaTheme.font(28, weight: .bold, relativeTo: .title))
                                Text("The selected app will be blocked after this much total use today.")
                                    .foregroundStyle(.secondary)
                            }

                            LazyVGrid(
                                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2),
                                spacing: 10
                            ) {
                                ForEach([15, 30, 45, 60, 120], id: \.self) { minutes in
                                    Button(Self.durationLabel(minutes: minutes)) {
                                        selectedDailyLimitMinutes = minutes
                                    }
                                    .buttonStyle(
                                        NoxaDurationButtonStyle(
                                            isSelected: selectedDailyLimitMinutes == minutes
                                        )
                                    )
                                }
                            }

                            Label(
                                "\(dailyLimitSelection.applicationTokens.count) app\(dailyLimitSelection.applicationTokens.count == 1 ? "" : "s") selected",
                                systemImage: "app.badge.checkmark"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(NoxaTheme.accent)

                            if let errorMessage = dailyLimits.errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }

                            Spacer()
                        }
                        .padding(20)
                        .noxaScreenBackground()
                    } else {
                        FamilyActivityPicker(selection: $dailyLimitSelection)
                            .disabled(focusSession.isActive)
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
                                    selection: dailyLimitSelection,
                                    minutes: selectedDailyLimitMinutes
                                )
                                if dailyLimits.errorMessage == nil {
                                    dailyLimitSelection = FamilyActivitySelection()
                                    isChoosingDailyLimitDuration = false
                                    isDailyLimitPickerPresented = false
                                }
                            }
                            .disabled(focusSession.isActive)
                        } else {
                            Button("Next") {
                                isChoosingDailyLimitDuration = true
                            }
                            .disabled(
                                focusSession.isActive
                                    || dailyLimitSelection.applicationTokens.isEmpty
                            )
                        }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isSchedulePickerPresented) {
            NavigationStack {
                FamilyActivityPicker(selection: $scheduleSelection)
                    .navigationTitle("Choose schedule apps")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                schedules.add(
                                    selection: scheduleSelection,
                                    allowedStart: scheduleAllowedStart,
                                    allowedEnd: scheduleAllowedEnd
                                )
                                if schedules.errorMessage == nil {
                                    scheduleSelection = FamilyActivitySelection()
                                    isSchedulePickerPresented = false
                                }
                            }
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .fullScreenCover(isPresented: $isEndRitualPresented) {
            EndSessionRitualView {
                if let sessionID = focusSession.activeSession?.id {
                    notifications.cancel(for: sessionID)
                }
                focusSession.endEarly()
            }
        }
        .task {
            authorization.refresh()
        }
        .onChange(of: scenePhase) { newPhase in
            guard newPhase == .active else { return }
            statsReferenceDate = Date()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            statsReferenceDate = Date()
        }
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

    private var homeContent: some View {
        ScrollView {
            VStack(spacing: 22) {
                hero

                if !authorization.state.isApproved {
                    permissionCard
                }

                focusSessionCard
                quickSetupCard
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
    }

    private var hero: some View {
        VStack(spacing: 8) {
            Text("TIME PROTECTED")
                .font(NoxaTheme.font(12, weight: .bold, relativeTo: .caption))
                .tracking(1.6)
                .foregroundStyle(NoxaTheme.accent)

            Text("\(dailyFocusMinutes)")
                .font(NoxaTheme.font(68, weight: .medium, relativeTo: .largeTitle))
                .monospacedDigit()
                .tracking(-1.5)

            Text("\(dailyFocusMinutes == 1 ? "minute" : "minutes") protected today")
                .font(NoxaTheme.font(16, weight: .medium, relativeTo: .subheadline))
                .foregroundStyle(NoxaTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Screen Time access required", systemImage: "hourglass")
                .font(.headline)

            Text(authorization.statusDescription)
                .foregroundStyle(.secondary)

            Button {
                isRequestingAuthorization = true
                Task { @MainActor in
                    await authorization.requestAuthorization()
                    isRequestingAuthorization = false
                }
            } label: {
                HStack {
                    Text(isRequestingAuthorization ? "Requesting…" : "Enable Screen Time Access")
                    Spacer()
                    if isRequestingAuthorization {
                        ProgressView()
                            .tint(.black)
                    }
                }
            }
            .buttonStyle(NoxaPrimaryButtonStyle())
            .disabled(isRequestingAuthorization)

            if let errorMessage = authorization.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .noxaCard()
    }

    private var focusSessionCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: focusSession.isActive ? .leading : .center, spacing: 4) {
                    Text(focusSession.isActive ? "Stay focused" : "Start a focus")
                        .font(NoxaTheme.font(24, weight: .bold, relativeTo: .title2))
                    Text(focusSession.isActive ? "Noxa is protecting your time." : "Choose a duration and begin.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(focusSession.isActive ? .leading : .center)
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: focusSession.isActive ? .leading : .center
                )
                if focusSession.isActive {
                    Text("LIVE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(NoxaTheme.accent, in: Capsule())
                }
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
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 190, height: 190)

                        Text("Blocked until \(activeSession.plannedEndAt.formatted(date: .omitted, time: .shortened))")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.secondary)

                        if let intention = focusSession.activeIntention, !intention.isEmpty {
                            Label(intention, systemImage: "scope")
                                .font(.subheadline.weight(.medium))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                Button("End Session Early") {
                    isEndRitualPresented = true
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
            } else {
                VStack(spacing: 2) {
                    Text(Self.durationLabel(minutes: chosenDurationMinutes))
                        .font(NoxaTheme.font(58, weight: .medium, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .tracking(-2)
                    Text("focus session")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9) {
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
                    HStack(spacing: 10) {
                        Button {
                            adjustCustomDuration(by: -5)
                        } label: {
                            Image(systemName: "minus")
                                .frame(width: 42, height: 42)
                        }
                        .buttonStyle(.plain)
                        .background(.thinMaterial, in: Circle())

                        TextField("Minutes", text: $customDurationText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .font(NoxaTheme.font(22, weight: .semibold, relativeTo: .title3))
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(.thinMaterial, in: Capsule())
                            .overlay { Capsule().stroke(NoxaTheme.border, lineWidth: 1) }
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
                        .background(.thinMaterial, in: Circle())
                    }

                    Text("Enter \(NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes)–\(NoxaDeviceActivityConfiguration.maximumFocusSessionMinutes) minutes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Button {
                        commitCustomDuration()
                        isCustomDurationFieldFocused = false
                    } label: {
                        Label("Done Entering Time", systemImage: "keyboard.chevron.compact.down")
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                }

                if hasFocusRestrictions {
                    Label("\(focusRestrictionCount) selected distraction\(focusRestrictionCount == 1 ? "" : "s") will be blocked", systemImage: "checkmark.shield.fill")
                        .font(.footnote.weight(.medium))
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
                    beginFocusSession(intention: "")
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
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .noxaCard()
    }

    private var quickSetupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Your blocklist", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Button(focusSession.isActive ? "Add" : "Edit") {
                    presentRestrictionPicker()
                }
                .font(.subheadline.weight(.semibold))
            }

            Text(hasConfiguredRestrictions
                 ? "\(configuredRestrictionCount) private selection\(configuredRestrictionCount == 1 ? "" : "s") saved on this device."
                 : "Nothing selected yet.")
                .foregroundStyle(.secondary)

            if !hasConfiguredRestrictions {
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
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose your distractions.")
                        .font(NoxaTheme.font(31, weight: .bold, relativeTo: .largeTitle))
                        .tracking(-0.7)
                    Text("Apps and websites stay organized separately and remain private on this device.")
                        .foregroundStyle(.secondary)
                }

                if focusSession.isActive {
                    Label("You can add distractions now, but existing ones stay locked until the session ends", systemImage: "lock.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Apps", systemImage: "square.grid.2x2")
                            .font(.headline)
                        Spacer()
                        Text("\(restrictions.selection.applicationTokens.count + restrictions.selection.categoryTokens.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if restrictions.selection.applicationTokens.isEmpty,
                       restrictions.selection.categoryTokens.isEmpty {
                        Text("No apps or categories selected.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        tokenRows(for: restrictions.selection, includeWebDomains: false)
                    }

                    Button(focusSession.isActive ? "Add Apps" : (restrictions.hasSelection ? "Edit Apps" : "Choose Apps")) {
                        presentRestrictionPicker()
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                    .disabled(!authorization.state.isApproved)
                }
                .noxaCard()

                websiteCard
                pomodoroCard

            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
    }

    private var dailyLimitsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Protect your time every day.")
                        .font(NoxaTheme.font(31, weight: .bold, relativeTo: .largeTitle))
                        .tracking(-0.7)
                    Text("Set a daily allowance for distracting apps. Noxa applies each limit locally using Screen Time.")
                        .font(NoxaTheme.font(16))
                        .foregroundStyle(NoxaTheme.secondaryText)
                }

                dailyLimitsCard
                scheduleCard
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
    }

    private var websiteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Website blocklist", systemImage: "globe")
                    .font(.headline)
                Spacer()
                Text("\(websites.domains.count)/\(WebsiteBlocklistService.maximumDomains)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("Add domains such as reddit.com or news.ycombinator.com. Noxa normalizes them and applies them locally during a focus session.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField("reddit.com", text: $newDomain)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)

                Button("Add Website") {
                    if websites.addDomain(newDomain) {
                        newDomain = ""
                    }
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
                .fixedSize()
                .disabled(websites.domains.count >= WebsiteBlocklistService.maximumDomains)
            }

            if websites.domains.isEmpty {
                if restrictions.selection.webDomainTokens.isEmpty {
                    Text("No websites added.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(websites.domains, id: \.self) { domain in
                    HStack {
                        Text(domain)
                            .font(.subheadline.monospaced())
                        Spacer()
                        Button("Remove") {
                            websites.removeDomain(domain)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .disabled(focusSession.isActive)
                    }
                }
            }

            ForEach(Array(restrictions.selection.webDomainTokens), id: \.self) { token in
                Label(token)
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
            }

            if let errorMessage = websites.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .noxaCard()
    }

    private var pomodoroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Pomodoro", systemImage: "timer.circle")
                    .font(.headline)
                Spacer()
                Text("\(pomodoroWorkMinutes)/\(pomodoroBreakMinutes)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(NoxaTheme.accent)
            }

            Text("Noxa blocks your current Blocklist during the focus interval, releases it for your break, and reminds you when it’s time to return.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach([(25, 5), (50, 10), (90, 15)], id: \.0) { preset in
                    Button("\(preset.0)/\(preset.1)") {
                        pomodoroWorkMinutes = preset.0
                        pomodoroBreakMinutes = preset.1
                        isCustomPomodoro = false
                    }
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
                .font(.subheadline.weight(.medium))
                .padding(14)
                .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }

            if hasFocusRestrictions {
                Button("Start \(pomodoroWorkMinutes)-minute Pomodoro") {
                    beginPomodoro()
                }
                .buttonStyle(NoxaPrimaryButtonStyle())
                .disabled(
                    !authorization.state.isApproved
                        || focusSession.isActive
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
                Label("Daily limits", systemImage: "hourglass.bottomhalf.fill")
                    .font(.headline)
                Spacer()
                Text("\(dailyLimits.configurations.count)/\(DailyLimitService.maximumConfigurations)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("Give selected apps a hard daily allowance. Usage from earlier today counts. Once started, existing limits cannot be changed or stopped until the next day, but you can still add new limits.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button("Add App Limit") {
                dailyLimitSelection = FamilyActivitySelection()
                selectedDailyLimitMinutes = 30
                isChoosingDailyLimitDuration = false
                isDailyLimitPickerPresented = true
            }
            .buttonStyle(NoxaSecondaryButtonStyle())
            .disabled(
                !authorization.state.isApproved
                    || focusSession.isActive
                    || dailyLimits.configurations.count >= DailyLimitService.maximumConfigurations
            )

            if dailyLimits.configurations.isEmpty {
                Text("No daily limits configured.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(dailyLimits.configurations) { configuration in
                    HStack(spacing: 12) {
                        Button {
                            dailyLimits.setEnabled(!configuration.isEnabled, for: configuration)
                        } label: {
                            Image(systemName: configuration.isEnabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(configuration.isEnabled ? .white : .secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(focusSession.isActive || dailyLimits.isHardLimitLocked)

                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(configuration.selection.applicationTokens), id: \.self) { token in
                                Label(token)
                                    .labelStyle(.titleAndIcon)
                                    .font(.subheadline.weight(.semibold))
                            }
                            if configuration.selection.applicationTokens.isEmpty {
                                Text("App selection")
                                    .font(.subheadline.weight(.semibold))
                            }
                            Menu("\(configuration.dailyLimitMinutes) min/day") {
                                ForEach([15, 30, 45, 60, 90, 120, 180, 240], id: \.self) { minutes in
                                    Button(Self.durationLabel(minutes: minutes)) {
                                        dailyLimits.updateMinutes(minutes, for: configuration)
                                    }
                                }
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NoxaTheme.accent)
                            .disabled(focusSession.isActive || dailyLimits.isHardLimitLocked)
                        }
                        Spacer()
                        Button("Remove") {
                            dailyLimits.remove(configuration)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .disabled(focusSession.isActive || dailyLimits.isHardLimitLocked)
                    }
                }
            }

            HStack {
                if dailyLimits.isHardLimitLocked {
                    Label("Hard limits active until tomorrow", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NoxaTheme.accent)
                } else {
                    Text(hasActiveDailyLimits ? "Daily limits active" : "Daily limits are off")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(hasActiveDailyLimits ? "Stop" : "Start Hard Limits") {
                        if hasActiveDailyLimits {
                            dailyLimits.stopMonitoring()
                        } else {
                            isHardLimitConfirmationPresented = true
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .disabled(
                        dailyLimits.configurations.filter(\.isEnabled).isEmpty
                            || (!hasActiveDailyLimits && !authorization.state.isApproved)
                            || focusSession.isActive
                    )
                }
            }

            if let errorMessage = dailyLimits.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .noxaCard()
        .confirmationDialog(
            "Start hard daily limits?",
            isPresented: $isHardLimitConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Start Hard Limits") {
                dailyLimits.startMonitoring()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You won’t be able to change or stop these limits until tomorrow.")
        }
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Allowed schedules", systemImage: "calendar.badge.clock")
                    .font(.headline)
                Spacer()
                Text("\(schedules.configurations.count)/\(RestrictionScheduleService.maximumConfigurations)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text("Choose a daily window when selected apps are available. Noxa blocks them before and after that window—even when the app is closed. Disabling or removing an active schedule takes 24 hours.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("AVAILABLE FROM")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    DatePicker("Available from", selection: $scheduleAllowedStart, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 5) {
                    Text("UNTIL")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    DatePicker("Until", selection: $scheduleAllowedEnd, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button("Add App Schedule") {
                scheduleSelection = FamilyActivitySelection()
                isSchedulePickerPresented = true
            }
            .buttonStyle(NoxaSecondaryButtonStyle())
            .disabled(
                !authorization.state.isApproved
                    || focusSession.isActive
                    || schedules.configurations.count >= RestrictionScheduleService.maximumConfigurations
            )

            if schedules.configurations.isEmpty {
                Text("No app schedules configured.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                            .disabled(focusSession.isActive || configuration.pendingRelaxation != nil)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Available \(Self.timeLabel(minutes: configuration.allowedStartMinutes))–\(Self.timeLabel(minutes: configuration.allowedEndMinutes))")
                                    .font(.subheadline.weight(.semibold))
                                Text("Blocked outside this window every day")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("Remove") {
                                schedules.remove(configuration)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .disabled(focusSession.isActive || configuration.pendingRelaxation != nil)
                        }

                        tokenRows(for: configuration.selection)

                        if let pending = configuration.pendingRelaxation {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Label(
                                        pending.action == .remove ? "Removal pending" : "Disable pending",
                                        systemImage: "clock.badge.exclamationmark"
                                    )
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(NoxaTheme.warning)

                                    Text("Takes effect \(pending.effectiveAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Button("Cancel Change") {
                                    schedules.cancelPendingRelaxation(for: configuration)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(NoxaTheme.accent)
                                .disabled(focusSession.isActive)
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
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .noxaCard()
    }

    @ViewBuilder
    private func tokenRows(
        for selection: FamilyActivitySelection,
        includeWebDomains: Bool = true
    ) -> some View {
        ForEach(Array(selection.applicationTokens), id: \.self) { token in
            Label(token)
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
        }
        ForEach(Array(selection.categoryTokens), id: \.self) { token in
            Label(token)
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
        }
        if includeWebDomains {
            ForEach(Array(selection.webDomainTokens), id: \.self) { token in
                Label(token)
                    .labelStyle(.titleAndIcon)
                    .font(.subheadline)
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
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 8) {
                    Text("TIME PROTECTED")
                        .font(NoxaTheme.font(12, weight: .bold, relativeTo: .caption))
                        .tracking(1.6)
                        .foregroundStyle(NoxaTheme.accent)
                    Text(Self.focusTimeLabel(minutes: statistics.totalFocusMinutes))
                        .font(NoxaTheme.font(48, weight: .bold, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                    Text("since you started using Noxa")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .noxaStatsCard()

                HStack(spacing: 8) {
                    ForEach(StatsRange.allCases, id: \.self) { range in
                        Button(range.title) {
                            selectedStatsRange = range
                        }
                        .buttonStyle(NoxaDurationButtonStyle(isSelected: selectedStatsRange == range))
                    }
                }

                HStack(spacing: 12) {
                    statCard(title: "Time protected", value: Self.compactFocusTime(minutes: period.focusMinutes))
                    statCard(title: "Completed", value: "\(period.completedSessions)")
                }

                HStack(spacing: 12) {
                    statCard(title: "Completion", value: "\(period.completionRate)%")
                    statCard(title: "Days focused", value: "\(period.focusedDays)")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Follow-through", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                    Text("\(period.completionRate)% completion rate")
                        .font(.title2.weight(.semibold))
                    Text("\(period.completedSessions) completed · \(period.abandonedSessions) ended early")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("\(statistics.currentStreak)-day current streak · \(statistics.longestStreak)-day best")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .noxaStatsCard()

                recentSessionsCard
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
    }

    private var recentSessionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Recent sessions", systemImage: "clock.arrow.circlepath")
                .font(.headline)

            if focusSession.history.isEmpty {
                Text("Complete a focus session and it will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(focusSession.history.prefix(8)) { session in
                    HStack(spacing: 12) {
                        Image(systemName: session.outcome == .completed ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                            .foregroundStyle(session.outcome == .completed ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.outcome.displayName)
                                .font(.subheadline.weight(.semibold))
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Self.durationLabel(
                            minutes: (session.actualDurationSeconds ?? session.plannedDurationSeconds) / 60
                        ))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if session.id != focusSession.history.prefix(8).last?.id {
                        Divider()
                            .overlay(Color.white.opacity(0.12))
                    }
                }
            }

            Text(cloudSync.historyStatusDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .noxaStatsCard()
    }

    private var accountContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                settingsSectionTitle("Account")

                VStack(alignment: .leading, spacing: 12) {
                    Label("Signed in", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                    if let displayName = authentication.displayName, !displayName.isEmpty {
                        Text(displayName)
                            .font(NoxaTheme.font(22, weight: .semibold, relativeTo: .title3))
                    }
                    Text(authentication.userEmail ?? "Apple account")
                        .foregroundStyle(.secondary)
                    Text("Screen Time selections and active shields stay on this device. Focus history and website domains sync securely when you’re online.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .noxaCard()

                VStack(alignment: .leading, spacing: 12) {
                    Label("Noxa subscription", systemImage: subscriptions.hasAccess ? "checkmark.seal.fill" : "creditcard")
                        .font(.headline)
                    Text(subscriptions.hasAccess
                         ? "\(subscriptions.activePlanDisplayName) is active."
                         : "A subscription is required to use Noxa.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(subscriptions.hasAccess ? "View Subscription" : "See Subscription Plans") {
                        isPaywallPresented = true
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                }
                .noxaCard()

                settingsSectionTitle("Preferences")

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Share usage analytics", isOn: $analytics.isEnabled)
                        .font(.headline)
                        .tint(NoxaTheme.accent)
                    Text("Helps improve Noxa using feature events and coarse counts. Noxa never sends your email, name, selected apps or websites, typed intentions, or screen recordings.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .noxaCard()

                settingsSectionTitle("Support & Legal")

                SettingsSupportLinksView()

                settingsSectionTitle("Data & Sync")

                cloudSyncStatusCard

                Button("Sign Out") {
                    Task {
                        await authentication.signOut()
                    }
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
                .disabled(authentication.isBusy || focusSession.isActive)

                Button("Delete Account", role: .destructive) {
                    isDeleteAccountConfirmationPresented = true
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .disabled(authentication.isBusy)

                if focusSession.isActive {
                    Text("End the active focus session before signing out.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let message = authentication.message {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
        .sheet(isPresented: $isPaywallPresented) {
            PaywallView()
                .environmentObject(subscriptions)
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
                    .font(.subheadline.weight(.semibold))
                if let lastSync = cloudSync.lastSuccessfulSyncAt {
                    Text("Last synced \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if let errorMessage = cloudSync.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                }
            }
            Spacer()
        }
        .noxaCard()
    }

    private func deleteAccountAndLocalData() async {
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
        guard isCustomDuration else { return selectedDurationMinutes }
        return normalizedCustomDuration
    }

    private var normalizedCustomDuration: Int {
        let value = Int(customDurationText) ?? NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes
        return min(
            max(value, NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes),
            NoxaDeviceActivityConfiguration.maximumFocusSessionMinutes
        )
    }

    private func commitCustomDuration() {
        customDurationText = String(normalizedCustomDuration)
    }

    private func adjustCustomDuration(by amount: Int) {
        let current = Int(customDurationText) ?? selectedDurationMinutes
        let adjusted = min(
            max(current + amount, NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes),
            NoxaDeviceActivityConfiguration.maximumFocusSessionMinutes
        )
        customDurationText = String(adjusted)
    }

    private func presentRestrictionPicker() {
        // During an active session the picker starts empty and acts only as an
        // additive selection. Outside a session it remains the normal editor.
        restrictionPickerSelection = focusSession.isActive
            ? FamilyActivitySelection()
            : restrictions.selection
        restrictions.isPickerPresented = true
    }

    private func finishRestrictionPicker() {
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
        pendingPomodoroBreakMinutes = nil
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

    private func beginPomodoro() {
        restrictions.persistSelection()
        focusSession.start(
            selection: restrictions.selection,
            websiteDomains: websites.domains,
            durationMinutes: pomodoroWorkMinutes,
            intention: "Pomodoro · \(pomodoroWorkMinutes)/\(pomodoroBreakMinutes)"
        )
        guard let session = focusSession.activeSession else { return }
        pendingPomodoroBreakMinutes = pomodoroBreakMinutes
        Task {
            await notifications.refreshAuthorizationStatus()
            if notifications.canSchedule {
                await notifications.schedulePomodoro(for: session, breakMinutes: pomodoroBreakMinutes)
            } else if notifications.authorizationStatus == .notDetermined {
                isNotificationPromptPresented = true
            }
        }
    }

    private func enableNotificationsForActiveSession() async {
        guard await notifications.requestAuthorization(),
              let session = focusSession.activeSession else { return }
        if let breakMinutes = pendingPomodoroBreakMinutes {
            await notifications.schedulePomodoro(for: session, breakMinutes: breakMinutes)
        } else {
            await notifications.schedule(for: session)
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(NoxaTheme.font(30, weight: .semibold, relativeTo: .title))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .noxaStatsCard()
    }

    private static func durationLabel(minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h" : "\(minutes)m"
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
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
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
}
