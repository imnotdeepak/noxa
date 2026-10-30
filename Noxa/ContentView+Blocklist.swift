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
            return "Turn on Noxa Safari Filter in Settings → Apps → Safari → Extensions, and allow instagram.com."
        }
        if safariFilterRecentlyConnected {
            return "Connected to Instagram in Safari."
        }
        return "Not connected yet. Open Instagram in Safari, allow the extension, and refresh."
    }

    var youtubeFilterRecentlyConnected: Bool {
        guard let youtubeFilterLastSeenAt else { return false }
        return safariExtensionEnabled != false
            && (0..<5 * 60).contains(Date().timeIntervalSince(youtubeFilterLastSeenAt))
    }

    var youtubeFilterStatusMessage: String {
        if safariExtensionEnabled == false {
            return "Turn on Noxa Safari Filter in Settings → Apps → Safari → Extensions, and allow youtube.com."
        }
        if youtubeFilterRecentlyConnected {
            return "Connected to YouTube in Safari."
        }
        return "Not connected yet. Open YouTube in Safari, allow the extension for youtube.com, and refresh."
    }

    func refreshSafariExtensionStatus() async {
        safariFilterLastSeenAt = AppGroupStore.shared.safariFilterLastSeenAt
        youtubeFilterLastSeenAt = AppGroupStore.shared.youtubeFilterLastSeenAt
        if #available(iOS 26.2, *) {
            let state = try? await SFSafariExtensionManager.stateOfExtension(
                withIdentifier: "LycheeCorp.Noxa.SafariFilter"
            )
            safariExtensionEnabled = state?.isEnabled
        }
    }

    var blocklistContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                let appCount = restrictions.selection.applicationTokens.count
                    + restrictions.selection.categoryTokens.count
                let siteCount = websites.domains.count + restrictions.selection.webDomainTokens.count
                HStack(spacing: 4) {
                    Text("\(appCount) app\(appCount == 1 ? "" : "s") · \(siteCount) website\(siteCount == 1 ? "" : "s") selected")
                        .font(NoxaType.body)
                        .foregroundStyle(NoxaTheme.secondaryText)
                        .contentTransition(.numericText())
                    NoxaInfoButton(
                        title: "Blocklist",
                        message: "These are what Focus and Pomodoro block. Being on this list doesn't mean an app is blocked right now, and each schedule keeps its own apps and sites."
                    )
                }

                // Scope, stated plainly: editing this list doesn't change rules.
                Text("Used by Focus and Pomodoro. Schedules and daily limits keep their own apps.")
                    .font(NoxaType.footnote)
                    .foregroundStyle(NoxaTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)

                if !authorization.state.isApproved {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Screen Time access is off", systemImage: "exclamationmark.triangle.fill")
                            .font(NoxaType.subheadlineSemibold)
                            .foregroundStyle(NoxaTheme.warning)
                        Text("Nothing on this list can be blocked until you allow it.")
                            .font(NoxaType.footnote)
                            .foregroundStyle(NoxaTheme.secondaryText)
                        Button("Allow Screen Time Access") {
                            Task { await authorization.requestAuthorization() }
                        }
                        .buttonStyle(NoxaSecondaryButtonStyle())
                    }
                    .noxaCard(padding: 16)
                }

                if focusSession.isActive {
                    Label("You can add, not remove, until Focus ends", systemImage: "lock.fill")
                        .font(NoxaType.footnoteSemibold)
                        .foregroundStyle(NoxaTheme.warning)
                } else if focusSession.hasPomodoroCycle {
                    Label("Locked until the Pomodoro ends or you stop it on a break", systemImage: "lock.fill")
                        .font(NoxaType.footnoteSemibold)
                        .foregroundStyle(NoxaTheme.warning)
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        Text("Apps")
                            .font(NoxaType.title2)
                            .foregroundStyle(NoxaTheme.primaryText)
                        Spacer()
                        Button(focusSession.isActive ? "Add" : (restrictions.hasSelection ? "Edit" : "Choose")) {
                            presentRestrictionPicker()
                        }
                        .font(NoxaType.subheadlineSemibold)
                        .foregroundStyle(NoxaTheme.accent)
                        .frame(minHeight: 44)
                        .disabled(!authorization.state.isApproved || (focusSession.hasPomodoroCycle && !focusSession.isActive))
                    }
                    .padding(.bottom, 6)

                    if restrictions.selection.applicationTokens.isEmpty,
                       restrictions.selection.categoryTokens.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Choose the apps that pull you away. Focus and Pomodoro will block them.")
                                .font(NoxaType.subheadline)
                                .foregroundStyle(NoxaTheme.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Choose Apps") { presentRestrictionPicker() }
                                .buttonStyle(NoxaSecondaryButtonStyle())
                                .disabled(!authorization.state.isApproved)
                        }
                        .padding(.vertical, 10)
                    } else {
                        ForEach(Array(restrictions.selection.applicationTokens.enumerated()), id: \.element) { index, token in
                            if index > 0 { Divider().overlay(NoxaTheme.border) }
                            Label(token)
                                .labelStyle(NoxaAppRowLabelStyle())
                        }
                        ForEach(Array(restrictions.selection.categoryTokens), id: \.self) { token in
                            if !restrictions.selection.applicationTokens.isEmpty {
                                Divider().overlay(NoxaTheme.border)
                            }
                            Label(token)
                                .labelStyle(NoxaAppRowLabelStyle())
                        }
                    }
                }
                .noxaCard(padding: 20)

                NavigationLink {
                    ScrollView {
                        websiteCard
                            .padding(.horizontal, NoxaTheme.Spacing.screen)
                            .padding(.vertical, 12)
                    }
                    .noxaScreenBackground()
                    .navigationTitle("Websites")
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "globe")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(NoxaTheme.accent)
                            .frame(width: 52, height: 52)
                            .background(NoxaTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Websites")
                                .font(NoxaType.headline)
                                .foregroundStyle(NoxaTheme.primaryText)
                            Text("\(siteCount) website\(siteCount == 1 ? "" : "s") selected")
                                .font(NoxaType.subheadline)
                                .foregroundStyle(NoxaTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(NoxaType.subheadlineSemibold)
                            .foregroundStyle(NoxaTheme.secondaryText)
                    }
                    .noxaCard(padding: 20)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
    }

    var websiteCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                NoxaCardHeader(
                    title: "Websites",
                    systemImage: "globe",
                    info: "Add domains like reddit.com. Noxa cleans them up and blocks them on this device during Focus."
                )
                Spacer()
                Text("\(websites.domains.count)/\(WebsiteBlocklistService.maximumDomains)")
                    .font(NoxaType.caption.monospacedDigit())
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .accessibilityLabel("\(websites.domains.count) of \(WebsiteBlocklistService.maximumDomains) websites")
            }

            HStack(spacing: 10) {
                TextField("reddit.com", text: $newDomain)
                    .accessibilityLabel("Website to block")
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(NoxaTextFieldStyle())

                Button("Add") {
                    if websites.addDomain(newDomain) {
                        newDomain = ""
                        showToast("Website added")
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

    /// The app block follows the filter. A release on the recovery screen or
    /// at paid-access expiry clears the flag, so restore it once the paid app
    /// is open again; this also turns it on for people who kept it off before.
    func restoreInstagramAppBlockIfNeeded() {
        let store = AppGroupStore.shared
        guard store.instagramSiteMode == .distractionFree,
              !store.instagramAppBlockEnabled else { return }
        store.setInstagramAppBlockEnabled(true)
        instagramAppBlockEnabled = true
        InstagramSiteProtectionService.reconcile()
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
            instagramAppBlockEnabled = instagramSiteMode == .distractionFree
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

    var youtubeAppPickerSheet: some View {
        NavigationStack {
            FamilyActivityPicker(selection: $youtubePickerSelection)
                .navigationTitle("Choose YouTube")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            isYouTubeAppPickerPresented = false
                            youtubeAppBlockEnabled = AppGroupStore.shared.youtubeAppBlockEnabled
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { saveYouTubeAppSelection() }
                            .disabled(youtubePickerSelection.applicationTokens.count != 1)
                    }
                }
        }
        .tint(NoxaTheme.accent)
        .preferredColorScheme(.dark)
    }

    /// Like Instagram: a release on the recovery screen or at paid-access
    /// expiry clears the flag, so restore it once the paid app is open again.
    func restoreYouTubeAppBlockIfNeeded() {
        let store = AppGroupStore.shared
        guard store.youtubeShortsHidden, !store.youtubeAppBlockEnabled else { return }
        store.setYouTubeAppBlockEnabled(true)
        youtubeAppBlockEnabled = true
        YouTubeShortsProtectionService.reconcile()
    }

    func presentYouTubeAppPicker() {
        youtubePickerSelection = youtubeAppSelection ?? FamilyActivitySelection()
        isYouTubeAppPickerPresented = true
    }

    /// Keeps only the app itself, so a category can't block unrelated apps.
    func saveYouTubeAppSelection() {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = youtubePickerSelection.applicationTokens
        do {
            try AppGroupStore.shared.saveYouTubeAppSelection(selection)
            youtubeAppSelection = selection
            youtubeAppBlockEnabled = youtubeShortsHidden
            AppGroupStore.shared.setYouTubeAppBlockEnabled(youtubeAppBlockEnabled)
            YouTubeShortsProtectionService.reconcile()
            youtubeAppBlockMessage = youtubeAppBlockEnabled && !YouTubeShortsProtectionService.isAppBlockApplied
                ? "Noxa could not activate the app block. Try again after reopening Noxa." : nil
            isYouTubeAppPickerPresented = false
        } catch {
            youtubeAppBlockEnabled = false
            youtubeAppBlockMessage = "Noxa could not save the YouTube app selection. Please try again."
            isYouTubeAppPickerPresented = false
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
