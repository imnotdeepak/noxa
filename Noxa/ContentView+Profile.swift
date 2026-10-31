import SwiftUI

extension ContentView {
    var profileContent: some View {
        let statistics = FocusStatistics(
            history: focusSession.history,
            now: statsReferenceDate,
            calendar: .autoupdatingCurrent
        )
        return ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                AnyView(HStack {
                    Text("Profile")
                        .font(NoxaTheme.font(34, weight: .bold, relativeTo: .largeTitle))
                        .tracking(-1.2)
                        .foregroundStyle(NoxaTheme.primaryText)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    NavigationLink {
                        settingsScreen
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 22))
                            .foregroundStyle(NoxaTheme.secondaryText)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Settings")
                })

                let milestones = allMilestones(statistics)
                let earned = milestones.filter(\.isEarned).count
                AnyView(HStack(spacing: 24) {
                    // The emblem's ring is milestones earned out of all of them.
                    ZStack {
                        Circle()
                            .fill(NoxaTheme.surfaceGradient)
                        Circle()
                            .stroke(NoxaTheme.elevated, lineWidth: 5)
                            .padding(10)
                        Circle()
                            .trim(from: 0, to: Double(earned) / Double(max(milestones.count, 1)))
                            .stroke(NoxaTheme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .shadow(color: NoxaTheme.accent.opacity(0.35), radius: 6)
                            .padding(10)
                        Text(profileInitial)
                            .font(.system(size: 48, weight: .regular))
                            .foregroundStyle(NoxaTheme.primaryText)
                    }
                    .frame(width: 104, height: 104)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(earned) of \(milestones.count) milestones earned")

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your journey")
                            .font(NoxaType.title2)
                            .foregroundStyle(NoxaTheme.primaryText)
                        Text("Building better habits, one session at a time.")
                            .font(NoxaType.subheadline)
                            .foregroundStyle(NoxaTheme.secondaryText)
                        Label("Ring: \(earned) of \(milestones.count) milestones", systemImage: "circle.dotted")
                            .font(NoxaType.caption)
                            .foregroundStyle(NoxaTheme.tertiaryText)
                    }
                })

                // Three all-time figures at one size.
                AnyView(VStack(spacing: 14) {
                    Text("ALL TIME")
                        .font(NoxaType.captionSemibold)
                        .tracking(1.4)
                        .foregroundStyle(NoxaTheme.tertiaryText)
                        .frame(maxWidth: .infinity)
                    HStack(spacing: 0) {
                        profileStat(value: Self.compactFocusTime(minutes: statistics.totalFocusMinutes), title: "Focus time")
                        profileStat(value: "\(statistics.currentStreak)", title: "Day streak")
                        profileStat(value: "\(statistics.completedSessions)", title: "Completed")
                    }
                }
                .noxaCard(padding: 20))

                AnyView(profileMilestonesSection(statistics))

                Divider().overlay(NoxaTheme.border)

