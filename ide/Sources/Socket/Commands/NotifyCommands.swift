import Foundation

extension IDECommandRouter {
    func registerNotifyCommands() {
        register("notify.send") { command in
            guard let title = command.args?["title"]?.value as? String, !title.isEmpty else {
                return .failure("Missing 'title' argument")
            }
            let body = command.args?["body"]?.value as? String ?? ""
            let paneId = command.args?["pane_id"]?.value as? String

            let id = NotificationManager.shared.send(title: title, body: body, paneId: paneId)
            return .success([
                "notification_id": id,
                "title": title,
            ])
        }

        register("notify.list") { _ in
            let notifications = NotificationManager.shared.listRecent()
            return .success(["notifications": notifications])
        }

        register("notify.clear") { _ in
            NotificationManager.shared.clearAll()
            return .success()
        }

        register("notify.status") { _ in
            let nm = NotificationManager.shared
            return .success([
                "unread_pane_ids": Array(nm.unreadPaneIds),
                "unread_count": nm.unreadPaneIds.count,
                "total_notifications": nm.recentNotifications.count,
            ])
        }
    }
}
