import Foundation

struct StreakInfo: Sendable, Equatable {
    let cold: Int
    let warm: Int

    static let zero = StreakInfo(cold: 0, warm: 0)

    /// Compute streaks from a list of conversation activity records.
    ///
    /// A "qualifying day" for a given type (cold or warm) has at least one
    /// conversation of that type. The streak is anchored at today if today
    /// qualifies, else at yesterday if yesterday qualifies (grace period —
    /// today isn't over yet), else zero. From the anchor we walk backward
    /// counting consecutive qualifying days.
    static func compute(
        activity: [ConversationActivity],
        today: Date = .now,
        calendar: Calendar = .current
    ) -> StreakInfo {
        let coldDays = Set(
            activity
                .filter { $0.wasColdAtTime }
                .map { calendar.startOfDay(for: $0.occurredAt) }
        )
        let warmDays = Set(
            activity
                .filter { !$0.wasColdAtTime }
                .map { calendar.startOfDay(for: $0.occurredAt) }
        )
        return StreakInfo(
            cold: streakLength(in: coldDays, today: today, calendar: calendar),
            warm: streakLength(in: warmDays, today: today, calendar: calendar)
        )
    }

    private static func streakLength(
        in qualifyingDays: Set<Date>,
        today: Date,
        calendar: Calendar
    ) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let anchor: Date
        if qualifyingDays.contains(todayStart) {
            anchor = todayStart
        } else if qualifyingDays.contains(yesterdayStart) {
            anchor = yesterdayStart
        } else {
            return 0
        }
        var count = 0
        var day = anchor
        while qualifyingDays.contains(day) {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }
}

struct ConversationActivity: Sendable, Equatable {
    let occurredAt: Date
    let wasColdAtTime: Bool
}
