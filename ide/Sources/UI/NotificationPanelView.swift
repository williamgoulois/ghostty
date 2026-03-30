import SwiftUI

/// In-app notification panel shown as a popover.
/// Lists recent notifications grouped by workspace, with actions.
struct NotificationPanelView: View {
    @Binding var isPresented: Bool
    let notifications: [NotificationManager.NotificationRecord]
    let onJumpToPane: ((String) -> Void)?
    let onClearAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Notifications")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                if !notifications.isEmpty {
                    Button("Clear All") {
                        onClearAll()
                    }
                    .font(.system(size: 11))
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }
                Button(action: { isPresented = false }, label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                })
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Notification list
            if notifications.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "bell.slash")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text("No notifications")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(notifications.reversed(), id: \.id) { notification in
                            NotificationRow(
                                notification: notification,
                                onJumpToPane: onJumpToPane
                            )
                            Divider()
                                .padding(.leading, 12)
                        }
                    }
                }
            }
        }
        .frame(width: 320, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// A single notification row in the panel.
private struct NotificationRow: View {
    let notification: NotificationManager.NotificationRecord
    let onJumpToPane: ((String) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(notification.title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(relativeTime(notification.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            if !notification.subtitle.isEmpty {
                Text(notification.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.primary.opacity(0.7))
                    .lineLimit(1)
            }

            if !notification.body.isEmpty {
                Text(notification.body)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            if let paneId = notification.paneId {
                onJumpToPane?(paneId)
            }
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}
