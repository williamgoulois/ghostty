import AppKit

extension IDECommandRouter {
    func registerSessionCommands() {
        register("session.save") { _ in
            let session = WorkspaceController.shared.captureSession()
            do {
                try IDESessionStore.shared.save(session)
                return .success([
                    "saved_at": session.savedAt,
                    "workspace_count": session.workspaces.count,
                ])
            } catch {
                return .failure(error.localizedDescription)
            }
        }

        register("session.info") { _ in
            guard IDESessionStore.shared.exists() else {
                return .success(["exists": false])
            }
            do {
                let session = try IDESessionStore.shared.load()
                return .success([
                    "exists": true,
                    "saved_at": session.savedAt,
                    "version": session.version,
                    "workspace_count": session.workspaces.count,
                    "workspaces": session.workspaces.map(\.name),
                    "projects": Array(Set(session.workspaces.map(\.project))).sorted(),
                    "active_project": session.activeProject,
                    "active_workspace": session.activeWorkspaceName ?? "",
                ])
            } catch {
                return .failure(error.localizedDescription)
            }
        }
    }
}
