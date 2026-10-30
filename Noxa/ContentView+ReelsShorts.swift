import SwiftUI
import UIKit

/// Hiding Reels and Shorts sits with limits and schedules: like them it is
/// always on, and it commits for a week at a time.
enum ShortVideoFilter: String, Identifiable {
    case instagram
    case youtube

    var id: Self { self }

    var title: String {
        switch self {
        case .instagram: "Instagram Reels"
        case .youtube: "YouTube Shorts"
        }
    }

    var subtitle: String {
        switch self {
        case .instagram: "Hides Reels and Explore"
        case .youtube: "Hides Shorts"
        }
    }

    var appName: String {
        switch self {
        case .instagram: "Instagram"
        case .youtube: "YouTube"
        }
    }

    var website: String {
        switch self {
        case .instagram: "instagram.com"
        case .youtube: "youtube.com"
        }
    }

    func openInSafari() {
        switch self {
        case .instagram: InstagramSiteProtectionService.openInSafari()
        case .youtube: YouTubeShortsProtectionService.openInSafari()
        }
    }
}

/// The Safari setup guide, for one filter or for both (from the section's
/// info button).
struct FilterSetupGuide: Identifiable {
    let filter: ShortVideoFilter?
    var id: String { filter?.rawValue ?? "both" }
}

