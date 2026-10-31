import FamilyControls
import SafariServices
import SwiftUI
import UIKit

extension ContentView {
    var schedulePickerSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    TextField("Schedule name", text: $scheduleName)
                        .textFieldStyle(NoxaTextFieldStyle())
                        .textInputAutocapitalization(.words)
                        .padding(.horizontal, NoxaTheme.Spacing.screen)
                    if let lockedUntil = editedScheduleLockedUntil {
                        // Only safe edits are offered while the window is locked.
                        VStack(alignment: .leading, spacing: 12) {
                            Label(
                                "Locked until \(Self.lockEndLabel(lockedUntil))",
                                systemImage: "lock.fill"
                            )
                            .font(NoxaType.subheadlineSemibold)
                            .foregroundStyle(NoxaTheme.accent)
                            Text("You can still rename it or change reminders.")
                                .font(NoxaType.footnote)
                                .foregroundStyle(NoxaTheme.secondaryText)
                            scheduleReminderToggles
                        }
                        .padding(.horizontal, NoxaTheme.Spacing.screen)
                    } else {
                        scheduleTimingControls
                            .padding(.horizontal, NoxaTheme.Spacing.screen)
                        scheduleAppsButton
                            .padding(.horizontal, NoxaTheme.Spacing.screen)
                        TextField("Websites (optional), e.g. reddit.com", text: $scheduleCustomDomains)
                            .textFieldStyle(NoxaTextFieldStyle())
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(.horizontal, NoxaTheme.Spacing.screen)
                    }
                    if let errorMessage = schedules.errorMessage {
                        Text(errorMessage)
                            .font(NoxaType.footnote)
                            .foregroundStyle(.red)
                            .padding(.horizontal, NoxaTheme.Spacing.screen)
                    }
                    // Only offered while the schedule isn't locked.
                    if let scheduleToEdit, editedScheduleLockedUntil == nil {
                        Button("Remove Schedule", role: .destructive) {
                            schedules.remove(scheduleToEdit)
                            if schedules.errorMessage == nil { isSchedulePickerPresented = false }
                        }
                        .buttonStyle(NoxaSecondaryButtonStyle())
                        .padding(.horizontal, NoxaTheme.Spacing.screen)
                        .padding(.top, 8)
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .noxaScreenBackground()
            // Apple's picker gets the whole screen so the app list isn't cropped.
            .sheet(isPresented: $isScheduleAppPickerPresented) {
                NavigationStack {
                    FamilyActivityPicker(selection: $scheduleSelection)
                        .navigationTitle("Choose apps")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { isScheduleAppPickerPresented = false }
                            }
                        }
                }
                .preferredColorScheme(.dark)
            }
            .navigationTitle(scheduleToEdit == nil ? "New schedule" : "Edit schedule")
            .alert(
                scheduleToEdit == nil ? "Lock this schedule for a week?" : "Lock this block now?",
                isPresented: $isScheduleLockConfirmationPresented
            ) {
                Button("Cancel", role: .cancel) {}
                Button(scheduleToEdit == nil ? "Lock for a Week" : "Lock Now") { saveSchedule() }
            } message: {
                if scheduleToEdit == nil {
                    Text("Until \(Date().addingTimeInterval(WeeklyCommitment.lockDuration).formatted(date: .abbreviated, time: .omitted)) you can't turn it off, change or remove it. Then you get one day to change it before it locks for another week.")
                } else {
                    Text("It's blocking now, so it locks as soon as you save, until \(proposedScheduleWindowEnd ?? "this window ends").")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isSchedulePickerPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if needsScheduleLockConfirmation {
                            isScheduleLockConfirmationPresented = true
                        } else {
                            saveSchedule()
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

    var scheduleAppsButton: some View {
        let count = scheduleSelection.applicationTokens.count
            + scheduleSelection.categoryTokens.count
            + scheduleSelection.webDomainTokens.count
        return Button {
            isScheduleAppPickerPresented = true
        } label: {
            HStack {
                Label(count == 0 ? "Choose apps" : "\(count) selected", systemImage: "square.grid.2x2")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(NoxaType.captionBold)
                    .foregroundStyle(NoxaTheme.secondaryText)
            }
        }
        .buttonStyle(NoxaSecondaryButtonStyle())
        .accessibilityHint("Opens Apple's app picker")
    }

    var scheduleTimingControls: some View {
        VStack(spacing: 12) {
            // New schedules always block during their hours. Older
            // allowed-hours schedules keep working exactly as saved.
            if scheduleMode == .allowedHours {
                Label("Older allowed-hours schedule: apps are blocked outside these hours. New schedules use blocked hours.", systemImage: "info.circle")
                    .font(NoxaType.footnote)
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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

            if ScheduleCommitmentPolicy.canLock(scheduleMode) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("These apps will be blocked from \(scheduleAllowedStart.formatted(date: .omitted, time: .shortened)) until \(scheduleAllowedEnd.formatted(date: .omitted, time: .shortened)).")
                        .font(NoxaType.subheadlineSemibold)
                        .foregroundStyle(NoxaTheme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                    NoxaInfoButton(
                        title: "Locked while active",
                        message: "Once a block starts, you can't turn it off, remove it, or weaken it in Noxa until it ends. You can still rename it and change reminders."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            scheduleReminderToggles
        }
    }

    var scheduleReminderToggles: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: $scheduleNotifyAtStart) {
                HStack(spacing: 4) {
                    Text("Remind me at start")
                    NoxaInfoButton(
                        title: "Reminders",
                        message: "Reminders need notification permission and can arrive late if iOS delays a schedule. Blocking doesn't depend on them."
                    )
                }
            }
            .tint(NoxaTheme.accent)
            Toggle("Remind me at end", isOn: $scheduleNotifyAtEnd)
                .tint(NoxaTheme.accent)
        }
    }

    /// The saved rule's lock, so pending edits can't change their own release.
    var editedScheduleLockedUntil: Date? {
        scheduleToEdit.flatMap { schedules.commitmentLockedUntil($0) }
    }

    /// The rule as it would be saved from the editor's current fields.
    var proposedScheduleRule: ScheduleRule {
        var rule = scheduleToEdit ?? ScheduleRule(
            name: scheduleName,
            mode: scheduleMode,
            selection: scheduleSelection,
            startMinutes: 0,
            endMinutes: 0
        )
        rule.name = scheduleName
        rule.mode = scheduleMode
        rule.selection = scheduleSelection
        rule.websiteDomains = Self.domains(from: scheduleCustomDomains)
        rule.weekdays = scheduleWeekdays
        rule.startMinutes = Self.minutesSinceMidnight(scheduleAllowedStart)
        rule.endMinutes = Self.minutesSinceMidnight(scheduleAllowedEnd)
        rule.notifyAtStart = scheduleNotifyAtStart
        rule.notifyAtEnd = scheduleNotifyAtEnd
        rule.lockWhileActive = ScheduleCommitmentPolicy.canLock(scheduleMode)
        rule.isEnabled = scheduleToEdit?.isEnabled ?? true
        rule.pendingLegacyRelaxation = nil
        return rule
    }

    var proposedScheduleWindowEnd: String? {
        ScheduleCommitmentPolicy.lockedUntil(proposedScheduleRule, at: Date(), calendar: .current)?
            .formatted(date: .omitted, time: .shortened)
    }

    /// A new schedule locks for a week; an edit during an active window
    /// locks that window immediately.
    var needsScheduleLockConfirmation: Bool {
        scheduleToEdit == nil
            || (editedScheduleLockedUntil == nil && proposedScheduleWindowEnd != nil)
    }

    /// "11:00 PM" for later today, otherwise the date only.
    static func lockEndLabel(_ end: Date) -> String {
        Calendar.autoupdatingCurrent.isDateInToday(end)
            ? end.formatted(date: .omitted, time: .shortened)
            : end.formatted(date: .abbreviated, time: .omitted)
    }

    func saveSchedule() {
        if scheduleToEdit != nil {
            schedules.update(proposedScheduleRule)
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
                notifyAtEnd: scheduleNotifyAtEnd,
                lockWhileActive: ScheduleCommitmentPolicy.canLock(scheduleMode)
            )
        }
        if schedules.errorMessage == nil {
            isSchedulePickerPresented = false
            showToast("Schedule saved")
        }
    }

    var schedulesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            limitsSectionHeader(
                "Schedules",
                info: "Choose the hours to block, the days they apply, and the apps, categories or websites. Each schedule locks for a week: you can't turn it off, change or remove it. After the week you get one day to change it, then it locks again. It also can't be weakened while it's blocking.",
                add: openNewScheduleEditor,
                canAdd: authorization.state.isApproved
                    && schedules.visibleConfigurations.count < RestrictionScheduleService.maximumConfigurations
            )

            if schedules.visibleConfigurations.isEmpty {
                Text("No schedules yet.")
                    .font(NoxaType.subheadline)
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .noxaCard(padding: 20)
            } else {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    VStack(spacing: 0) {
                        ForEach(Array(schedules.visibleConfigurations.enumerated()), id: \.element.id) { index, configuration in
                            if index > 0 { Divider().overlay(NoxaTheme.border) }
                            scheduleRow(configuration, now: context.date)
                        }
                    }
                    .noxaCard(padding: 20)
                }
            }

            if let errorMessage = schedules.errorMessage {
                Text(errorMessage)
                    .font(NoxaType.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    func scheduleRow(_ configuration: ScheduleRule, now: Date) -> some View {
        let lockedUntil = schedules.lockedUntil(configuration)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                Button {
                    openScheduleEditor(configuration)
                } label: {
                    HStack(spacing: 16) {
                        let isBlocking = configuration.isEnabled
                            && ScheduleRuleEvaluator.isBlocking(configuration, at: now, calendar: .autoupdatingCurrent)
                        // Only a schedule that is blocking right now gets light.
                        Image(systemName: Self.scheduleIcon(configuration))
                            .font(.system(size: 20))
                            .foregroundStyle(configuration.isEnabled ? NoxaTheme.accent : NoxaTheme.tertiaryText)
                            .frame(width: 40, height: 40)
                            .background {
                                if isBlocking {
                                    Circle().fill(RadialGradient(
                                        colors: [NoxaTheme.olive.opacity(0.9), .clear],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: 26
                                    ))
                                }
                            }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(configuration.name)
                                .font(NoxaType.body)
                                .foregroundStyle(NoxaTheme.primaryText)
                                .lineLimit(1)
                            Text("\(Self.timeLabel(minutes: configuration.startMinutes)) – \(Self.timeLabel(minutes: configuration.endMinutes)) · \(Self.shortWeekdaySummary(configuration.weekdays))")
                                .font(NoxaType.subheadline)
                                .foregroundStyle(NoxaTheme.secondaryText)
                            scheduleStateLabel(configuration, lockedUntil: lockedUntil, now: now)
                            weeklyLockLabel(schedules.weeklyState(configuration, at: now))
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                noxaStatePill(
                    isOn: configuration.isEnabled,
                    isDisabled: configuration.isEnabled && schedules.commitmentLockedUntil(configuration, at: now) != nil,
                    label: configuration.name
                ) {
                    schedules.setEnabled(!configuration.isEnabled, for: configuration)
                }
            }

            scheduleTargetsDisclosure(for: configuration)
                .padding(.leading, 56)

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
                            .font(NoxaType.caption)
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
                .background(NoxaTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(.vertical, 12)
    }

    /// The row's state, from the shared rule vocabulary.
    func scheduleStateLabel(_ configuration: ScheduleRule, lockedUntil: Date?, now: Date) -> some View {
        let status = RuleStatus.schedule(
            configuration,
            isAuthorized: authorization.state.isApproved,
            lockedUntil: lockedUntil,
            at: now,
            calendar: .autoupdatingCurrent
        )
        return ruleStatusLabel(status, now: now)
    }

    /// Text plus icon for every state, so status never relies on color alone.
    func ruleStatusLabel(_ status: RuleStatus, now: Date) -> some View {
        let time: (Date) -> String = { date in
            let day = Calendar.autoupdatingCurrent.isDate(date, inSameDayAs: now)
                ? "" : date.formatted(.dateTime.weekday(.abbreviated)) + " "
            return day + date.formatted(date: .omitted, time: .shortened)
        }
        let (text, icon, color): (String, String, Color) = switch status {
        case .needsPermission: ("Needs permission", "exclamationmark.triangle.fill", NoxaTheme.warning)
        case .off: ("Off", "circle.slash", NoxaTheme.tertiaryText)
        case .paused: ("Paused · daily limits are stopped", "pause.circle.fill", NoxaTheme.warning)
        case .scheduled(let next): ("Scheduled · next at \(time(next))", "clock", NoxaTheme.secondaryText)
        case .blockingNow: ("Blocking now", "shield.fill", NoxaTheme.accent)
        case .lockedUntil(let end): ("Blocking now · until \(time(end))", "shield.fill", NoxaTheme.accent)
        case .counting: ("Counting today's use", "hourglass", NoxaTheme.secondaryText)
        }
        return Label(text, systemImage: icon)
            .font(NoxaType.captionSemibold)
            .foregroundStyle(color)
    }

    static func scheduleIcon(_ configuration: ScheduleRule) -> String {
        if configuration.mode == .allowedHours { return "sun.max" }
        let start = configuration.startMinutes
        return (start >= 19 * 60 || start < 5 * 60) ? "moon" : "calendar"
    }

    nonisolated static func shortWeekdaySummary(_ weekdays: Set<Int>) -> String {
        if weekdays == Set(1...7) { return "Daily" }
        if weekdays == Set(2...6) { return "Weekdays" }
        if weekdays == [1, 7] { return "Weekends" }
        return weekdays.sorted().map(weekdayName).joined(separator: ", ")
    }

    func openNewScheduleEditor() {
        schedules.clearError()
        scheduleToEdit = nil
        scheduleName = ""
        scheduleCustomDomains = ""
        scheduleSelection = FamilyActivitySelection()
        scheduleMode = .blockedHours
        scheduleWeekdays = Set(1...7)
        scheduleNotifyAtStart = false
        scheduleNotifyAtEnd = false
        scheduleAllowedStart = Self.dateForScheduleMinute(21 * 60)
        scheduleAllowedEnd = Self.dateForScheduleMinute(22 * 60)
        isSchedulePickerPresented = true
    }

    func openScheduleEditor(_ configuration: ScheduleRule) {
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

    /// Keeps each schedule row short: the apps and sites sit behind a chevron.
    @ViewBuilder
    func scheduleTargetsDisclosure(for configuration: ScheduleRule) -> some View {
        let isExpanded = expandedScheduleIDs.contains(configuration.id)
        let count = configuration.selection.applicationTokens.count
            + configuration.selection.categoryTokens.count
            + configuration.selection.webDomainTokens.count
            + configuration.websiteDomains.count
        Button {
            withAnimation(NoxaMotion.spring) {
                NoxaHaptics.selection()
                if isExpanded {
                    expandedScheduleIDs.remove(configuration.id)
                } else {
                    expandedScheduleIDs.insert(configuration.id)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text("\(count) \(count == 1 ? "app or site" : "apps and sites")")
                    .font(NoxaType.footnoteMedium)
                Image(systemName: "chevron.down")
                    .font(NoxaType.captionBold)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                Spacer()
            }
            .foregroundStyle(NoxaTheme.secondaryText)
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")

        if isExpanded {
            tokenRows(for: configuration.selection)
            ForEach(configuration.websiteDomains, id: \.self) { domain in
                Label(domain, systemImage: "globe")
                    .font(NoxaType.subheadline)
            }
        }
    }

    @ViewBuilder
    func tokenRows(
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
}
