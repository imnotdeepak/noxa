//
//  DailyLimitCallbacks.swift
//  Shared by Noxa and NoxaMonitor
//

import DeviceActivity
import FamilyControls
import Foundation

/// Event names and registration for daily limits.
///
/// Every registration has a generation number, carried in each event name,
/// so callbacks queued for an earlier registration can be told apart. Each
/// limit also gets a usage event for every minute below its allowance; their
/// arrival times are the only usage signal Apple's public API gives a
/// monitor, and DailyLimitCallbackVerifier checks a limit against them.
enum DailyLimitEvents {
    static let reachedPrefix = "noxa.daily.limit."
    static let usagePrefix = "noxa.daily.usage."
    static let maximumMinutes = 60

    static let generationKey = "noxa.dailyLimitGeneration"
    static let baselinesKey = "noxa.dailyLimitBaselines"
    static let usageTimesKey = "noxa.dailyLimitUsageTimes"
    static let usedMinutesKey = "noxa.dailyLimitUsedMinutes"
    static let rearmsKey = "noxa.dailyLimitRearms"

    struct Limit: Equatable {
        let id: String
        let minutes: Int
    }

    enum Callback: Equatable {
        case reached(id: String, generation: Int)
        case usage(id: String, generation: Int, minute: Int)

        var id: String {
            switch self {
            case .reached(let id, _), .usage(let id, _, _): id
            }
        }

        var generation: Int {
            switch self {
            case .reached(_, let generation), .usage(_, let generation, _): generation
            }
        }
    }

    static let schedule = DeviceActivitySchedule(
        intervalStart: DateComponents(hour: 0, minute: 0),
        intervalEnd: DateComponents(hour: 23, minute: 59),
        repeats: true,
        warningTime: DateComponents(minute: 5)
    )

    /// The name the reached state is stored under, independent of generation.
    static func canonicalReachedName(id: String) -> String {
        "\(reachedPrefix)\(id)"
    }

    static func reachedName(id: String, generation: Int) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("\(reachedPrefix)\(id).g\(generation)")
    }

    static func usageName(id: String, generation: Int, minute: Int) -> DeviceActivityEvent.Name {
        DeviceActivityEvent.Name("\(usagePrefix)\(id).g\(generation).\(minute)")
    }

    /// Names without a generation came from monitors registered before
    /// generations existed, and count as generation 0.
    static func parse(_ event: DeviceActivityEvent.Name) -> Callback? {
        let raw = event.rawValue
        if raw.hasPrefix(reachedPrefix) {
            let parts = raw.dropFirst(reachedPrefix.count).split(separator: ".")
            switch parts.count {
            case 1: return .reached(id: String(parts[0]), generation: 0)
            case 2:
                guard let generation = generationNumber(parts[1]) else { return nil }
                return .reached(id: String(parts[0]), generation: generation)
            default: return nil
            }
        }
        if raw.hasPrefix(usagePrefix) {
            let parts = raw.dropFirst(usagePrefix.count).split(separator: ".")
            switch parts.count {
            case 2:
                guard let minute = Int(parts[1]) else { return nil }
                return .usage(id: String(parts[0]), generation: 0, minute: minute)
            case 3:
                guard let generation = generationNumber(parts[1]), let minute = Int(parts[2]) else { return nil }
                return .usage(id: String(parts[0]), generation: generation, minute: minute)
            default: return nil
            }
        }
        return nil
    }

    private static func generationNumber(_ text: Substring) -> Int? {
        guard text.hasPrefix("g") else { return nil }
        return Int(text.dropFirst())
    }

    static func usageStep(limitMinutes: Int) -> Int {
        limitMinutes <= maximumMinutes ? 1 : 5
    }

    /// Usage minutes still to be reported, counted from the minutes already
    /// credited to this limit today. Limits saved before the one-hour cap
    /// count every 5 minutes.
    static func usageMinutes(limitMinutes: Int, baseline: Int = 0) -> [Int] {
        Array(stride(from: baseline + 1, to: limitMinutes, by: usageStep(limitMinutes: limitMinutes)))
    }

    /// Thresholds count from registration, so a limit re-armed with minutes
    /// already credited only needs the remainder.
    static func events(
        for limits: [(limit: Limit, selection: FamilyActivitySelection, baseline: Int)],
        generation: Int
    ) -> [DeviceActivityEvent.Name: DeviceActivityEvent] {
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for (limit, selection, baseline) in limits {
            events[reachedName(id: limit.id, generation: generation)] =
                event(selection: selection, minutes: limit.minutes - baseline)
            for minute in usageMinutes(limitMinutes: limit.minutes, baseline: baseline) {
                events[usageName(id: limit.id, generation: generation, minute: minute)] =
                    event(selection: selection, minutes: minute - baseline)
            }
        }
        return events
    }

    /// No includesPastActivity: it made iOS fire limits minutes after a
    /// re-register with little real use.
    private static func event(selection: FamilyActivitySelection, minutes: Int) -> DeviceActivityEvent {
        DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: max(1, minutes))
        )
    }
}

/// Decides whether a daily-limit callback may block an app.
///
/// iOS has delivered "reached" callbacks for several limits, and every usage
/// event below them, within the same second while Screen Time showed little
/// use. No public API lets a monitor read usage directly, so a reached
/// callback is only trusted when its usage events arrived at a pace real use
/// could produce: N minutes of use take at least about N minutes. That is a
/// necessary condition, not proof, so a premature callback that arrives
/// gradually would still pass. A genuine limit whose callbacks iOS delivers
/// late in a batch can fail it; the limit is then re-armed with the minutes
/// that were credible, so it blocks a few minutes late rather than early.
enum DailyLimitCallbackVerifier {
    enum Verdict: Equatable {
        case accept
        case reject(creditedMinutes: Int)
    }

