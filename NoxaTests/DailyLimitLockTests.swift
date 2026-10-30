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
