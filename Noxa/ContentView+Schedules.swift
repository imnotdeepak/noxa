import FamilyControls
import SafariServices
import SwiftUI
import UIKit

extension ContentView {
    var schedulePickerSheet: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TextField("Schedule name", text: $scheduleName)
                    .textFieldStyle(NoxaTextFieldStyle())
                    .textInputAutocapitalization(.words)
                    .padding(.horizontal, NoxaTheme.Spacing.screen)
                if let lockedUntil = editedScheduleLockedUntil {
                    // Only safe edits are offered while the window is locked.
                    VStack(alignment: .leading, spacing: 12) {
                        Label(
                            "Locked until \(lockedUntil.formatted(date: .omitted, time: .shortened))",
                            systemImage: "lock.fill"
                        )
                        .font(NoxaType.subheadlineSemibold)
                        .foregroundStyle(NoxaTheme.accent)
                        Text("This block can't be turned off, removed, or changed until its window ends. You can still rename it or change reminders.")
                            .font(NoxaType.caption)
                            .foregroundStyle(NoxaTheme.secondaryText)
                        scheduleReminderToggles
                    }
                    .padding(.horizontal, NoxaTheme.Spacing.screen)
                    Spacer()
                } else {
                    scheduleTimingControls
                        .padding(.horizontal, NoxaTheme.Spacing.screen)
                    TextField("Websites, separated by commas (optional)", text: $scheduleCustomDomains)
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
                if editedScheduleLockedUntil == nil {
                    FamilyActivityPicker(selection: $scheduleSelection)
                }
            }
            .navigationTitle(scheduleToEdit == nil ? "New schedule" : "Edit schedule")
            .alert("Lock this block now?", isPresented: $isScheduleLockConfirmationPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Lock Now") { saveSchedule() }
            } message: {
                Text("This schedule is blocking right now. Once you save, you can't turn it off, remove, or change it in Noxa until \(proposedScheduleWindowEnd ?? "this window ends").")
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

    var scheduleTimingControls: some View {
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

            if ScheduleCommitmentPolicy.canLock(scheduleMode) {
                VStack(alignment: .leading, spacing: 5) {
                    Toggle("Lock while active", isOn: $scheduleLockWhileActive)
                        .tint(NoxaTheme.accent)
                    Text("Once this scheduled block starts, you can't disable, delete, or weaken it in Noxa until its blocking window ends.")
                        .font(NoxaType.caption)
                        .foregroundStyle(NoxaTheme.secondaryText)
                    if scheduleLockWhileActive, let window = proposedScheduleWindowDescription {
                        Text(window)
                            .font(NoxaType.captionSemibold)
                            .foregroundStyle(NoxaTheme.accent)
                    }
                }
            }

            scheduleReminderToggles
        }
    }

    var scheduleReminderToggles: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Remind me when this schedule starts", isOn: $scheduleNotifyAtStart)
                .tint(NoxaTheme.accent)
            Toggle("Remind me when this schedule ends", isOn: $scheduleNotifyAtEnd)
                .tint(NoxaTheme.accent)
            Text("Reminders need notification permission and may arrive late if iOS delays a schedule callback. Blocking does not depend on reminders.")
                .font(NoxaType.caption)
                .foregroundStyle(NoxaTheme.secondaryText)
        }
    }

    /// The saved rule's lock, so pending edits can't change their own release.
    var editedScheduleLockedUntil: Date? {
        scheduleToEdit.flatMap { schedules.lockedUntil($0) }
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
        rule.lockWhileActive = scheduleLockWhileActive && ScheduleCommitmentPolicy.canLock(scheduleMode)
        rule.isEnabled = scheduleToEdit?.isEnabled ?? true
        rule.pendingLegacyRelaxation = nil
        return rule
    }

    var proposedScheduleWindowDescription: String? {
        guard !scheduleWeekdays.isEmpty,
              let window = ScheduleCommitmentPolicy.upcomingWindow(
                  for: proposedScheduleRule, after: Date(), calendar: .current
              ) else { return nil }
        let end = window.end.formatted(date: .abbreviated, time: .shortened)
        guard let start = window.start else { return "Blocking now. Locked until \(end) once saved." }
        return "Next locked window: \(start.formatted(date: .abbreviated, time: .shortened)) – \(end)"
    }

    var proposedScheduleWindowEnd: String? {
        ScheduleCommitmentPolicy.lockedUntil(proposedScheduleRule, at: Date(), calendar: .current)?
            .formatted(date: .omitted, time: .shortened)
    }

    /// Turning the lock on during an active window starts it immediately.
    var needsScheduleLockConfirmation: Bool {
        editedScheduleLockedUntil == nil && proposedScheduleWindowEnd != nil
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
                lockWhileActive: scheduleLockWhileActive && ScheduleCommitmentPolicy.canLock(scheduleMode)
            )
        }
        if schedules.errorMessage == nil {
            isSchedulePickerPresented = false
        }
    }

    var scheduleCard: some View {
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
                scheduleLockWhileActive = false
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
                            .disabled(schedules.lockedUntil(configuration) != nil)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(configuration.name)
                                    .font(NoxaType.subheadlineSemibold)
                                Text("\(configuration.mode == .allowedHours ? "Available" : "Blocked") \(Self.timeLabel(minutes: configuration.startMinutes))–\(Self.timeLabel(minutes: configuration.endMinutes))")
                                    .font(NoxaType.caption)
                                Text(Self.weekdaySummary(configuration.weekdays))
                                    .font(NoxaType.caption)
                                    .foregroundStyle(NoxaTheme.secondaryText)
                                if let lockedUntil = schedules.lockedUntil(configuration) {
                                    Label(
                                        "Locked until \(lockedUntil.formatted(date: .omitted, time: .shortened))",
                                        systemImage: "lock.fill"
                                    )
                                    .font(NoxaType.captionSemibold)
                                    .foregroundStyle(NoxaTheme.accent)
                                } else if configuration.lockWhileActive {
                                    Label("Locks while active", systemImage: "lock")
                                        .font(NoxaType.caption)
                                        .foregroundStyle(NoxaTheme.secondaryText)
                                }
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
                                scheduleLockWhileActive = configuration.lockWhileActive
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
                            .disabled(schedules.lockedUntil(configuration) != nil)
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
