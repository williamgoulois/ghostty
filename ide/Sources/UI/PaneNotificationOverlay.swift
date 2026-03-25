import SwiftUI

/// A subtle border overlay on panes with unread notifications.
/// Applied as a SwiftUI overlay on terminal split leaves under #if GHOSTTY_IDE.
struct PaneNotificationOverlay: View {
    let hasUnread: Bool

    var body: some View {
        if hasUnread {
            RoundedRectangle(cornerRadius: 2)
                .stroke(Color.accentColor.opacity(0.6), lineWidth: 2)
                .allowsHitTesting(false)
        }
    }
}
