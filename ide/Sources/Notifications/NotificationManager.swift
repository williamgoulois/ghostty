import AppKit
import Combine
import Foundation
import UserNotifications

/// Manages macOS system notifications for GhosttyIDE.
/// Foreground presentation is handled by AppDelegate's UNUserNotificationCenterDelegate.
///
/// ObservableObject so SwiftUI views (IDETopBarView, TerminalSplitLeaf) can react
/// to changes in per-pane unread state via @ObservedObject / @EnvironmentObject.
final class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    private(set) var recentNotifications: [NotificationRecord] = []
    private let maxRecent = 100

    /// Pane IDs with unread notifications. @Published so Combine subscribers
    /// (WorkspaceStatusBridge) and SwiftUI views react to changes.
    @Published private(set) var unreadPaneIds: Set<String> = []

    struct NotificationRecord {
        let id: String
        let title: String
        let subtitle: String
        let body: String
        let paneId: String?
        let timestamp: Date
    }

    /// Request notification permission. Call once at app launch.
    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Send a macOS system notification and store in recent list.
    /// Safe to call from any thread — @Published writes are dispatched to main.
    func send(title: String, subtitle: String = "", body: String = "", paneId: String? = nil) -> String {
        let id = UUID().uuidString

        let content = UNMutableNotificationContent()
        content.title = title
        if !subtitle.isEmpty { content.subtitle = subtitle }
        if !body.isEmpty { content.body = body }
        content.sound = .default
        if let paneId { content.userInfo["pane_id"] = paneId }

        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)

        let record = NotificationRecord(id: id, title: title, subtitle: subtitle, body: body, paneId: paneId, timestamp: Date())
        recentNotifications.append(record)
        if recentNotifications.count > maxRecent {
            recentNotifications.removeFirst(recentNotifications.count - maxRecent)
        }

        // @Published must be written on main thread for Combine pipeline to fire.
        // send() can be called from socket handler (background thread).
        if let paneId {
            if Thread.isMainThread {
                unreadPaneIds.insert(paneId)
            } else {
                DispatchQueue.main.async { self.unreadPaneIds.insert(paneId) }
            }
        }
        updateDockBadge()

        return id
    }

    /// Return recent notifications as dictionaries for JSON serialization.
    func listRecent() -> [[String: Any]] {
        let formatter = ISO8601DateFormatter()
        return recentNotifications.map { r in
            var dict: [String: Any] = [
                "id": r.id,
                "title": r.title,
                "subtitle": r.subtitle,
                "body": r.body,
                "timestamp": formatter.string(from: r.timestamp),
            ]
            if let paneId = r.paneId { dict["pane_id"] = paneId }
            return dict
        }
    }

    /// Clear all recent notifications and delivered system notifications.
    /// Safe to call from any thread — @Published writes are dispatched to main.
    func clearAll() {
        recentNotifications.removeAll()
        if Thread.isMainThread {
            unreadPaneIds.removeAll()
        } else {
            DispatchQueue.main.async { self.unreadPaneIds.removeAll() }
        }
        updateDockBadge()
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    /// Mark all as read (resets all pane unread state and dock badge).
    func markAllRead() {
        unreadPaneIds.removeAll()
        updateDockBadge()
    }

    /// Mark a specific pane as read (called when pane receives focus).
    func markPaneRead(paneId: String) {
        unreadPaneIds.remove(paneId)
        updateDockBadge()
    }

    /// Update the dock tile badge with the current unread count.
    private func updateDockBadge() {
        let count = unreadPaneIds.count
        DispatchQueue.main.async {
            NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        }
    }
}
