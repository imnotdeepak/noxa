import DeviceActivity
import FamilyControls
import Foundation
import Testing
@testable import Noxa

struct DailyLimitLockTests {
    private let day: TimeInterval = 24 * 60 * 60
    private let anchor = Date(timeIntervalSince1970: 1_800_000_000)

    private func limit(anchor: Date?, minutes: Int = 30) -> DailyLimitConfiguration {
        DailyLimitConfiguration(selection: FamilyActivitySelection(), dailyLimitMinutes: minutes, lockAnchor: anchor)
    }

    @Test func olderLimitsDecodeUnlocked() throws {
        let encoded = try JSONEncoder().encode(limit(anchor: anchor))
        var payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        payload.removeValue(forKey: "lockAnchor")
        let old = try JSONDecoder().decode(
            DailyLimitConfiguration.self, from: JSONSerialization.data(withJSONObject: payload)
        )
        #expect(old.lockAnchor == nil)
        #expect(DailyLimitCommitmentPolicy.state(for: old, at: anchor) == .unlocked)
    }

    @Test func weekLockedThenOneDayOpenThenLockedAgain() {
        let saved = limit(anchor: anchor)
        #expect(DailyLimitCommitmentPolicy.state(for: saved, at: anchor) == .locked(until: anchor + 7 * day))
        #expect(DailyLimitCommitmentPolicy.state(for: saved, at: anchor + 6.9 * day) == .locked(until: anchor + 7 * day))
        #expect(DailyLimitCommitmentPolicy.state(for: saved, at: anchor + 7 * day) == .changeWindow(until: anchor + 8 * day))
        #expect(DailyLimitCommitmentPolicy.state(for: saved, at: anchor + 7.5 * day) == .changeWindow(until: anchor + 8 * day))
        // Left unchanged through the window, it stays for another week.
        #expect(DailyLimitCommitmentPolicy.state(for: saved, at: anchor + 8 * day) == .locked(until: anchor + 15 * day))
        #expect(DailyLimitCommitmentPolicy.state(for: saved, at: anchor + 15.2 * day) == .changeWindow(until: anchor + 16 * day))
    }

    @Test func clockSetBackStaysLocked() {
        let saved = limit(anchor: anchor)
        #expect(DailyLimitCommitmentPolicy.lockedUntil(saved, at: anchor - day) == anchor + 7 * day)
    }

    @Test func onlyLowerAllowancesWhileLocked() {
        let saved = limit(anchor: anchor, minutes: 30)
        #expect(DailyLimitCommitmentPolicy.canChangeMinutes(of: saved, to: 15, at: anchor + day))
        #expect(!DailyLimitCommitmentPolicy.canChangeMinutes(of: saved, to: 45, at: anchor + day))
        #expect(DailyLimitCommitmentPolicy.canChangeMinutes(of: saved, to: 45, at: anchor + 7.5 * day))
    }

    // MARK: Service boundary

    @MainActor private func service(with configuration: DailyLimitConfiguration) throws -> (DailyLimitService, AppGroupStore) {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.DailyLimitLock.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        try store.saveDailyLimitConfigurations([configuration])
        return (DailyLimitService(store: store), store)
    }

    @Test @MainActor func lockedLimitRejectsRaiseDisableAndRemove() throws {
        let locked = limit(anchor: Date(), minutes: 30)
        let (service, store) = try service(with: locked)

        service.updateMinutes(60, for: locked)
        #expect(service.errorMessage?.contains("locked until") == true)
        service.setEnabled(false, for: locked)
        service.remove(locked)
        service.requestStop()

        let saved = try #require(try store.loadDailyLimitConfigurations().first)
        #expect(saved.dailyLimitMinutes == 30)
        #expect(saved.isEnabled)
        #expect(service.hasLockedLimits)

        service.updateMinutes(15, for: locked)
        #expect(try store.loadDailyLimitConfigurations().first?.dailyLimitMinutes == 15)
    }

