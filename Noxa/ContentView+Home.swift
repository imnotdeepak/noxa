import FamilyControls
import SafariServices
import SwiftUI
import UIKit

enum HomeFocusMode: Hashable {
    case focus
    case pomodoro
}

extension ContentView {
    // Home is built from separately erased pieces: as one inlined value it
    // sits at the edge of what the runtime can copy safely and crashes.
    var homeContent: some View {
        homeScrollView
            .safeAreaInset(edge: .bottom) {
                if focusSession.activeSession == nil && focusSession.pomodoroBreakEndsAt == nil {
                    AnyView(homeStartButton)
                        .padding(.horizontal, NoxaTheme.Spacing.screen)
                        .padding(.top, 12)
                        .padding(.bottom, 8)
                }
            }
            .noxaScreenBackground()
            .onChange(of: focusSession.activeSession?.id) { newID in
                celebrateCompletionIfNeeded(endedSessionID: lastHomeSessionID, newSessionID: newID)
                lastHomeSessionID = newID
            }
            .onAppear { lastHomeSessionID = focusSession.activeSession?.id }
    }

    var homeScrollView: AnyView {
        AnyView(ScrollView { homeStack }.scrollIndicators(.hidden))
    }

    var homeStack: AnyView {
        AnyView(
            VStack(spacing: 24) {
                AnyView(homeHeader)

                if !authorization.state.isApproved {
                    AnyView(permissionCard)
                        .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }

                AnyView(completedSessionCard)

                if focusSession.isPausedForScreenTimeAccess {
                    AnyView(screenTimePauseNotice)
                }

                // The Halo's light spreads past the ring; keep it behind cards.
                focusSection
                    .zIndex(-1)

                if let errorMessage = focusSession.errorMessage {
                    Text(errorMessage)
                        .font(NoxaType.footnote)
                        .foregroundStyle(.red)
                }

                AnyView(nextScheduledBlockCard)

                if instagramSiteMode == .distractionFree && instagramAppBlockEnabled {
                    Button(action: openInstagramInSafari) {
                        Label("Open Instagram in Safari", systemImage: "safari")
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                }

                if youtubeShortsHidden && youtubeAppBlockEnabled {
                    Button(action: YouTubeShortsProtectionService.openInSafari) {
                        Label("Open YouTube in Safari", systemImage: "safari")
                    }
                    .buttonStyle(NoxaSecondaryButtonStyle())
                }
            }
            .noxaAnimation(value: authorization.state.isApproved)
            .noxaAnimation(value: focusSession.isActive)
            .noxaAnimation(value: isCustomDuration)
            .noxaAnimation(value: homeMode)
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.top, 4)
            .padding(.bottom, 16)
        )
    }

    /// A light success tap when a session really completes; never for an
    /// early end, an interruption or a failed start.
    func celebrateCompletionIfNeeded(endedSessionID: UUID?, newSessionID: UUID?) {
        guard newSessionID == nil,
              let endedSessionID,
              focusSession.history.first(where: { $0.id == endedSessionID })?.outcome == .completed else { return }
        NoxaHaptics.success()
        lastCompletedSessionID = endedSessionID
    }

