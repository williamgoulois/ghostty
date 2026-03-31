import Foundation

/// Classification of a foreground process detected in a terminal pane.
enum ProcessCategory: String, Codable, CaseIterable {
    case shell
    case agent
    case longRunning
    case editor
    case unknown
}

/// A process detected as the foreground process (or descendant) in a terminal pane.
struct DetectedProcess: Identifiable {
    let pid: pid_t
    let name: String
    let category: ProcessCategory
    let paneId: UUID
    let workspaceId: UUID
    let workspaceName: String
    /// Merged from `status.set` hook (e.g. "working", "waiting", "error").
    var agentStatus: String?

    var id: pid_t { pid }
}

/// A TCP port in LISTEN state discovered from a pane's process tree.
struct DetectedPort: Identifiable, Hashable {
    let port: UInt16
    let pid: pid_t
    let processName: String
    let paneId: UUID
    let workspaceId: UUID
    let workspaceName: String
    /// Whether a TLS handshake succeeded on this port (use https:// if true).
    let tls: Bool

    var id: UInt16 { port }
    var scheme: String { tls ? "https" : "http" }

    func hash(into hasher: inout Hasher) {
        hasher.combine(port)
        hasher.combine(workspaceId)
    }

    static func == (lhs: DetectedPort, rhs: DetectedPort) -> Bool {
        lhs.port == rhs.port && lhs.workspaceId == rhs.workspaceId
    }
}

/// Snapshot of all process/port state for one workspace, produced by ProcessScanner.
struct WorkspaceProcessSnapshot {
    let workspaceId: UUID
    let processes: [DetectedProcess]
    let ports: [DetectedPort]
    let hasAgent: Bool
    let agentPaneIds: Set<UUID>
    let longRunningPaneIds: Set<UUID>
}
