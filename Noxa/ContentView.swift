//
//  ContentView.swift
//  Noxa
//

import FamilyControls
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var authentication: AuthenticationService
    @EnvironmentObject private var subscriptions: SubscriptionService
    @EnvironmentObject private var focusSession: FocusSessionService
    @EnvironmentObject private var restrictions: ScreenTimeRestrictionService
    @EnvironmentObject private var monitoring: DeviceActivityMonitoringService
    @EnvironmentObject private var dailyLimits: DailyLimitService
    @EnvironmentObject private var cloudSync: CloudSyncService
    @EnvironmentObject private var websites: WebsiteBlocklistService
    @EnvironmentObject private var notifications: FocusNotificationService
    @StateObject private var authorization = FamilyControlsAuthorizationService()
    @State private var selectedDurationMinutes = NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes
    @State private var isRequestingAuthorization = false
    @State private var newDomain = ""
    @State private var isDailyLimitPickerPresented = false
    @State private var dailyLimitSelection = FamilyActivitySelection()
    @State private var selectedDailyLimitMinutes = 30
    @State private var isPaywallPresented = false
    @State private var isDeleteAccountConfirmationPresented = false
    @State private var isCustomDuration = false
    @State private var customDurationMinutes = 30
    @State private var isStartRitualPresented = false
    @State private var isEndRitualPresented = false
    @State private var isNotificationPromptPresented = false

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

    var body: some View {
        TabView {
            NavigationStack {
                homeContent
                    .navigationTitle("Home")
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationStack {
                blocklistContent
                    .navigationTitle("Blocklist")
            }
            .tabItem {
                Label("Blocklist", systemImage: "hand.raised.slash")
            }

            NavigationStack {
                statsContent
                    .navigationTitle("Stats")
            }
            .tabItem {
                Label("Stats", systemImage: "chart.bar")
            }

            NavigationStack {
                accountContent
                    .navigationTitle("Account")
            }
            .tabItem {
                Label("Account", systemImage: "person.crop.circle")
            }
        }
        .tint(.white)
        .preferredColorScheme(.dark)
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $restrictions.isPickerPresented) {
            NavigationStack {
                FamilyActivityPicker(selection: $restrictions.selection)
                    .navigationTitle("Choose restrictions")
                    .disabled(focusSession.isActive)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                restrictions.isPickerPresented = false
                                restrictions.persistSelection()
                            }
                            .disabled(focusSession.isActive)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isDailyLimitPickerPresented) {
            NavigationStack {
                FamilyActivityPicker(selection: $dailyLimitSelection)
                    .navigationTitle("Choose limit apps")
                    .disabled(focusSession.isActive)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                dailyLimits.add(
                                    selection: dailyLimitSelection,
                                    minutes: selectedDailyLimitMinutes
                                )
                                if dailyLimits.errorMessage == nil {
                                    dailyLimitSelection = FamilyActivitySelection()
                                    isDailyLimitPickerPresented = false
                                }
                            }
                            .disabled(focusSession.isActive)
                        }
                    }
            }
            .preferredColorScheme(.dark)
        }
        .sheet(isPresented: $isStartRitualPresented) {
            FocusStartRitualView(durationMinutes: chosenDurationMinutes) { intention in
                beginFocusSession(intention: intention)
            }
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
            Text("Noxa can remind you five minutes before a session ends and let you know when it is complete.")
        }
    }

    private var homeContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
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
        .background(Color.black)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Noxa")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            Text("Take back\nyour attention.")
                .font(.system(size: 40, weight: .bold, design: .rounded))
                .tracking(-1)

            Text("Block distractions when you need to focus.\nKeep the rest of your day yours.")
                .font(.body)
                .foregroundStyle(.secondary)
        }
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
                Label("Focus session", systemImage: "timer")
                    .font(.headline)
                Spacer()
                if focusSession.isActive {
                    Text("ACTIVE")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }
            }

            if let activeSession = focusSession.activeSession {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let remaining = max(0, activeSession.plannedEndAt.timeIntervalSince(context.date))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Self.durationString(seconds: Int(remaining)))
                            .font(.system(size: 54, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .tracking(-2)

                        Text("Your selected distractions are blocked until \(activeSession.plannedEndAt.formatted(date: .omitted, time: .shortened)).")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        if let intention = focusSession.activeIntention, !intention.isEmpty {
                            Label(intention, systemImage: "scope")
                                .font(.subheadline.weight(.medium))
                                .padding(.top, 4)
                        }
                    }
                }

                Button("End Session Early") {
                    isEndRitualPresented = true
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
            } else {
                Text(hasFocusRestrictions
                     ? "\(focusRestrictionCount) distraction(s) ready to block."
                     : "Choose apps or websites first, then start a session.")
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([15, 25, 45, 60, 120], id: \.self) { minutes in
                            Button(Self.durationLabel(minutes: minutes)) {
                                selectedDurationMinutes = minutes
                                isCustomDuration = false
                            }
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(!isCustomDuration && selectedDurationMinutes == minutes ? .black : .white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(!isCustomDuration && selectedDurationMinutes == minutes ? Color.white : Color.white.opacity(0.08))
                            .clipShape(Capsule())
                        }

                        Button("Custom") {
                            isCustomDuration = true
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(isCustomDuration ? .black : .white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(isCustomDuration ? Color.white : Color.white.opacity(0.08))
                        .clipShape(Capsule())
                    }
                }

                if isCustomDuration {
                    HStack(spacing: 12) {
                        Text("Custom duration")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        TextField("Minutes", value: $customDurationMinutes, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 88)
                            .onChange(of: customDurationMinutes) { value in
                                customDurationMinutes = min(
                                    max(value, NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes),
                                    NoxaDeviceActivityConfiguration.maximumFocusSessionMinutes
                                )
                            }
                    }

                    Text("Choose \(NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes)–\(NoxaDeviceActivityConfiguration.maximumFocusSessionMinutes) minutes.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button("Start Focus Session") {
                    isStartRitualPresented = true
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
                Button("Edit") {
                    restrictions.isPickerPresented = true
                }
                .font(.subheadline.weight(.semibold))
                .disabled(focusSession.isActive)
            }

            Text(hasConfiguredRestrictions
                 ? "\(configuredRestrictionCount) private selection(s) saved on this device."
                 : "Nothing selected yet.")
                .foregroundStyle(.secondary)

            if !hasConfiguredRestrictions {
                Button("Choose Apps and Websites") {
                    restrictions.isPickerPresented = true
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
                .disabled(!authorization.state.isApproved || focusSession.isActive)
            }
        }
        .noxaCard()
    }

    private var blocklistContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Selections stay private on this device. Noxa works with Apple’s opaque Screen Time tokens instead of reading inside your apps.")
                    .foregroundStyle(.secondary)

                if focusSession.isActive {
                    Label("Blocklist locked until this focus session ends", systemImage: "lock.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                Button("Choose Apps and Websites") {
                    restrictions.isPickerPresented = true
                }
                .buttonStyle(NoxaPrimaryButtonStyle())
                .disabled(!authorization.state.isApproved || focusSession.isActive)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Saved selection", systemImage: "lock.shield")
                        .font(.headline)
                    Text(hasConfiguredRestrictions
                         ? "\(configuredRestrictionCount) item(s) selected. Apple keeps app identity private to Noxa."
                         : "No apps, categories, or websites selected yet.")
                        .foregroundStyle(.secondary)
                }
                .noxaCard()

                websiteCard
                dailyLimitsCard

                #if DEBUG
                VStack(alignment: .leading, spacing: 14) {
                    Label("Validation controls", systemImage: "wrench.and.screwdriver")
                        .font(.headline)

                    Text("Use these controls to verify the Screen Time integration on a physical iPhone.")
                        .foregroundStyle(.secondary)

                    HStack {
                        Button(restrictions.isShieldActive ? "Shield Active" : "Apply Test Shield") {
                            restrictions.persistSelection()
                            restrictions.applyShield(customDomains: websites.domains)
                        }
                        .buttonStyle(NoxaPrimaryButtonStyle())
                        .disabled(
                            !authorization.state.isApproved
                                || !hasFocusRestrictions
                                || restrictions.isShieldActive
                                || focusSession.isActive
                        )

                        Button("Remove Shield") {
                            restrictions.removeShield()
                        }
                        .buttonStyle(NoxaSecondaryButtonStyle())
                        .disabled(!restrictions.isShieldActive || focusSession.isActive)
                    }

                    Button("Block After 1 Minute of Use") {
                        restrictions.persistSelection()
                        monitoring.start(selection: restrictions.selection)
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                    .disabled(
                        !authorization.state.isApproved
                            || !restrictions.hasSelection
                            || restrictions.isShieldActive
                            || focusSession.isActive
                            || monitoring.isMonitoring
                    )

                    if monitoring.isMonitoring {
                        HStack {
                            Text("Usage monitor active")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Stop") {
                                monitoring.stop()
                                restrictions.removeShield()
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .noxaCard()
                #endif
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(Color.black)
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
                    .disabled(focusSession.isActive)

                Button("Add") {
                    if websites.addDomain(newDomain) {
                        newDomain = ""
                    }
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
                .fixedSize()
                .disabled(focusSession.isActive || websites.domains.count >= WebsiteBlocklistService.maximumDomains)
            }

            if websites.domains.isEmpty {
                Text("No custom websites added.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

            if let errorMessage = websites.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
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

            Text("Give selected apps a daily allowance. When the allowance is reached, Noxa asks Apple’s Screen Time controls to shield them until the next day.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach([15, 30, 45, 60, 120], id: \.self) { minutes in
                    Button(Self.durationLabel(minutes: minutes)) {
                        selectedDailyLimitMinutes = minutes
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(selectedDailyLimitMinutes == minutes ? .black : .white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(selectedDailyLimitMinutes == minutes ? Color.white : Color.white.opacity(0.08))
                    .clipShape(Capsule())
                    .disabled(focusSession.isActive)
                }
            }

            Button("Add App Limit") {
                dailyLimitSelection = FamilyActivitySelection()
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
                        .disabled(focusSession.isActive)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(configuration.dailyLimitMinutes) minutes per day")
                                .font(.subheadline.weight(.semibold))
                            Text("\(configuration.selection.applicationTokens.count) app(s) selected")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Remove") {
                            dailyLimits.remove(configuration)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .disabled(focusSession.isActive)
                    }
                }
            }

            HStack {
                Text(hasActiveDailyLimits ? "Daily limits active" : "Daily limits are off")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(hasActiveDailyLimits ? "Stop" : "Start") {
                    if hasActiveDailyLimits {
                        dailyLimits.stopMonitoring()
                    } else {
                        dailyLimits.startMonitoring()
                    }
                }
                .font(.subheadline.weight(.semibold))
                .disabled(
                    dailyLimits.configurations.filter(\.isEnabled).isEmpty
                        || (!hasActiveDailyLimits && !authorization.state.isApproved)
                        || focusSession.isActive
                )
            }

            if let errorMessage = dailyLimits.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .noxaCard()
    }

    private var statsContent: some View {
        let statistics = FocusStatistics(history: focusSession.history)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Build a calmer day.")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text("Your completed focus sessions and streaks will appear here.")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    statCard(title: "Sessions", value: "\(statistics.completedSessions)")
                    statCard(title: "This week", value: "\(statistics.weeklyFocusMinutes)m")
                }

                HStack(spacing: 12) {
                    statCard(title: "Current streak", value: "\(statistics.currentStreak)d")
                    statCard(title: "Longest streak", value: "\(statistics.longestStreak)d")
                }

                VStack(alignment: .leading, spacing: 10) {
                    Label("Follow-through", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.headline)
                    Text("\(statistics.completionRate)% completion rate")
                        .font(.title2.weight(.semibold))
                    Text("\(statistics.completedSessions) completed · \(statistics.abandonedSessions) ended early")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .noxaCard()

                recentSessionsCard
            }
            .padding()
        }
        .scrollIndicators(.hidden)
        .background(Color.black)
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
        .noxaCard()
    }

    private var accountContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Signed in", systemImage: "checkmark.shield.fill")
                        .font(.headline)
                    Text(authentication.userEmail ?? "Apple account")
                        .foregroundStyle(.secondary)
                    Text("Screen Time selections and active shields stay on this device. Focus history and website domains sync securely when you’re online.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .noxaCard()

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

                VStack(alignment: .leading, spacing: 12) {
                    Label("Noxa subscription", systemImage: subscriptions.hasAccess ? "checkmark.seal.fill" : "creditcard")
                        .font(.headline)
                    Text(subscriptions.hasAccess
                         ? "Your subscription is active."
                         : "A subscription is required to use Noxa.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button(subscriptions.hasAccess ? "View Subscription" : "See Subscription Plans") {
                        isPaywallPresented = true
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                }
                .noxaCard()

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
        .background(Color.black)
        .sheet(isPresented: $isPaywallPresented) {
            PaywallView()
                .environmentObject(subscriptions)
        }
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
            websites: websites,
            cloudSync: cloudSync
        )
    }

    private var chosenDurationMinutes: Int {
        isCustomDuration ? customDurationMinutes : selectedDurationMinutes
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

    private func enableNotificationsForActiveSession() async {
        guard await notifications.requestAuthorization(),
              let session = focusSession.activeSession else { return }
        await notifications.schedule(for: session)
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.system(size: 30, weight: .semibold, design: .rounded))
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .noxaCard()
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
}

struct NoxaPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}

struct NoxaSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08))
            .clipShape(RoundedRectangle(cornerRadius: 13))
    }
}

extension View {
    func noxaCard() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
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
        .environmentObject(SubscriptionService())
        .environmentObject(FocusSessionService())
        .environmentObject(ScreenTimeRestrictionService())
        .environmentObject(DeviceActivityMonitoringService())
        .environmentObject(DailyLimitService())
        .environmentObject(WebsiteBlocklistService())
        .environmentObject(CloudSyncService())
        .environmentObject(FocusNotificationService())
}
