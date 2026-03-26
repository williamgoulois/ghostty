import AppKit
import GhosttyKit

/// Executes IDE actions dispatched from the keybind registry.
///
/// Bridges keybindings to WorkspaceController, NotificationManager,
/// and Ghostty's surface binding action API.
final class IDEActionDispatcher {
    static let shared = IDEActionDispatcher()

    /// Dispatch an IDE action.
    ///
    /// - Parameters:
    ///   - action: The action to execute.
    ///   - surfaceView: The focused surface view (needed for vim detection and Ghostty actions).
    /// - Returns: `true` if the action was handled and the event should be consumed.
    ///            `false` if the event should pass through (e.g., vim passthrough).
    func dispatch(_ action: IDEAction, surfaceView: Ghostty.SurfaceView?) -> Bool {
        switch action {
        case .workspaceNew:
            promptNewWorkspace()
            return true

        case .workspaceNext:
            WorkspaceController.shared.switchNext()
            return true

        case .workspacePrevious:
            WorkspaceController.shared.switchPrevious()
            return true

        case .workspaceGoto(let index):
            WorkspaceController.shared.switchToIndex(index)
            return true

        case .workspaceClose:
            if let active = WorkspaceController.shared.activeWorkspace {
                WorkspaceController.shared.removeWorkspace(id: active.id)
            }
            return true

        case .workspaceRename:
            promptRenameWorkspace()
            return true

        case .focusDirection(let direction):
            return handleFocusDirection(direction, surfaceView: surfaceView)

        case .notificationsToggle:
            NotificationCenter.default.post(
                name: .ideToggleNotificationPanel,
                object: nil
            )
            return true

        case .notificationsJumpUnread:
            jumpToUnreadNotification()
            return true

        case .projectSwitch:
            // Cycle to next project
            let projects = WorkspaceController.shared.projects
            guard projects.count > 1 else { return true }
            let current = WorkspaceController.shared.activeProject
            if let idx = projects.firstIndex(of: current) {
                let next = projects[(idx + 1) % projects.count]
                WorkspaceController.shared.switchProject(name: next)
            }
            return true

        case .projectPicker:
            IDEPaletteState.mode = .projects
            return executeGhosttyAction("toggle_command_palette", surfaceView: surfaceView)

        case .projectRename:
            promptRenameProject()
            return true

        case .ghosttyAction(let actionStr):
            return executeGhosttyAction(actionStr, surfaceView: surfaceView)
        }
    }

    // MARK: - Vim-Aware Pane Navigation

    /// Handle directional pane focus with vim detection.
    ///
    /// If vim is running in the focused surface, returns `false` so the key
    /// passes through to the terminal. Neovim's mux-navigator will handle it
    /// and call `ide pane focus-direction` if at the edge of vim splits.
    ///
    /// If vim is NOT running, executes `goto_split:<direction>` natively.
    private func handleFocusDirection(
        _ direction: IDEDirection,
        surfaceView: Ghostty.SurfaceView?
    ) -> Bool {
        guard let view = surfaceView else { return false }

        // Check if vim is running — if so, let the key pass through.
        // Uses tcgetpgrp() on the PTY master fd (O(1) kernel call).
        if VimDetector.shared.isVimRunning(surface: view.surface) {
            return false // Caller will forward to terminal via keyDown()
        }

        // No vim: execute goto_split natively
        return executeGhosttyAction(direction.ghosttyAction, surfaceView: view)
    }

    // MARK: - Ghostty Action Forwarding

    /// Forward a raw action string to Ghostty's binding action API.
    private func executeGhosttyAction(
        _ actionStr: String,
        surfaceView: Ghostty.SurfaceView?
    ) -> Bool {
        guard let view = surfaceView, let surface = view.surface else {
            return false
        }

        let len = UInt(actionStr.lengthOfBytes(using: .utf8))
        return actionStr.withCString { cString in
            ghostty_surface_binding_action(surface, cString, len)
        }
    }

    // MARK: - Prompts

    /// Show a dialog to create a new workspace.
    private func promptNewWorkspace() {
        let alert = NSAlert()
        alert.messageText = "New Workspace"
        alert.informativeText = "Enter a name for the new workspace:"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.placeholderString = "workspace name"
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let project = WorkspaceController.shared.activeProject
        let ws = WorkspaceController.shared.addWorkspace(
            name: name,
            project: project.isEmpty ? "default" : project
        )
        WorkspaceController.shared.switchTo(workspace: ws)
    }

    /// Show a dialog to rename the current project.
    private func promptRenameProject() {
        let controller = WorkspaceController.shared
        let current = controller.activeProject
        guard !current.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText = "Rename Project"
        alert.informativeText = "Rename '\(current)' to:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = current
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        _ = controller.renameProject(from: current, to: name)
    }

    /// Show a dialog to rename the current workspace.
    private func promptRenameWorkspace() {
        guard let active = WorkspaceController.shared.activeWorkspace else { return }

        let alert = NSAlert()
        alert.messageText = "Rename Workspace"
        alert.informativeText = "Enter a new name:"
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        input.stringValue = active.name
        alert.accessoryView = input
        alert.window.initialFirstResponder = input

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = input.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        WorkspaceController.shared.renameWorkspace(id: active.id, name: name)
    }

    // MARK: - Notifications

    /// Jump to the first workspace with unread notifications.
    private func jumpToUnreadNotification() {
        let workspaces = WorkspaceController.shared.filteredWorkspaces
        if let ws = workspaces.first(where: { $0.unreadNotifications > 0 }) {
            WorkspaceController.shared.switchTo(workspace: ws)
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    /// Posted when the notification panel should be toggled.
    static let ideToggleNotificationPanel = Notification.Name("ideToggleNotificationPanel")
}
