import FamilyControls
import SafariServices
import SwiftUI
import UIKit

extension ContentView {
    var statsContent: some View {
        let statistics = FocusStatistics(
            history: focusSession.history,
            now: statsReferenceDate,
            calendar: .autoupdatingCurrent
        )
        let period = FocusStatistics.period(
            history: focusSession.history,
            days: selectedStatsRange.rawValue,
            now: statsReferenceDate,
            calendar: .autoupdatingCurrent
        )
        let scheduleCommitment = ScheduleCommitmentEvaluator.lastSevenDays(
            events: schedules.commitmentEvents,
            now: statsReferenceDate,
            calendar: .autoupdatingCurrent
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: NoxaTheme.Spacing.section) {
                VStack(spacing: 8) {
                    Text("FOCUS TIME")
                        .font(NoxaTheme.font(12, weight: .bold, relativeTo: .caption))
                        .tracking(1.6)
                        .foregroundStyle(NoxaTheme.accent)
                    Text(Self.focusTimeLabel(minutes: statistics.totalFocusMinutes))
                        .font(NoxaTheme.font(48, weight: .bold, relativeTo: .largeTitle))
                        .monospacedDigit()
                        .multilineTextAlignment(.center)
                    Text("in Focus sessions since you started using Noxa")
                        .foregroundStyle(NoxaTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .noxaStatsCard()

                LazyVGrid(columns: durationGridColumns(regularCount: 4, spacing: 8), spacing: 8) {
                    ForEach(StatsRange.allCases, id: \.self) { range in
                        Button(range.title) {
                            selectedStatsRange = range
                        }
                        .buttonStyle(NoxaDurationButtonStyle(isSelected: selectedStatsRange == range))
                    }
                }

                HStack(spacing: 12) {
                    statCard(title: "Focus time", value: Self.compactFocusTime(minutes: period.focusMinutes))
                    statCard(title: "Completed", value: "\(period.completedSessions)")
                }

                HStack(spacing: 12) {
                    statCard(title: "Completion", value: "\(period.completionRate)%")
                    statCard(title: "Days focused", value: "\(period.focusedDays)")
                }

                // Noxa records how long Focus blocked distractions; it doesn't
                // measure app use, so never present this as time saved.
                Text("Focus time is how long your Focus sessions kept distractions blocked. It isn't a measure of screen time saved.")
                    .font(NoxaType.caption)
                    .foregroundStyle(NoxaTheme.secondaryText)

                VStack(alignment: .leading, spacing: 10) {
                    NoxaCardHeader(title: "Follow-through", systemImage: "chart.line.uptrend.xyaxis")
                    Text("\(period.completionRate)% completion rate")
                        .font(NoxaType.title2)
                    Text("\(period.completedSessions) completed · \(period.abandonedSessions) not completed")
                        .font(NoxaType.subheadline)
                        .foregroundStyle(NoxaTheme.secondaryText)
                    Text("\(statistics.currentStreak)-day current streak · \(statistics.longestStreak)-day best")
                        .font(NoxaType.caption)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                .noxaStatsCard()

                VStack(alignment: .leading, spacing: 10) {
                    NoxaCardHeader(title: "Schedules on track · last 7 days", systemImage: "calendar.badge.checkmark")
                    if scheduleCommitment.totalWindows == 0 {
                        Text("No schedule windows have finished yet. Tracking starts with the next full window.")
                            .font(NoxaType.subheadline)
                            .foregroundStyle(NoxaTheme.secondaryText)
                    } else {
                        Text("\(scheduleCommitment.keptWindows) of \(scheduleCommitment.totalWindows) windows kept")
                            .font(NoxaType.title2)
                        Text("\(scheduleCommitment.percentage)% kept · \(scheduleCommitment.interruptedWindows) changed or stopped early")
                            .font(NoxaType.subheadline)
                            .foregroundStyle(NoxaTheme.secondaryText)
                    }
                    Text("Based on whether schedules stayed enabled through their planned windows, not measured app use or proof of blocking.")
                        .font(NoxaType.caption)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                .noxaStatsCard()

                recentSessionsCard
            }
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
    }

    var recentSessionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            NoxaCardHeader(title: "Recent sessions", systemImage: "clock.arrow.circlepath")

            if focusSession.history.isEmpty {
                Text("Complete a focus session and it will appear here.")
                    .foregroundStyle(NoxaTheme.secondaryText)
            } else {
                ForEach(focusSession.history.prefix(8)) { session in
                    HStack(spacing: 12) {
                        Image(systemName: session.outcome == .completed ? "checkmark.circle.fill" : "arrow.uturn.backward.circle")
                            .foregroundStyle(session.outcome == .completed ? .green : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(session.outcome.displayName)
                                .font(NoxaType.subheadlineSemibold)
                            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(NoxaType.caption)
                                .foregroundStyle(NoxaTheme.secondaryText)
                        }
                        Spacer()
                        Text(Self.durationLabel(
                            minutes: (session.actualDurationSeconds ?? session.plannedDurationSeconds) / 60
                        ))
                            .font(NoxaType.subheadline.monospacedDigit())
                            .foregroundStyle(NoxaTheme.secondaryText)
                    }
                    if session.id != focusSession.history.prefix(8).last?.id {
                        Divider()
                            .overlay(Color.white.opacity(0.12))
                    }
                }
            }

            Text(cloudSync.historyStatusDescription)
                .font(NoxaType.footnote)
                .foregroundStyle(NoxaTheme.secondaryText)
        }
        .noxaStatsCard()
    }

    func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(NoxaTheme.font(30, weight: .semibold, relativeTo: .title))
            Text(title)
                .font(NoxaType.subheadline)
                .foregroundStyle(NoxaTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .noxaStatsCard()
    }

    static func compactFocusTime(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
    }

    static func focusTimeLabel(minutes: Int) -> String {
        guard minutes >= 60 else { return "\(minutes) min" }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours) hr" : "\(hours) hr \(remainder) min"
    }
}