    enum Action: Equatable {
        case recordUsage(id: String, minute: Int)
        case ignoreStale
        case ignoreDuplicate
        case ignoreUnknown
        case block(id: String)
        /// Re-register every unblocked limit with these credited minutes.
        case rearm(baselines: [String: Int])
        /// Too many re-arms today: leave the limit unblocked.
        case reject(id: String)
    }

    struct State: Equatable {
        var generation = 0
        var reachedIDs: Set<String> = []
        var baselines: [String: Int] = [:]
        /// When each usage minute was first reported in this generation.
        var usageTimes: [String: [Int: Date]] = [:]
        var rearmsToday = 0
    }

    static let maximumRearmsPerDay = 4
    /// Minutes that stay to be counted after a re-arm, so a re-armed limit
    /// still has usage events to verify against.
    static let minimumRemainingMinutes = 3

    /// The least time k minutes of use can take, with slack for iOS
    /// reporting a little late.
    static func minimumElapsed(minutes k: Int) -> TimeInterval {
        max(0, Double(k) * 48 - 45)
    }

    static func decide(
        _ callback: DailyLimitEvents.Callback,
        state: State,
        limits: [DailyLimitEvents.Limit],
        now: Date
    ) -> Action {
        guard callback.generation == state.generation else { return .ignoreStale }
        guard let limit = limits.first(where: { $0.id == callback.id }) else { return .ignoreUnknown }
        if state.reachedIDs.contains(limit.id) { return .ignoreDuplicate }

        switch callback {
        case .usage(_, _, let minute):
            if state.usageTimes[limit.id]?[minute] != nil { return .ignoreDuplicate }
            return .recordUsage(id: limit.id, minute: minute)
        case .reached:
            let baseline = state.baselines[limit.id] ?? 0
            let times = state.usageTimes[limit.id] ?? [:]
            switch verify(limitMinutes: limit.minutes, baseline: baseline, usageTimes: times, reachedAt: now) {
            case .accept:
                return .block(id: limit.id)
            case .reject:
                guard state.rearmsToday < maximumRearmsPerDay else { return .reject(id: limit.id) }
                var baselines: [String: Int] = [:]
                for other in limits where !state.reachedIDs.contains(other.id) {
                    baselines[other.id] = credibleMinutes(
                        limitMinutes: other.minutes,
                        baseline: state.baselines[other.id] ?? 0,
                        usageTimes: state.usageTimes[other.id] ?? [:]
                    )
                }
                return .rearm(baselines: baselines)
            }
        }
    }

    static func verify(
        limitMinutes: Int,
        baseline: Int,
        usageTimes: [Int: Date],
        reachedAt: Date
    ) -> Verdict {
        let expected = DailyLimitEvents.usageMinutes(limitMinutes: limitMinutes, baseline: baseline)
        let step = DailyLimitEvents.usageStep(limitMinutes: limitMinutes)
        let chain = credibleChain(baseline: baseline, usageTimes: usageTimes, step: step)
        let credited = cappedCredit(chain.top, limitMinutes: limitMinutes, baseline: baseline)

        // The usage events must reach close to the allowance, all at a pace
        // real use allows, and the allowance must follow at that pace too.
        guard chain.isComplete,
              let last = expected.last,
              chain.top >= last - step,
              let lastTime = chain.lastTime,
              reachedAt.timeIntervalSince(lastTime) >= minimumElapsed(minutes: limitMinutes - chain.top)
        else { return .reject(creditedMinutes: credited) }
        return .accept
    }

    /// Minutes worth carrying into a re-arm: the credible part of today's
    /// usage, leaving a few minutes to be counted and verified again.
    static func credibleMinutes(limitMinutes: Int, baseline: Int, usageTimes: [Int: Date]) -> Int {
        let step = DailyLimitEvents.usageStep(limitMinutes: limitMinutes)
        let chain = credibleChain(baseline: baseline, usageTimes: usageTimes, step: step)
        return cappedCredit(chain.top, limitMinutes: limitMinutes, baseline: baseline)
    }

    private static func cappedCredit(_ minutes: Int, limitMinutes: Int, baseline: Int) -> Int {
        max(baseline, min(minutes, limitMinutes - minimumRemainingMinutes))
    }

    /// Walks the usage minutes in order and stops at the first one that
    /// arrived sooner after the previous than that much use could take.
    private static func credibleChain(
        baseline: Int,
        usageTimes: [Int: Date],
        step: Int
    ) -> (top: Int, lastTime: Date?, isComplete: Bool) {
        let minutes = usageTimes.keys.filter { $0 > baseline }.sorted()
        guard let first = minutes.first, first <= baseline + step, let firstTime = usageTimes[first] else {
            return (baseline, nil, minutes.isEmpty)
        }
        var top = first
        var lastTime = firstTime
        for minute in minutes.dropFirst() {
            guard let time = usageTimes[minute],
                  time.timeIntervalSince(lastTime) >= minimumElapsed(minutes: minute - top) else {
                return (top, lastTime, false)
            }
            top = minute
            lastTime = time
        }
        return (top, lastTime, true)
    }
}
