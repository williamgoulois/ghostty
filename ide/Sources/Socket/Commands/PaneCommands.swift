import AppKit
import GhosttyKit

extension IDECommandRouter {

    /// Find the currently focused surface, trying NSApp.keyWindow first,
    /// then falling back to WorkspaceController's active workspace.
    /// This ensures commands work even when GhosttyIDE isn't the frontmost app.
    private static func focusedSurfaceView() -> (
        surface: Ghostty.SurfaceView, ghostty: ghostty_surface_t
    )? {
        // Try key window first (works when app is focused)
        if let keyWindow = NSApp.keyWindow,
           let controller = keyWindow.windowController as? BaseTerminalController,
           let surfaceView = controller.focusedSurface,
           let surface = surfaceView.surface {
            return (surfaceView, surface)
        }

        // Fall back to WorkspaceController (works without focus)
        if let ws = WorkspaceController.shared.activeWorkspace,
           let surfaceView = ws.focusedSurface,
           let surface = surfaceView.surface {
            // Ensure the window is brought forward
            if let window = surfaceView.window {
                window.makeKeyAndOrderFront(nil)
            }
            return (surfaceView, surface)
        }

        // Last resort: try the terminal controller directly
        if let ctrl = WorkspaceController.shared.terminalController,
           let surfaceView = ctrl.focusedSurface,
           let surface = surfaceView.surface {
            return (surfaceView, surface)
        }

        return nil
    }

