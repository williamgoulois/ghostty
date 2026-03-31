import AppKit
import Combine
import Foundation
import OSLog

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
    private static let logger = IDELogger.make(for: WorkspaceController.self)

    // MARK: - Terminal Controller Bridge

    /// The terminal controller whose surfaceTree we swap when switching workspaces.
    /// Set by TerminalController under #if GHOSTTY_IDE.
    weak var terminalController: BaseTerminalController?

    // MARK: - Published State

    /// All workspaces across all projects.
    @Published private(set) var workspaces: [IDEWorkspace] = []

    /// The currently active workspace (visible, receiving input).
    @Published private(set) var activeWorkspace: IDEWorkspace?

    /// The active project filter. Only workspaces matching this tag are shown.
    @Published var activeProject: String = ""

    /// Last-active workspace per project (for restoring position on project switch).
    private var lastActivePerProject: [String: UUID] = [:]

    /// Deferred active workspace name (set during restore, activated after window creation).
    private var pendingActiveWorkspaceName: String?

    /// Background activity scheduler for periodic session auto-save.
    private var autoSaveActivity: NSBackgroundActivityScheduler?

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

        // Insert after the active workspace so new workspaces appear next to the current one.
        if let active = activeWorkspace,
           let idx = workspaces.firstIndex(where: { $0.id == active.id }) {
            workspaces.insert(ws, at: workspaces.index(after: idx))
        } else {
            workspaces.append(ws)
        }

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

    // MARK: - Close with Fallback

    /// Called when the active workspace's tree becomes empty (last pane closed).
    /// Removes the workspace and switches to a fallback. Returns `true` if a
    /// fallback was found (caller should NOT close the window).
    func closeActiveWorkspaceOrFallback() -> Bool {
        guard activeWorkspace != nil else { return false }

        // Clear undo to prevent stale entries referencing removed workspace
        terminalController?.undoManager?.removeAllActions()

        // removeWorkspace already handles fallback: picks adjacent in filtered list
        removeWorkspace(id: activeWorkspace!.id)

        // If removeWorkspace found a fallback, activeWorkspace is non-nil
        if activeWorkspace != nil { return true }

        // No workspaces in current project — try switching to another project
        if let other = workspaces.first {
            activeProject = other.project
            switchTo(workspace: other)
            return true
        }

        activeProject = ""
        return false // no workspaces left, let window close
    }

    // MARK: - Switching

    /// Switch to a specific workspace. Swaps the terminal controller's surfaceTree
    /// so each workspace has its own independent split layout with live PTY processes.
    func switchTo(workspace: IDEWorkspace) {
        guard workspace.id != activeWorkspace?.id else { return }

        // Save current tree + focus to outgoing workspace
        if let current = activeWorkspace, let ctrl = terminalController {
            current.splitTree = ctrl.surfaceTree
            current.focusedSurface = ctrl.focusedSurface
            lastActivePerProject[current.project] = current.id
        }

        // Cross-project jump: update activeProject so bars + picker stay in sync
        if workspace.project != activeProject {
            activeProject = workspace.project
        }

        activeWorkspace = workspace

        // Swap tree for incoming workspace
        guard let ctrl = terminalController else { return }
        if let tree = workspace.splitTree {
            // Revisiting — restore saved tree (surfaces are still alive)
            ctrl.surfaceTree = tree
            if let focused = workspace.focusedSurface {
                DispatchQueue.main.async {
                    ctrl.focusedSurface = focused
                    Ghostty.moveFocus(to: focused)
                }
            }
        } else if let treeData = workspace.pendingSurfaceTreeData {
            // Session restore — decode saved tree (creates surfaces with saved CWD)
            workspace.pendingSurfaceTreeData = nil
            let focusId = workspace.pendingFocusedSurfaceId
            workspace.pendingFocusedSurfaceId = nil
            do {
                let tree = try JSONDecoder().decode(
                    SplitTree<Ghostty.SurfaceView>.self, from: treeData)
                ctrl.surfaceTree = tree
                workspace.splitTree = tree
                if let focusId {
                    for surface in ctrl.surfaceTree where surface.id == focusId {
                        DispatchQueue.main.async {
                            ctrl.focusedSurface = surface
                            Ghostty.moveFocus(to: surface)
                        }
                        break
                    }
                }
            } catch {
                Self.logger.error("Tree restore failed, creating blank surface: \(error.localizedDescription)")
                guard let appDelegate = NSApp.delegate as? AppDelegate,
                      let ghostty_app = appDelegate.ghostty.app else { return }
                let surface = Ghostty.SurfaceView(ghostty_app, baseConfig: nil)
                ctrl.surfaceTree = .init(view: surface)
                workspace.splitTree = ctrl.surfaceTree
            }
        } else {
            // First visit — lazy surface creation
            guard let appDelegate = NSApp.delegate as? AppDelegate,
                  let ghostty_app = appDelegate.ghostty.app else { return }
            let surface = Ghostty.SurfaceView(ghostty_app, baseConfig: nil)
            ctrl.surfaceTree = .init(view: surface)
            workspace.splitTree = ctrl.surfaceTree
            // Match the "revisiting" branch: set focusedSurface + moveFocus together
            // in an async block so SwiftUI has a chance to lay out the new tree first.
            // moveFocus retries with backoff until .window is set.
            DispatchQueue.main.async {
                ctrl.focusedSurface = surface
                Ghostty.moveFocus(to: surface)
            }
        }
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

    /// Move the active workspace one position forward in the filtered list.
    func moveNext() {
        let filtered = filteredWorkspaces
        guard filtered.count > 1, let index = activeIndex else { return }
        let nextIndex = (index + 1) % filtered.count
        // Swap positions in the global workspaces array
        guard let globalA = workspaces.firstIndex(where: { $0.id == filtered[index].id }),
              let globalB = workspaces.firstIndex(where: { $0.id == filtered[nextIndex].id }) else { return }
        workspaces.swapAt(globalA, globalB)
    }

    /// Move the active workspace one position backward in the filtered list.
    func movePrevious() {
        let filtered = filteredWorkspaces
        guard filtered.count > 1, let index = activeIndex else { return }
        let prevIndex = (index - 1 + filtered.count) % filtered.count
        // Swap positions in the global workspaces array
        guard let globalA = workspaces.firstIndex(where: { $0.id == filtered[index].id }),
              let globalB = workspaces.firstIndex(where: { $0.id == filtered[prevIndex].id }) else { return }
        workspaces.swapAt(globalA, globalB)
    }

    // MARK: - Jump to Pane

    /// Jump to a specific pane by ID — switches workspace if needed, then focuses the pane.
    func jumpToPane(id paneId: String) {
        guard let uuid = UUID(uuidString: paneId),
              let result = findSurface(id: uuid) else { return }

        // Switch workspace if needed (handles cross-project too)
        if result.workspace.id != activeWorkspace?.id {
            switchTo(workspace: result.workspace)
        }

        // Focus the specific pane
        guard let ctrl = terminalController else { return }
        ctrl.focusedSurface = result.surface
        Ghostty.moveFocus(to: result.surface)
    }

    // MARK: - Break Pane

    /// Move the focused pane to a new workspace. Like tmux break-pane.
    func breakPaneToNewWorkspace() {
        guard let ctrl = terminalController,
              let focused = ctrl.focusedSurface,
              let node = ctrl.surfaceTree.root?.node(view: focused) else { return }

        // No-op if the workspace has only one pane (nothing to break out of)
        if !ctrl.surfaceTree.isSplit { return }

        // Compute the tree after removing the focused pane
        let newCurrentTree = ctrl.surfaceTree.removing(node)

        // Auto-generate workspace name
        let baseName = "pane"
        var name = baseName
        var counter = 1
        while workspaces.contains(where: { $0.name == name }) {
            counter += 1
            name = "\(baseName)-\(counter)"
        }

        let project = activeProject.isEmpty ? "default" : activeProject

        // Update the LIVE controller tree so the surface is removed from the
        // current workspace. This is critical: switchTo() saves ctrl.surfaceTree
        // to the outgoing workspace, so the live tree must already exclude the
        // extracted pane. If the tree is now empty, surfaceTreeDidChange will
        // fire but the #if GHOSTTY_IDE guard prevents window closure.
        ctrl.surfaceTree = newCurrentTree

        // Update focusedSurface to a remaining pane so switchTo() saves valid
        // focus state for the outgoing workspace.
        if let remainingRoot = newCurrentTree.root {
            ctrl.focusedSurface = remainingRoot.leftmostLeaf()
        }
        let oldWorkspace = activeWorkspace

        // Create new workspace with the extracted surface
        let ws = addWorkspace(name: name, project: project)
        ws.splitTree = SplitTree(view: focused)
        ws.focusedSurface = focused

        // Switch to the new workspace (handles live tree swap + focus)
        switchTo(workspace: ws)

        // If old workspace is now empty, remove it
        if let old = oldWorkspace, newCurrentTree.isEmpty {
            removeWorkspace(id: old.id)
        }

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

    // MARK: - Project Rename

    /// Rename a project (change the tag on all its workspaces).
    func renameProject(from oldName: String, to newName: String) -> Bool {
        guard !newName.isEmpty, oldName != newName else { return false }
        guard workspaces.contains(where: { $0.project == oldName }) else { return false }
        for ws in workspaces where ws.project == oldName {
            ws.project = newName
        }
        if activeProject == oldName { activeProject = newName }
        if let lastId = lastActivePerProject.removeValue(forKey: oldName) {
            lastActivePerProject[newName] = lastId
        }
        return true
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

    /// Find the workspace that contains a surface with the given pane ID.
    func workspace(containingPaneId paneId: String) -> IDEWorkspace? {
        for ws in workspaces {
            guard let root = liveRoot(for: ws) else { continue }
            if Self.treeContains(root, paneId: paneId) { return ws }
        }
        return nil
    }

    /// Count how many panes in a workspace are in the given unread set.
    func countUnreadPanes(in workspace: IDEWorkspace, unreadPaneIds: Set<String>) -> Int {
        guard let root = liveRoot(for: workspace) else { return 0 }
        return Self.countMatching(root, in: unreadPaneIds)
    }

    /// Enumerate all live surfaces across all workspaces.
    /// Returns tuples of (surface, workspace) for each visited workspace's surfaces.
    func allSurfaces() -> [(surface: Ghostty.SurfaceView, workspace: IDEWorkspace)] {
        var result: [(Ghostty.SurfaceView, IDEWorkspace)] = []
        for ws in workspaces {
            guard let root = liveRoot(for: ws) else { continue }
            for surface in root.leaves() {
                result.append((surface, ws))
            }
        }
        return result
    }

    /// Find a surface by UUID across all workspaces (active + inactive).
    func findSurface(id targetID: UUID) -> (surface: Ghostty.SurfaceView, workspace: IDEWorkspace)? {
        for ws in workspaces {
            guard let root = liveRoot(for: ws) else { continue }
            for surface in root.leaves() where surface.id == targetID {
                return (surface, ws)
            }
        }
        return nil
    }

    /// For the active workspace, use the live controller tree (the saved splitTree
    /// may be stale since SplitTree is a value type). For inactive workspaces, use
    /// the snapshot saved on last switch-away.
    private func liveRoot(for workspace: IDEWorkspace) -> SplitTree<Ghostty.SurfaceView>.Node? {
        if workspace.id == activeWorkspace?.id, let ctrl = terminalController {
            return ctrl.surfaceTree.root
        }
        return workspace.splitTree?.root
    }

    private static func treeContains(_ node: SplitTree<Ghostty.SurfaceView>.Node, paneId: String) -> Bool {
        switch node {
        case .leaf(let view): return view.id.uuidString == paneId
        case .split(let split): return treeContains(split.left, paneId: paneId)
                                     || treeContains(split.right, paneId: paneId)
        }
    }

    private static func countMatching(_ node: SplitTree<Ghostty.SurfaceView>.Node, in paneIds: Set<String>) -> Int {
        switch node {
        case .leaf(let view): return paneIds.contains(view.id.uuidString) ? 1 : 0
        case .split(let split): return countMatching(split.left, in: paneIds)
                                      + countMatching(split.right, in: paneIds)
        }
    }

    // MARK: - Session Persistence

    /// Capture current workspace state as a session file (metadata + split layout + CWD).
    func captureSession() -> IDESessionFile {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        // Sync active workspace's live tree before capturing
        if let active = activeWorkspace, let ctrl = terminalController {
            active.splitTree = ctrl.surfaceTree
            active.focusedSurface = ctrl.focusedSurface
        }

        var lastActiveMapped: [String: String] = [:]
        for (project, uuid) in lastActivePerProject {
            if let ws = workspace(byId: uuid) {
                lastActiveMapped[project] = ws.name
            }
        }

        let sessionWorkspaces = workspaces.map { ws -> IDESessionWorkspace in
            let metadataEntries = ws.metadata.mapValues { entry in
                IDESessionMetadataEntry(value: entry.value, icon: entry.icon, url: entry.url)
            }

            // Encode split tree if workspace has been visited
            var surfaceTreeCodable: AnyCodable?
            var focusedId: String?
            if let tree = ws.splitTree {
                if let data = try? JSONEncoder().encode(tree),
                   let codable = try? JSONDecoder().decode(AnyCodable.self, from: data) {
                    surfaceTreeCodable = codable
                }
            }
            if let surface = ws.focusedSurface {
                focusedId = surface.id.uuidString
            }

            return IDESessionWorkspace(
                name: ws.name,
                project: ws.project,
                colorHex: ws.color?.hexString,
                emoji: ws.emoji,
                metadata: metadataEntries,
                surfaceTree: surfaceTreeCodable,
                focusedSurfaceId: focusedId
            )
        }

        return IDESessionFile(
            version: IDESessionFile.currentVersion,
            savedAt: formatter.string(from: Date()),
            activeProject: activeProject,
            activeWorkspaceName: activeWorkspace?.name,
            lastActivePerProject: lastActiveMapped,
            workspaces: sessionWorkspaces
        )
    }

    /// Restore workspace metadata from a saved session. Does NOT activate any workspace
    /// (deferred until terminalController is wired via `activateRestoredSession()`).
    func restoreSessionMetadata(_ session: IDESessionFile) {
        for wsData in session.workspaces {
            var color: NSColor?
            if let hex = wsData.colorHex {
                color = NSColor(hex: hex)
            }

            let ws = addWorkspace(
                name: wsData.name,
                project: wsData.project,
                color: color,
                emoji: wsData.emoji
            )

            for (key, entry) in wsData.metadata {
                ws.setMetadata(key: key, value: entry.value, icon: entry.icon, url: entry.url)
            }

            // Store tree data for lazy decode on first switchTo()
            if let treeCodable = wsData.surfaceTree {
                if let data = try? JSONEncoder().encode(treeCodable) {
                    ws.pendingSurfaceTreeData = data
                }
            }
            if let idStr = wsData.focusedSurfaceId {
                ws.pendingFocusedSurfaceId = UUID(uuidString: idStr)
            }
        }

        // Rebuild lastActivePerProject (name → UUID)
        for (project, wsName) in session.lastActivePerProject {
            if let ws = workspaces.first(where: { $0.name == wsName && $0.project == project }) {
                lastActivePerProject[project] = ws.id
            }
        }

        if !session.activeProject.isEmpty && !workspaces.isEmpty {
            activeProject = session.activeProject
        }

        pendingActiveWorkspaceName = session.activeWorkspaceName
    }

    /// Activate the workspace deferred during restore. Call after terminalController is wired.
    func activateRestoredSession() {
        let name = pendingActiveWorkspaceName
        pendingActiveWorkspaceName = nil

        if let name, let ws = filteredWorkspaces.first(where: { $0.name == name }) {
            switchTo(workspace: ws)
        } else if let first = filteredWorkspaces.first {
            switchTo(workspace: first)
        } else {
            // No session or empty session — create default project + workspace
            ensureDefaultWorkspace()
        }
    }

    /// Guarantee at least one workspace exists. Creates project "default" / workspace "main"
    /// and adopts the terminal controller's existing surface tree (created during window setup).
    private func ensureDefaultWorkspace() {
        guard workspaces.isEmpty else { return }
        Self.logger.info("No workspaces found, creating default workspace")
        activeProject = "default"
        let ws = addWorkspace(name: "main", project: "default")

        // Adopt the existing surface tree rather than creating a new surface,
        // since TerminalController already set one up during windowDidLoad.
        activeWorkspace = ws
        if let ctrl = terminalController {
            ws.splitTree = ctrl.surfaceTree
            ws.focusedSurface = ctrl.focusedSurface
        }
    }

    /// Start periodic auto-save using NSBackgroundActivityScheduler (10 min interval).
    func startAutoSave() {
        stopAutoSave()
        let activity = NSBackgroundActivityScheduler(
            identifier: "com.ghosttyide.session-autosave")
        activity.repeats = true
        activity.interval = 10 * 60
        activity.qualityOfService = .utility
        activity.schedule { [weak self] completion in
            self?.performAutoSave()
            completion(.finished)
        }
        autoSaveActivity = activity
    }

    /// Stop the auto-save scheduler.
    func stopAutoSave() {
        autoSaveActivity?.invalidate()
        autoSaveActivity = nil
    }

    private func performAutoSave() {
        guard !workspaces.isEmpty else { return }
        let session = captureSession()
        do {
            try IDESessionStore.shared.save(session)
        } catch {
            Self.logger.error("Auto-save session failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Query

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
