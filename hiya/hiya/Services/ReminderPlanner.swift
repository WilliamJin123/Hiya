import Foundation

/// One scheduled daily reminder. Pure value type — no UNNotification dependency,
/// so it can be planned and asserted on in tests.
struct PlannedReminder: Equatable, Sendable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
}

/// Pure scheduling policy for the daily approach reminder. Decides *which*
/// reminders should exist; the `NotificationScheduler` decides how to register
/// them with the OS.
enum ReminderPlanner {
    static let idPrefix = "hiya.reminder."
    static let title = "Time for an approach"
    static let body = "Say hi to someone new today — even a small one counts."

    /// One reminder per day for the next `horizonDays`, at `hour:minute`.
    /// Today is skipped when the goal is already met or the time has passed.
    static func plan(
        enabled: Bool,
        hour: Int,
        minute: Int,
        now: Date,
        goalMetToday: Bool,
        horizonDays: Int,
        calendar: Calendar
    ) -> [PlannedReminder] {
        guard enabled else { return [] }
        let startDay = calendar.startOfDay(for: now)
        var result: [PlannedReminder] = []
        for offset in 0..<horizonDays {
            guard
                let day = calendar.date(byAdding: .day, value: offset, to: startDay),
                let fire = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)
            else { continue }
            if offset == 0 {
                if goalMetToday { continue }
                if fire <= now { continue }
            }
            result.append(PlannedReminder(id: idPrefix + dayKey(day, calendar: calendar),
                                          fireDate: fire, title: title, body: body))
        }
        return result
    }

    static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
