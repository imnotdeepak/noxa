import ActivityKit
import SwiftUI
import WidgetKit

private struct FocusWidgetEntry: TimelineEntry {
    let date: Date
    let plannedEndAt: Date?
    let breakEndsAt: Date?
    let isStrict: Bool
}

private struct PomodoroWidgetCycle: Decodable {
    struct Plan: Decodable {
        let startedAt: Date
        let workMinutes: Int
        let breakMinutes: Int

        func workInterval(round: Int) -> DateInterval {
            let work = TimeInterval(workMinutes * 60)
            let rest = TimeInterval(breakMinutes * 60)
            return DateInterval(
                start: startedAt.addingTimeInterval(TimeInterval(round - 1) * (work + rest)),
                duration: work
            )
        }
    }

    let plan: Plan
    let isStrict: Bool
}

private struct FocusSnapshot: Decodable {
    struct Session: Decodable {
        let plannedEndAt: Date
        let outcome: String
        let isStrict: Bool
    }

    let activeSession: Session?
}

private struct FocusWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusWidgetEntry {
        FocusWidgetEntry(date: Date(), plannedEndAt: nil, breakEndsAt: nil, isStrict: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusWidgetEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusWidgetEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var entries = [current]
        if let cycle = pomodoroCycle() {
            let boundaries = (1...4).flatMap { round -> [Date] in
                let interval = cycle.plan.workInterval(round: round)
                return [interval.start, interval.end]
            }
            entries += boundaries.filter { $0 > now }.map { entry(at: $0) }
        } else if let end = current.plannedEndAt {
            entries.append(FocusWidgetEntry(
                date: end, plannedEndAt: nil, breakEndsAt: nil, isStrict: false
            ))
        }
        completion(Timeline(entries: entries, policy: .never))
    }

    private func entry(at date: Date) -> FocusWidgetEntry {
        if let cycle = pomodoroCycle() {
            for round in 1...4 {
                let interval = cycle.plan.workInterval(round: round)
                if date >= interval.start && date < interval.end {
                    return FocusWidgetEntry(
                        date: date,
                        plannedEndAt: interval.end,
                        breakEndsAt: nil,
                        isStrict: cycle.isStrict
                    )
                }
                if round < 4, date >= interval.end {
                    let nextStart = cycle.plan.workInterval(round: round + 1).start
                    if date < nextStart {
                        return FocusWidgetEntry(
                            date: date,
                            plannedEndAt: nil,
                            breakEndsAt: nextStart,
                            isStrict: cycle.isStrict
                        )
                    }
                }
            }
        }
        guard let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.localSnapshot"),
              let snapshot = try? JSONDecoder().decode(FocusSnapshot.self, from: data),
              let session = snapshot.activeSession,
              session.outcome == "active",
              session.plannedEndAt > date else {
            return FocusWidgetEntry(date: date, plannedEndAt: nil, breakEndsAt: nil, isStrict: false)
        }
        return FocusWidgetEntry(
            date: date,
            plannedEndAt: session.plannedEndAt,
            breakEndsAt: nil,
            isStrict: session.isStrict
        )
    }

    private func pomodoroCycle() -> PomodoroWidgetCycle? {
        guard let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.pomodoroCycle") else { return nil }
        return try? JSONDecoder().decode(PomodoroWidgetCycle.self, from: data)
    }
}

private struct FocusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FocusWidgetEntry

    private var isActive: Bool { entry.plannedEndAt != nil || entry.breakEndsAt != nil }
    private var isBreak: Bool { entry.breakEndsAt != nil }
    private var timerEndAt: Date? { entry.plannedEndAt ?? entry.breakEndsAt }

    @ViewBuilder
    var body: some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) {
                Color(red: 0.06, green: 0.10, blue: 0.10)
            }
        } else {
            content.background(Color(red: 0.06, green: 0.10, blue: 0.10))
        }
    }

    private var content: some View {
        Group {
            switch family {
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: isBreak ? "cup.and.saucer" : isActive ? "timer" : "play.fill")
                    if let end = timerEndAt {
                        Text(timerInterval: entry.date...end, countsDown: true, showsHours: false)
                            .font(.caption2.monospacedDigit())
                    } else {
                        Text("Focus").font(.caption2)
                    }
                }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: isBreak ? "cup.and.saucer" : isActive ? "timer" : "play.circle.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isBreak ? "Break" : isActive ? "Focus" : "Start Focus")
                            .font(.headline)
                        if let end = timerEndAt {
                            Text(timerInterval: entry.date...end, countsDown: true, showsHours: false)
                                .monospacedDigit()
                        } else {
                            Text("Choose your time in Noxa")
                                .font(.caption)
                        }
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 10) {
                    Label("NOXA FOCUS", systemImage: isBreak ? "cup.and.saucer" : isActive ? "timer" : "play.circle.fill")
                        .font(.caption.weight(.bold))
                    Spacer(minLength: 4)
                    if let end = timerEndAt {
                        Text(timerInterval: entry.date...end, countsDown: true, showsHours: false)
                            .font(.title.bold().monospacedDigit())
                            .minimumScaleFactor(0.6)
                        Text(isBreak ? "Pomodoro break" : "Focus session")
                            .font(.caption)
                    } else {
                        Text("Start Focus")
                            .font(.headline)
                        Text("One hour selected · change it before starting")
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .widgetURL(URL(string: isActive ? "noxa://focus/active" : "noxa://focus/start"))
    }
}

private struct FocusWidget: Widget {
    let kind = "NoxaFocusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FocusWidgetProvider()) { entry in
            FocusWidgetView(entry: entry)
        }
        .configurationDisplayName("Noxa Focus")
        .description("Start a session or see the time remaining.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

private struct FocusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: context.attributes.isStrict ? "lock.fill" : "timer")
                VStack(alignment: .leading) {
                    if context.isStale {
                        Text("Focus interval ended")
                            .font(.headline)
                        Text("Open Noxa for current status")
                            .font(.subheadline)
                    } else {
                        Text("Focus")
                            .font(.headline)
                        Text(timerInterval: context.state.startedAt...context.state.plannedEndAt, countsDown: true)
                            .font(.title.bold().monospacedDigit())
                    }
                }
                Spacer()
            }
            .padding()
            .activityBackgroundTint(Color(red: 0.06, green: 0.10, blue: 0.10))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "noxa://focus/active"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Focus", systemImage: "timer")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.isStale {
                        Text("Ended")
                    } else {
                        Text(timerInterval: context.state.startedAt...context.state.plannedEndAt, countsDown: true)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.isStale
                         ? "Open Noxa for current status"
                         : "Focus session")
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                if context.isStale {
                    Text("Done")
                } else {
                    Text(context.state.plannedEndAt, style: .timer)
                }
            } minimal: {
                Image(systemName: "timer")
            }
            .widgetURL(URL(string: "noxa://focus/active"))
        }
    }
}

@main
struct NoxaWidgets: WidgetBundle {
    var body: some Widget {
        FocusWidget()
        FocusLiveActivityWidget()
    }
}
