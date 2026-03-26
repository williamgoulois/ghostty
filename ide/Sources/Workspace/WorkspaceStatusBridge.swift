import AppKit
import Combine
import Foundation

/// Bridges external status providers (git branch, agent state, notifications)
/// to the active workspace in WorkspaceController.
///
/// Started once at app launch. Observes workspace switches and updates metadata
/// from GitBranchProvider, StatusStore, and NotificationManager.
final class WorkspaceStatusBridge {
    static let shared = WorkspaceStatusBridge()

    private var cancellables = Set<AnyCancellable>()
    private var branchTimer: Timer?

    /// Start observing workspace changes and updating status.
    func start() {
        // Prevent double-start: invalidate existing timer and subscriptions
        stop()

        // Observe active workspace changes
        WorkspaceController.shared.$activeWorkspace
            .sink { [weak self] ws in
                self?.onWorkspaceChanged(ws)
            }
            .store(in: &cancellables)

        // Periodic git branch refresh (every 10s)
        branchTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.refreshGitBranch()
        }

        // Recompute workspace unread counts when per-pane unread set changes
        NotificationManager.shared.$unreadPaneIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paneIds in
                self?.recomputeWorkspaceUnreadCounts(unreadPaneIds: paneIds)
            }
            .store(in: &cancellables)
    }

    func stop() {
        branchTimer?.invalidate()
        branchTimer = nil
        cancellables.removeAll()
    }

    // MARK: - Workspace Change

    private func onWorkspaceChanged(_ workspace: IDEWorkspace?) {
        guard let ws = workspace else { return }

        // Refresh git branch for new workspace
        refreshGitBranch(for: ws)

        // Sync agent state from StatusStore
        syncAgentState(for: ws)
    }

    // MARK: - Git Branch

    private func refreshGitBranch() {
        guard let ws = WorkspaceController.shared.activeWorkspace else { return }
        refreshGitBranch(for: ws)
    }

    private func refreshGitBranch(for workspace: IDEWorkspace) {
        // Get pwd from the focused surface or first surface in the workspace
        guard let path = currentWorkingDirectory(for: workspace) else { return }

        GitBranchProvider.shared.detectBranch(at: path) { [weak workspace] branch in
            workspace?.gitBranch = branch
        }
    }

    /// Extract the current working directory from a workspace's focused surface or split tree.
    private func currentWorkingDirectory(for workspace: IDEWorkspace) -> String? {
        // Try focused surface first
        if let surface = workspace.focusedSurface {
            if let pwd = surface.pwd, !pwd.isEmpty {
                return pwd
            }
        }

        // Fallback: try to get pwd from the first leaf in the split tree
        if let tree = workspace.splitTree, let root = tree.root {
            return firstSurfacePwd(in: root)
        }

        // Fallback: home directory
        return NSHomeDirectory()
    }

    private func firstSurfacePwd(in node: SplitTree<Ghostty.SurfaceView>.Node) -> String? {
        switch node {
        case .leaf(let view):
            return view.pwd
        case .split(let split):
            return firstSurfacePwd(in: split.left) ?? firstSurfacePwd(in: split.right)
        }
    }

    // MARK: - Agent State

    /// Map StatusStore entries for panes in this workspace to workspace-level agent state.
    private func syncAgentState(for workspace: IDEWorkspace) {
        // Look for "agent" key in StatusStore for any pane in this workspace
        let allStatuses = StatusStore.shared.list()

        // Find the most relevant agent state from panes in this workspace
        var highestPriority: AgentState?

        for status in allStatuses {
            guard let key = status["key"] as? String, key == "agent" else { continue }
            guard let value = status["value"] as? String else { continue }

            if let state = AgentState(rawValue: value) {
                highestPriority = higherPriority(highestPriority, state)
            }
        }

        workspace.agentState = highestPriority
    }

    /// Priority: error > working > waiting > idle
    private func higherPriority(_ a: AgentState?, _ b: AgentState) -> AgentState {
        guard let a else { return b }
        let order: [AgentState] = [.idle, .waiting, .working, .error]
        let ai = order.firstIndex(of: a) ?? 0
        let bi = order.firstIndex(of: b) ?? 0
        return ai >= bi ? a : b
    }

    // MARK: - Notifications

    /// Recompute each workspace's unreadNotifications from per-pane unread state.
    private func recomputeWorkspaceUnreadCounts(unreadPaneIds: Set<String>) {
        let ctrl = WorkspaceController.shared
        for ws in ctrl.workspaces {
            ws.unreadNotifications = ctrl.countUnreadPanes(in: ws, unreadPaneIds: unreadPaneIds)
        }
    }
}