                AnyView(NavigationLink {
                    settingsScreen
                } label: {
                    HStack(spacing: 16) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 22))
                            .foregroundStyle(NoxaTheme.secondaryText)
                        Text("Settings & account")
                            .font(NoxaType.body)
                            .foregroundStyle(NoxaTheme.primaryText)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(NoxaType.subheadlineSemibold)
                            .foregroundStyle(NoxaTheme.secondaryText)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain))
            }
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
    }

    var settingsScreen: some View {
        accountContent
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { AnalyticsService.shared.screen("Settings") }
    }

    var profileInitial: String {
        let source = authentication.displayName?.trimmingCharacters(in: .whitespaces).nilIfEmpty
            ?? authentication.userEmail
            ?? ""
        return source.first.map { String($0).uppercased() } ?? "N"
    }

    func profileStat(value: String, title: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 26, weight: .semibold).monospacedDigit())
                .tracking(-0.6)
                .foregroundStyle(NoxaTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(title)
                .font(NoxaType.footnote)
                .foregroundStyle(NoxaTheme.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    func allMilestones(_ statistics: FocusStatistics) -> [FocusMilestone] {
        FocusMilestone.all(
            totalFocusMinutes: statistics.totalFocusMinutes,
            completedSessions: statistics.completedSessions,
            longestStreak: statistics.longestStreak,
            totalFocusedDays: FocusStatistics.totalFocusedDays(history: focusSession.history, calendar: .autoupdatingCurrent),
            longSessions: FocusStatistics.completedSessionCount(
                history: focusSession.history,
                minimumMinutes: FocusMilestone.longSessionMinutes
            )
        )
    }

    /// The three closest milestones, then the full list one tap away.
    func profileMilestonesSection(_ statistics: FocusStatistics) -> some View {
        let milestones = allMilestones(statistics)
        let earnedCount = milestones.filter(\.isEarned).count
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Milestones")
                    .font(NoxaType.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text("\(earnedCount) of \(milestones.count) earned")
                    .font(NoxaType.footnote)
                    .foregroundStyle(NoxaTheme.secondaryText)
            }
            ForEach(FocusMilestone.featured(from: milestones)) { milestone in
                milestoneLink(milestone)
            }
            NavigationLink {
                moreMilestonesScreen
                    .onAppear { AnalyticsService.shared.screen("More milestones") }
            } label: {
                HStack {
                    Text("More milestones")
                        .font(NoxaType.subheadlineSemibold)
                        .foregroundStyle(NoxaTheme.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(NoxaType.footnoteSemibold)
                        .foregroundStyle(NoxaTheme.accent)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    func milestoneRow(_ milestone: FocusMilestone) -> some View {
        HStack(spacing: 14) {
            Image(systemName: milestone.isEarned ? "checkmark.circle.fill" : milestone.category.systemImage)
                .font(.system(size: 20))
                .foregroundStyle(milestone.isEarned ? NoxaTheme.accent : NoxaTheme.accentSoft)
                .frame(width: 40, height: 40)
                .background(NoxaTheme.elevated, in: Circle())
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(milestone.title)
                        .font(NoxaType.subheadlineSemibold)
                        .foregroundStyle(NoxaTheme.primaryText)
                    Spacer()
                    Text("\(milestone.percent)%")
                        .font(NoxaType.subheadlineSemibold.monospacedDigit())
                        .foregroundStyle(milestone.isEarned ? NoxaTheme.accent : NoxaTheme.secondaryText)
                }
                ProgressView(value: min(milestone.current, milestone.target), total: milestone.target)
                    .tint(NoxaTheme.accent)
                Text(milestone.isEarned ? "Earned" : milestone.goal)
                    .font(NoxaType.caption)
                    .foregroundStyle(NoxaTheme.tertiaryText)
            }
        }
        .noxaCard(padding: 14)
        .accessibilityElement(children: .combine)
        .accessibilityValue(milestone.isEarned ? "Earned" : "\(milestone.percent) percent")
    }

    func milestoneLink(_ milestone: FocusMilestone) -> some View {
        NavigationLink {
            milestoneDetail(milestone)
        } label: {
            milestoneRow(milestone)
        }
        .buttonStyle(.plain)
    }

    /// What it takes, where you are, and what's left, in the milestone's unit.
    func milestoneDetail(_ milestone: FocusMilestone) -> some View {
        let remaining = max(milestone.target - milestone.current, 0)
        return ScrollView {
            VStack(spacing: 20) {
                Image(systemName: milestone.isEarned ? "checkmark.circle.fill" : milestone.category.systemImage)
                    .font(.system(size: 44))
                    .foregroundStyle(milestone.isEarned ? NoxaTheme.accent : NoxaTheme.accentSoft)
                    .frame(width: 96, height: 96)
                    .background(NoxaTheme.elevated, in: Circle())
                VStack(spacing: 6) {
                    Text(milestone.title)
                        .font(NoxaType.title2)
                        .foregroundStyle(NoxaTheme.primaryText)
                    Text(milestone.goal)
                        .font(NoxaType.subheadline)
                        .foregroundStyle(NoxaTheme.secondaryText)
                        .multilineTextAlignment(.center)
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(milestone.isEarned ? "Earned" : "\(milestone.percent)% there")
                            .font(NoxaType.headline)
                            .foregroundStyle(milestone.isEarned ? NoxaTheme.accent : NoxaTheme.primaryText)
                        Spacer()
                    }
                    ProgressView(value: min(milestone.current, milestone.target), total: milestone.target)
                        .tint(NoxaTheme.accent)
                    detailRow("So far", Self.milestoneAmount(milestone.current, category: milestone.category))
                    detailRow("Goal", Self.milestoneAmount(milestone.target, category: milestone.category))
                    if !milestone.isEarned {
                        detailRow("Left to go", Self.milestoneAmount(remaining, category: milestone.category))
                    }
                }
                .noxaCard(padding: 18)
                Text(Self.milestoneCounting(milestone.category))
                    .font(NoxaType.footnote)
                    .foregroundStyle(NoxaTheme.tertiaryText)
                    .multilineTextAlignment(.center)
            }
            .padding(NoxaTheme.Spacing.screen)
        }
        .noxaScreenBackground()
        .navigationTitle("Milestone")
        .navigationBarTitleDisplayMode(.inline)
    }

    func detailRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(NoxaTheme.secondaryText)
            Spacer()
            Text(value)
                .monospacedDigit()
                .foregroundStyle(NoxaTheme.primaryText)
        }
        .font(NoxaType.subheadline)
        .accessibilityElement(children: .combine)
    }

    static func milestoneAmount(_ value: Double, category: FocusMilestone.Category) -> String {
        switch category {
        case .focusTime:
            return compactFocusTime(minutes: Int((value * 60).rounded(.down)))
        case .sessions, .longSessions:
            let count = Int(value)
            return "\(count.formatted()) session\(count == 1 ? "" : "s")"
        case .streak, .focusedDays:
            let count = Int(value)
            return "\(count.formatted()) day\(count == 1 ? "" : "s")"
        }
    }

    static func milestoneCounting(_ category: FocusMilestone.Category) -> String {
        switch category {
        case .focusTime: "Counts time your Focus sessions kept distractions blocked, all time."
        case .sessions: "Counts Focus sessions that ran to their end time."
        case .streak: "Your longest run of days in a row with a completed session. Missing a day doesn't undo a milestone you've earned."
        case .focusedDays: "Counts different days with at least one completed session."
        case .longSessions: "Counts completed sessions where distractions were blocked for 2 hours or more."
        }
    }

    var moreMilestonesScreen: some View {
        let statistics = FocusStatistics(history: focusSession.history, now: statsReferenceDate, calendar: .autoupdatingCurrent)
        let milestones = allMilestones(statistics)
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                ForEach(FocusMilestone.Category.allCases, id: \.self) { category in
                    VStack(alignment: .leading, spacing: 10) {
                        Label(category.rawValue, systemImage: category.systemImage)
                            .font(NoxaType.headline)
                            .foregroundStyle(NoxaTheme.primaryText)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(milestones.filter { $0.category == category }) { milestone in
                            milestoneLink(milestone)
                        }
                    }
                }
            }
            .padding(.horizontal, NoxaTheme.Spacing.screen)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .noxaScreenBackground()
        .navigationTitle("More milestones")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