    func registerPaneCommands() {
        register("pane.list") { command in
            let filterProject = command.args?["project"]?.value as? String
            let filterWorkspace = command.args?["workspace"]?.value as? String

            var panes: [[String: Any]] = []
            let activeWsId = WorkspaceController.shared.activeWorkspace?.id

            for (surface, ws) in WorkspaceController.shared.allSurfaces() {
                if let fp = filterProject, ws.project != fp { continue }
                if let fw = filterWorkspace, ws.name != fw { continue }
                // Foreground process detection
                var processName: String = ""
                var foregroundPid: Int = 0
                if let surfacePtr = surface.surface {
                    let pid = ghostty_surface_foreground_pid(surfacePtr)
                    if pid > 0 {
                        foregroundPid = Int(pid)
                        processName = IDEProcessInfo.processName(for: pid_t(pid)) ?? ""
                    }
                }

                // Process category + ports from cached scanner snapshot
                let category = processName.isEmpty
                    ? ProcessCategory.unknown.rawValue
                    : ProcessScanner.classify(processName).rawValue
                let snapshot = ProcessScanner.shared.lastSnapshot[ws.id]
                let panePorts = snapshot?.ports
                    .filter { $0.paneId == surface.id }
                    .map { Int($0.port) } ?? []

                // Agent status from merged detection
                let agentStatus: String? = snapshot?.processes
                    .first(where: { $0.paneId == surface.id && $0.category == .agent })?
                    .agentStatus

                // Only the active workspace's surfaces are in the window
                let isFocused = ws.id == activeWsId && surface.focused

                var paneDict: [String: Any] = [
                    "id": surface.id.uuidString,
                    "title": surface.title,
                    "pwd": surface.pwd ?? "",
                    "window_id": surface.window?.windowNumber ?? 0,
                    "focused": isFocused,
                    "foreground_process": processName,
                    "foreground_pid": foregroundPid,
                    "process_category": category,
                    "ports": panePorts,
                    "workspace": ws.name,
                    "project": ws.project,
                ]
                if let agentStatus {
                    paneDict["agent_status"] = agentStatus
                }
                panes.append(paneDict)
            }
            return .success(["panes": panes])
        }

        register("pane.split") { command in
            let dirStr = (command.args?["direction"]?.value as? String) ?? "right"
            let direction: ghostty_action_split_direction_e
            switch dirStr {
            case "right": direction = GHOSTTY_SPLIT_DIRECTION_RIGHT
            case "left": direction = GHOSTTY_SPLIT_DIRECTION_LEFT
            case "down": direction = GHOSTTY_SPLIT_DIRECTION_DOWN
            case "up": direction = GHOSTTY_SPLIT_DIRECTION_UP
            default: return .failure("Invalid direction: \(dirStr). Use: right, left, up, down")
            }

            guard let focused = IDECommandRouter.focusedSurfaceView() else {
                return .failure("No active terminal surface")
            }

            ghostty_surface_split(focused.ghostty, direction)
            return .success(["direction": dirStr])
        }

        register("pane.focus") { command in
            guard let idStr = command.args?["id"]?.value as? String,
                  let targetID = UUID(uuidString: idStr) else {
                return .failure("Missing or invalid 'id' argument")
            }

            guard let (surface, ws) = WorkspaceController.shared.findSurface(id: targetID) else {
                return .failure("Pane not found: \(idStr)")
            }

            // Switch workspace if needed
            if ws.id != WorkspaceController.shared.activeWorkspace?.id {
                WorkspaceController.shared.switchTo(workspace: ws)
            }

            if let window = surface.window {
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(surface)
            }
            return .success(["id": idStr])
        }

        register("pane.focus-direction") { command in
            let dirStr = (command.args?["direction"]?.value as? String) ?? ""
            guard !dirStr.isEmpty else {
                return .failure("Missing 'direction' argument (left, right, up, down)")
            }

            guard ["left", "right", "up", "down"].contains(dirStr) else {
                return .failure("Invalid direction: \(dirStr). Use: left, right, up, down")
            }

            guard let focused = IDECommandRouter.focusedSurfaceView() else {
                return .failure("No active terminal surface")
            }

            let action = "goto_split:\(dirStr)"
            let ok = ghostty_surface_binding_action(
                focused.ghostty,
                action,
                UInt(action.lengthOfBytes(using: .utf8))
            )
            if ok {
                return .success(["direction": dirStr])
            } else {
                return .success(["direction": dirStr, "at_edge": true])
            }
        }

        register("pane.close") { command in
            guard let idStr = command.args?["id"]?.value as? String,
                  let targetID = UUID(uuidString: idStr) else {
                return .failure("Missing or invalid 'id' argument")
            }

            guard let (surface, ws) = WorkspaceController.shared.findSurface(id: targetID) else {
                return .failure("Pane not found: \(idStr)")
            }

            // Switch workspace if needed so the surface is in the active tree
            if ws.id != WorkspaceController.shared.activeWorkspace?.id {
                WorkspaceController.shared.switchTo(workspace: ws)
            }

            guard let window = surface.window,
                  let controller = window.windowController as? BaseTerminalController else {
                return .failure("Surface not attached to a window: \(idStr)")
            }

            controller.closeSurface(surface, withConfirmation: false)
            return .success(["id": idStr])
        }

        register("pane.send-text") { command in
            guard let idStr = command.args?["id"]?.value as? String,
                  let targetID = UUID(uuidString: idStr) else {
                return .failure("Missing or invalid 'id' argument")
            }

            guard let text = command.args?["text"]?.value as? String, !text.isEmpty else {
                return .failure("Missing or empty 'text' argument")
            }

            let shouldFocus = (command.args?["focus"]?.value as? String) == "true"
                || (command.args?["focus"]?.value as? Bool) == true

            guard let (surface, ws) = WorkspaceController.shared.findSurface(id: targetID) else {
                return .failure("Pane not found: \(idStr)")
            }

            guard let surfaceModel = surface.surfaceModel else {
                return .failure("Surface model not available for pane: \(idStr)")
            }

            // If target is in a different workspace, switch to it first
            if ws.id != WorkspaceController.shared.activeWorkspace?.id {
                WorkspaceController.shared.switchTo(workspace: ws)
            }

            // Handler runs on main thread (DispatchQueue.main.sync in SocketServer),
            // but sendText is @MainActor so we need to tell the compiler.
            MainActor.assumeIsolated {
                surfaceModel.sendText(text)
            }

            if shouldFocus {
                if let window = surface.window {
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(surface)
                }
            }

            return .success([
                "id": idStr,
                "text_length": text.count,
                "focused": shouldFocus,
            ])
        }
    }
}
