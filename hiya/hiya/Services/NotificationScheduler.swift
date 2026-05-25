import Foundation
import UserNotifications

/// App-level view of notification authorization, decoupled from UNAuthorizationStatus.
enum NotifAuthStatus: Equatable, Sendable {
    case notDetermined, authorized, denied
}

/// The seam between the app and `UNUserNotificationCenter`. MainActor-isolated
/// because it is only ever driven by `NotificationManager` (also MainActor).
@MainActor
protocol NotificationScheduler {
    func authorizationStatus() async -> NotifAuthStatus
    func requestAuthorization() async -> Bool
    /// Removes all of Hiya's pending reminder requests and registers the given set.
    func replaceReminders(_ reminders: [PlannedReminder]) async
    func pendingReminderIDs() async -> [String]
}

@MainActor
final class LiveNotificationScheduler: NotificationScheduler {
    private let center = UNUserNotificationCenter.current()

    func authorizationStatus() async -> NotifAuthStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .notDetermined
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func replaceReminders(_ reminders: [PlannedReminder]) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let request = UNNotificationRequest(identifier: reminder.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func pendingReminderIDs() async -> [String] {
        let pending = await center.pendingNotificationRequests()
        return pending.map(\.identifier).filter { $0.hasPrefix(ReminderPlanner.idPrefix) }
    }
}
