import AppKit
import Combine
import Foundation

/// Manages the lifecycle of IDE workspaces within a single window.
///
/// WorkspaceController holds a list of IDEWorkspaces and coordinates which one
/// is visible. Only the active workspace's SplitTree is rendered; others are
/// hidden but their terminal processes stay alive.
///
/// Project = UI-only grouping (a tag on workspaces). Switching projects changes
/// which workspaces appear in the bottom bar. No surface lifecycle cost.
final class WorkspaceController: ObservableObject {
    static let shared = WorkspaceController()

    // MARK: - Published State

    /// All workspaces across all projects.
    @Published private(set) var workspaces: [IDEWorkspace] = []

    /// The currently active workspace (visible, receiving input).
    @Published private(set) var activeWorkspace: IDEWorkspace?

    /// The active project filter. Only workspaces matching this tag are shown.
    @Published var activeProject: String = ""

    /// Last-active workspace per project (for restoring position on project switch).
    private var lastActivePerProject: [String: UUID] = [:]

    // MARK: - Computed

    /// Workspaces filtered by the active project.
    var filteredWorkspaces: [IDEWorkspace] {
        if activeProject.isEmpty {
            return workspaces
        }
        return workspaces.filter { $0.project == activeProject }
    }

    /// All unique project names.
    var projects: [String] {
        Array(Set(workspaces.map(\.project))).sorted()
    }

    /// Index of the active workspace within the filtered list.
    var activeIndex: Int? {
        guard let active = activeWorkspace else { return nil }
        return filteredWorkspaces.firstIndex(where: { $0.id == active.id })
    }

    // MARK: - Workspace CRUD

    /// Add a new workspace. Does not activate it.
    @discardableResult
    func addWorkspace(
        name: String,
        project: String,
        color: NSColor? = nil,
        emoji: String? = nil
    ) -> IDEWorkspace {
        let ws = IDEWorkspace(name: name, project: project, color: color, emoji: emoji)
        workspaces.append(ws)

        // If this is the first workspace or matches active project with no active,
        // set the project filter.
        if activeProject.isEmpty {
            activeProject = project
        }

        return ws
    }

    /// Remove a workspace. If it was active, switch to an adjacent one.
    func removeWorkspace(id: UUID) {
        // Find position in filtered list *before* removal for correct fallback
        let filteredIndex = filteredWorkspaces.firstIndex(where: { $0.id == id })
        guard let index = workspaces.firstIndex(where: { $0.id == id }) else { return }

        let wasActive = activeWorkspace?.id == id
        workspaces.remove(at: index)

        if wasActive {
            let filtered = filteredWorkspaces
            if let fi = filteredIndex, !filtered.isEmpty {
                // Pick the workspace that was next; if we removed the last, pick the new last
                switchTo(workspace: filtered[min(fi, filtered.count - 1)])
            } else if let first = filtered.first {
                switchTo(workspace: first)
            } else {
                activeWorkspace = nil
            }
        }
    }

    /// Rename a workspace.
    func renameWorkspace(id: UUID, name: String) {
        guard let ws = workspaces.first(where: { $0.id == id }) else { return }
        ws.name = name
    }

    // MARK: - Switching

    /// Switch to a specific workspace. Creates surfaces lazily on first visit.
    func switchTo(workspace: IDEWorkspace) {
        guard workspace.id != activeWorkspace?.id else { return }

        // Save current position for current project
        if let current = activeWorkspace {
            lastActivePerProject[current.project] = current.id
        }

        activeWorkspace = workspace

        // Lazy surface creation happens in the UI layer:
        // When the UI detects activeWorkspace changed, it checks isVisited
        // and creates surfaces if needed.
    }

    /// Switch to workspace by name (within active project).
    func switchTo(name: String) -> Bool {
        guard let ws = filteredWorkspaces.first(where: { $0.name == name }) else {
            return false
        }
        switchTo(workspace: ws)
        return true
    }

    /// Switch to next workspace (within active project).
    func switchNext() {
        let filtered = filteredWorkspaces
        guard !filtered.isEmpty, let index = activeIndex else { return }
        let next = (index + 1) % filtered.count
        switchTo(workspace: filtered[next])
    }

    /// Switch to previous workspace (within active project).
    func switchPrevious() {
        let filtered = filteredWorkspaces
        guard !filtered.isEmpty, let index = activeIndex else { return }
        let prev = (index - 1 + filtered.count) % filtered.count
        switchTo(workspace: filtered[prev])
    }

    /// Switch to workspace by 1-based index (within active project).
    func switchToIndex(_ index: Int) {
        let filtered = filteredWorkspaces
        guard index >= 1, index <= filtered.count else { return }
        switchTo(workspace: filtered[index - 1])
    }

    // MARK: - Project Switching

    /// Switch the active project filter. Instant — no surface lifecycle cost.
    func switchProject(name: String) {
        guard name != activeProject else { return }
        activeProject = name

        // Restore last-active workspace for this project, or first available
        let filtered = filteredWorkspaces
        if let lastId = lastActivePerProject[name],
           let ws = filtered.first(where: { $0.id == lastId }) {
            switchTo(workspace: ws)
        } else if let first = filtered.first {
            switchTo(workspace: first)
        } else {
            activeWorkspace = nil
        }
    }

    // MARK: - Metadata

    /// Set extensible metadata on a workspace.
    func setMetadata(workspaceName: String, key: String, value: String, icon: String? = nil, url: String? = nil) -> Bool {
        guard let ws = workspaces.first(where: { $0.name == workspaceName }) else {
            return false
        }
        ws.setMetadata(key: key, value: value, icon: icon, url: url)
        return true
    }

    /// Clear a metadata entry from a workspace.
    func clearMetadata(workspaceName: String, key: String) -> Bool {
        guard let ws = workspaces.first(where: { $0.name == workspaceName }) else {
            return false
        }
        ws.clearMetadata(key: key)
        return true
    }

    // MARK: - Query

    /// Find a workspace by ID.
    func workspace(byId id: UUID) -> IDEWorkspace? {
        workspaces.first { $0.id == id }
    }

    /// Find a workspace by name (searches all projects).
    func workspace(byName name: String) -> IDEWorkspace? {
        workspaces.first { $0.name == name }
    }

    /// Serialize current state for socket/CLI responses.
    func listAsDict() -> [[String: Any]] {
        filteredWorkspaces.map { ws in
            var dict: [String: Any] = [
                "id": ws.id.uuidString,
                "name": ws.name,
                "project": ws.project,
                "is_active": ws.id == activeWorkspace?.id,
                "is_visited": ws.isVisited,
            ]
            if let emoji = ws.emoji { dict["emoji"] = emoji }
            if let branch = ws.gitBranch { dict["git_branch"] = branch }
            if let state = ws.agentState { dict["agent_state"] = state.rawValue }
            if ws.unreadNotifications > 0 { dict["unread"] = ws.unreadNotifications }
            if !ws.metadata.isEmpty {
                dict["metadata"] = ws.metadata.mapValues { meta -> [String: String] in
                    var d: [String: String] = ["value": meta.value]
                    if let icon = meta.icon { d["icon"] = icon }
                    if let url = meta.url { d["url"] = url }
                    return d
                }
            }
            return dict
        }
    }
}
