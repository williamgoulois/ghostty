import SwiftUI

/// Bottom bar showing workspace pills for the active project.
/// Active workspace = accent color, others = muted. Shows emoji, name, indicators.
struct IDEBottomBarView: View {
    @ObservedObject var controller: WorkspaceController

    var body: some View {
        HStack(spacing: 0) {
            // Left: workspace pills (scrollable if many)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(controller.filteredWorkspaces) { ws in
                        WorkspacePill(
                            workspace: ws,
                            isActive: ws.id == controller.activeWorkspace?.id
                        ) {
                            controller.switchTo(workspace: ws)
                        }
                    }
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)

            // Build marker — bump each rebuild to verify running build
            Text("b10")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.5))
                .padding(.trailing, 6)
        }
        .frame(height: 28)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
    }
}

/// A single workspace pill in the bottom bar.
struct WorkspacePill: View {
    @ObservedObject var workspace: IDEWorkspace
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                // Emoji
                if let emoji = workspace.emoji {
                    Text(emoji)
                        .font(.system(size: 10))
                }

                // Name
                Text(workspace.name)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)

                // Agent status indicator
                if let status = workspace.agentStatus {
                    let style = AgentStateStyle.from(status)
                    Image(systemName: style.icon)
                        .font(.system(size: 8))
                        .foregroundColor(agentColor(style))
                }

                // Notification dot
                if workspace.unreadNotifications > 0 {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundColor(isActive ? .white : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(pillBackground)
            )
        }
        .buttonStyle(.plain)
    }

    private var pillBackground: Color {
        if isActive {
            if let color = workspace.color {
                return Color(nsColor: color).opacity(0.8)
            }
            return Color.accentColor.opacity(0.8)
        }
        return Color.secondary.opacity(0.12)
    }

    private func agentColor(_ style: AgentStateStyle) -> Color {
        switch style {
        case .idle: return .secondary
        case .working: return .blue
        case .waiting: return .orange
        case .error: return .red
        }
    }
}
