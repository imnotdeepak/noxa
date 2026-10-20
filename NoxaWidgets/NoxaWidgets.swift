import ActivityKit
import SwiftUI
import WidgetKit

private struct FocusWidgetEntry: TimelineEntry {
    let date: Date
    let plannedEndAt: Date?
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
        FocusWidgetEntry(date: Date(), plannedEndAt: nil, isStrict: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusWidgetEntry) -> Void) {
        completion(entry(at: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusWidgetEntry>) -> Void) {
        let now = Date()
        let current = entry(at: now)
        var entries = [current]
        if let end = current.plannedEndAt {
            entries.append(FocusWidgetEntry(date: end, plannedEndAt: nil, isStrict: false))
        }
        completion(Timeline(entries: entries, policy: .never))
    }

    private func entry(at date: Date) -> FocusWidgetEntry {
        guard let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa"),
              let data = defaults.data(forKey: "noxa.localSnapshot"),
              let snapshot = try? JSONDecoder().decode(FocusSnapshot.self, from: data),
              let session = snapshot.activeSession,
              session.outcome == "active",
              session.plannedEndAt > date else {
            return FocusWidgetEntry(date: date, plannedEndAt: nil, isStrict: false)
        }
        return FocusWidgetEntry(
            date: date,
            plannedEndAt: session.plannedEndAt,
            isStrict: session.isStrict
        )
    }
}

private struct FocusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: FocusWidgetEntry

    private var isActive: Bool { entry.plannedEndAt != nil }

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
                    Image(systemName: isActive ? "timer" : "play.fill")
                    if let end = entry.plannedEndAt {
                        Text(timerInterval: entry.date...end, countsDown: true, showsHours: false)
                            .font(.caption2.monospacedDigit())
                    } else {
                        Text("Focus").font(.caption2)
                    }
                }
            case .accessoryRectangular:
                HStack(spacing: 8) {
                    Image(systemName: isActive ? "timer" : "play.circle.fill")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(isActive ? "Focus in progress" : "Start Focus")
                            .font(.headline)
                        if let end = entry.plannedEndAt {
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
                    Label("NOXA FOCUS", systemImage: isActive ? "timer" : "play.circle.fill")
                        .font(.caption.weight(.bold))
                    Spacer(minLength: 4)
                    if let end = entry.plannedEndAt {
                        Text(timerInterval: entry.date...end, countsDown: true, showsHours: false)
                            .font(.title.bold().monospacedDigit())
                            .minimumScaleFactor(0.6)
                        Text(entry.isStrict ? "Strict session" : "Focus session")
                            .font(.caption)
                    } else {
                        Text("Start a focus session")
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
                    Text(context.attributes.isStrict ? "Strict Focus" : "Focus")
                        .font(.headline)
                    Text(timerInterval: context.state.startedAt...context.state.plannedEndAt, countsDown: true)
                        .font(.title.bold().monospacedDigit())
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
                    Text(timerInterval: context.state.startedAt...context.state.plannedEndAt, countsDown: true)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.attributes.isStrict ? "Strict session" : "Focus session")
                }
            } compactLeading: {
                Image(systemName: "timer")
            } compactTrailing: {
                Text(context.state.plannedEndAt, style: .timer)
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