    @Test @MainActor func changeWindowAllowsEverything() throws {
        let open = limit(anchor: Date().addingTimeInterval(-7.5 * day), minutes: 30)
        let (service, store) = try service(with: open)
        service.updateMinutes(60, for: open)
        #expect(try store.loadDailyLimitConfigurations().first?.dailyLimitMinutes == 60)
        service.remove(open)
        #expect(service.configurations.isEmpty)
    }

    @Test @MainActor func olderLimitStartsItsWeekWhenItsTimeChanges() throws {
        let legacy = limit(anchor: nil, minutes: 30)
        let (service, store) = try service(with: legacy)
        #expect(service.lockState(legacy) == .unlocked)
        service.updateMinutes(45, for: legacy)
        let saved = try #require(try store.loadDailyLimitConfigurations().first)
        #expect(saved.dailyLimitMinutes == 45)
        #expect(saved.lockAnchor != nil)
        #expect(service.lockedUntil(saved) != nil)
    }
}

struct DailyLimitMonitorRegistrationTests {
    private func limit(_ minutes: Int, enabled: Bool = true) -> DailyLimitConfiguration {
        var value = DailyLimitConfiguration(selection: FamilyActivitySelection(), dailyLimitMinutes: minutes)
        value.isEnabled = enabled
        return value
    }

    @Test func signatureTracksEnabledLimitsAndAllowances() {
        let a = limit(10)
        let b = limit(30)
        let signature = NoxaDeviceActivityConfiguration.dailyLimitMonitorSignature(configurations: [a, b])
        #expect(signature.hasPrefix(NoxaDeviceActivityConfiguration.dailyLimitMonitorVersion + "|"))
        // Order doesn't matter, and turned-off limits aren't monitored.
        var off = limit(45)
        off.isEnabled = false
        #expect(NoxaDeviceActivityConfiguration.dailyLimitMonitorSignature(configurations: [b, a, off]) == signature)
        var lowered = a
        lowered.dailyLimitMinutes = 5
        #expect(NoxaDeviceActivityConfiguration.dailyLimitMonitorSignature(configurations: [lowered, b]) != signature)
    }

    // Restarting the monitor on every launch made iOS fire limits early.
    @Test func launchLeavesAMatchingMonitorAlone() {
        let current = NoxaDeviceActivityConfiguration.dailyLimitMonitorSignature(configurations: [limit(10)])
        #expect(DailyLimitService.launchAction(isRegistered: true, savedSignature: current, currentSignature: current) == .keep)
        let changed = NoxaDeviceActivityConfiguration.dailyLimitMonitorSignature(configurations: [limit(20)])
        #expect(DailyLimitService.launchAction(isRegistered: true, savedSignature: changed, currentSignature: current) == .reregister)
    }

    // Older monitors counted earlier use, which fired limits early.
    @Test func olderMonitorsAreReregistered() {
        let limit = limit(10)
        let current = NoxaDeviceActivityConfiguration.dailyLimitMonitorSignature(configurations: [limit])
        #expect(DailyLimitService.launchAction(isRegistered: true, savedSignature: nil, currentSignature: current) == .reregister)
        let v1 = "v1|\(limit.id.uuidString.lowercased()):10"
        #expect(DailyLimitService.launchAction(isRegistered: true, savedSignature: v1, currentSignature: current) == .reregister)
    }

    @Test func usageEventsCountEachMinuteBelowTheAllowance() {
        #expect(DailyLimitEvents.usageMinutes(limitMinutes: 5) == [1, 2, 3, 4])
        #expect(DailyLimitEvents.usageMinutes(limitMinutes: 60).count == 59)
        // Limits saved before the one-hour cap count every 5 minutes.
        #expect(DailyLimitEvents.usageMinutes(limitMinutes: 120).prefix(3) == [1, 6, 11])
        // A re-armed limit only reports the minutes after those credited.
        #expect(DailyLimitEvents.usageMinutes(limitMinutes: 10, baseline: 6) == [7, 8, 9])
    }

    @Test func newAllowancesAreCappedAtAnHour() {
        #expect(limit(240).dailyLimitMinutes == 60)
    }

