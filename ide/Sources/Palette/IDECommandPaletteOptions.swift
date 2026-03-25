import SwiftUI

/// Builds CommandOption entries for IDE-specific commands in the command palette.
struct IDECommandPaletteOptions {

    /// All IDE command options for the palette.
    /// Workspaces and projects are loaded dynamically each time the palette opens.
    static func options(
        onSaveProject: @escaping () -> Void,
        onRestoreProject: @escaping (String) -> Void,
        onDeleteProject: @escaping (String) -> Void,
        onNewWorkspace: @escaping () -> Void
    ) -> [CommandOption] {
        var opts: [CommandOption] = []

        // --- Workspace commands ---

        opts.append(CommandOption(
            title: "Workspace: New",
            description: "Create a new workspace in the current project",
            leadingIcon: "plus.rectangle",
            action: onNewWorkspace
        ))

        let controller = WorkspaceController.shared
        let filtered = controller.filteredWorkspaces

        for ws in filtered {
            let isActive = ws.id == controller.activeWorkspace?.id
            if isActive { continue } // skip active — already there

            var subtitle = ws.project
            if let branch = ws.gitBranch { subtitle += " · \(branch)" }
            if let agent = ws.agentState { subtitle += " · \(agent.rawValue)" }

            opts.append(CommandOption(
                title: "Workspace: Switch to \(ws.displayName)",
                subtitle: subtitle,
                leadingIcon: "rectangle.stack",
                leadingColor: ws.color.map { Color(nsColor: $0) },
                badge: ws.unreadNotifications > 0 ? "\(ws.unreadNotifications)" : nil,
                action: { controller.switchTo(workspace: ws) }
            ))
        }

        opts.append(CommandOption(
            title: "Workspace: Next",
            description: "Switch to the next workspace",
            leadingIcon: "chevron.right",
            action: { controller.switchNext() }
        ))

        opts.append(CommandOption(
            title: "Workspace: Previous",
            description: "Switch to the previous workspace",
            leadingIcon: "chevron.left",
            action: { controller.switchPrevious() }
        ))

        // --- Project switching ---

        let allProjects = controller.projects
        for project in allProjects {
            if project == controller.activeProject { continue }
            let count = controller.workspaces.filter { $0.project == project }.count
            opts.append(CommandOption(
                title: "Project: Switch to \(project)",
                subtitle: "\(count) workspace\(count == 1 ? "" : "s")",
                leadingIcon: "folder",
                action: { controller.switchProject(name: project) }
            ))
        }

        // --- Project save/restore ---

        opts.append(CommandOption(
            title: "Project: Save Current",
            description: "Save all windows as a named project",
            leadingIcon: "square.and.arrow.down",
            action: onSaveProject
        ))

        if let projects = try? WorkspaceStore.shared.list() {
            for p in projects {
                opts.append(CommandOption(
                    title: "Project: Restore — \(p.name)",
                    subtitle: "\(p.windowCount) windows, \(p.paneCount) panes",
                    leadingIcon: "arrow.uturn.backward",
                    action: { onRestoreProject(p.name) }
                ))
            }
            for p in projects {
                opts.append(CommandOption(
                    title: "Project: Delete — \(p.name)",
                    description: "Permanently remove this saved project",
                    leadingIcon: "trash",
                    action: { onDeleteProject(p.name) }
                ))
            }
        }

        opts.append(CommandOption(
            title: "Project: Close All Windows",
            description: "Close every terminal window",
            leadingIcon: "xmark.rectangle",
            action: { let _ = WorkspaceManager.shared.closeAll() }
        ))

        // --- Notification commands ---

        opts.append(CommandOption(
            title: "Notifications: Show Panel",
            description: "Toggle the notification panel",
            leadingIcon: "bell",
            action: {
                NotificationCenter.default.post(name: .ideToggleNotificationPanel, object: nil)
            }
        ))

        opts.append(CommandOption(
            title: "Notifications: Clear All",
            description: "Clear all IDE notifications",
            leadingIcon: "bell.slash",
            action: { NotificationManager.shared.clearAll() }
        ))

        opts.append(CommandOption(
            title: "Notifications: Mark All Read",
            description: "Reset unread count and dock badge",
            leadingIcon: "bell.badge.slash",
            action: { NotificationManager.shared.markAllRead() }
        ))

        // --- Status commands ---

        opts.append(CommandOption(
            title: "Status: Clear All",
            description: "Clear all per-pane status entries",
            leadingIcon: "gauge.with.dots.needle.0percent",
            action: { StatusStore.shared.clear(paneId: nil, key: nil) }
        ))

        return opts
    }
}
