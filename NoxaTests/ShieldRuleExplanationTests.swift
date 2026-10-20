import FamilyControls
import Foundation
import Testing
@testable import Noxa

@MainActor struct ShieldRuleExplanationTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 10))!
    }

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "NoxaTests.Shield.\(UUID())"))
    }

    @Test func focusExplanationUsesMatchingTargetAndIgnoresExpiredSession() throws {
        let defaults = try defaults()
        let end = now.addingTimeInterval(1_800)
        let session = ActiveSessionRecord(
            startedAt: now.addingTimeInterval(-300),
            plannedEndAt: end,
            plannedDurationSeconds: 2_100,
            outcome: .active
        )
        defaults.set(
            try JSONEncoder().encode(NoxaLocalSnapshot(sessionEngineState: .active, activeSession: session)),
            forKey: "noxa.localSnapshot"
        )
        defaults.set(
            try JSONEncoder().encode(FocusSessionRestrictionConfiguration(
                selection: FamilyActivitySelection(),
                websiteDomains: ["example.com"],
                intention: "Write the outline"
            )),
            forKey: "noxa.focusSessionRestrictions"
        )

        let matching = ShieldRuleExplanation.domain("www.example.com", defaults: defaults, now: now, calendar: calendar)
        #expect(matching?.contains("Focus until") == true)
        #expect(matching?.contains("Write the outline") == true)
        #expect(ShieldRuleExplanation.domain("notexample.com", defaults: defaults, now: now, calendar: calendar) == nil)
        #expect(ShieldRuleExplanation.domain("example.com", defaults: defaults, now: end, calendar: calendar) == nil)
    }

    @Test func overlappingScheduleKeepsOtherRuleWarning() throws {
        let defaults = try defaults()
        let rule = ScheduleRule(
            name: "Morning study",
            mode: .blockedHours,
            selection: FamilyActivitySelection(),
            websiteDomains: ["example.com"],
            weekdays: [3],
            startMinutes: 9 * 60,
            endMinutes: 11 * 60
        )
        defaults.set(
            try JSONEncoder().encode(ScheduleRuleArchive(version: 2, rules: [rule])),
            forKey: "noxa.scheduleRules.v2"
        )
        let end = now.addingTimeInterval(1_800)
        let session = ActiveSessionRecord(
            startedAt: now.addingTimeInterval(-300),
            plannedEndAt: end,
            plannedDurationSeconds: 2_100,
            outcome: .active
        )
        defaults.set(
            try JSONEncoder().encode(NoxaLocalSnapshot(sessionEngineState: .active, activeSession: session)),
            forKey: "noxa.localSnapshot"
        )
        defaults.set(
            try JSONEncoder().encode(FocusSessionRestrictionConfiguration(
                selection: FamilyActivitySelection(), websiteDomains: ["example.com"]
            )),
            forKey: "noxa.focusSessionRestrictions"
        )

        let overlap = ShieldRuleExplanation.domain("example.com", defaults: defaults, now: now, calendar: calendar)
        #expect(overlap?.contains("Focus until") == true)
        #expect(overlap?.contains("Morning study until") == true)
        #expect(overlap?.contains("Other rules may still apply") == true)

        let scheduleOnly = ShieldRuleExplanation.domain("example.com", defaults: defaults, now: end, calendar: calendar)
        #expect(scheduleOnly?.contains("Morning study until") == true)
        #expect(scheduleOnly?.contains("Focus until") == false)
    }

    @Test func manualAndWebsiteListsIdentifyOnlyMatchingDomains() throws {
        let defaults = try defaults()
        defaults.set(
            try JSONEncoder().encode(ManualShieldConfiguration(
                selection: FamilyActivitySelection(), websiteDomains: ["manual.example"]
            )),
            forKey: "noxa.manualShield"
        )
        defaults.set(true, forKey: "noxa.websiteShieldActive")
        defaults.set(try JSONEncoder().encode(["blocked.example"]), forKey: "noxa.websiteBlocklist")

        #expect(ShieldRuleExplanation.domain("manual.example", defaults: defaults, now: now, calendar: calendar)?
            .contains("Manually blocked") == true)
        #expect(ShieldRuleExplanation.domain("blocked.example", defaults: defaults, now: now, calendar: calendar)?
            .contains("blocked websites list") == true)
        #expect(ShieldRuleExplanation.domain("allowed.example", defaults: defaults, now: now, calendar: calendar) == nil)
    }

    @Test func dailyLimitExplanationRequiresTodaysReachedEvent() throws {
        let defaults = try defaults()
        let limit = DailyLimitConfiguration(selection: FamilyActivitySelection(), dailyLimitMinutes: 30)
        defaults.set(try JSONEncoder().encode([limit]), forKey: "noxa.dailyLimits")
        defaults.set(
            ["noxa.daily.limit.\(limit.id.uuidString.lowercased())"],
            forKey: "noxa.dailyLimitReachedEvents"
        )
        defaults.set("1-2026-10-20", forKey: "noxa.dailyLimitResetDay")

        let current = ShieldRuleExplanation.explain(defaults: defaults, now: now, calendar: calendar) { _, _ in true }
        #expect(current?.contains("Daily allowance reached") == true)

        defaults.set("1-2026-10-19", forKey: "noxa.dailyLimitResetDay")
        let stale = ShieldRuleExplanation.explain(defaults: defaults, now: now, calendar: calendar) { _, _ in true }
        #expect(stale == nil)
    }
}
