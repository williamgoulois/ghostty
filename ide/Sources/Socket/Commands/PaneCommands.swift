import AppKit
import GhosttyKit

extension IDECommandRouter {
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
                if let surfacePtr = surface.surface {
                    let pid = ghostty_surface_foreground_pid(surfacePtr)
                    if pid > 0 {
                        processName = IDEProcessInfo.processName(for: pid_t(pid)) ?? ""
                    }
                }

                // Only the active workspace's surfaces are in the window
                let isFocused = ws.id == activeWsId && surface.focused

                panes.append([
                    "id": surface.id.uuidString,
                    "title": surface.title,
                    "pwd": surface.pwd ?? "",
                    "window_id": surface.window?.windowNumber ?? 0,
                    "focused": isFocused,
                    "foreground_process": processName,
                    "workspace": ws.name,
                    "project": ws.project,
                ])
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

            guard let keyWindow = NSApp.keyWindow,
                  let controller = keyWindow.windowController as? BaseTerminalController,
                  let focusedSurface = controller.focusedSurface,
                  let surface = focusedSurface.surface else {
                return .failure("No active terminal surface")
            }

            ghostty_surface_split(surface, direction)
            return .success(["direction": dirStr])
        }

        register("pane.focus") { command in
            guard let idStr = command.args?["id"]?.value as? String,
                  let targetID = UUID(uuidString: idStr) else {
                return .failure("Missing or invalid 'id' argument")
            }

            for window in NSApp.windows {
                guard let controller = window.windowController as? BaseTerminalController else {
                    continue
                }
                for surface in controller.surfaceTree where surface.id == targetID {
                    window.makeKeyAndOrderFront(nil)
                    window.makeFirstResponder(surface)
                    return .success(["id": idStr])
                }
            }
            return .failure("Pane not found: \(idStr)")
        }

        register("pane.focus-direction") { command in
            let dirStr = (command.args?["direction"]?.value as? String) ?? ""
            guard !dirStr.isEmpty else {
                return .failure("Missing 'direction' argument (left, right, up, down)")
            }

            guard ["left", "right", "up", "down"].contains(dirStr) else {
                return .failure("Invalid direction: \(dirStr). Use: left, right, up, down")
            }

            guard let keyWindow = NSApp.keyWindow,
                  let controller = keyWindow.windowController as? BaseTerminalController,
                  let focusedSurface = controller.focusedSurface,
                  let surface = focusedSurface.surface else {
                return .failure("No active terminal surface")
            }

            let action = "goto_split:\(dirStr)"
            let ok = ghostty_surface_binding_action(
                surface,
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

            for window in NSApp.windows {
                guard let controller = window.windowController as? BaseTerminalController else {
                    continue
                }
                for surface in controller.surfaceTree where surface.id == targetID {
                    controller.closeSurface(surface, withConfirmation: false)
                    return .success(["id": idStr])
                }
            }
            return .failure("Pane not found: \(idStr)")
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
