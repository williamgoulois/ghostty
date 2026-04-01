import SwiftUI

/// Top bar showing active workspace context: name, git branch, agent state, extensible metadata.
/// Right side: project name + notification bell with popover panel.
struct IDETopBarView: View {
    @ObservedObject var controller: WorkspaceController
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var showNotificationPanel = false
    @State private var showProcessPanel = false
    @State private var showPortPanel = false

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
                // Project name (first element)
                if !controller.activeProject.isEmpty {
                    IDEMetadataChip(
                        icon: "folder",
                        text: controller.activeProject,
                        color: .secondary
                    )
                }

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

                // Agent status (click = focus agent pane)
                if let status = ws.agentStatus {
                    let style = AgentStateStyle.from(status)
                    IDEMetadataChip(
                        icon: style.icon,
                        text: status,
                        color: agentColor(style),
                        onTap: {
                            if let snapshot = ws.processSnapshot,
                               let agentPaneId = snapshot.agentPaneIds.first {
                                controller.jumpToPane(id: agentPaneId.uuidString)
                            }
                        }
                    )
                }

                // Port chips (click = focus pane, ⌘+click = open browser)
                if let snapshot = ws.processSnapshot {
                    ForEach(snapshot.ports) { port in
                        IDEPortChip(
                            port: port,
                            onFocusPane: {
                                controller.jumpToPane(id: port.paneId.uuidString)
                            },
                            onOpenBrowser: {
                                let urlStr = "\(port.scheme)://localhost:\(port.port)"
                                if let url = URL(string: urlStr) {
                                    NSWorkspace.shared.open(url)
                                }
                            }
                        )
                    }
                }

                // Extensible metadata entries (exclude port entries, rendered above)
                let nonPortMetadata = ws.metadata.values
                    .filter { !$0.key.hasPrefix("port:") }
                    .sorted { $0.key < $1.key }
                ForEach(nonPortMetadata, id: \.key) { entry in
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
            // Port panel button
            Button {
                showPortPanel.toggle()
            } label: {
                Image(systemName: "network")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showPortPanel, arrowEdge: .bottom) {
                PortPanelView(
                    isPresented: $showPortPanel,
                    snapshots: ProcessScanner.shared.lastSnapshot,
                    onJumpToPane: { paneId in
                        controller.jumpToPane(id: paneId)
                        showPortPanel = false
                    }
                )
            }

            // Process panel button
            Button {
                showProcessPanel.toggle()
            } label: {
                Image(systemName: "terminal")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showProcessPanel, arrowEdge: .bottom) {
                ProcessPanelView(
                    isPresented: $showProcessPanel,
                    snapshots: ProcessScanner.shared.lastSnapshot,
                    onJumpToPane: { paneId in
                        controller.jumpToPane(id: paneId)
                        showProcessPanel = false
                    },
                    onKillProcess: { pid, signal in
                        ProcessScanner.shared.killProcess(pid: pid, signal: signal)
                    }
                )
            }

            // Notification bell — global count across ALL projects/workspaces/panes
            let totalUnread = notificationManager.unreadPaneIds.count
            Button(action: { showNotificationPanel.toggle() }, label: {
                if totalUnread > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 10))
                        Text("\(totalUnread)")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.red))
                } else {
                    Image(systemName: "bell")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(width: 16, height: 16)
                }
            })
            .buttonStyle(.plain)
            .popover(isPresented: $showNotificationPanel, arrowEdge: .bottom) {
                NotificationPanelView(
                    isPresented: $showNotificationPanel,
                    notifications: notificationManager.recentNotifications,
                    onJumpToPane: { paneId in
                        controller.jumpToPane(id: paneId)
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

    private func agentColor(_ style: AgentStateStyle) -> Color {
        switch style {
        case .idle: return .secondary
        case .working: return .blue
        case .waiting: return .orange
        case .error: return .red
        }
    }
}

/// A port chip with click = focus pane, ⌘+click = open in browser.
struct IDEPortChip: View {
    let port: DetectedPort
    let onFocusPane: () -> Void
    let onOpenBrowser: () -> Void

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "network")
                .font(.system(size: 9))
            Text(verbatim: ":\(port.port)")
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
            if port.tls {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7))
            }
        }
        .foregroundColor(.secondary)
        .onTapGesture {
            if NSEvent.modifierFlags.contains(.command) {
                onOpenBrowser()
            } else {
                onFocusPane()
            }
        }
    }
}

/// A small pill showing icon + text for workspace metadata.
struct IDEMetadataChip: View {
    let icon: String
    let text: String
    var color: Color = .secondary
    var url: String?
    var onTap: (() -> Void)?

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
            if let onTap {
                onTap()
            } else if let url, let nsURL = URL(string: url) {
                NSWorkspace.shared.open(nsURL)
            }
        }
    }
}

