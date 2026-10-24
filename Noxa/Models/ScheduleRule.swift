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
    var notifyAtStart: Bool
    var notifyAtEnd: Bool
    var pendingLegacyRelaxation: PendingScheduleRelaxation?

    private enum CodingKeys: String, CodingKey {
        case id, name, mode, selection, websiteDomains, weekdays
        case startMinutes, endMinutes, createdAt, isEnabled
        case notifyAtStart, notifyAtEnd, pendingLegacyRelaxation
    }

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
        notifyAtStart: Bool = false,
        notifyAtEnd: Bool = false,
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
        self.notifyAtStart = notifyAtStart
        self.notifyAtEnd = notifyAtEnd
        self.pendingLegacyRelaxation = pendingLegacyRelaxation
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        mode = try values.decode(Mode.self, forKey: .mode)
        selection = try values.decode(FamilyActivitySelection.self, forKey: .selection)
        websiteDomains = try values.decode([String].self, forKey: .websiteDomains)
        weekdays = try values.decode(Set<Int>.self, forKey: .weekdays)
        startMinutes = try values.decode(Int.self, forKey: .startMinutes)
        endMinutes = try values.decode(Int.self, forKey: .endMinutes)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        isEnabled = try values.decode(Bool.self, forKey: .isEnabled)
        notifyAtStart = try values.decodeIfPresent(Bool.self, forKey: .notifyAtStart) ?? false
        notifyAtEnd = try values.decodeIfPresent(Bool.self, forKey: .notifyAtEnd) ?? false
        pendingLegacyRelaxation = try values.decodeIfPresent(
            PendingScheduleRelaxation.self, forKey: .pendingLegacyRelaxation
        )
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
        ScheduleWindow.isBlocking(
            mode: rule.mode.rawValue,
            weekdays: rule.weekdays,
            startMinutes: rule.startMinutes,
            endMinutes: rule.endMinutes,
            isEnabled: rule.isEnabled,
            pendingRelaxationAt: rule.pendingLegacyRelaxation?.effectiveAt,
            at: date,
            calendar: calendar
        )
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
