import Testing
import Foundation
@testable import hiya

struct ReminderPlannerTests {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    @Test func disabledProducesNothing() {
        let out = ReminderPlanner.plan(enabled: false, hour: 18, minute: 0,
                                       now: date(2026, 5, 25, 9, 0), goalMetToday: false,
                                       horizonDays: 7, calendar: cal)
        #expect(out.isEmpty)
    }

    @Test func includesTodayWhenTimeFutureAndGoalNotMet() {
        let out = ReminderPlanner.plan(enabled: true, hour: 18, minute: 0,
                                       now: date(2026, 5, 25, 9, 0), goalMetToday: false,
                                       horizonDays: 7, calendar: cal)
        #expect(out.count == 7)
        #expect(out.first?.id == "hiya.reminder.2026-05-25")
    }

    @Test func skipsTodayWhenGoalMet() {
        let out = ReminderPlanner.plan(enabled: true, hour: 18, minute: 0,
                                       now: date(2026, 5, 25, 9, 0), goalMetToday: true,
                                       horizonDays: 7, calendar: cal)
        #expect(out.count == 6)
        #expect(out.first?.id == "hiya.reminder.2026-05-26")
    }

    @Test func skipsTodayWhenTimePassed() {
        let out = ReminderPlanner.plan(enabled: true, hour: 18, minute: 0,
                                       now: date(2026, 5, 25, 20, 0), goalMetToday: false,
                                       horizonDays: 7, calendar: cal)
        #expect(out.count == 6)
        #expect(out.first?.id == "hiya.reminder.2026-05-26")
    }

    @Test func fireDateMatchesConfiguredTime() {
        let out = ReminderPlanner.plan(enabled: true, hour: 18, minute: 30,
                                       now: date(2026, 5, 25, 9, 0), goalMetToday: false,
                                       horizonDays: 1, calendar: cal)
        #expect(out.count == 1)
        let comps = cal.dateComponents([.hour, .minute], from: out[0].fireDate)
        #expect(comps.hour == 18)
        #expect(comps.minute == 30)
    }
}
