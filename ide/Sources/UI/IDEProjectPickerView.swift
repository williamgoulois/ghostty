import SwiftUI

/// Palette mode: regular commands (Cmd+Shift+P) or project picker (Cmd+P).
/// Shared between TerminalView (sets mode) and TerminalCommandPaletteView (reads mode).
enum IDEPaletteMode {
    case commands
    case projects
}

/// Shared state so TerminalView can tell the command palette which options to show.
final class IDEPaletteState {
    static var mode: IDEPaletteMode = .commands
}

/// Builds the project picker options shown when Cmd+P opens the command palette.
enum IDEProjectPickerOptions {
    static func options(onNewProject: @escaping () -> Void) -> [CommandOption] {
        var options: [CommandOption] = []
        let controller = WorkspaceController.shared

        // Live projects — alphabetical
        let liveProjects = controller.projects
        for project in liveProjects {
            let count = controller.workspaces.filter { $0.project == project }.count
            let isActive = project == controller.activeProject
            let emoji = controller.workspaces.first(where: { $0.project == project })?.emoji

            let title: String
            if let emoji = emoji {
                title = "\(emoji) \(project)"
            } else {
                title = project
            }

            options.append(CommandOption(
                title: title,
                subtitle: "\(count) workspace\(count == 1 ? "" : "s")",
                leadingIcon: isActive ? "folder.fill" : "folder",
                badge: isActive ? "active" : nil
            ) {
                controller.switchProject(name: project)
            })
        }

        // Saved-but-not-loaded projects
        if let saved = try? WorkspaceStore.shared.list() {
            let loadedNames = Set(liveProjects)
            let unloaded = saved.filter { !loadedNames.contains($0.name) }
            for p in unloaded {
                options.append(CommandOption(
                    title: "Restore: \(p.name)",
                    subtitle: "\(p.windowCount) windows, \(p.paneCount) panes",
                    leadingIcon: "arrow.uturn.backward"
                ) {
                    _ = try? WorkspaceManager.shared.restore(name: p.name)
                })
            }
        }

        // "New Project..." — always last
        options.append(CommandOption(
            title: "New Project...",
            subtitle: "Create with a default 'main' workspace",
            leadingIcon: "plus.rectangle.on.folder",
            emphasis: false,
            action: onNewProject
        ))

        return options
    }
}
