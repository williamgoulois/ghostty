import AppKit

extension IDECommandRouter {
    func registerStatusCommands() {
        register("status.set") { command in
            guard let key = command.args?["key"]?.value as? String, !key.isEmpty else {
                return .failure("Missing 'key' argument")
            }
            guard let value = command.args?["value"]?.value as? String else {
                return .failure("Missing 'value' argument")
            }

            // Use provided pane_id, or fall back to the focused pane.
            let paneId: String
            if let id = command.args?["pane_id"]?.value as? String, !id.isEmpty {
                paneId = id
            } else if let focusedSurface = (NSApp.keyWindow?.windowController as? BaseTerminalController)?.focusedSurface {
                paneId = focusedSurface.id.uuidString
            } else {
                return .failure("No pane_id provided and no focused pane")
            }

            StatusStore.shared.set(paneId: paneId, key: key, value: value)
            return .success(["key": key, "value": value, "pane_id": paneId])
        }

        register("status.clear") { command in
            let paneId = command.args?["pane_id"]?.value as? String
            let key = command.args?["key"]?.value as? String
            StatusStore.shared.clear(paneId: paneId, key: key)
            return .success()
        }

        register("status.list") { command in
            let paneId = command.args?["pane_id"]?.value as? String
            let statuses = StatusStore.shared.list(paneId: paneId)
            return .success(["statuses": statuses])
        }
    }
}