    // iOS dropped the monitor on device while every limit was still on.
    @Test func droppedMonitorIsRestoredUnlessStopped() {
        let current = NoxaDeviceActivityConfiguration.dailyLimitMonitorSignature(configurations: [limit(10)])
        #expect(DailyLimitService.launchAction(isRegistered: false, savedSignature: current, currentSignature: current) == .reregister)
        // Stopping clears the signature, so stopped limits stay stopped.
        #expect(DailyLimitService.launchAction(isRegistered: false, savedSignature: nil, currentSignature: current) == .keep)
    }
}

/// Replays monitor callbacks through DailyLimitCallbackVerifier, applying each
/// decision the way NoxaMonitor does.
struct DailyLimitCallbackVerificationTests {
    private let noon = Date(timeIntervalSince1970: 1_800_000_000)
    private let limits = [
        DailyLimitEvents.Limit(id: "a", minutes: 10),
        DailyLimitEvents.Limit(id: "b", minutes: 10),
        DailyLimitEvents.Limit(id: "c", minutes: 15),
        DailyLimitEvents.Limit(id: "d", minutes: 15)
    ]

    @discardableResult
    private func deliver(
        _ callback: DailyLimitEvents.Callback,
        at date: Date,
        to state: inout DailyLimitCallbackVerifier.State
    ) -> DailyLimitCallbackVerifier.Action {
        let action = DailyLimitCallbackVerifier.decide(callback, state: state, limits: limits, now: date)
        switch action {
        case .recordUsage(let id, let minute):
            state.usageTimes[id, default: [:]][minute] = date
        case .block(let id):
            state.reachedIDs.insert(id)
        case .rearm(let baselines):
            state.generation += 1
            state.baselines = baselines.filter { $0.value > 0 }
            state.usageTimes = [:]
            state.rearmsToday += 1
        case .ignoreStale, .ignoreDuplicate, .ignoreUnknown, .reject:
            break
        }
        return action
    }

    /// Reports every usage minute of a limit one minute apart, then reaches it.
    private func useSteadily(
        _ limit: DailyLimitEvents.Limit,
        from start: Date,
        baseline: Int = 0,
        state: inout DailyLimitCallbackVerifier.State
    ) -> DailyLimitCallbackVerifier.Action {
        let generation = state.generation
        for minute in DailyLimitEvents.usageMinutes(limitMinutes: limit.minutes, baseline: baseline) {
            let at = start.addingTimeInterval(Double(minute - baseline) * 60)
            deliver(.usage(id: limit.id, generation: generation, minute: minute), at: at, to: &state)
        }
        let reachedAt = start.addingTimeInterval(Double(limit.minutes - baseline) * 60)
        return deliver(.reached(id: limit.id, generation: generation), at: reachedAt, to: &state)
    }

    // On device, iOS reported four limits and every usage minute below them
    // within one second while Screen Time showed little use.
    @Test func fourSimultaneousEarlyCallbacksBlockNothing() {
        var state = DailyLimitCallbackVerifier.State(generation: 3)
        var actions: [DailyLimitCallbackVerifier.Action] = []
        for limit in limits {
            for minute in DailyLimitEvents.usageMinutes(limitMinutes: limit.minutes) {
                deliver(.usage(id: limit.id, generation: 3, minute: minute), at: noon, to: &state)
            }
        }
        for limit in limits {
            actions.append(deliver(.reached(id: limit.id, generation: 3), at: noon.addingTimeInterval(1), to: &state))
        }

        #expect(state.reachedIDs.isEmpty)
        guard case .rearm(let baselines) = actions[0] else {
            Issue.record("Expected the first early callback to re-arm, got \(actions[0])")
            return
        }
        // Only the first usage minute of each burst is believable.
        #expect(baselines.values.allSatisfy { $0 <= 1 })
        // The other three were registered under the old generation.
        #expect(actions.dropFirst().allSatisfy { $0 == .ignoreStale })
    }

