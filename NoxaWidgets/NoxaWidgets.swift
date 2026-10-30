import ActivityKit
import SwiftUI
import WidgetKit

private struct FocusWidgetEntry: TimelineEntry {
    let date: Date
    /// The current focus interval, or the Pomodoro break; nil when idle.
    let interval: DateInterval?
    let isBreak: Bool

    static func idle(at date: Date) -> Self {
        FocusWidgetEntry(date: date, interval: nil, isBreak: false)
    }

    /// How much of the interval has passed at this entry, 0...1.
    var progress: Double {
        guard let interval, interval.duration > 0 else { return 0 }
        return min(max(date.timeIntervalSince(interval.start) / interval.duration, 0), 1)
    }
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
}

private struct FocusSnapshot: Decodable {
    struct Session: Decodable {
        let startedAt: Date
        let plannedEndAt: Date
        let outcome: String
    }

    let activeSession: Session?
}

private struct FocusWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusWidgetEntry {
        .idle(at: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusWidgetEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusWidgetEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var dates: Set<Date> = [now]
        if let cycle = pomodoroCycle() {
            for round in 1...4 {
                let interval = cycle.plan.workInterval(round: round)
                dates.formUnion([interval.start, interval.end].filter { $0 > now })
            }
        } else if let end = current.interval?.end {
            dates.insert(end)
        }
        // A step each minute so the ring fills; capped at six hours.
        let last = dates.max() ?? now
        if current.interval != nil || last > now {
            var tick = now.addingTimeInterval(60)
            while tick < last, tick < now.addingTimeInterval(6 * 3_600) {
                dates.insert(tick)
                tick = tick.addingTimeInterval(60)
            }
        }
        let entries = dates.sorted().map { entry(at: $0) }
        completion(Timeline(entries: entries, policy: .never))
    }

