import FamilyControls
import Foundation

struct ScheduleRuleArchive: Codable, Equatable, Sendable {
    let version: Int
    let rules: [ScheduleRule]
}

enum ScheduleRuleArchiveError: Error {
    case unsupportedVersion
}

/// A local-time schedule. Weekdays use Calendar's Sunday = 1 ... Saturday = 7.
struct ScheduleRule: Codable, Equatable, Identifiable, Sendable {
    enum Mode: String, Codable, Hashable, Sendable {
        case blockedHours
        case allowedHours
    }

    let id: UUID
    var name: String
    var mode: Mode
    var selection: FamilyActivitySelection
    var websiteDomains: [String]
    var weekdays: Set<Int>
    var startMinutes: Int
    var endMinutes: Int
    var createdAt: Date
    var isEnabled: Bool
    var pendingLegacyRelaxation: PendingScheduleRelaxation?

    init(
        id: UUID = UUID(),
        name: String,
        mode: Mode,
        selection: FamilyActivitySelection,
        websiteDomains: [String] = [],
        weekdays: Set<Int> = Set(1...7),
        startMinutes: Int,
        endMinutes: Int,
        createdAt: Date = Date(),
        isEnabled: Bool = true,
        pendingLegacyRelaxation: PendingScheduleRelaxation? = nil
    ) {
        self.id = id
        self.name = name
        self.mode = mode
        self.selection = selection
        self.websiteDomains = websiteDomains
        self.weekdays = weekdays
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.createdAt = createdAt
        self.isEnabled = isEnabled
        self.pendingLegacyRelaxation = pendingLegacyRelaxation
    }

    init(legacy: RestrictionScheduleConfiguration) {
        let rawName = legacy.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let migratedName = rawName?.isEmpty == true ? nil : rawName
        self.init(
            id: legacy.id,
            name: migratedName ?? "Allowed hours, every day",
            mode: .allowedHours,
            selection: legacy.selection,
            weekdays: Set(1...7),
            startMinutes: legacy.allowedStartMinutes,
            endMinutes: legacy.allowedEndMinutes,
            createdAt: legacy.createdAt,
            isEnabled: legacy.isEnabled,
            pendingLegacyRelaxation: legacy.pendingRelaxation
        )
    }
}

/// A selected weekday is the day on which the interval starts. Overnight
/// intervals continue into the following day, including an unselected day.
enum ScheduleRuleEvaluator {
    /// Wake at every possible local-time transition. Daily wakes keep the
    /// number of Device Activity monitors fixed when weekdays are edited.
    static func dailyWakeMinutes(for rule: ScheduleRule) -> [Int] {
        var minutes: Set<Int> = [rule.startMinutes, rule.endMinutes]
        if rule.mode == .allowedHours { minutes.insert(0) }
        return minutes.filter { (0..<1_440).contains($0) }.sorted()
    }

    static func isBlocking(_ rule: ScheduleRule, at date: Date, calendar: Calendar) -> Bool {
        guard rule.isEnabled, rule.weekdays.contains(where: { (1...7).contains($0) }),
              (0..<1_440).contains(rule.startMinutes),
              (0..<1_440).contains(rule.endMinutes),
              rule.startMinutes != rule.endMinutes else { return false }
        if let pending = rule.pendingLegacyRelaxation, pending.effectiveAt <= date {
            return false
        }

        let weekday = calendar.component(.weekday, from: date)
        let minutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date)
            .map { calendar.component(.weekday, from: $0) }
        let startsToday = rule.weekdays.contains(weekday)
        let startsYesterday = yesterday.map(rule.weekdays.contains) ?? false
        let overnight = rule.endMinutes < rule.startMinutes

        let withinWindow: Bool
        if overnight {
            withinWindow = (startsToday && minutes >= rule.startMinutes)
                || (startsYesterday && minutes < rule.endMinutes)
        } else {
            withinWindow = startsToday
                && minutes >= rule.startMinutes
                && minutes < rule.endMinutes
        }

        switch rule.mode {
        case .blockedHours:
            return withinWindow
        case .allowedHours:
            return startsToday && !withinWindow
        }
    }

    static func nextChange(
        for rule: ScheduleRule,
        after date: Date,
        calendar: Calendar
    ) -> Date? {
        guard rule.isEnabled else { return nil }
        var candidates: Set<Date> = []
        let startOfToday = calendar.startOfDay(for: date)
        for dayOffset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday) else {
                continue
            }
            for minute in dailyWakeMinutes(for: rule) {
                let hour = minute / 60
                let minutePart = minute % 60
                for policy in [Calendar.RepeatedTimePolicy.first, .last] {
                    guard let candidate = calendar.nextDate(
                        after: day.addingTimeInterval(-1),
                        matching: DateComponents(hour: hour, minute: minutePart, second: 0),
                        matchingPolicy: .nextTime,
                        repeatedTimePolicy: policy,
                        direction: .forward
                    ), calendar.isDate(candidate, inSameDayAs: day), candidate > date else {
                        continue
                    }
                    candidates.insert(candidate)
                }
            }
        }
        if let transition = calendar.timeZone.nextDaylightSavingTimeTransition(after: date) {
            candidates.insert(transition)
        }
        if let pending = rule.pendingLegacyRelaxation, pending.effectiveAt > date {
            candidates.insert(pending.effectiveAt)
        }
        return candidates.sorted().first { candidate in
            isBlocking(rule, at: candidate.addingTimeInterval(-1), calendar: calendar)
                != isBlocking(rule, at: candidate.addingTimeInterval(1), calendar: calendar)
        }
    }
}
