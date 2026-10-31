import FamilyControls
import Foundation
import Testing
@testable import Noxa

struct ScheduleLockTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, month: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private func rule(
        mode: ScheduleRule.Mode = .blockedHours,
        start: Int = 21 * 60,
        end: Int = 23 * 60,
        weekdays: Set<Int> = Set(1...7),
        locked: Bool = true,
        anchor: Date? = nil
    ) -> ScheduleRule {
        // By default the weekly lock is in its open day on October 28, so
        // these tests see only the active-window lock.
        ScheduleRule(
            name: "Evening",
            mode: mode,
            selection: FamilyActivitySelection(),
            websiteDomains: ["example.com"],
            weekdays: weekdays,
            startMinutes: start,
            endMinutes: end,
            lockWhileActive: locked,
            lockAnchor: anchor ?? date(21, 0)
        )
    }

    @Test func olderSchedulesStillLock() throws {
        let encoded = try JSONEncoder().encode(rule())
        var payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        payload.removeValue(forKey: "lockWhileActive")
        let old = try JSONDecoder().decode(
            ScheduleRule.self, from: JSONSerialization.data(withJSONObject: payload)
        )
        #expect(!old.lockWhileActive)
        // The lock is mandatory, so the old flag no longer opts out.
        #expect(ScheduleCommitmentPolicy.lockedUntil(old, at: date(28, 22), calendar: calendar) == date(28, 23))
    }

    @Test func lockedBlockedHoursProtectOnlyTheActiveWindow() {
        let schedule = rule()
        #expect(ScheduleCommitmentPolicy.lockedUntil(schedule, at: date(28, 22), calendar: calendar) == date(28, 23))
        #expect(ScheduleCommitmentPolicy.lockedUntil(schedule, at: date(28, 20), calendar: calendar) == nil)
        #expect(ScheduleCommitmentPolicy.lockedUntil(schedule, at: date(28, 23, 1), calendar: calendar) == nil)
    }

    @Test func allowedHoursAndDisabledSchedulesAreNeverLocked() {
        #expect(ScheduleCommitmentPolicy.lockedUntil(rule(locked: false), at: date(28, 22), calendar: calendar) == date(28, 23))
        let allowed = rule(mode: .allowedHours, start: 9 * 60, end: 10 * 60)
        #expect(ScheduleCommitmentPolicy.lockedUntil(allowed, at: date(28, 22), calendar: calendar) == nil)
        var disabled = rule()
        disabled.isEnabled = false
        #expect(ScheduleCommitmentPolicy.lockedUntil(disabled, at: date(28, 22), calendar: calendar) == nil)
    }

    @Test func weakeningEditsAreRejectedWhileLocked() {
        let saved = rule()
        let now = date(28, 22)
        var shorter = saved
        shorter.endMinutes = 22 * 60 + 30
        var fewerTargets = saved
        fewerTargets.websiteDomains = []
        var otherMode = saved
        otherMode.mode = .allowedHours
        var fewerDays = saved
        fewerDays.weekdays = [2]
        for proposed in [shorter, fewerTargets, otherMode, fewerDays] {
            #expect(ScheduleCommitmentPolicy.update(from: saved, to: proposed, at: now, calendar: calendar)
                == .locked(until: date(28, 23)))
        }
        #expect(ScheduleCommitmentPolicy.removal(of: saved, at: now, calendar: calendar)
            == .locked(until: date(28, 23)))
    }

    @Test func safeEditsAreAllowedWhileLocked() {
        let saved = rule()
        var renamed = saved
        renamed.name = "Night"
        renamed.notifyAtStart = true
        renamed.notifyAtEnd = true
        // Re-saving an older schedule sets the flag; that isn't a weakening.
        renamed.lockWhileActive = false
        #expect(ScheduleCommitmentPolicy.update(from: saved, to: renamed, at: date(28, 22), calendar: calendar) == .allowed)
    }

    @Test func everythingIsEditableAfterTheWindowEnds() {
        let saved = rule()
        var shorter = saved
        shorter.endMinutes = 22 * 60
        #expect(ScheduleCommitmentPolicy.update(from: saved, to: shorter, at: date(28, 23, 5), calendar: calendar) == .allowed)
        #expect(ScheduleCommitmentPolicy.removal(of: saved, at: date(28, 23, 5), calendar: calendar) == .allowed)
    }

    @Test func overnightLockReleasesOnTheNextMorningEvenOnAnUnselectedDay() {
        // Wednesday only, 10 PM to 6 AM; Thursday is not selected.
        let saved = rule(start: 22 * 60, end: 6 * 60, weekdays: [4])
        #expect(ScheduleCommitmentPolicy.lockedUntil(saved, at: date(28, 23), calendar: calendar) == date(29, 6))
        #expect(ScheduleCommitmentPolicy.lockedUntil(saved, at: date(29, 3), calendar: calendar) == date(29, 6))
        #expect(ScheduleCommitmentPolicy.lockedUntil(saved, at: date(29, 6, 1), calendar: calendar) == nil)
    }

    @Test func daylightSavingNightStillReleases() throws {
        // US clocks fall back at 2 AM on November 1, 2026.
        let saved = rule(start: 23 * 60, end: 3 * 60)
        let release = try #require(ScheduleCommitmentPolicy.lockedUntil(
            saved, at: date(1, 0, 30, month: 11), calendar: calendar
        ))
        #expect(release > date(1, 0, 30, month: 11))
        #expect(release.timeIntervalSince(date(1, 0, 30, month: 11)) <= 24 * 60 * 60)
        #expect(ScheduleCommitmentPolicy.lockedUntil(saved, at: release.addingTimeInterval(60), calendar: calendar) == nil)
    }

    @Test func upcomingWindowIsShownBeforeLocking() throws {
        let saved = rule()
        let next = try #require(ScheduleCommitmentPolicy.upcomingWindow(for: saved, after: date(28, 12), calendar: calendar))
        #expect(next.start == date(28, 21))
        #expect(next.end == date(28, 23))
        let active = try #require(ScheduleCommitmentPolicy.upcomingWindow(for: saved, after: date(28, 22), calendar: calendar))
        #expect(active.start == nil)
        #expect(active.end == date(28, 23))
    }

    // MARK: Service boundary

    @MainActor private func serviceWithActiveRule(locked: Bool) throws -> (RestrictionScheduleService, AppGroupStore, ScheduleRule) {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.ScheduleLock.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        let local = Calendar.autoupdatingCurrent
        let parts = local.dateComponents([.hour, .minute], from: Date())
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let active = ScheduleRule(
            name: "Now",
            mode: .blockedHours,
            selection: FamilyActivitySelection(),
            websiteDomains: ["example.com"],
            startMinutes: (now - 60 + 1_440) % 1_440,
            endMinutes: (now + 60) % 1_440,
            lockWhileActive: locked
        )
        try store.saveScheduleRules([active])
        return (RestrictionScheduleService(store: store), store, active)
    }

    @Test @MainActor func serviceRejectsDisableRemoveAndWeakeningWhileLocked() throws {
        let (service, store, active) = try serviceWithActiveRule(locked: true)
        #expect(service.lockedUntil(active) != nil)

        service.setEnabled(false, for: active)
        #expect(service.errorMessage?.contains("locked until") == true)
        service.remove(active)
        service.requestDisableAll()
        var weaker = active
        weaker.websiteDomains = ["other.com"]
        service.update(weaker)

        let saved = try #require(store.loadScheduleRules().first)
        #expect(saved.isEnabled)
        #expect(saved.websiteDomains == ["example.com"])
        #expect(service.configurations.count == 1)

        service.rename(active, to: "Deep work")
        #expect(try store.loadScheduleRules().first?.name == "Deep work")
    }

    @Test @MainActor func olderUnlockedScheduleIsLockedToo() throws {
        let (service, store, active) = try serviceWithActiveRule(locked: false)
        #expect(service.lockedUntil(active) != nil)
        service.setEnabled(false, for: active)
        #expect(try store.loadScheduleRules().first?.isEnabled == true)
    }

    @Test @MainActor func newBlockedHoursSchedulesAlwaysSaveLocked() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.ScheduleLockNew.\(UUID())"))
        let service = RestrictionScheduleService(store: AppGroupStore(defaults: defaults))
        service.add(
            name: "Evening",
            mode: .blockedHours,
            selection: FamilyActivitySelection(),
            websiteDomains: ["example.com"],
            weekdays: Set(1...7),
            start: Date(),
            end: Date().addingTimeInterval(3_600),
            lockWhileActive: false
        )
        #expect(service.configurations.first?.lockWhileActive == true)
    }

    @Test @MainActor func allowedHoursCannotBeSavedLocked() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.ScheduleLockAllowed.\(UUID())"))
        let service = RestrictionScheduleService(store: AppGroupStore(defaults: defaults))
        service.add(
            name: "Allowed",
            mode: .allowedHours,
            selection: FamilyActivitySelection(),
            websiteDomains: ["example.com"],
            weekdays: Set(1...7),
            start: Date(),
            end: Date().addingTimeInterval(3_600),
            lockWhileActive: true
        )
        #expect(service.configurations.first?.lockWhileActive == false)
    }

    // MARK: Weekly lock

    @Test func scheduleLocksForAWeekThenOpensForADay() {
        let saved = rule(start: 9 * 60, end: 10 * 60, anchor: date(1, 12))
        // Outside its blocking hours, the week alone keeps it locked.
        #expect(ScheduleCommitmentPolicy.removal(of: saved, at: date(5, 12), calendar: calendar)
            == .locked(until: date(8, 12)))
        #expect(ScheduleCommitmentPolicy.weeklyState(saved, at: date(8, 13))
            == .changeWindow(until: date(9, 12)))
        #expect(ScheduleCommitmentPolicy.removal(of: saved, at: date(8, 13), calendar: calendar) == .allowed)
        // Left alone through the open day, it locks for another week.
        #expect(ScheduleCommitmentPolicy.weeklyState(saved, at: date(9, 13))
            == .locked(until: date(16, 12)))
    }

    @Test func weeklyLockStillAllowsRenamesAndReminders() {
        let saved = rule(start: 9 * 60, end: 10 * 60, anchor: date(1, 12))
        var renamed = saved
        renamed.name = "Mornings"
        renamed.notifyAtEnd = true
        #expect(ScheduleCommitmentPolicy.update(from: saved, to: renamed, at: date(5, 12), calendar: calendar) == .allowed)
        var later = saved
        later.startMinutes = 11 * 60
        #expect(ScheduleCommitmentPolicy.update(from: saved, to: later, at: date(5, 12), calendar: calendar)
            == .locked(until: date(8, 12)))
    }

    @Test func offAndAllowedHoursSchedulesAreNotWeeklyLocked() {
        var off = rule(start: 9 * 60, end: 10 * 60, anchor: date(1, 12))
        off.isEnabled = false
        #expect(ScheduleCommitmentPolicy.weeklyState(off, at: date(5, 12)) == .unlocked)
        let allowed = rule(mode: .allowedHours, start: 9 * 60, end: 10 * 60, anchor: date(1, 12))
        #expect(ScheduleCommitmentPolicy.weeklyState(allowed, at: date(5, 12)) == .unlocked)
    }

    @Test func olderSchedulesUseTheirCreationDate() throws {
        let saved = rule(anchor: date(1, 12))
        let encoded = try JSONEncoder().encode(saved)
        var payload = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        payload.removeValue(forKey: "lockAnchor")
        let old = try JSONDecoder().decode(ScheduleRule.self, from: JSONSerialization.data(withJSONObject: payload))
        #expect(old.lockAnchor == old.createdAt)
    }
}
