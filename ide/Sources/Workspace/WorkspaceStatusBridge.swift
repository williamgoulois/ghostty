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
    private var pidCheckTimer: Timer?
    private var burstTimers: [Timer] = []

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

        // Layer 2: Cheap PID-change check every 10s (tcgetpgrp only, ~0.01ms)
        pidCheckTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkPidsAndScanIfChanged()
        }

        // Layer 1: Wire dispatch source events → burst scan
        ProcessScanner.shared.onProcessEvent = { [weak self] _, isExit in
            if isExit {
                // Process exited — snapshot already updated by scanner, apply to UI
                self?.applyProcessSnapshots(ProcessScanner.shared.lastSnapshot)
            } else {
                // Fork/exec — trigger burst scan (port may bind soon)
                self?.triggerBurstScan()
            }
        }

        // Initial scan
        performFullScan()

        // Recompute workspace unread counts when per-pane unread set changes
        NotificationManager.shared.$unreadPaneIds
            .receive(on: DispatchQueue.main)
            .sink { [weak self] paneIds in
                self?.recomputeWorkspaceUnreadCounts(unreadPaneIds: paneIds)
            }
            .store(in: &cancellables)

        // Recompute agent state when StatusStore changes (status.set / status.clear)
        NotificationCenter.default.publisher(for: StatusStore.didChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.syncAllAgentStates()
            }
            .store(in: &cancellables)
    }

    func stop() {
        branchTimer?.invalidate()
        branchTimer = nil
        pidCheckTimer?.invalidate()
        pidCheckTimer = nil
        cancelBurstTimers()
        ProcessScanner.shared.unwatchAll()
        ProcessScanner.shared.onProcessEvent = nil
        cancellables.removeAll()
    }

    // MARK: - Workspace Change

    private func onWorkspaceChanged(_ workspace: IDEWorkspace?) {
        guard let ws = workspace else { return }

        // Refresh git branch for new workspace
        refreshGitBranch(for: ws)

        // Sync agent state from StatusStore
        syncAgentState(for: ws)

        // Immediate process/port scan on workspace switch
        performFullScan()
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

    /// Recompute agent status for a workspace from StatusStore + process detection.
    /// StatusStore (hook-based) is authoritative; auto-detection is a fallback.
    private func syncAgentState(for workspace: IDEWorkspace) {
        // Collect pane IDs belonging to this workspace
        let ctrl = WorkspaceController.shared
        let wsPaneIds: Set<String> = Set(
            ctrl.allSurfaces()
                .filter { $0.workspace.id == workspace.id }
                .map { $0.surface.id.uuidString }
        )

        // Determine which panes currently have an agent process running
        let agentPaneIds = workspace.processSnapshot?.agentPaneIds ?? []
        let agentPaneIdStrings = Set(agentPaneIds.map(\.uuidString))

        // Clean up stale StatusStore entries: if a pane had an agent status
        // but the agent process is gone, clear it
        for paneId in wsPaneIds where !agentPaneIdStrings.contains(paneId) {
            let statuses = StatusStore.shared.list(paneId: paneId)
            if statuses.contains(where: { $0["key"] as? String == "agent" }) {
                StatusStore.shared.clear(paneId: paneId, key: "agent")
            }
        }

        // Check StatusStore for agent status from hooks (authoritative source)
        // Pick the highest-priority status across all panes in this workspace
        var bestStatus: String?
        var bestPriority = -1
        for paneId in wsPaneIds {
            let statuses = StatusStore.shared.list(paneId: paneId)
            for status in statuses {
                guard status["key"] as? String == "agent",
                      let value = status["value"] as? String else { continue }
                let priority = statusPriority(value)
                if priority > bestPriority {
                    bestPriority = priority
                    bestStatus = value
                }
            }
        }

        if let hookStatus = bestStatus {
            workspace.agentStatus = hookStatus
            return
        }

        // Fallback: auto-detect from process scanner (no hook data, default to idle)
        if let snapshot = workspace.processSnapshot, snapshot.hasAgent {
            workspace.agentStatus = "idle"
        } else {
            workspace.agentStatus = nil
        }
    }

    /// Recompute agent status for all workspaces.
    private func syncAllAgentStates() {
        for ws in WorkspaceController.shared.workspaces {
            syncAgentState(for: ws)
        }
    }

    /// Priority ranking for status strings. Higher = takes precedence.
    /// error > waiting > any working verb > idle
    private func statusPriority(_ status: String) -> Int {
        switch AgentStateStyle.from(status) {
        case .error: return 3
        case .waiting: return 2
        case .working: return 1
        case .idle: return 0
        }
    }

    // MARK: - Notifications

    /// Recompute each workspace's unreadNotifications from per-pane unread state.
    private func recomputeWorkspaceUnreadCounts(unreadPaneIds: Set<String>) {
        let ctrl = WorkspaceController.shared
        for ws in ctrl.workspaces {
            ws.unreadNotifications = ctrl.countUnreadPanes(in: ws, unreadPaneIds: unreadPaneIds)
        }
    }

    // MARK: - Process & Port Scanning

    /// Layer 2: Cheap PID check — only triggers full scan if something changed.
    private func checkPidsAndScanIfChanged() {
        let surfaces = WorkspaceController.shared.allSurfaces()
        let changed = ProcessScanner.shared.checkForPidChanges(surfaces: surfaces)
        if !changed.isEmpty {
            triggerBurstScan()
        }
    }

    /// Perform a full process/port scan and apply results.
    private func performFullScan() {
        let surfaces = WorkspaceController.shared.allSurfaces()
        guard !surfaces.isEmpty else { return }

        ProcessScanner.shared.scan(surfaces: surfaces) { [weak self] snapshots in
            self?.applyProcessSnapshots(snapshots)
        }
    }

    /// Layer 3: Burst scan — 3 scans at 0.5s, 2s, 5s after a change event.
    /// Coalesces multiple triggers within a burst window.
    private func triggerBurstScan() {
        // If a burst is already in progress, don't start another
        guard burstTimers.isEmpty else { return }

        let intervals: [TimeInterval] = [0.5, 2.0, 5.0]
        for interval in intervals {
            let timer = Timer.scheduledTimer(
                withTimeInterval: interval, repeats: false
            ) { [weak self] _ in self?.performFullScan() }
            burstTimers.append(timer)
        }

        // Clean up burst timers after last one fires
        let cleanupTimer = Timer.scheduledTimer(
            withTimeInterval: 6.0, repeats: false
        ) { [weak self] _ in self?.burstTimers.removeAll() }
        burstTimers.append(cleanupTimer)
    }

    private func cancelBurstTimers() {
        for timer in burstTimers {
            timer.invalidate()
        }
        burstTimers.removeAll()
    }

    /// Apply process snapshots to workspace @Published properties.
    private func applyProcessSnapshots(_ snapshots: [UUID: WorkspaceProcessSnapshot]) {
        let ctrl = WorkspaceController.shared
        for ws in ctrl.workspaces {
            guard let snapshot = snapshots[ws.id] else {
                ws.processSnapshot = nil
                // Remove stale port metadata
                let portKeys = ws.metadata.keys.filter { $0.hasPrefix("port:") }
                for key in portKeys { ws.clearMetadata(key: key) }
                continue
            }

            ws.processSnapshot = snapshot

            // Update per-port metadata entries
            let currentPortKeys = Set(ws.metadata.keys.filter { $0.hasPrefix("port:") })
            var newPortKeys: Set<String> = []

            for port in snapshot.ports {
                let key = "port:\(port.port)"
                newPortKeys.insert(key)
                ws.setMetadata(key: key, value: ":\(port.port)", icon: "network")
            }

            // Remove stale ports
            for staleKey in currentPortKeys.subtracting(newPortKeys) {
                ws.clearMetadata(key: staleKey)
            }
        }

        // Recompute agent state for all workspaces (hooks + auto-detection)
        syncAllAgentStates()
    }
}
