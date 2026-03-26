import SwiftUI

/// Top bar showing active workspace context: name, git branch, agent state, extensible metadata.
/// Right side: project name + notification bell with popover panel.
struct IDETopBarView: View {
    @ObservedObject var controller: WorkspaceController
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var showNotificationPanel = false

    var body: some View {
        HStack(spacing: 0) {
            // Left: workspace metadata
            leftContent
                .padding(.leading, 10)

            Spacer(minLength: 4)

            // Right: project name + notification badge + drag handle
            rightContent
                .padding(.trailing, 10)
        }
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        .onReceive(NotificationCenter.default.publisher(for: .ideToggleNotificationPanel)) { _ in
            showNotificationPanel.toggle()
        }
        .onChange(of: showNotificationPanel) { isShowing in
            if isShowing {
                notificationManager.markAllRead()
            }
        }
    }

    // MARK: - Left Side (workspace context)

    @ViewBuilder
    private var leftContent: some View {
        if let ws = controller.activeWorkspace {
            HStack(spacing: 8) {
                // Workspace name
                HStack(spacing: 4) {
                    if let emoji = ws.emoji {
                        Text(emoji)
                            .font(.system(size: 12))
                    }
                    Text(ws.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.primary)
                }

                // Git branch
                if let branch = ws.gitBranch {
                    IDEMetadataChip(
                        icon: "arrow.triangle.branch",
                        text: branch,
                        color: .secondary
                    )
                }

                // Agent state
                if let agent = ws.agentState {
                    IDEMetadataChip(
                        icon: agentIcon(agent),
                        text: agent.rawValue,
                        color: agentColor(agent)
                    )
                }

                // Extensible metadata entries
                ForEach(Array(ws.metadata.values).sorted(by: { $0.key < $1.key }), id: \.key) { entry in
                    IDEMetadataChip(
                        icon: entry.icon ?? "info.circle",
                        text: entry.value,
                        color: .secondary,
                        url: entry.url
                    )
                }
            }
        } else {
            Text("No workspace")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Right Side (project + notifications + drag)

    @ViewBuilder
    private var rightContent: some View {
        HStack(spacing: 8) {
            // Project name
            if !controller.activeProject.isEmpty {
                Text(controller.activeProject)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }

            // Notification bell — global count across ALL projects/workspaces/panes
            let totalUnread = notificationManager.unreadPaneIds.count
            Button(action: { showNotificationPanel.toggle() }, label: {
                HStack(spacing: 3) {
                    Image(systemName: totalUnread > 0 ? "bell.fill" : "bell")
                        .font(.system(size: 10))
                    if totalUnread > 0 {
                        Text("\(totalUnread)")
                            .font(.system(size: 10, weight: .medium))
                    }
                }
                .foregroundColor(totalUnread > 0 ? .white : .secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(totalUnread > 0 ? Color.red : Color.clear)
                )
            })
            .buttonStyle(.plain)
            .popover(isPresented: $showNotificationPanel, arrowEdge: .bottom) {
                NotificationPanelView(
                    isPresented: $showNotificationPanel,
                    notifications: notificationManager.recentNotifications,
                    onJumpToPane: { paneId in
                        if let ws = controller.workspace(containingPaneId: paneId) {
                            controller.switchTo(workspace: ws)
                        }
                        showNotificationPanel = false
                    },
                    onClearAll: {
                        notificationManager.clearAll()
                        showNotificationPanel = false
                    }
                )
            }

        }
    }

    // MARK: - Helpers

    private func agentIcon(_ state: AgentState) -> String {
        switch state {
        case .idle: return "circle"
        case .working: return "bolt.fill"
        case .waiting: return "hourglass"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    private func agentColor(_ state: AgentState) -> Color {
        switch state {
        case .idle: return .secondary
        case .working: return .blue
        case .waiting: return .orange
        case .error: return .red
        }
    }
}

/// A small pill showing icon + text for workspace metadata.
struct IDEMetadataChip: View {
    let icon: String
    let text: String
    var color: Color = .secondary
    var url: String?

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundColor(color)
        .onTapGesture {
            if let url, let nsURL = URL(string: url) {
                NSWorkspace.shared.open(nsURL)
            }
        }
    }
}

