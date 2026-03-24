import Foundation
import UserNotifications

/// Manages macOS system notifications for GhosttyIDE.
final class NotificationManager: NSObject {
    static let shared = NotificationManager()

    private var recentNotifications: [NotificationRecord] = []
    private let maxRecent = 100

    struct NotificationRecord {
        let id: String
        let title: String
        let body: String
        let paneId: String?
        let timestamp: Date
    }

    /// Request notification permission. Call once at app launch.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        UNUserNotificationCenter.current().delegate = self
    }

    /// Send a macOS system notification and store in recent list.
    func send(title: String, body: String = "", paneId: String? = nil) -> String {
        let id = UUID().uuidString

        let content = UNMutableNotificationContent()
        content.title = title
        if !body.isEmpty { content.body = body }
        content.sound = .default
        if let paneId { content.userInfo["pane_id"] = paneId }

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)

        let record = NotificationRecord(id: id, title: title, body: body, paneId: paneId, timestamp: Date())
        recentNotifications.append(record)
        if recentNotifications.count > maxRecent {
            recentNotifications.removeFirst(recentNotifications.count - maxRecent)
        }

        return id
    }

    /// Return recent notifications as dictionaries for JSON serialization.
    func listRecent() -> [[String: Any]] {
        let formatter = ISO8601DateFormatter()
        return recentNotifications.map { r in
            var dict: [String: Any] = [
                "id": r.id,
                "title": r.title,
                "body": r.body,
                "timestamp": formatter.string(from: r.timestamp),
            ]
            if let paneId = r.paneId { dict["pane_id"] = paneId }
            return dict
        }
    }

    /// Clear all recent notifications and delivered system notifications.
    func clearAll() {
        recentNotifications.removeAll()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }
}

// Show notifications even when app is in foreground.
extension NotificationManager: UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
