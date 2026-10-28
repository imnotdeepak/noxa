import FamilyControls
import SafariServices
import SwiftUI
import UIKit

extension ContentView {
    var homeContent: some View {
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

    var focusStartReviewSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: NoxaTheme.Spacing.section) {
                    NoxaScreenHeader(
                        title: "Ready to commit?",
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

                    // The duration card above shows the exact end time.
                    Label(
                        "You can't end this Focus session early in Noxa. iOS Screen Time permissions can still be changed in Settings.",
                        systemImage: "lock.fill"
                    )
                    .font(NoxaType.subheadlineSemibold)
                    .foregroundStyle(NoxaTheme.warning)
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

    var hero: some View {
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

    var homeScheduleCard: some View {
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

    var homeActiveRulesCard: some View {
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
                ) ? instagramAppSelection : nil
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

    var focusSessionCard: some View {
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
                    Label("Can't end early · Ends at \(activeSession.plannedEndAt.formatted(date: .omitted, time: .shortened))", systemImage: "lock.fill")
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

    var screenTimePauseNotice: some View {
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

    var screenTimePauseDetail: String {
        let end = (focusSession.activeSession?.plannedEndAt ?? focusSession.pomodoroBreakEndsAt)
            .map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        return "Turn it back on in Settings → Screen Time → Apps with Screen Time Access to resume\(end). This session won't count as completed."
    }

    var quickSetupCard: some View {
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

    func commitCustomDuration() {
        customDurationText = String(normalizedCustomDuration)
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
