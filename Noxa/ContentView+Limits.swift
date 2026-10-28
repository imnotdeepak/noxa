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
                            dailyLimits.add(
                                selection: newDailyLimitSelection,
                                minutes: selectedDailyLimitMinutes
                            )
                            if dailyLimits.errorMessage == nil {
                                dailyLimitSelection = FamilyActivitySelection()
                                isChoosingDailyLimitDuration = false
                                isDailyLimitPickerPresented = false
                            }
                        }
                    } else {
                        Button("Next") {
                            isChoosingDailyLimitDuration = true
                        }
                        .disabled(newDailyLimitSelection.applicationTokens.isEmpty)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    var dailyLimitDurationStep: some View {
        VStack(alignment: .leading, spacing: NoxaTheme.Spacing.section) {
            NoxaScreenHeader(
                title: "Choose a daily allowance",
                subtitle: "The selected app will be blocked after this much total use today."
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

    var dailyLimitsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NoxaTheme.Spacing.section) {
                Text("Set a daily allowance for distracting apps. Noxa applies each limit locally using Screen Time.")
                    .font(NoxaType.body)
                    .foregroundStyle(NoxaTheme.secondaryText)

                dailyLimitsCard
                scheduleCard
            }
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
    }

    var dailyLimitsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                NoxaCardHeader(title: "Daily limits", systemImage: "hourglass.bottomhalf.fill")
                Spacer()
                Text("\(dailyLimits.configurations.count)/\(DailyLimitService.maximumConfigurations)")
                    .font(NoxaType.caption.monospacedDigit())
                    .foregroundStyle(NoxaTheme.secondaryText)
            }

            Text("Give selected apps a daily allowance. Usage from earlier today counts. You can edit or stop limits at any time; other active blocks still apply.")
                .font(NoxaType.subheadline)
                .foregroundStyle(NoxaTheme.secondaryText)

            Text(notifications.canSchedule
                 ? "Noxa requests an alert about five minutes before a limit is reached. iOS may deliver it late."
                 : "Enable notifications for approaching-limit alerts. Daily limits still work without alerts.")
                .font(NoxaType.footnote)
                .foregroundStyle(NoxaTheme.secondaryText)

            Button("Add App Limit") {
                dailyLimitSelection = existingDailyLimitSelection
                selectedDailyLimitMinutes = 30
                isChoosingDailyLimitDuration = false
                isDailyLimitPickerPresented = true
            }
            .buttonStyle(NoxaSecondaryButtonStyle())
            .disabled(
                !authorization.state.isApproved
                    || dailyLimits.configurations.count >= DailyLimitService.maximumConfigurations
            )

            if dailyLimits.configurations.isEmpty {
                Text("No daily limits configured.")
                    .font(NoxaType.subheadline)
                    .foregroundStyle(NoxaTheme.secondaryText)
            } else {
                ForEach(dailyLimits.configurations) { configuration in
                    HStack(spacing: 12) {
                        Button {
                            dailyLimits.setEnabled(!configuration.isEnabled, for: configuration)
                        } label: {
                            Image(systemName: configuration.isEnabled ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(configuration.isEnabled ? .white : .secondary)
                                .font(.system(size: 22))
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(configuration.isEnabled ? "Turn off daily limit" : "Turn on daily limit")

                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array(configuration.selection.applicationTokens), id: \.self) { token in
                                Label(token)
                                    .labelStyle(.titleAndIcon)
                                    .font(NoxaType.subheadlineSemibold)
                            }
                            if configuration.selection.applicationTokens.isEmpty {
                                Text("App selection")
                                    .font(NoxaType.subheadlineSemibold)
                            }
                            Menu {
                                ForEach([10, 15, 30, 45, 60, 90, 120, 180, 240], id: \.self) { minutes in
                                    Button(Self.durationLabel(minutes: minutes)) {
                                        dailyLimits.updateMinutes(minutes, for: configuration)
                                    }
                                }
                            } label: {
                                Text("\(configuration.dailyLimitMinutes) min/day")
                                    .font(NoxaType.captionSemibold)
                                    .foregroundStyle(NoxaTheme.accent)
                                    .frame(minWidth: 96, minHeight: 44, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                        }
                        Spacer()
                        Button {
                            dailyLimits.remove(configuration)
                        } label: {
                            Text("Remove")
                                .font(NoxaType.captionSemibold)
                                .foregroundStyle(NoxaTheme.secondaryText)
                                .frame(minWidth: 70, minHeight: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack {
                Text(hasActiveDailyLimits ? "Daily limits active" : "Daily limits are off")
                    .font(NoxaType.subheadline)
                    .foregroundStyle(NoxaTheme.secondaryText)
                Spacer()
                Button {
                    if hasActiveDailyLimits {
                        dailyLimits.stopMonitoring()
                    } else {
                        dailyLimits.startMonitoring()
                    }
                } label: {
                    Text(hasActiveDailyLimits ? "Stop" : "Start Limits")
                        .font(NoxaType.subheadlineSemibold)
                        .foregroundStyle(NoxaTheme.accent)
                        .frame(minWidth: 100, minHeight: 44, alignment: .trailing)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(
                    dailyLimits.configurations.filter(\.isEnabled).isEmpty
                        || (!hasActiveDailyLimits && !authorization.state.isApproved)
                )
            }

            if let errorMessage = dailyLimits.errorMessage {
                Text(errorMessage)
                    .font(NoxaType.footnote)
                    .foregroundStyle(.red)
            }
        }
        .noxaCard()
    }
}