    /// Shown after a session really completes, until dismissed or the next
    /// session starts. Early ends and failures never get this card.
    @ViewBuilder
    var completedSessionCard: some View {
        if focusSession.activeSession == nil,
           let id = lastCompletedSessionID,
           let record = focusSession.history.first(where: { $0.id == id }),
           record.outcome == .completed {
            let minutes = (record.actualDurationSeconds ?? record.plannedDurationSeconds) / 60
            HStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(NoxaTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Focus complete")
                        .font(NoxaType.headline)
                        .foregroundStyle(NoxaTheme.primaryText)
                    Text("\(Self.compactFocusTime(minutes: minutes)) with distractions blocked")
                        .font(NoxaType.subheadline)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                Spacer()
                Button {
                    withAnimation(NoxaMotion.snappy) { lastCompletedSessionID = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(NoxaType.footnoteSemibold)
                        .foregroundStyle(NoxaTheme.secondaryText)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Dismiss")
            }
            .noxaCard(padding: 16)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    var homeStartButton: some View {
        if homeMode == .focus {
            Button(chosenDurationMinutes < 60 ? "Start \(chosenDurationMinutes)-minute Focus" : "Start \(Self.durationLabel(minutes: chosenDurationMinutes)) Focus") {
                isCustomDurationFieldFocused = false
                NoxaHaptics.selection()
                isFocusStartReviewPresented = true
            }
            .buttonStyle(NoxaPrimaryButtonStyle())
            .disabled(
                !authorization.state.isApproved
                    || !hasFocusRestrictions
                    || !isCustomDurationValid
                    || restrictions.isShieldActive
                    || monitoring.isMonitoring
            )
        } else {
            Button("Start Pomodoro") {
                NoxaHaptics.selection()
                isPomodoroStartConfirmationPresented = true
            }
            .buttonStyle(NoxaPrimaryButtonStyle())
            .disabled(
                !authorization.state.isApproved
                    || !hasFocusRestrictions
                    || focusSession.hasPomodoroCycle
                    || restrictions.isShieldActive
                    || monitoring.isMonitoring
            )
        }
    }

    /// Type-erased so Home's view value stays small enough to copy safely.
    var focusSection: AnyView {
        if let activeSession = focusSession.activeSession {
            return AnyView(activeFocusView(activeSession))
        } else if let breakEndsAt = focusSession.pomodoroBreakEndsAt {
            return AnyView(pomodoroBreakView(endsAt: breakEndsAt))
        }
        return AnyView(idleFocusView)
    }

    var homeHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text(homeEyebrow)
                    .font(NoxaType.footnoteSemibold)
                    .tracking(2)
                    .foregroundStyle(NoxaTheme.secondaryText)
                Text(focusSession.pomodoroBreakEndsAt != nil
                     ? "Take a breather."
                     : (focusSession.isActive ? "Stay focused." : "Find your focus."))
                    .font(NoxaTheme.font(34, weight: .bold, relativeTo: .largeTitle))
                    .tracking(-1.2)
                    .foregroundStyle(NoxaTheme.primaryText)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                selectedTab = .dailyLimits
            } label: {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Limits and schedules")
        }
    }

    var homeEyebrow: String {
        let date = Date().formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased()
        guard dailyFocusMinutes > 0 else { return date }
        return "\(date) · \(dailyFocusMinutes) MIN TODAY"
    }

    var idleFocusView: some View {
        VStack(spacing: 22) {
            NoxaFocusHalo(
                progress: Double(homeMode == .pomodoro ? pomodoroWorkMinutes : haloDurationMinutes) / 60,
                value: Self.durationString(
                    seconds: (homeMode == .pomodoro ? pomodoroWorkMinutes : haloDurationMinutes) * 60
                ),
                caption: homeMode == .pomodoro ? "4 ROUNDS · \(pomodoroBreakMinutes)M BREAKS" : "READY TO FOCUS",
                diameter: haloDiameter,
                style: .ready
            )

            Text("Choose your time. Take back your attention.")
                .font(NoxaType.subheadline)
                .foregroundStyle(NoxaTheme.secondaryText)
                .multilineTextAlignment(.center)

            Picker("Mode", selection: $homeMode) {
                Text("Focus").tag(HomeFocusMode.focus)
                Text("Pomodoro").tag(HomeFocusMode.pomodoro)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)

            if homeMode == .focus {
                focusDurationChips
            } else {
                pomodoroChips
            }

            distractionsRow
        }
    }

    /// What the Halo shows: the typed custom value, even out of range, so
    /// the timer and the validation message never disagree.
    var haloDurationMinutes: Int {
        guard isCustomDuration, let typed = Int(customDurationText) else { return chosenDurationMinutes }
        return typed
    }

    var isCustomDurationValid: Bool {
        guard isCustomDuration else { return true }
        guard let typed = Int(customDurationText) else { return false }
        return (NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes...maximumFocusMinutes).contains(typed)
    }

    var haloDiameter: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 220 : 250
    }

    var focusDurationChips: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
                ForEach([25, 30, 45, 60], id: \.self) { minutes in
                    durationButton(title: "\(minutes)m", minutes: minutes)
                }
                Button {
                    customDurationText = String(selectedDurationMinutes)
                    isCustomDuration = true
                    isCustomDurationFieldFocused = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(NoxaDurationButtonStyle(isSelected: isCustomDuration))
                .frame(width: 58)
                .accessibilityLabel("Custom duration")
            }

            // The editor only exists while Custom is chosen.
            if isCustomDuration {
                HStack(spacing: 10) {
                    Button {
                        adjustCustomDuration(by: -5)
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .background(NoxaTheme.elevated, in: Circle())
                    .accessibilityLabel("Five minutes less")

                    TextField("Minutes", text: $customDurationText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.center)
                        .font(NoxaTheme.font(22, weight: .semibold, relativeTo: .title3))
                        .frame(maxWidth: .infinity, minHeight: 46)
                        .background(NoxaTheme.elevated, in: Capsule())
                        .focused($isCustomDurationFieldFocused)
                        .onChange(of: customDurationText) { value in
                            customDurationText = String(value.filter(\.isNumber).prefix(3))
                        }

                    Button {
                        adjustCustomDuration(by: 5)
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .background(NoxaTheme.elevated, in: Circle())
                    .accessibilityLabel("Five minutes more")
                }
                Text(isCustomDurationValid
                     ? "\(NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes)–\(maximumFocusMinutes) minutes"
                     : "Choose \(NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes)–\(maximumFocusMinutes) minutes to start")
                    .font(NoxaType.footnote)
                    .foregroundStyle(isCustomDurationValid ? NoxaTheme.secondaryText : NoxaTheme.warning)
                    .transition(.opacity)
            }
        }
    }

    var pomodoroChips: some View {
        VStack(spacing: 14) {
            HStack(spacing: 10) {
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
                Button {
                    isCustomPomodoro = true
                } label: {
                    Image(systemName: "ellipsis")
                }
                .buttonStyle(NoxaDurationButtonStyle(isSelected: isCustomPomodoro))
                .frame(width: 58)
                .accessibilityLabel("Custom Pomodoro")
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
                .background(NoxaTheme.surface, in: RoundedRectangle(cornerRadius: NoxaTheme.Radius.control, style: .continuous))
            }

            HStack(spacing: 4) {
                Text("4 rounds · breaks unblock")
                    .font(NoxaType.footnote)
                    .foregroundStyle(NoxaTheme.secondaryText)
                NoxaInfoButton(
                    title: "Pomodoro",
                    message: "Four work rounds run automatically with a break between each. Your blocklist is released during breaks, and Noxa reminds you before work resumes."
                )
            }
        }
    }

    var distractionsRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "shield.lefthalf.filled")
                .foregroundStyle(NoxaTheme.accent)
                .accessibilityHidden(true)
            Text(hasFocusRestrictions
                 ? "\(focusRestrictionCount) distraction\(focusRestrictionCount == 1 ? "" : "s") selected"
                 : "No distractions selected")
                .font(NoxaType.subheadline)
                .foregroundStyle(NoxaTheme.secondaryText)
            Button(hasFocusRestrictions ? "Edit" : "Choose") {
                presentRestrictionPicker()
            }
            .font(NoxaType.subheadlineSemibold)
            .foregroundStyle(NoxaTheme.accent)
            .frame(minHeight: 44)
            .disabled(!authorization.state.isApproved)
        }
    }

    func activeFocusView(_ activeSession: ActiveSessionRecord) -> some View {
        VStack(spacing: 22) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, activeSession.plannedEndAt.timeIntervalSince(context.date))
                let elapsed = 1 - remaining / max(Double(activeSession.plannedDurationSeconds), 1)
                // Until Screen Time confirms the block, the ring stays muted
                // and says so, rather than claiming protection.
                let isConfirmed = focusSession.monitorReceipt(for: activeSession) != nil
                NoxaFocusHalo(
                    progress: elapsed,
                    value: Self.durationString(seconds: Int(remaining)),
                    caption: isConfirmed
                        ? "ENDS \(activeSession.plannedEndAt.formatted(date: .omitted, time: .shortened))"
                        : "APPLYING BLOCK…",
                    diameter: haloDiameter,
                    isCountingDown: true,
                    style: isConfirmed ? .progress : .pending
                )
            }

            VStack(spacing: 8) {
                if let round = focusSession.pomodoroRoundDescription {
                    Text(round)
                        .font(NoxaType.subheadlineSemibold)
                }
                if focusSession.monitorReceipt(for: activeSession) != nil {
                    Label("Block active", systemImage: "checkmark.shield.fill")
                        .font(NoxaType.footnoteMedium)
                        .foregroundStyle(NoxaTheme.accent)
                } else {
                    Label("Applying block…", systemImage: "clock.arrow.circlepath")
                        .font(NoxaType.footnoteMedium)
                        .foregroundStyle(NoxaTheme.secondaryText)
                    TimelineView(.periodic(from: .now, by: 5)) { context in
                        if context.date.timeIntervalSince(activeSession.startedAt) > 30 {
                            Text("Apps still open? Check Screen Time access in Settings.")
                                .font(NoxaType.footnote)
                                .foregroundStyle(NoxaTheme.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
                if let intention = focusSession.activeIntention, !intention.isEmpty {
                    Label(intention, systemImage: "scope")
                        .font(NoxaType.subheadlineMedium)
                }
            }

            distractionsRow

            if activeSession.isStrict {
                Label("Can't end early", systemImage: "lock.fill")
                    .font(NoxaType.subheadlineSemibold)
                    .foregroundStyle(NoxaTheme.secondaryText)
            } else {
                Button("End Session Early") {
                    isEndRitualPresented = true
                }
                .buttonStyle(NoxaSecondaryButtonStyle())
            }
        }
    }

    func pomodoroBreakView(endsAt breakEndsAt: Date) -> some View {
        VStack(spacing: 22) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = max(0, breakEndsAt.timeIntervalSince(context.date))
                let total = Double((focusSession.pomodoroCycle?.plan.breakMinutes ?? pomodoroBreakMinutes) * 60)
                // Breaks unblock, so the ring is neutral rather than lime.
                NoxaFocusHalo(
                    progress: 1 - remaining / max(total, 1),
                    value: Self.durationString(seconds: Int(remaining)),
                    caption: "BREAK · APPS UNBLOCKED",
                    diameter: haloDiameter,
                    isCountingDown: true
                )
                .saturation(0)
            }
            if let round = focusSession.pomodoroRoundDescription {
                Text(round)
                    .font(NoxaType.subheadlineSemibold)
            }
            Text("Next round starts automatically.")
                .font(NoxaType.subheadline)
                .foregroundStyle(NoxaTheme.secondaryText)
            Button("Stop Pomodoro") {
                if let cycle = focusSession.pomodoroCycle {
                    notifications.cancelPomodoroCycle(cycle.id)
                }
                focusSession.stopPomodoroDuringBreak()
            }
            .buttonStyle(NoxaSecondaryButtonStyle())
        }
    }

    /// The soonest enabled schedule window, or the one blocking now.
    @ViewBuilder
    var nextScheduledBlockCard: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let windows = schedules.configurations
                .filter(\.isEnabled)
                .compactMap { rule in
                    ScheduleCommitmentPolicy.upcomingWindow(for: rule, after: context.date, calendar: .autoupdatingCurrent)
                        .map { (rule: rule, start: $0.start, end: $0.end) }
                }
                .sorted { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
            if let next = windows.first {
                Button {
                    selectedTab = .dailyLimits
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(next.start == nil ? "\(next.rule.name) is blocking now" : "Your next scheduled block")
                                .font(NoxaType.headline)
                                .foregroundStyle(NoxaTheme.primaryText)
                            Text(Self.scheduleWindowText(start: next.start, end: next.end, now: context.date))
                                .font(NoxaType.subheadline)
                                .foregroundStyle(NoxaTheme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(NoxaType.subheadlineSemibold)
                            .foregroundStyle(NoxaTheme.secondaryText)
                    }
                    .noxaCard()
                }
                .buttonStyle(.plain)
            }
        }
    }

    static func scheduleWindowText(start: Date?, end: Date, now: Date) -> String {
        let time: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
        guard let start else { return "Until \(time(end))" }
        let calendar = Calendar.autoupdatingCurrent
        let day = calendar.isDate(start, inSameDayAs: now)
            ? "Today"
            : (calendar.isDateInTomorrow(start) ? "Tomorrow" : start.formatted(.dateTime.weekday(.wide)))
        return "\(day) · \(time(start)) – \(time(end))"
    }

    var focusStartReviewSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoxaTheme.Spacing.section) {
                    NoxaScreenHeader(
                        title: "Ready to commit?",
                        subtitle: "Blocks these for \(Self.durationLabel(minutes: chosenDurationMinutes))."
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

                    // The duration card above shows the exact end time.
                    HStack(spacing: 4) {
                        Label("You can't end this early.", systemImage: "lock.fill")
                            .font(NoxaType.subheadlineSemibold)
                            .foregroundStyle(NoxaTheme.warning)
                        NoxaInfoButton(
                            title: "Committed Focus",
                            message: "Noxa has no way to end this session before its end time. iOS Screen Time permissions can still be changed in Settings."
                        )
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

    func activeRestrictionPlan(at date: Date) -> EffectiveRestrictions<RestrictionTarget> {
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
                ) ? instagramAppSelection.flatMap { $0.applicationTokens.isEmpty ? nil : $0 } : nil,
                youtubeAppBlock: YouTubeShortsProtectionService.shouldApplyAppBlock(
                    shortsHidden: localStore.youtubeShortsHidden,
                    isEnabled: localStore.youtubeAppBlockEnabled,
                    allowedUntil: localStore.safariFilterAllowedUntil,
                    appSelection: youtubeAppSelection,
                    now: date
                ) ? youtubeAppSelection.flatMap { $0.applicationTokens.isEmpty ? nil : $0 } : nil
            ),
            at: date,
            calendar: .autoupdatingCurrent
        )
    }

    var permissionCard: some View {
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

    var screenTimePauseNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Paused: Screen Time access is off", systemImage: "pause.circle.fill")
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

    var screenTimePauseDetail: String {
        let end = (focusSession.activeSession?.plannedEndAt ?? focusSession.pomodoroBreakEndsAt)
            .map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        return "Turn it back on to resume\(end). This session won't count as completed."
    }

    var chosenDurationMinutes: Int {
        guard isCustomDuration else { return min(selectedDurationMinutes, maximumFocusMinutes) }
        return normalizedCustomDuration
    }

    var pomodoroFirstRoundEndDescription: String {
        Date().addingTimeInterval(TimeInterval(pomodoroWorkMinutes * 60))
            .formatted(date: .omitted, time: .shortened)
    }

    var maximumFocusMinutes: Int {
        NoxaDeviceActivityConfiguration.maximumFocusSessionMinutes
    }

    var normalizedCustomDuration: Int {
        let value = Int(customDurationText) ?? NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes
        return min(
            max(value, NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes),
            maximumFocusMinutes
        )
    }

    /// Leaves the typed value alone: an out-of-range entry shows a message
    /// and disables Start instead of being clipped behind the user's back.
    func commitCustomDuration() {
        customDurationText = String(customDurationText.filter(\.isNumber).prefix(3))
    }

    func adjustCustomDuration(by amount: Int) {
        let current = Int(customDurationText) ?? selectedDurationMinutes
        let adjusted = min(
            max(current + amount, NoxaDeviceActivityConfiguration.minimumFocusSessionMinutes),
            maximumFocusMinutes
        )
        customDurationText = String(adjusted)
    }

    func durationButton(title: String, minutes: Int) -> some View {
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

    func beginFocusSession(intention: String) {
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

    func enableNotificationsForActiveSession() async {
        guard await notifications.requestAuthorization(),
              let session = focusSession.activeSession else { return }
        if let cycle = focusSession.pomodoroCycle {
            await notifications.schedulePomodoroCycle(cycle)
        } else {
            await notifications.schedule(for: session)
        }
    }
}
