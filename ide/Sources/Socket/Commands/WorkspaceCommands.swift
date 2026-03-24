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
    }
}
