import Foundation

/// In-memory scheduler for tests and previews. Records calls instead of touching
/// the OS. Lives in the app target (like `MockHiyaRepository`) so previews use it too.
@MainActor
final class MockNotificationScheduler: NotificationScheduler {
    var status: NotifAuthStatus = .notDetermined
    var grantOnRequest = true
    private(set) var requestCount = 0
    private(set) var scheduled: [PlannedReminder] = []

    func authorizationStatus() async -> NotifAuthStatus { status }

    func requestAuthorization() async -> Bool {
        requestCount += 1
        status = grantOnRequest ? .authorized : .denied
        return grantOnRequest
    }

    func replaceReminders(_ reminders: [PlannedReminder]) async { scheduled = reminders }

    func pendingReminderIDs() async -> [String] { scheduled.map(\.id) }
}