    private func entry(at date: Date) -> FocusWidgetEntry {
        if let cycle = pomodoroCycle() {
            for round in 1...4 {
                let interval = cycle.plan.workInterval(round: round)
                if date >= interval.start && date < interval.end {
                    return FocusWidgetEntry(date: date, interval: interval, isBreak: false)
                }
                if round < 4, date >= interval.end {
                    let nextStart = cycle.plan.workInterval(round: round + 1).start
                    if date < nextStart {
                        return FocusWidgetEntry(
                            date: date,
                            interval: DateInterval(start: interval.end, end: nextStart),
                            isBreak: true
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
              session.plannedEndAt > date,
              session.startedAt < session.plannedEndAt else {
            return .idle(at: date)
        }
        return FocusWidgetEntry(
            date: date,
            interval: DateInterval(start: session.startedAt, end: session.plannedEndAt),
            isBreak: false
        )
    }

    private func pomodoroCycle() -> PomodoroWidgetCycle? {
        guard let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.pomodoroCycle") else { return nil }
        return try? JSONDecoder().decode(PomodoroWidgetCycle.self, from: data)
    }
}

private enum WidgetPalette {
    static let background = Color(red: 3 / 255, green: 5 / 255, blue: 3 / 255)
    static let track = Color(red: 23 / 255, green: 27 / 255, blue: 23 / 255)
    static let accent = Color(red: 168 / 255, green: 240 / 255, blue: 0)
    static let secondary = Color(red: 168 / 255, green: 176 / 255, blue: 165 / 255)
}

private struct FocusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FocusWidgetEntry

    @ViewBuilder
    var body: some View {
        if #available(iOS 17.0, *) {
            content.containerBackground(for: .widget) { WidgetPalette.background }
        } else {
            content.background(WidgetPalette.background)
        }
    }

    private var content: some View {
        Group {
            if let interval = entry.interval {
                active(interval)
            } else {
                idle
            }
        }
        .widgetURL(URL(string: entry.interval == nil ? "noxa://focus/start" : "noxa://focus/active"))
    }

    @ViewBuilder
    private var idle: some View {
        switch family {
        case .accessoryCircular, .accessoryRectangular:
            Text("Start Focus")
                .font(.headline)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            Text("Start Focus")
                .font(.system(size: family == .systemSmall ? 24 : 28, weight: .bold))
                .foregroundStyle(WidgetPalette.accent)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func active(_ interval: DateInterval) -> some View {
        let range = interval.start...interval.end
        let label = entry.isBreak ? "Break" : "Focus"
        switch family {
        case .accessoryCircular:
            Gauge(value: entry.progress) {
                Text(label)
            } currentValueLabel: {
                Text(timerInterval: range, countsDown: true, showsHours: false)
                    .monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(label).font(.headline)
                    Spacer()
                    Text(timerInterval: range, countsDown: true, showsHours: false)
                        .monospacedDigit()
                }
                ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
            }
        case .systemSmall:
            // A ring that fills as the session runs, with time left inside.
            ZStack {
                Circle()
                    .stroke(WidgetPalette.track, lineWidth: 10)
                Circle()
                    .trim(from: 0, to: entry.progress)
                    .stroke(WidgetPalette.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 2) {
                    Text(timerInterval: range, countsDown: true, showsHours: false)
                        .font(.system(size: 22, weight: .bold).monospacedDigit())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(WidgetPalette.secondary)
                }
                .frame(width: 96)
            }
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        default:
            // A bar that fills left to right as the session runs.
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(label)
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.secondary)
                    Spacer()
                    Text(timerInterval: range, countsDown: true, showsHours: false)
                        .font(.system(size: 34, weight: .bold).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.white)
                }
                ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear)
                    .tint(WidgetPalette.accent)
                Text("Ends \(interval.end.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(WidgetPalette.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
}

private struct FocusWidget: Widget {
    let kind = "NoxaFocusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FocusWidgetProvider()) { entry in
            FocusWidgetView(entry: entry)
        }
        .configurationDisplayName("Focus")
        .description("Start a session or see the time remaining.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

private struct FocusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            let range = context.state.startedAt...context.state.plannedEndAt
            VStack(alignment: .leading, spacing: 10) {
                if context.isStale {
                    Text("Focus ended")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text("Open Noxa for current status")
                        .font(.subheadline)
                        .foregroundStyle(WidgetPalette.secondary)
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Focus")
                            .font(.headline)
                            .foregroundStyle(WidgetPalette.secondary)
                        Spacer()
                        Text(timerInterval: range, countsDown: true)
                            .font(.system(size: 30, weight: .bold).monospacedDigit())
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.white)
                    }
                    ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.linear)
                        .tint(WidgetPalette.accent)
                }
            }
            .padding()
            .activityBackgroundTint(WidgetPalette.background)
            .activitySystemActionForegroundColor(.white)
            .widgetURL(URL(string: "noxa://focus/active"))
        } dynamicIsland: { context in
            let range = context.state.startedAt...context.state.plannedEndAt
            return DynamicIsland {
                // Inset so the corners of the island don't clip the text.
                DynamicIslandExpandedRegion(.leading) {
                    Text("Focus")
                        .font(.headline)
                        .foregroundStyle(WidgetPalette.accent)
                        .padding(.leading, 8)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if context.isStale {
                            Text("Ended")
                        } else {
                            Text(timerInterval: range, countsDown: true)
                                .monospacedDigit()
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    .padding(.trailing, 8)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.isStale {
                        Text("Open Noxa for current status")
                    } else {
                        ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                            .progressViewStyle(.linear)
                            .tint(WidgetPalette.accent)
                    }
                }
            } compactLeading: {
                ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular)
                    .tint(WidgetPalette.accent)
            } compactTrailing: {
                if context.isStale {
                    Text("Done")
                } else {
                    Text(timerInterval: range, countsDown: true, showsHours: false)
                        .monospacedDigit()
                        .frame(maxWidth: 52)
                }
            } minimal: {
                ProgressView(timerInterval: range, countsDown: false) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.circular)
                    .tint(WidgetPalette.accent)
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

#if DEBUG
@available(iOS 17.0, *)
#Preview("Small", as: .systemSmall) {
    FocusWidget()
} timeline: {
    FocusWidgetEntry.idle(at: .now)
    FocusWidgetEntry(date: .now, interval: DateInterval(start: .now.addingTimeInterval(-600), duration: 1_800), isBreak: false)
}

@available(iOS 17.0, *)
#Preview("Medium", as: .systemMedium) {
    FocusWidget()
} timeline: {
    FocusWidgetEntry.idle(at: .now)
    FocusWidgetEntry(date: .now, interval: DateInterval(start: .now.addingTimeInterval(-600), duration: 1_800), isBreak: false)
}

@available(iOS 17.0, *)
#Preview("Live Activity", as: .content, using: FocusActivityAttributes(sessionID: UUID(), isStrict: true)) {
    FocusLiveActivityWidget()
} contentStates: {
    FocusActivityAttributes.ContentState(startedAt: .now.addingTimeInterval(-600), plannedEndAt: .now.addingTimeInterval(1_200))
}
#endif
