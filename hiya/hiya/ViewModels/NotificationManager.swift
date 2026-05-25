import Foundation
import Observation

/// Owns the daily-reminder preference (default OFF) and keeps the OS schedule in
/// sync via a `NotificationScheduler`. Injected into the environment for Settings
/// and Home to drive.
@MainActor
@Observable
final class NotificationManager {
    private let scheduler: any NotificationScheduler
    private let defaults: UserDefaults

    private let enabledKey = "hiya.notif.dailyEnabled"
    private let hourKey = "hiya.notif.dailyHour"
    private let minuteKey = "hiya.notif.dailyMinute"
    static let horizonDays = 7

    private(set) var enabled: Bool
    private(set) var hour: Int
    private(set) var minute: Int
    private(set) var authorizationStatus: NotifAuthStatus = .notDetermined

    init(scheduler: any NotificationScheduler, defaults: UserDefaults = .standard) {
        self.scheduler = scheduler
        self.defaults = defaults
        self.enabled = defaults.bool(forKey: enabledKey)                 // default false
        self.hour = (defaults.object(forKey: hourKey) as? Int) ?? 18
        self.minute = (defaults.object(forKey: minuteKey) as? Int) ?? 0
    }

    /// The configured reminder time as a `Date` (today at hour:minute) for binding
    /// to a `DatePicker(.hourAndMinute)`.
    var time: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    func refreshAuthorizationStatus() async {
        authorizationStatus = await scheduler.authorizationStatus()
    }

    /// Turn the reminder on: request permission, persist, schedule. Returns granted.
    func enable() async -> Bool {
        let granted = await scheduler.requestAuthorization()
        authorizationStatus = granted ? .authorized : .denied
        guard granted else { return false }
        enabled = true
        defaults.set(true, forKey: enabledKey)
        await reschedule(goalMetToday: false)
        return true
    }

    func disable() async {
        enabled = false
        defaults.set(false, forKey: enabledKey)
        await scheduler.replaceReminders([])
    }

    func setTime(_ date: Date) async {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        hour = c.hour ?? 18
        minute = c.minute ?? 0
        defaults.set(hour, forKey: hourKey)
        defaults.set(minute, forKey: minuteKey)
        if enabled { await reschedule(goalMetToday: false) }
    }

    /// Recompute and apply the schedule. Called by Home on appear / after a log /
    /// on foreground. No-op when disabled.
    func refresh(goalMetToday: Bool) async {
        guard enabled else { return }
        await reschedule(goalMetToday: goalMetToday)
    }

    private func reschedule(goalMetToday: Bool, now: Date = .now) async {
        let plan = ReminderPlanner.plan(
            enabled: enabled, hour: hour, minute: minute,
            now: now, goalMetToday: goalMetToday,
            horizonDays: Self.horizonDays, calendar: .current
        )
        await scheduler.replaceReminders(plan)
    }
}
