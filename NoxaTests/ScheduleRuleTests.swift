import FamilyControls
import Foundation
import Testing
@testable import Noxa

struct ScheduleRuleTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test @MainActor func migratesLegacySchedulesWithoutChangingTheirWindow() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.ScheduleMigration.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        let pending = PendingScheduleRelaxation(
            action: .disable,
            requestedAt: date(20, 9),
            effectiveAt: date(21, 9)
        )
        let legacy = RestrictionScheduleConfiguration(
            selection: FamilyActivitySelection(),
            allowedStartMinutes: 9 * 60,
            allowedEndMinutes: 17 * 60,
            pendingRelaxation: pending
        )
        try store.saveRestrictionSchedules([legacy])

        let migrated = try #require(store.loadScheduleRules().first)
        #expect(migrated.id == legacy.id)
        #expect(migrated.name == "Allowed hours, every day")
        #expect(migrated.mode == .allowedHours)
        #expect(migrated.weekdays == Set(1...7))
        #expect(migrated.pendingLegacyRelaxation == pending)
        #expect(ScheduleRuleEvaluator.isBlocking(migrated, at: date(20, 8), calendar: calendar))
        #expect(!ScheduleRuleEvaluator.isBlocking(migrated, at: date(20, 12), calendar: calendar))
        #expect(ScheduleRuleEvaluator.isBlocking(migrated, at: date(20, 18), calendar: calendar))

        try store.saveScheduleRules([migrated])
        #expect(try store.loadScheduleRules() == [migrated])
        #expect(try store.loadRestrictionSchedules() == [legacy])
    }

    @Test func blockedOvernightWindowContinuesIntoUnselectedDay() {
        let rule = ScheduleRule(
            name: "Monday night",
            mode: .blockedHours,
            selection: FamilyActivitySelection(),
            weekdays: [2],
            startMinutes: 22 * 60,
            endMinutes: 7 * 60
        )
        #expect(!ScheduleRuleEvaluator.isBlocking(rule, at: date(19, 21), calendar: calendar))
        #expect(ScheduleRuleEvaluator.isBlocking(rule, at: date(19, 23), calendar: calendar))
        #expect(ScheduleRuleEvaluator.isBlocking(rule, at: date(20, 6), calendar: calendar))
        #expect(!ScheduleRuleEvaluator.isBlocking(rule, at: date(20, 7), calendar: calendar))
    }

    @Test func allowedOvernightWindowUsesUnionOfAdjacentSelectedDays() {
        let rule = ScheduleRule(
            name: "Evenings",
            mode: .allowedHours,
            selection: FamilyActivitySelection(),
            weekdays: [2, 3],
            startMinutes: 22 * 60,
            endMinutes: 7 * 60
        )
        #expect(ScheduleRuleEvaluator.isBlocking(rule, at: date(19, 12), calendar: calendar))
        #expect(!ScheduleRuleEvaluator.isBlocking(rule, at: date(20, 6), calendar: calendar))
        #expect(ScheduleRuleEvaluator.isBlocking(rule, at: date(20, 12), calendar: calendar))
        #expect(!ScheduleRuleEvaluator.isBlocking(rule, at: date(20, 23), calendar: calendar))
        #expect(!ScheduleRuleEvaluator.isBlocking(rule, at: date(21, 6), calendar: calendar))
    }

    @Test func anAllowedScheduleCannotReleaseAnotherScheduleOrFocusBlock() {
        let allowed = ScheduleRule(
            name: "Available during class",
            mode: .allowedHours,
            selection: FamilyActivitySelection(),
            weekdays: [2],
            startMinutes: 9 * 60,
            endMinutes: 17 * 60
        )
        let blocked = ScheduleRule(
            name: "Lunch block",
            mode: .blockedHours,
            selection: FamilyActivitySelection(),
            weekdays: [2],
            startMinutes: 12 * 60,
            endMinutes: 13 * 60
        )
        let atLunch = date(19, 12, 30)
        let target = "Instagram"
        let rules = [allowed, blocked].map { schedule in
            RestrictionRule(
                id: RestrictionRuleID(source: .schedule, value: schedule.id),
                effect: ScheduleRuleEvaluator.isBlocking(schedule, at: atLunch, calendar: calendar)
                    ? .block : .allow,
                targets: [target]
            )
        } + [RestrictionRule(
            id: RestrictionRuleID(source: .focusSession, value: UUID()),
            effect: .block,
            targets: [target]
        )]
        let result = RestrictionRuleEvaluator.evaluate(rules)
        #expect(result.blockedTargets == [target])
        #expect(result.owners(for: target).count == 2)
    }

    @Test func scheduleUsesTheDevicesCurrentLocalTimeZone() {
        let rule = ScheduleRule(
            name: "Morning",
            mode: .blockedHours,
            selection: FamilyActivitySelection(),
            weekdays: [2],
            startMinutes: 9 * 60,
            endMinutes: 10 * 60
        )
        var newYork = calendar
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let instant = date(19, 13, 30)
        #expect(ScheduleRuleEvaluator.isBlocking(rule, at: instant, calendar: newYork))
        #expect(!ScheduleRuleEvaluator.isBlocking(rule, at: instant, calendar: calendar))
    }

    @Test @MainActor func dailyLimitEditsIgnoreAnOldHardLock() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.DailyLimitEdit.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        let limit = DailyLimitConfiguration(
            selection: FamilyActivitySelection(),
            dailyLimitMinutes: 30
        )
        try store.saveDailyLimitConfigurations([limit])
        defaults.set(
            NoxaDeviceActivityConfiguration.dailyLimitDayStamp(),
            forKey: "noxa.dailyLimitHardLockDay"
        )

        let service = DailyLimitService(store: store)
        service.updateMinutes(45, for: limit)
        service.setEnabled(false, for: limit)
        #expect(service.configurations.first?.dailyLimitMinutes == 45)
        #expect(service.configurations.first?.isEnabled == false)
        #expect(try store.loadDailyLimitConfigurations().first?.isEnabled == false)
        service.remove(limit)
        #expect(service.configurations.isEmpty)
    }

    @Test @MainActor func scheduleCanBeDisabledImmediatelyDespitePendingLegacyChange() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.ScheduleEdit.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        let pending = PendingScheduleRelaxation(
            action: .remove,
            requestedAt: Date(),
            effectiveAt: Date().addingTimeInterval(86_400)
        )
        let schedule = RestrictionScheduleConfiguration(
            selection: FamilyActivitySelection(),
            allowedStartMinutes: 9 * 60,
            allowedEndMinutes: 17 * 60,
            pendingRelaxation: pending
        )
        try store.saveRestrictionSchedules([schedule])

        let service = RestrictionScheduleService(store: store)
        service.setEnabled(false, for: schedule)
        let updated = try #require(store.loadRestrictionSchedules().first)
        #expect(!updated.isEnabled)
        #expect(updated.pendingRelaxation == nil)
    }

    @Test @MainActor func renamedLegacyScheduleKeepsItsNameDuringMigration() throws {
        let defaults = try #require(UserDefaults(suiteName: "NoxaTests.ScheduleRename.\(UUID())"))
        let store = AppGroupStore(defaults: defaults)
        let schedule = RestrictionScheduleConfiguration(
            selection: FamilyActivitySelection(),
            allowedStartMinutes: 9 * 60,
            allowedEndMinutes: 17 * 60
        )
        try store.saveRestrictionSchedules([schedule])

        let service = RestrictionScheduleService(store: store)
        service.rename(schedule, to: "  Study hours  ")
        #expect(service.configurations.first?.name == "Study hours")
        #expect(try store.loadScheduleRules().first?.name == "Study hours")
    }
}