extension ContentView {
    var reelsShortsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                Text("Reels & Shorts")
                    .font(NoxaType.title2)
                    .foregroundStyle(NoxaTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                // Opens the full setup guide rather than a small popover.
                Button {
                    filterSetupGuide = FilterSetupGuide(filter: nil)
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(NoxaTheme.secondaryText)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("How to set up Reels & Shorts")
            }

            VStack(spacing: 0) {
                filterRow(.instagram)
                Divider().overlay(NoxaTheme.border)
                filterRow(.youtube)
            }
            .noxaCard(padding: 16)
        }
        .task { await refreshSafariExtensionStatus() }
        .sheet(item: $filterSetupGuide) { guide in
            AnyView(filterSetupSheet(guide.filter))
        }
        .alert(
            "Lock this for a week?",
            isPresented: Binding(
                get: { pendingFilterLock != nil },
                set: { if !$0 { pendingFilterLock = nil } }
            ),
            presenting: pendingFilterLock
        ) { filter in
            Button("Cancel", role: .cancel) {}
            Button("Lock for a Week") { setFilter(filter, on: true) }
        } message: { filter in
            Text("First allow \(filter == .instagram ? "instagram.com" : "youtube.com") in Safari → Extensions → Noxa Safari Filter. If you lock now, you can't turn this off until \(Date().addingTimeInterval(WeeklyCommitment.lockDuration).formatted(date: .abbreviated, time: .omitted)). Then you get one day to change it before it locks again.")
        }
    }

    private func filterRow(_ filter: ShortVideoFilter) -> some View {
        let isOn = isFilterOn(filter)
        let state = filterLockState(filter)
        let isLocked: Bool = if case .locked = state { true } else { false }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(filter.title)
                        .font(NoxaType.body)
                        .foregroundStyle(NoxaTheme.primaryText)
                    if isOn {
                        weeklyLockLabel(state)
                    } else {
                        Text(filter.subtitle)
                            .font(NoxaType.subheadline)
                            .foregroundStyle(NoxaTheme.secondaryText)
                    }
                }
                Spacer(minLength: 0)
                noxaStatePill(
                    isOn: isOn,
                    isDisabled: (isOn && isLocked) || !authorization.state.isApproved,
                    label: filter.title
                ) {
                    if isOn {
                        setFilter(filter, on: false)
                    } else {
                        pendingFilterLock = filter
                    }
                }
            }

            if isOn {
                // Until Safari reports in, setup isn't finished.
                if !isFilterConnected(filter) {
                    Button {
                        filterSetupGuide = FilterSetupGuide(filter: filter)
                    } label: {
                        Label("Finish setup in Safari", systemImage: "exclamationmark.triangle.fill")
                            .font(NoxaType.captionSemibold)
                            .foregroundStyle(NoxaTheme.warning)
                    }
                    .frame(maxWidth: .infinity)
                }
                HStack(spacing: 24) {
                    Button {
                        filter.openInSafari()
                    } label: {
                        Label("Open in Safari", systemImage: "safari")
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(NoxaTheme.accent)
                    // Fallback for when blocking by app ID doesn't match.
                    Button("App still opens?") {
                        switch filter {
                        case .instagram: presentInstagramAppPicker()
                        case .youtube: presentYouTubeAppPicker()
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(NoxaTheme.secondaryText)
                }
                .font(NoxaType.footnoteSemibold)
                .frame(maxWidth: .infinity, minHeight: 32)
                if let message = filter == .instagram ? instagramAppBlockMessage : youtubeAppBlockMessage {
                    Text(message)
                        .font(NoxaType.caption)
                        .foregroundStyle(NoxaTheme.warning)
                }
            }
        }
        .padding(.vertical, 12)
    }

    func isFilterOn(_ filter: ShortVideoFilter) -> Bool {
        switch filter {
        case .instagram: instagramSiteMode == .distractionFree
        case .youtube: youtubeShortsHidden
        }
    }

    func filterLockState(_ filter: ShortVideoFilter, at date: Date = Date()) -> WeeklyCommitment.State {
        guard isFilterOn(filter) else { return .unlocked }
        let store = AppGroupStore.shared
        return WeeklyCommitment.state(
            anchor: filter == .instagram ? store.instagramLockAnchor : store.youtubeLockAnchor,
            at: date
        )
    }

    private func isFilterConnected(_ filter: ShortVideoFilter) -> Bool {
        filter == .instagram ? safariFilterRecentlyConnected : youtubeFilterRecentlyConnected
    }

    /// Turning on blocks the app right away by its app ID and starts a
    /// locked week. Turning off is refused while that week is running.
    func setFilter(_ filter: ShortVideoFilter, on: Bool) {
        if !on, case .locked = filterLockState(filter) { return }
        let store = AppGroupStore.shared
        switch filter {
        case .instagram:
            let mode: InstagramSiteMode = on ? .distractionFree : .off
            store.setInstagramSiteMode(mode)
            instagramSiteMode = mode
            instagramAppBlockEnabled = on
            instagramAppBlockMessage = nil
            InstagramSiteProtectionService.reconcile()
        case .youtube:
            store.setYouTubeShortsHidden(on)
            youtubeShortsHidden = on
            youtubeAppBlockEnabled = on
            youtubeAppBlockMessage = nil
            YouTubeShortsProtectionService.reconcile()
        }
        showToast(on ? "\(filter.title) hidden · locked for a week" : "\(filter.title) back on")
        // First time on, or never connected: walk through the Safari setup.
        if on, !isFilterConnected(filter) {
            // Wait for the lock alert to finish closing before presenting.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                filterSetupGuide = FilterSetupGuide(filter: filter)
            }
        }
    }

    /// The Safari steps, shown when a filter is turned on before Safari has
    /// connected, from "Finish setup" until it does, and from the info button.
    func filterSetupSheet(_ filter: ShortVideoFilter?) -> some View {
        let sites = filter.map { "**\($0.website)**" } ?? "**instagram.com** and **youtube.com**"
        let opener = filter.map { "Open \($0.appName) in Safari" }
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(filter.map { "Set up \($0.title)" } ?? "Set up Reels & Shorts")
                            .font(NoxaTheme.font(32, weight: .bold, relativeTo: .largeTitle))
                            .tracking(-0.6)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(filter.map {
                            "The \($0.appName) app is blocked. Use \($0.website) in Safari, where Noxa hides \($0 == .instagram ? "Reels" : "Shorts")."
                        } ?? "The apps can't be filtered, so Noxa blocks them. Use the websites in Safari, where Noxa hides Reels and Shorts.")
                            .font(NoxaType.body)
                            .foregroundStyle(NoxaTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 26) {
                        setupStep(1, "Open the **Settings** app.")
                        setupStep(2, "Go to **Apps → Safari → Extensions**.")
                        setupStep(3, "Tap **Noxa Safari Filter** and turn it **on**.")
                        setupStep(4, "Under **Permissions**, set \(sites) to **Allow**.")
                        setupStep(5, opener.map { "Come back and tap **\($0)**." }
                            ?? "Come back and open Instagram or YouTube in Safari.")
                    }

                    if let filter {
                        Label(
                            isFilterConnected(filter) ? "Connected to \(filter.appName) in Safari" : "Not connected yet",
                            systemImage: isFilterConnected(filter) ? "checkmark.circle.fill" : "circle.dashed"
                        )
                        .font(NoxaType.subheadlineSemibold)
                        .foregroundStyle(isFilterConnected(filter) ? NoxaTheme.accent : NoxaTheme.secondaryText)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 6) {
                    if let filter, let opener {
                        Button {
                            filter.openInSafari()
                        } label: {
                            Text(opener).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(NoxaPrimaryButtonStyle())
                    }
                    Button("Done") { filterSetupGuide = nil }
                        .font(NoxaType.subheadlineSemibold)
                        .foregroundStyle(NoxaTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                .background(NoxaTheme.background)
            }
            .noxaScreenBackground()
        }
        .tint(NoxaTheme.accent)
        .preferredColorScheme(.dark)
        .presentationDragIndicator(.visible)
        .task { await refreshSafariExtensionStatus() }
    }

    /// `markdown` may bold inserted site names, which a LocalizedStringKey
    /// interpolation would print as literal asterisks.
    private func setupStep(_ number: Int, _ markdown: String) -> some View {
        let text = Text((try? AttributedString(markdown: markdown)) ?? AttributedString(markdown))
        return setupStepRow(number, text)
    }

    private func setupStepRow(_ number: Int, _ text: Text) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text("\(number)")
                .font(NoxaTheme.font(18, weight: .bold, relativeTo: .headline))
                .foregroundStyle(.black)
                .frame(width: 36, height: 36)
                .background(NoxaTheme.accent, in: Circle())
                .accessibilityHidden(true)
            text
                .font(NoxaTheme.font(20, relativeTo: .title3))
                .foregroundStyle(NoxaTheme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 5)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Step \(number). ") + text)
    }
}