    @Test func earlyCallbackWithoutUsageEventsIsRejected() {
        var state = DailyLimitCallbackVerifier.State(generation: 1)
        let action = deliver(.reached(id: "a", generation: 1), at: noon, to: &state)
        #expect(action == .rearm(baselines: ["a": 0, "b": 0, "c": 0, "d": 0]))
        #expect(state.reachedIDs.isEmpty)
    }

    @Test func steadyUseBlocksAtTheAllowance() {
        var state = DailyLimitCallbackVerifier.State(generation: 1)
        #expect(useSteadily(limits[0], from: noon, state: &state) == .block(id: "a"))
        #expect(state.reachedIDs == ["a"])
        // iOS repeating the callback changes nothing.
        let later = noon.addingTimeInterval(3_600)
        #expect(deliver(.reached(id: "a", generation: 1), at: later, to: &state) == .ignoreDuplicate)
    }

    @Test func limitStillBlocksAfterAnEarlyBurstIsRejected() {
        var state = DailyLimitCallbackVerifier.State(generation: 1)
        for minute in 1...9 {
            deliver(.usage(id: "a", generation: 1, minute: minute), at: noon, to: &state)
        }
        #expect(deliver(.reached(id: "a", generation: 1), at: noon, to: &state) == .rearm(baselines: ["a": 1, "b": 0, "c": 0, "d": 0]))
        #expect(state.generation == 2)

        // Nine more minutes of real use, counted from the credited minute.
        let start = noon.addingTimeInterval(600)
        #expect(useSteadily(limits[0], from: start, baseline: 1, state: &state) == .block(id: "a"))
    }

    @Test func callbacksFromAnEarlierRegistrationAreIgnored() {
        var state = DailyLimitCallbackVerifier.State(generation: 2)
        #expect(deliver(.reached(id: "a", generation: 1), at: noon, to: &state) == .ignoreStale)
        #expect(deliver(.usage(id: "a", generation: 1, minute: 4), at: noon, to: &state) == .ignoreStale)
        #expect(state.usageTimes.isEmpty)
    }

    // iOS can hold callbacks back and deliver several at once. The limit is
    // re-armed with the minutes that arrived at a believable pace.
    @Test func lateBatchCreditsTheSteadyMinutes() {
        var state = DailyLimitCallbackVerifier.State(generation: 1)
        for minute in 1...6 {
            deliver(.usage(id: "a", generation: 1, minute: minute), at: noon.addingTimeInterval(Double(minute) * 60), to: &state)
        }
        let batch = noon.addingTimeInterval(600)
        for minute in 7...9 {
            deliver(.usage(id: "a", generation: 1, minute: minute), at: batch, to: &state)
        }
        let action = deliver(.reached(id: "a", generation: 1), at: batch, to: &state)
        // Minute 7 came four minutes after minute 6; 8 and 9 came with it.
        #expect(action == .rearm(baselines: ["a": 7, "b": 0, "c": 0, "d": 0]))
    }

    @Test func repeatedEarlyCallbacksStopReArmingForTheDay() {
        var state = DailyLimitCallbackVerifier.State(generation: 1)
        state.rearmsToday = DailyLimitCallbackVerifier.maximumRearmsPerDay
        #expect(deliver(.reached(id: "a", generation: 1), at: noon, to: &state) == .reject(id: "a"))
        #expect(state.reachedIDs.isEmpty)
    }

    @Test func eventNamesCarryTheirGeneration() {
        #expect(DailyLimitEvents.parse(DailyLimitEvents.reachedName(id: "a", generation: 7)) == .reached(id: "a", generation: 7))
        #expect(DailyLimitEvents.parse(DailyLimitEvents.usageName(id: "a", generation: 7, minute: 4))
            == .usage(id: "a", generation: 7, minute: 4))
        // Monitors registered before generations existed.
        #expect(DailyLimitEvents.parse(.init("noxa.daily.limit.a")) == .reached(id: "a", generation: 0))
        #expect(DailyLimitEvents.parse(.init("noxa.daily.usage.a.4")) == .usage(id: "a", generation: 0, minute: 4))
        #expect(DailyLimitEvents.parse(.init("noxa.focus.session")) == nil)
    }
}
