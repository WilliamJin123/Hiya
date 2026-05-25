import Testing
import Foundation
@testable import hiya

@MainActor
struct NotificationManagerTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    @Test func defaultsAreOffAtSixPM() {
        let m = NotificationManager(scheduler: MockNotificationScheduler(), defaults: freshDefaults())
        #expect(m.enabled == false)
        #expect(m.hour == 18)
        #expect(m.minute == 0)
    }

    @Test func enableRequestsAuthAndSchedules() async {
        let sched = MockNotificationScheduler()
        let m = NotificationManager(scheduler: sched, defaults: freshDefaults())
        let ok = await m.enable()
        #expect(ok)
        #expect(sched.requestCount == 1)
        #expect(m.enabled)
        #expect(m.authorizationStatus == .authorized)
        #expect(!sched.scheduled.isEmpty)
    }

    @Test func deniedAuthLeavesDisabled() async {
        let sched = MockNotificationScheduler()
        sched.grantOnRequest = false
        let m = NotificationManager(scheduler: sched, defaults: freshDefaults())
        let ok = await m.enable()
        #expect(!ok)
        #expect(!m.enabled)
        #expect(m.authorizationStatus == .denied)
        #expect(sched.scheduled.isEmpty)
    }

    @Test func disableClearsSchedule() async {
        let sched = MockNotificationScheduler()
        let m = NotificationManager(scheduler: sched, defaults: freshDefaults())
        _ = await m.enable()
        await m.disable()
        #expect(!m.enabled)
        #expect(sched.scheduled.isEmpty)
    }

    @Test func refreshNoOpWhenDisabled() async {
        let sched = MockNotificationScheduler()
        let m = NotificationManager(scheduler: sched, defaults: freshDefaults())
        await m.refresh(goalMetToday: false)
        #expect(sched.scheduled.isEmpty)   // never enabled → nothing scheduled
    }

    @Test func enabledStatePersistsAcrossInstances() async {
        let defaults = freshDefaults()
        let sched = MockNotificationScheduler()
        let m = NotificationManager(scheduler: sched, defaults: defaults)
        _ = await m.enable()
        await m.setTime(makeTime(hour: 9, minute: 15))
        let m2 = NotificationManager(scheduler: MockNotificationScheduler(), defaults: defaults)
        #expect(m2.enabled)
        #expect(m2.hour == 9)
        #expect(m2.minute == 15)
    }

    private func makeTime(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now)!
    }
}
