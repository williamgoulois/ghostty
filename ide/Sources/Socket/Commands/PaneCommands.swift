import AppKit
import GhosttyKit

extension IDECommandRouter {
    func registerPaneCommands() {
        register("pane.list") { _ in
            var panes: [[String: Any]] = []
            for window in NSApp.windows {
                guard let controller = window.windowController as? BaseTerminalController else {
                    continue
                }
                for surface in controller.surfaceTree {
                    panes.append([
                        "id": surface.id.uuidString,
                        "title": surface.title,
                        "pwd": surface.pwd ?? "",
                        "window_id": window.windowNumber,
                        "focused": surface.focused,
                    ])
                }
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
    }
}
