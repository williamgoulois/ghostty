import SwiftUI

/// Top bar showing active workspace context: name, git branch, agent state, extensible metadata.
/// Right side: project name + notification badge. Right edge is a drag handle.
struct IDETopBarView: View {
    @ObservedObject var controller: WorkspaceController

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

            // Notification badge
            let totalUnread = controller.filteredWorkspaces.reduce(0) { $0 + $1.unreadNotifications }
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
                .background(
                    Capsule().fill(Color.red)
                )
            }

            // Drag handle area (invisible but provides window drag)
            IDEDragHandleView()
                .frame(width: 40, height: 20)
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
    var url: String? = nil

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

/// An NSView-backed drag handle that allows window dragging.
struct IDEDragHandleView: NSViewRepresentable {
    func makeNSView(context: Context) -> DragHandleNSView {
        DragHandleNSView()
    }

    func updateNSView(_ nsView: DragHandleNSView, context: Context) {}

    class DragHandleNSView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            // Draw subtle grip dots
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            let dotColor = NSColor.tertiaryLabelColor
            context.setFillColor(dotColor.cgColor)

            let dotSize: CGFloat = 2
            let spacing: CGFloat = 4
            let cols = 3
            let rows = 2
            let totalWidth = CGFloat(cols) * dotSize + CGFloat(cols - 1) * spacing
            let totalHeight = CGFloat(rows) * dotSize + CGFloat(rows - 1) * spacing
            let startX = (bounds.width - totalWidth) / 2
            let startY = (bounds.height - totalHeight) / 2

            for row in 0..<rows {
                for col in 0..<cols {
                    let x = startX + CGFloat(col) * (dotSize + spacing)
                    let y = startY + CGFloat(row) * (dotSize + spacing)
                    context.fillEllipse(in: CGRect(x: x, y: y, width: dotSize, height: dotSize))
                }
            }
        }
    }
}
