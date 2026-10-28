import Foundation

/// The same local-time decision is used by the app, monitor, and shield.
enum ScheduleWindow {
    static func isBlocking(
        mode: String,
        weekdays: Set<Int>,
        startMinutes: Int,
        endMinutes: Int,
        isEnabled: Bool,
        pendingRelaxationAt: Date?,
        at date: Date,
        calendar: Calendar
    ) -> Bool {
        guard isEnabled,
              mode == "blockedHours" || mode == "allowedHours",
              weekdays.contains(where: { (1...7).contains($0) }),
              (0..<1_440).contains(startMinutes),
              (0..<1_440).contains(endMinutes),
              startMinutes != endMinutes,
              pendingRelaxationAt.map({ $0 > date }) ?? true else { return false }

        let weekday = calendar.component(.weekday, from: date)
        let minutes = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date)
            .map { calendar.component(.weekday, from: $0) }
        let startsToday = weekdays.contains(weekday)
        let startsYesterday = yesterday.map(weekdays.contains) ?? false

        let withinWindow: Bool
        if endMinutes < startMinutes {
            withinWindow = (startsToday && minutes >= startMinutes)
                || (startsYesterday && minutes < endMinutes)
        } else {
            withinWindow = startsToday && minutes >= startMinutes && minutes < endMinutes
        }
        return mode == "blockedHours" ? withinWindow : (startsToday && !withinWindow)
    }
}
