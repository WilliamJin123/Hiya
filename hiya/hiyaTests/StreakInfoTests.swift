import Testing
import Foundation
@testable import hiya

struct StreakInfoTests {

    private let cal = Calendar(identifier: .gregorian)
    private let today: Date = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: 2026, month: 5, day: 22, hour: 14))!
    }()

    private func dayOffset(_ days: Int, hour: Int = 12) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        let base = c.date(from: DateComponents(year: 2026, month: 5, day: 22, hour: hour))!
        return c.date(byAdding: .day, value: days, to: base)!
    }

    private var utcCal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func emptyActivity_yieldsZero() {
        let s = StreakInfo.compute(activity: [], today: today, calendar: utcCal)
        #expect(s.cold == 0)
        #expect(s.warm == 0)
    }

    @Test func todayOnly_cold_yieldsOne() {
        let s = StreakInfo.compute(
            activity: [ConversationActivity(occurredAt: dayOffset(0), wasColdAtTime: true)],
            today: today,
            calendar: utcCal
        )
        #expect(s.cold == 1)
        #expect(s.warm == 0)
    }

    @Test func todayOnly_warm_yieldsOne() {
        let s = StreakInfo.compute(
            activity: [ConversationActivity(occurredAt: dayOffset(0), wasColdAtTime: false)],
            today: today,
            calendar: utcCal
        )
        #expect(s.cold == 0)
        #expect(s.warm == 1)
    }

    @Test func consecutiveDaysIncludingToday_yieldsLength() {
        let activity = (0..<5).map {
            ConversationActivity(occurredAt: dayOffset(-$0), wasColdAtTime: true)
        }
        let s = StreakInfo.compute(activity: activity, today: today, calendar: utcCal)
        #expect(s.cold == 5)
    }

    @Test func yesterdayButNotToday_stillCounts_withGracePeriod() {
        // Yesterday has cold, today has nothing. Streak still 1 (grace — today
        // not yet broken since the day isn't over).
        let s = StreakInfo.compute(
            activity: [ConversationActivity(occurredAt: dayOffset(-1), wasColdAtTime: true)],
            today: today,
            calendar: utcCal
        )
        #expect(s.cold == 1)
    }

    @Test func twoDaysAgoButNotYesterdayOrToday_yieldsZero() {
        let s = StreakInfo.compute(
            activity: [ConversationActivity(occurredAt: dayOffset(-2), wasColdAtTime: true)],
            today: today,
            calendar: utcCal
        )
        #expect(s.cold == 0)
    }

    @Test func gapBreaksStreak() {
        // Today + day before yesterday, no yesterday → streak from today is 1.
        let activity = [
            ConversationActivity(occurredAt: dayOffset(0), wasColdAtTime: true),
            ConversationActivity(occurredAt: dayOffset(-2), wasColdAtTime: true),
        ]
        let s = StreakInfo.compute(activity: activity, today: today, calendar: utcCal)
        #expect(s.cold == 1)
    }

    @Test func multipleConvosOnOneDay_countOnce() {
        let activity = (0..<5).map { _ in
            ConversationActivity(occurredAt: dayOffset(0), wasColdAtTime: true)
        }
        let s = StreakInfo.compute(activity: activity, today: today, calendar: utcCal)
        #expect(s.cold == 1)
    }

    @Test func coldAndWarmAreIndependent() {
        // Today: warm only. Yesterday: cold only.
        // Cold streak: anchored at yesterday → 1
        // Warm streak: anchored at today → 1
        let activity = [
            ConversationActivity(occurredAt: dayOffset(0), wasColdAtTime: false),
            ConversationActivity(occurredAt: dayOffset(-1), wasColdAtTime: true),
        ]
        let s = StreakInfo.compute(activity: activity, today: today, calendar: utcCal)
        #expect(s.cold == 1)
        #expect(s.warm == 1)
    }
}
