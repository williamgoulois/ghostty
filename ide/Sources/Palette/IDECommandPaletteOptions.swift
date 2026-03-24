import SwiftUI

/// Builds CommandOption entries for IDE-specific commands in the command palette.
struct IDECommandPaletteOptions {

    /// All IDE command options for the palette.
    /// Projects are loaded dynamically from disk each time the palette opens.
    static func options(
        onSaveProject: @escaping () -> Void,
        onRestoreProject: @escaping (String) -> Void,
        onDeleteProject: @escaping (String) -> Void
    ) -> [CommandOption] {
        var opts: [CommandOption] = []

        // --- Project commands ---

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
            title: "Notifications: Clear All",
            description: "Clear all IDE notifications",
            leadingIcon: "bell.slash",
            action: { NotificationManager.shared.clearAll() }
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
