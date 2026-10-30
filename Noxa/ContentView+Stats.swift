import FamilyControls
import SafariServices
import SwiftUI
import UIKit

extension ContentView {
    var statsCalendar: Calendar { FocusStatistics.insightsCalendar() }

    var statsInterval: DateInterval {
        FocusStatistics.interval(of: selectedStatsRange.unit, containing: statsAnchorDate, calendar: statsCalendar)
    }

    /// The period on screen is the current one; there is nothing after it.
    var isShowingCurrentStatsPeriod: Bool {
        statsInterval.contains(statsReferenceDate)
    }

    // Built from separately erased sections so the screen's view value
    // stays small enough for the runtime to copy safely.
    var statsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                AnyView(insightsHeader)
                AnyView(insightsHeroMetric)
                AnyView(insightsChart)
                AnyView(insightsPrimaryMetrics)
                AnyView(insightsConsistency)
                AnyView(activityHistoryLink)
            }
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
        .onChange(of: selectedStatsRange) { _ in
            selectedFocusBucket = nil
            statsAnchorDate = statsReferenceDate
        }
    }

    var insightsHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Insights")
                .font(NoxaTheme.font(34, weight: .bold, relativeTo: .largeTitle))
                .tracking(-1.2)
                .foregroundStyle(NoxaTheme.primaryText)
                .accessibilityAddTraits(.isHeader)

            Picker("Period", selection: $selectedStatsRange) {
                ForEach(StatsRange.allCases, id: \.self) { range in
                    Text(range.title).tag(range)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Button {
                    stepStatsPeriod(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 44, height: 36)
                }
                .accessibilityLabel("Previous \(selectedStatsRange.title.lowercased())")
                Spacer()
                Text(statsPeriodTitle)
                    .font(NoxaType.headline)
                    .foregroundStyle(NoxaTheme.primaryText)
                    .contentTransition(.numericText())
                Spacer()
                Button {
                    stepStatsPeriod(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 44, height: 36)
                }
                .disabled(isShowingCurrentStatsPeriod)
                .opacity(isShowingCurrentStatsPeriod ? 0.25 : 1)
                .accessibilityLabel("Next \(selectedStatsRange.title.lowercased())")
            }
            .font(NoxaType.subheadlineSemibold)
            .foregroundStyle(NoxaTheme.accent)
        }
    }

    func stepStatsPeriod(by value: Int) {
        selectedFocusBucket = nil
        guard let next = statsCalendar.date(byAdding: selectedStatsRange.unit.component, value: value, to: statsAnchorDate),
              next <= statsReferenceDate || value < 0 else { return }
        NoxaHaptics.selection()
        statsAnchorDate = next
    }

    var statsPeriodTitle: String {
        let interval = statsInterval
        let calendar = statsCalendar
        switch selectedStatsRange {
        case .day:
            if calendar.isDateInToday(interval.start) { return "Today" }
            if calendar.isDateInYesterday(interval.start) { return "Yesterday" }
            return interval.start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        case .week:
            if isShowingCurrentStatsPeriod { return "This week" }
            let last = interval.end.addingTimeInterval(-1)
            return "\(interval.start.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
        case .month:
            return isShowingCurrentStatsPeriod ? "This month" : interval.start.formatted(.dateTime.month(.wide).year())
        case .year:
            return isShowingCurrentStatsPeriod ? "This year" : interval.start.formatted(.dateTime.year())
        }
    }

    var insightsChart: some View {
        let buckets = FocusStatistics.buckets(
            history: focusSession.history,
            in: statsInterval,
            unit: selectedStatsRange.unit,
            now: statsReferenceDate,
            calendar: statsCalendar
        )
        let isEmpty = buckets.allSatisfy { $0.minutes == 0 }
        return VStack(spacing: 6) {
            // Details get their own row so they never cover a point.
            Group {
                if let selected = selectedFocusBucket {
                    Text("\(Self.bucketLabel(selected, range: selectedStatsRange)) · \(Self.compactFocusTime(minutes: selected.minutes)) · \(selected.sessions) session\(selected.sessions == 1 ? "" : "s")")
                        .font(NoxaType.footnoteMedium)
                        .foregroundStyle(NoxaTheme.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(NoxaTheme.elevated, in: Capsule())
                } else if !isEmpty {
                    Text("Tap a point for details")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.tertiaryText)
                }
            }
            .frame(height: 32)

            ZStack {
                NoxaFocusChart(
                    buckets: buckets,
                    label: { Self.bucketLabel($0, range: selectedStatsRange) },
                    axisLabel: { Self.axisLabel($0, range: selectedStatsRange) },
                    selection: $selectedFocusBucket
                )
                .frame(height: 180)

                if isEmpty {
                    VStack(spacing: 4) {
                        Text("No focus sessions \(selectedStatsRange.emptyPhrase(isCurrent: isShowingCurrentStatsPeriod))")
                            .font(NoxaType.subheadline)
                            .foregroundStyle(NoxaTheme.secondaryText)
                        if focusSession.history.isEmpty {
                            Text("Start a Focus on Home and it will show up here.")
                                .font(NoxaType.footnote)
                                .foregroundStyle(NoxaTheme.tertiaryText)
                        }
                    }
                    .multilineTextAlignment(.center)
                }
            }
        }
    }

    var statsSummary: FocusPeriodSummary {
        FocusStatistics.summary(history: focusSession.history, in: statsInterval, calendar: statsCalendar)
    }

    var insightsHeroMetric: some View {
        let summary = statsSummary
        return VStack(spacing: 2) {
            Text(Self.compactFocusTime(minutes: summary.focusMinutes))
                .font(.system(size: 44, weight: .semibold).monospacedDigit())
                .tracking(-1.4)
                .foregroundStyle(NoxaTheme.primaryText)
                .contentTransition(.numericText())
                .noxaAnimation(value: summary.focusMinutes)
            Text("Focused \(statsHeroPhrase)")
                .font(NoxaType.subheadline)
                .foregroundStyle(NoxaTheme.secondaryText)
            if let comparison = statsComparisonText {
                Text(comparison)
                    .font(NoxaType.footnote)
                    .foregroundStyle(NoxaTheme.tertiaryText)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// Descriptive, not a judgement: more time isn't presented as better.
    var statsComparisonText: String? {
        guard let comparison = FocusStatistics.comparison(
            history: focusSession.history,
            in: statsInterval,
            unit: selectedStatsRange.unit,
            now: statsReferenceDate,
            calendar: statsCalendar
        ) else { return nil }
        let previous: String = switch selectedStatsRange {
        case .day: "the day before"
        case .week: "last week"
        case .month: "last month"
        case .year: "last year"
        }
        let point = isShowingCurrentStatsPeriod ? "the same point \(previous)" : previous
        let difference = comparison.current - comparison.previous
        if difference == 0 { return "Same as \(point)" }
        return "\(Self.compactFocusTime(minutes: abs(difference))) \(difference > 0 ? "more" : "less") than \(point)"
    }

    var statsHeroPhrase: String {
        let title = statsPeriodTitle
        switch selectedStatsRange {
        case .day:
            return title == "Today" || title == "Yesterday" ? title.lowercased() : "on \(title)"
        case .week:
            return isShowingCurrentStatsPeriod ? "this week" : title
        case .month, .year:
            return isShowingCurrentStatsPeriod ? title.lowercased() : "in \(title)"
        }
    }

    var insightsPrimaryMetrics: some View {
        let summary = statsSummary
        return HStack(spacing: 10) {
            statTile(value: "\(summary.completedSessions)", title: "Sessions completed")
            statTile(
                value: summary.completedSessions + summary.abandonedSessions == 0 ? "–" : "\(summary.completionRate)%",
                title: "Completion rate"
            )
        }
    }

    var activityHistoryLink: some View {
        NavigationLink {
            activityHistoryScreen
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 20))
                    .foregroundStyle(NoxaTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity & History")
                        .font(NoxaType.headline)
                        .foregroundStyle(NoxaTheme.primaryText)
                    Text("More stats, schedules and every session")
                        .font(NoxaType.footnote)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(NoxaType.subheadlineSemibold)
                    .foregroundStyle(NoxaTheme.secondaryText)
            }
            .noxaCard(padding: 16)
        }
        .buttonStyle(.plain)
    }

    /// Everything the overview leaves out, for the period on screen.
    var activityHistoryScreen: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(statsPeriodTitle)
                    .font(NoxaType.title2)
                    .foregroundStyle(NoxaTheme.primaryText)
                AnyView(insightsStatTiles)
                if let sentence = bestPeriodSentence {
                    Text(sentence)
                        .font(NoxaType.subheadline)
                        .foregroundStyle(NoxaTheme.secondaryText)
                }
                AnyView(insightsScheduleCard)
                AnyView(recentSessionsCard(limit: 50))
                AnyView(metricDefinitions)
            }
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.vertical, 12)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
        .navigationTitle("Activity & History")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A factual line about the period's busiest day, block or month.
    var bestPeriodSentence: String? {
        let buckets = FocusStatistics.buckets(
            history: focusSession.history,
            in: statsInterval,
            unit: selectedStatsRange.unit,
            now: statsReferenceDate,
            calendar: statsCalendar
        )
        guard let best = buckets.max(by: { $0.minutes < $1.minutes }), best.minutes > 0 else { return nil }
        let name = Self.bucketLabel(best, range: selectedStatsRange)
        let scope: String = switch selectedStatsRange {
        case .day: "today"
        case .week: "this week"
        case .month: "this month"
        case .year: "this year"
        }
        return "\(name) had your most focus time \(isShowingCurrentStatsPeriod ? scope : "in this period"): \(Self.compactFocusTime(minutes: best.minutes))."
    }

    var metricDefinitions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How these are counted")
                .font(NoxaType.headline)
            Group {
                Text("Focus time: how long Focus sessions kept distractions blocked. It isn't screen time saved.")
                Text("Completed: sessions that ran to their end time.")
                Text("Completion rate: completed sessions out of completed plus those ended early or interrupted.")
                Text("Days focused: days with at least one completed session.")
                Text("Sessions count on the day they started. Weeks run Monday to Sunday.")
            }
            .font(NoxaType.footnote)
            .foregroundStyle(NoxaTheme.secondaryText)
        }
        .noxaStatsCard()
    }

    /// The secondary numbers, shown on the Activity & History page.
    var insightsStatTiles: some View {
        let summary = statsSummary
        let buckets = FocusStatistics.buckets(
            history: focusSession.history,
            in: statsInterval,
            unit: selectedStatsRange.unit,
            now: statsReferenceDate,
            calendar: statsCalendar
        )
        let best = buckets.max { $0.minutes < $1.minutes }.flatMap { $0.minutes > 0 ? $0 : nil }
        let bestTitle: String = switch selectedStatsRange {
        case .day: "Best block"
        case .week, .month: "Best day"
        case .year: "Best month"
        }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            statTile(value: "\(summary.focusedDays)", title: summary.focusedDays == 1 ? "Day focused" : "Days focused")
            statTile(value: summary.focusedDays == 0 ? "–" : Self.compactFocusTime(minutes: summary.averageMinutesPerFocusedDay), title: "Avg per focus day")
            statTile(value: summary.longestSessionMinutes == 0 ? "–" : Self.compactFocusTime(minutes: summary.longestSessionMinutes), title: "Longest session")
            statTile(
                value: best.map { Self.compactFocusTime(minutes: $0.minutes) } ?? "–",
                title: best.map { "\(bestTitle) · \(Self.bucketLabel($0, range: selectedStatsRange))" } ?? bestTitle
            )
        }
    }

    func statTile(value: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .semibold).monospacedDigit())
                .tracking(-0.6)
                .foregroundStyle(NoxaTheme.primaryText)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(NoxaType.footnote)
                .foregroundStyle(NoxaTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .noxaStatsCard(padding: 14)
        .accessibilityElement(children: .combine)
    }

    /// Monday to Sunday of the week on screen (or the current week).
    var insightsConsistency: some View {
        let anchor = selectedStatsRange == .week ? statsAnchorDate : statsReferenceDate
        let week = FocusStatistics.focusedDays(inWeekContaining: anchor, history: focusSession.history, calendar: statsCalendar)
        let focusedCount = week.filter(\.focused).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(selectedStatsRange == .week && !isShowingCurrentStatsPeriod ? "Consistency" : "This week's consistency")
                    .font(NoxaType.headline)
                Spacer()
                Text("\(focusedCount) of 7 days")
                    .font(NoxaType.subheadlineMedium)
                    .foregroundStyle(NoxaTheme.accent)
            }
            HStack(spacing: 0) {
                ForEach(week, id: \.day) { entry in
                    VStack(spacing: 8) {
                        Circle()
                            .fill(entry.focused ? NoxaTheme.accent.opacity(0.85) : NoxaTheme.elevated)
                            .frame(width: 14, height: 14)
                        Text(entry.day.formatted(.dateTime.weekday(.narrow)))
                            .font(NoxaType.caption)
                            .foregroundStyle(NoxaTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(entry.day.formatted(.dateTime.weekday(.wide))), \(entry.focused ? "focused" : "no focus")")
                }
            }
        }
        .noxaStatsCard()
    }

    var insightsScheduleCard: some View {
        let scheduleCommitment = ScheduleCommitmentEvaluator.lastSevenDays(
            events: schedules.commitmentEvents,
            now: statsReferenceDate,
            calendar: .autoupdatingCurrent
        )
        return VStack(alignment: .leading, spacing: 10) {
            NoxaCardHeader(
                title: "Schedules · last 7 days",
                systemImage: "calendar.badge.checkmark",
                info: "Based on whether schedules stayed on through their planned windows. It doesn't measure app use or prove blocking."
            )
            if scheduleCommitment.totalWindows == 0 {
                Text("No windows finished yet.")
                    .font(NoxaType.subheadline)
                    .foregroundStyle(NoxaTheme.secondaryText)
            } else {
                Text("\(scheduleCommitment.keptWindows) of \(scheduleCommitment.totalWindows) windows kept")
                    .font(NoxaType.title2)
                Text("\(scheduleCommitment.percentage)% kept · \(scheduleCommitment.interruptedWindows) changed or stopped early")
                    .font(NoxaType.subheadline)
                    .foregroundStyle(NoxaTheme.secondaryText)
            }
        }
        .noxaStatsCard()
    }

    /// Sparse x-axis labels: every block or day of a week, Mondays in a
    /// month, and month initials in a year.
    static func axisLabel(_ bucket: FocusBucket, range: StatsRange) -> String? {
        switch range {
        case .day:
            return bucket.start.formatted(.dateTime.hour())
        case .week:
            return bucket.start.formatted(.dateTime.weekday(.narrow))
        case .month:
            let day = Calendar.autoupdatingCurrent.component(.day, from: bucket.start)
            return [1, 8, 15, 22, 29].contains(day) ? bucket.start.formatted(.dateTime.day()) : nil
        case .year:
            return bucket.start.formatted(.dateTime.month(.narrow))
        }
    }

    static func bucketLabel(_ bucket: FocusBucket, range: StatsRange) -> String {
        switch range {
        case .day: bucket.start.formatted(date: .omitted, time: .shortened)
        case .week: bucket.start.formatted(.dateTime.weekday(.wide))
        case .month: bucket.start.formatted(.dateTime.month(.abbreviated).day())
        case .year: bucket.start.formatted(.dateTime.month(.wide))
        }
    }

    func recentSessionsCard(limit: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NoxaCardHeader(title: "Recent sessions", systemImage: "clock.arrow.circlepath")

            if focusSession.history.isEmpty {
                Text("Your sessions will show up here.")
                    .foregroundStyle(NoxaTheme.secondaryText)
            } else {
                ForEach(focusSession.history.prefix(limit)) { session in
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
                    if session.id != focusSession.history.prefix(limit).last?.id {
                        Divider()
                            .overlay(NoxaTheme.border)
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
                .font(NoxaType.display(32))
                .tracking(-0.8)
                .foregroundStyle(NoxaTheme.primaryText)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(title)
                .font(NoxaType.subheadline)
                .foregroundStyle(NoxaTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
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
