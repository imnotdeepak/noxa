import DeviceActivity
import FamilyControls
import SafariServices
import SwiftUI
import UIKit

extension ContentView {
    var dailyLimitPickerSheet: some View {
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
                            isDailyLimitLockConfirmationPresented = true
                        }
                    } else {
                        Button("Next") {
                            isChoosingDailyLimitDuration = true
                        }
                        .disabled(newDailyLimitSelection.applicationTokens.isEmpty)
                    }
                }
            }
            .alert("Lock this limit for a week?", isPresented: $isDailyLimitLockConfirmationPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Lock for a Week") {
                    dailyLimits.add(
                        selection: newDailyLimitSelection,
                        minutes: selectedDailyLimitMinutes
                    )
                    if dailyLimits.errorMessage == nil {
                        dailyLimitSelection = FamilyActivitySelection()
                        isChoosingDailyLimitDuration = false
                        isDailyLimitPickerPresented = false
                        showToast("Limit added · locked for a week")
                    }
                }
            } message: {
                Text("Until \(Date().addingTimeInterval(DailyLimitCommitmentPolicy.lockDuration).formatted(date: .abbreviated, time: .omitted)) you can lower it but not raise, turn off or remove it. Then you get one day to change it before it locks for another week.")
            }
        }
        .preferredColorScheme(.dark)
    }

    var dailyLimitDurationStep: some View {
        VStack(alignment: .leading, spacing: NoxaTheme.Spacing.section) {
            NoxaScreenHeader(
                title: "Choose a daily allowance",
                subtitle: "Blocks the app after this much use each day. Locked for a week once added."
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

    func dailyLimitLockLabel(for configuration: DailyLimitConfiguration) -> some View {
        weeklyLockLabel(dailyLimits.lockState(configuration))
    }

    /// The weekly cycle shared by limits, schedules, and Reels & Shorts.
    @ViewBuilder
    func weeklyLockLabel(_ state: WeeklyCommitment.State) -> some View {
        switch state {
        case .locked(let end):
            Label("Locked until \(end.formatted(date: .abbreviated, time: .omitted))", systemImage: "lock.fill")
                .font(NoxaType.captionSemibold)
                .foregroundStyle(NoxaTheme.secondaryText)
        case .changeWindow(let end):
            Label("Open to change until \(end.formatted(date: .abbreviated, time: .omitted))", systemImage: "lock.open.fill")
                .font(NoxaType.captionSemibold)
                .foregroundStyle(NoxaTheme.warning)
        case .unlocked:
            EmptyView()
        }
    }

    var dailyLimitsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                dailyLimitsSection
                schedulesSection
                reelsShortsSection
            }
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
    }

    func limitsSectionHeader(_ title: String, info: String, add: @escaping () -> Void, canAdd: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(NoxaType.title2)
                .foregroundStyle(NoxaTheme.primaryText)
                .accessibilityAddTraits(.isHeader)
            NoxaInfoButton(title: title, message: info)
            Spacer()
            Button("Add", action: add)
                .font(NoxaType.subheadlineSemibold)
                .foregroundStyle(NoxaTheme.accent)
                .frame(minHeight: 44)
                .disabled(!canAdd)
                .accessibilityLabel("Add \(title.lowercased())")
        }
    }

    /// The On/Off capsule at the end of each row.
    func noxaStatePill(isOn: Bool, isDisabled: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // "On" means the rule is on, not that it is blocking right now,
            // so it stays quiet: lime text on charcoal, never a neon fill.
            Text(isOn ? "On" : "Off")
                .font(NoxaType.footnoteSemibold)
                .foregroundStyle(isOn ? NoxaTheme.accent : NoxaTheme.tertiaryText)
                .frame(width: 56, height: 32)
                .background(NoxaTheme.elevated, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(isOn ? NoxaTheme.accent.opacity(0.35) : .clear, lineWidth: 1)
                }
                .opacity(isDisabled ? 0.55 : 1)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
    }

    var dailyLimitsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            limitsSectionHeader(
                "Daily app limits",
                info: "Give apps a daily allowance. Earlier use today counts. Each limit locks for a week: you can lower it, but not raise, turn off or remove it. After the week you get one day to change it, then it locks again. "
                    + (notifications.canSchedule
                       ? "Noxa alerts you about five minutes before a limit, though iOS may deliver it late."
                       : "Turn on notifications to get an alert before a limit is reached."),
                add: {
                    dailyLimitSelection = existingDailyLimitSelection
                    selectedDailyLimitMinutes = 30
                    isChoosingDailyLimitDuration = false
                    isDailyLimitPickerPresented = true
                },
                canAdd: authorization.state.isApproved
                    && dailyLimits.visibleConfigurations.count < DailyLimitService.maximumConfigurations
            )

            if dailyLimits.visibleConfigurations.isEmpty {
                Text("No limits yet.")
                    .font(NoxaType.subheadline)
                    .foregroundStyle(NoxaTheme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .noxaCard(padding: 20)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dailyLimits.visibleConfigurations.enumerated()), id: \.element.id) { index, configuration in
                        if index > 0 { Divider().overlay(NoxaTheme.border) }
                        dailyLimitRow(configuration)
                    }
                }
                .noxaCard(padding: 20)
            }

            if !dailyLimits.visibleConfigurations.isEmpty, !hasActiveDailyLimits,
               dailyLimits.visibleConfigurations.contains(where: \.isEnabled) {
                HStack {
                    Text("Limits are paused")
                        .font(NoxaType.subheadline)
                        .foregroundStyle(NoxaTheme.secondaryText)
                    Spacer()
                    Button("Start") { dailyLimits.startMonitoring() }
                        .font(NoxaType.subheadlineSemibold)
                        .foregroundStyle(NoxaTheme.accent)
                        .frame(minHeight: 44)
                        .disabled(!authorization.state.isApproved)
                }
            }

            if let errorMessage = dailyLimits.errorMessage {
                Text(errorMessage)
                    .font(NoxaType.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    func dailyLimitRow(_ configuration: DailyLimitConfiguration) -> some View {
        let lockedUntil = dailyLimits.lockedUntil(configuration)
        return HStack(spacing: 16) {
            Button {
                dailyLimits.clearError()
                dailyLimitToEdit = configuration
            } label: {
                HStack(spacing: 16) {
                    Group {
                        if let token = configuration.selection.applicationTokens.first {
                            Label(token).labelStyle(.iconOnly).scaleEffect(1.6)
                        } else {
                            Image(systemName: "hourglass")
                                .font(.system(size: 22))
                                .foregroundStyle(NoxaTheme.accent)
                        }
                    }
                    .frame(width: 52, height: 52)
                    .background(NoxaTheme.elevated, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                    VStack(alignment: .leading, spacing: 3) {
                        Group {
                            if let token = configuration.selection.applicationTokens.first {
                                Label(token).labelStyle(.titleOnly)
                            } else {
                                Text("App limit")
                            }
                        }
                        .font(NoxaType.body)
                        .foregroundStyle(NoxaTheme.primaryText)
                        .lineLimit(1)
                        Text("\(configuration.dailyLimitMinutes) minutes per day")
                            .font(NoxaType.subheadline)
                            .foregroundStyle(NoxaTheme.secondaryText)
                        ruleStatusLabel(
                            RuleStatus.dailyLimit(
                                isEnabled: configuration.isEnabled,
                                isAuthorized: authorization.state.isApproved,
                                isMonitoring: hasActiveDailyLimits,
                                hasReachedLimit: AppGroupStore.shared.reachedDailyLimitEventNames().contains(
                                    NoxaDeviceActivityConfiguration.dailyLimitEventName(for: configuration.id).rawValue
                                )
                            ),
                            now: Date()
                        )
                        dailyLimitLockLabel(for: configuration)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            noxaStatePill(
                isOn: configuration.isEnabled,
                isDisabled: configuration.isEnabled && lockedUntil != nil,
                label: "Daily limit"
            ) {
                dailyLimits.setEnabled(!configuration.isEnabled, for: configuration)
            }
        }
        .padding(.vertical, 12)
    }

    /// Opened from a limit row: the allowance, its lock and removal.
    func dailyLimitDetailSheet(_ configuration: DailyLimitConfiguration) -> some View {
        let saved = dailyLimits.visibleConfigurations.first { $0.id == configuration.id } ?? configuration
        let lockedUntil = dailyLimits.lockedUntil(saved)
        return NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(saved.selection.applicationTokens), id: \.self) { token in
                        Label(token).labelStyle(NoxaAppRowLabelStyle())
                    }
                    dailyLimitLockLabel(for: saved)

                    Text("Daily allowance")
                        .font(NoxaType.headline)
                    LazyVGrid(columns: durationGridColumns(regularCount: 3, spacing: 10), spacing: 10) {
                        ForEach([10, 15, 30, 45, 60, 90, 120, 180, 240], id: \.self) { minutes in
                            Button(Self.durationLabel(minutes: minutes)) {
                                dailyLimits.updateMinutes(minutes, for: saved)
                            }
                            .buttonStyle(NoxaDurationButtonStyle(isSelected: saved.dailyLimitMinutes == minutes))
                            .disabled(lockedUntil != nil && minutes > saved.dailyLimitMinutes)
                        }
                    }

                    if let errorMessage = dailyLimits.errorMessage {
                        Text(errorMessage)
                            .font(NoxaType.footnote)
                            .foregroundStyle(.red)
                    }

                    // Locked limits can't be removed or stopped, so the
                    // buttons only appear once the lock opens.
                    if lockedUntil == nil {
                        Button("Remove Limit", role: .destructive) {
                            dailyLimits.remove(saved)
                            if dailyLimits.errorMessage == nil { dailyLimitToEdit = nil }
                        }
                        .buttonStyle(NoxaSecondaryButtonStyle())
                    }

                    if hasActiveDailyLimits && !dailyLimits.hasLockedVisibleLimits {
                        Button("Stop All Limits") {
                            dailyLimits.requestStop()
                        }
                        .font(NoxaType.subheadlineSemibold)
                        .foregroundStyle(NoxaTheme.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                .padding(NoxaTheme.Spacing.screen)
            }
            .noxaScreenBackground()
            .navigationTitle("Daily limit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dailyLimitToEdit = nil }
                }
            }
        }
        .tint(NoxaTheme.accent)
        .preferredColorScheme(.dark)
    }
}
