import FamilyControls
import Foundation
import ManagedSettings

/// Reads only device-local state. A shield can appear while the main app is closed.
enum ShieldRuleExplanation {
    private static let defaults = UserDefaults(suiteName: "group.LycheeCorp.Noxa")
    private static let decoder = JSONDecoder()

    static func app(_ application: Application, category: ActivityCategory?) -> String? {
        explain { selection, _ in
            (application.token.map { selection.applicationTokens.contains($0) } ?? false)
                || (category?.token.map { selection.categoryTokens.contains($0) } ?? false)
        }
    }

    static func website(_ website: WebDomain, category: ActivityCategory?) -> String? {
        explain { selection, domains in
            (website.token.map { selection.webDomainTokens.contains($0) } ?? false)
                || (category?.token.map { selection.categoryTokens.contains($0) } ?? false)
                || (website.domain.map { domainMatches($0, savedDomains: domains) } ?? false)
        }
    }

    static func domain(
        _ domain: String,
        defaults: UserDefaults,
        now: Date,
        calendar: Calendar
    ) -> String? {
        explain(defaults: defaults, now: now, calendar: calendar) { _, domains in
            domainMatches(domain, savedDomains: domains)
        }
    }

    private static func domainMatches(_ domain: String, savedDomains: [String]) -> Bool {
        let host = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return savedDomains.contains { saved in
            let normalized = saved.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return !normalized.isEmpty && (host == normalized || host.hasSuffix("." + normalized))
        }
    }

    static func explain(
        defaults: UserDefaults? = Self.defaults,
        now: Date = Date(),
        calendar: Calendar = .current,
        matches: (FamilyActivitySelection, [String]) -> Bool
    ) -> String? {
        guard let defaults else { return nil }
        var reasons: [String] = []

        if let snapshot: Snapshot = decode("noxa.localSnapshot", from: defaults),
           let session = snapshot.activeSession,
           snapshot.sessionEngineState == "active",
           session.outcome == "active",
           session.plannedEndAt > now,
           let focus: FocusRestrictions = decode("noxa.focusSessionRestrictions", from: defaults),
           matches(focus.selection, focus.websiteDomains) {
            let end = session.plannedEndAt.formatted(date: .omitted, time: .shortened)
            let intention = focus.intention?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            if let intention, !intention.isEmpty {
                reasons.append("Focus until \(end). \(String(intention.prefix(65)))")
            } else {
                reasons.append("Focus until \(end).")
            }
        }

        if let archive: ScheduleArchive = decode("noxa.scheduleRules.v2", from: defaults),
           archive.version == 2 {
            for rule in archive.rules where rule.isBlocking(at: now, calendar: calendar)
                && matches(rule.selection, rule.websiteDomains) {
                let name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
                let label = name.isEmpty ? "Schedule" : String(name.prefix(45))
                if let end = rule.nextEnd(after: now, calendar: calendar) {
                    reasons.append("\(label) until \(end.formatted(date: .abbreviated, time: .shortened)).")
                } else {
                    reasons.append("\(label) is active.")
                }
            }
        }

        if let manual: ManualRestrictions = decode("noxa.manualShield", from: defaults),
           matches(manual.selection, manual.websiteDomains) {
            reasons.append("Manually blocked in Noxa.")
        }

        let day = calendar.dateComponents([.era, .year, .month, .day], from: now)
        let dayStamp = "\(day.era ?? 0)-\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)"
        if defaults.string(forKey: "noxa.dailyLimitResetDay") == dayStamp,
           let limits: [DailyLimit] = decode("noxa.dailyLimits", from: defaults) {
            let reached = Set(defaults.stringArray(forKey: "noxa.dailyLimitReachedEvents") ?? [])
            if limits.contains(where: { limit in
                limit.isEnabled
                    && reached.contains("noxa.daily.limit.\(limit.id.uuidString.lowercased())")
                    && matches(limit.selection, [])
            }) {
                reasons.append("Daily allowance reached for today.")
            }
        }

        if defaults.bool(forKey: "noxa.websiteShieldActive"),
           let domains: [String] = decode("noxa.websiteBlocklist", from: defaults),
           matches(FamilyActivitySelection(), domains) {
            reasons.append("On your blocked websites list.")
        }

        var distinctReasons: [String] = []
        for reason in reasons where !distinctReasons.contains(reason) {
            distinctReasons.append(reason)
        }
        guard !distinctReasons.isEmpty else { return nil }
        return distinctReasons.prefix(2).joined(separator: " ") + " Other rules may still apply."
    }

    private static func decode<T: Decodable>(_ key: String, from defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(T.self, from: data)
    }
}

private struct Snapshot: Decodable {
    let sessionEngineState: String
    let activeSession: Session?
}

private struct Session: Decodable {
    let plannedEndAt: Date
    let outcome: String
}

private struct FocusRestrictions: Decodable {
    let selection: FamilyActivitySelection
    let websiteDomains: [String]
    let intention: String?

    private enum CodingKeys: String, CodingKey {
        case selection, websiteDomains, intention
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        selection = try container.decode(FamilyActivitySelection.self, forKey: .selection)
        websiteDomains = try container.decodeIfPresent([String].self, forKey: .websiteDomains) ?? []
        intention = try container.decodeIfPresent(String.self, forKey: .intention)
    }
}

private struct ManualRestrictions: Decodable {
    let selection: FamilyActivitySelection
    let websiteDomains: [String]
}

private struct DailyLimit: Decodable {
    let id: UUID
    let selection: FamilyActivitySelection
    let isEnabled: Bool
}

private struct ScheduleArchive: Decodable {
    let version: Int
    let rules: [Rule]
}

private struct Rule: Decodable {
    let name: String
    let selection: FamilyActivitySelection
    let websiteDomains: [String]
    let mode: String
    let weekdays: Set<Int>
    let startMinutes: Int
    let endMinutes: Int
    let isEnabled: Bool
    let pendingLegacyRelaxation: PendingRelaxation?

    func isBlocking(at date: Date, calendar: Calendar) -> Bool {
        ScheduleWindow.isBlocking(
            mode: mode,
            weekdays: weekdays,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            isEnabled: isEnabled,
            pendingRelaxationAt: pendingLegacyRelaxation?.effectiveAt,
            at: date,
            calendar: calendar
        )
    }

    func nextEnd(after date: Date, calendar: Calendar) -> Date? {
        let startOfToday = calendar.startOfDay(for: date)
        var candidates: Set<Date> = []
        for offset in 0...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { continue }
            for minute in Set([0, startMinutes, endMinutes]) {
                for policy in [Calendar.RepeatedTimePolicy.first, .last] {
                    guard let candidate = calendar.nextDate(
                        after: day.addingTimeInterval(-1),
                        matching: DateComponents(hour: minute / 60, minute: minute % 60, second: 0),
                        matchingPolicy: .nextTime,
                        repeatedTimePolicy: policy,
                        direction: .forward
                    ), calendar.isDate(candidate, inSameDayAs: day), candidate > date else { continue }
                    candidates.insert(candidate)
                }
            }
        }
        if let pending = pendingLegacyRelaxation, pending.effectiveAt > date {
            candidates.insert(pending.effectiveAt)
        }
        if let dst = calendar.timeZone.nextDaylightSavingTimeTransition(after: date) {
            candidates.insert(dst)
        }
        return candidates.sorted().first { candidate in
            isBlocking(at: candidate.addingTimeInterval(-1), calendar: calendar)
                && !isBlocking(at: candidate.addingTimeInterval(1), calendar: calendar)
        }
    }
}

private struct PendingRelaxation: Decodable {
    let effectiveAt: Date
}
