import AppKit

extension IDECommandRouter {
    func registerWorkspaceCommands() {
        register("project.save") { command in
            guard let name = command.args?["name"]?.value as? String, !name.isEmpty else {
                return .failure("Missing project name")
            }

            do {
                let project = try WorkspaceManager.shared.save(name: name)
                return .success([
                    "name": name,
                    "windows": project.windowCount,
                    "panes": project.paneCount,
                    "saved_at": project.savedAt,
                ])
            } catch {
                return .failure(error.localizedDescription)
            }
        }

        register("project.restore") { command in
            guard let name = command.args?["name"]?.value as? String, !name.isEmpty else {
                return .failure("Missing project name")
            }

            do {
                let windowsCreated = try WorkspaceManager.shared.restore(name: name)
                return .success([
                    "name": name,
                    "windows_created": windowsCreated,
                ])
            } catch {
                return .failure(error.localizedDescription)
            }
        }

        register("project.list") { _ in
            do {
                let projects = try WorkspaceManager.shared.list()
                let items: [[String: Any]] = projects.map { p in
                    [
                        "name": p.name,
                        "windows": p.windowCount,
                        "panes": p.paneCount,
                        "saved_at": p.savedAt,
                    ]
                }
                return .success(["projects": items])
            } catch {
                return .failure(error.localizedDescription)
            }
        }

        register("project.delete") { command in
            guard let name = command.args?["name"]?.value as? String, !name.isEmpty else {
                return .failure("Missing project name")
            }

            do {
                try WorkspaceManager.shared.delete(name: name)
                return .success(["name": name])
            } catch {
                return .failure(error.localizedDescription)
            }
        }

        register("project.close-all") { _ in
            let closed = WorkspaceManager.shared.closeAll()
            return .success(["closed": closed])
        }

        // --- Live workspace commands (Phase 7) ---

        register("workspace.new") { command in
            guard let name = command.args?["name"]?.value as? String, !name.isEmpty else {
                return .failure("Missing workspace name")
            }
            let project = command.args?["project"]?.value as? String ?? WorkspaceController.shared.activeProject
            guard !project.isEmpty else {
                return .failure("Missing project name (no active project)")
            }

            let colorHex = command.args?["color"]?.value as? String
            let emoji = command.args?["emoji"]?.value as? String

            var color: NSColor? = nil
            if let hex = colorHex {
                color = NSColor(hex: hex)
            }

            let ws = WorkspaceController.shared.addWorkspace(
                name: name, project: project, color: color, emoji: emoji
            )
            return .success([
                "id": ws.id.uuidString,
                "name": ws.name,
                "project": ws.project,
            ])
        }

        register("workspace.switch") { command in
            if let name = command.args?["name"]?.value as? String, !name.isEmpty {
                if WorkspaceController.shared.switchTo(name: name) {
                    return .success(["name": name])
                }
                return .failure("Workspace not found: \(name)")
            }
            return .failure("Missing workspace name")
        }

        register("workspace.next") { _ in
            WorkspaceController.shared.switchNext()
            let active = WorkspaceController.shared.activeWorkspace
            return .success(["name": active?.name ?? ""])
        }

        register("workspace.previous") { _ in
            WorkspaceController.shared.switchPrevious()
            let active = WorkspaceController.shared.activeWorkspace
            return .success(["name": active?.name ?? ""])
        }

        register("workspace.list") { _ in
            let items = WorkspaceController.shared.listAsDict()
            return .success(["workspaces": items])
        }

        register("workspace.rename") { command in
            guard let name = command.args?["name"]?.value as? String, !name.isEmpty,
                  let newName = command.args?["new_name"]?.value as? String, !newName.isEmpty else {
                return .failure("Missing name or new_name")
            }
            guard let ws = WorkspaceController.shared.workspace(byName: name) else {
                return .failure("Workspace not found: \(name)")
            }
            WorkspaceController.shared.renameWorkspace(id: ws.id, name: newName)
            return .success(["old_name": name, "new_name": newName])
        }

        register("workspace.remove") { command in
            guard let name = command.args?["name"]?.value as? String, !name.isEmpty else {
                return .failure("Missing workspace name")
            }
            guard let ws = WorkspaceController.shared.workspace(byName: name) else {
                return .failure("Workspace not found: \(name)")
            }
            WorkspaceController.shared.removeWorkspace(id: ws.id)
            return .success(["name": name])
        }

        register("workspace.meta.set") { command in
            guard let workspace = command.args?["workspace"]?.value as? String, !workspace.isEmpty,
                  let key = command.args?["key"]?.value as? String, !key.isEmpty,
                  let value = command.args?["value"]?.value as? String else {
                return .failure("Missing workspace, key, or value")
            }
            let icon = command.args?["icon"]?.value as? String
            let url = command.args?["url"]?.value as? String

            if WorkspaceController.shared.setMetadata(workspaceName: workspace, key: key, value: value, icon: icon, url: url) {
                return .success(["workspace": workspace, "key": key, "value": value])
            }
            return .failure("Workspace not found: \(workspace)")
        }

        register("workspace.meta.clear") { command in
            guard let workspace = command.args?["workspace"]?.value as? String, !workspace.isEmpty,
                  let key = command.args?["key"]?.value as? String, !key.isEmpty else {
                return .failure("Missing workspace or key")
            }
            if WorkspaceController.shared.clearMetadata(workspaceName: workspace, key: key) {
                return .success(["workspace": workspace, "key": key])
            }
            return .failure("Workspace not found: \(workspace)")
        }

        register("project.rename") { command in
            guard let name = command.args?["name"]?.value as? String, !name.isEmpty,
                  let newName = command.args?["new_name"]?.value as? String, !newName.isEmpty else {
                return .failure("Missing name or new_name")
            }
            if WorkspaceController.shared.renameProject(from: name, to: newName) {
                return .success(["old_name": name, "new_name": newName])
            }
            return .failure("Project not found: \(name)")
        }

        register("project.switch") { command in
            guard let name = command.args?["name"]?.value as? String, !name.isEmpty else {
                return .failure("Missing project name")
            }
            WorkspaceController.shared.switchProject(name: name)
            let active = WorkspaceController.shared.activeWorkspace
            return .success([
                "project": name,
                "active_workspace": active?.name ?? "",
            ])
        }
    }
}
