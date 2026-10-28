import FamilyControls
import SafariServices
import SwiftUI
import UIKit

extension ContentView {
    var safariFilterRecentlyConnected: Bool {
        guard let safariFilterLastSeenAt else { return false }
        return safariExtensionEnabled != false
            && (0..<5 * 60).contains(Date().timeIntervalSince(safariFilterLastSeenAt))
    }

    var safariFilterStatusMessage: String {
        if safariExtensionEnabled == false {
            return "Turn on Noxa Instagram Filter in Settings → Apps → Safari → Extensions, then allow access to instagram.com. You can also block Instagram with a schedule or your blocklist."
        }
        if safariFilterRecentlyConnected {
            return "Noxa recently connected to Instagram in Safari. Check Reels and Explore there; this connection alone cannot confirm that every page element was hidden."
        }
        return "Noxa has not recently connected to Instagram in Safari. Open the site, allow extension access, and refresh it. If filtering stays unavailable, block Instagram with a schedule or your blocklist."
    }

    func refreshSafariExtensionStatus() async {
        safariFilterLastSeenAt = AppGroupStore.shared.safariFilterLastSeenAt
        if #available(iOS 26.2, *) {
            let state = try? await SFSafariExtensionManager.stateOfExtension(
                withIdentifier: "LycheeCorp.Noxa.SafariFilter"
            )
            safariExtensionEnabled = state?.isEnabled
        }
    }

    var blocklistContent: some View {
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

    var websiteCard: some View {
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

    var pomodoroCard: some View {
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
                    isPomodoroStartConfirmationPresented = true
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

    func openInstagramInSafari() {
        InstagramSiteProtectionService.openInSafari()
    }

    @ViewBuilder
    var instagramAppBlockControls: some View {
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

    var instagramAppPickerSheet: some View {
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

    func presentInstagramAppPicker() {
        instagramPickerSelection = instagramAppSelection ?? FamilyActivitySelection()
        isInstagramAppPickerPresented = true
    }

    /// Keeps only the app itself. Categories would block unrelated apps, and
    /// Instagram's website stays reachable through the Safari filter.
    func saveInstagramAppSelection() {
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

    func beginPomodoro() {
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
}
