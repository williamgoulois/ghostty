import AppKit
import Foundation

/// Visual category for agent state display.
enum AgentStateStyle {
    case idle       // gray circle
    case working    // blue bolt
    case waiting    // orange hourglass
    case error      // red warning

    /// Derive style from a raw status string.
    static func from(_ status: String) -> AgentStateStyle {
        switch status {
        case "idle": return .idle
        case "waiting": return .waiting
        case "error": return .error
        default: return .working  // working, reading, editing, running command, etc.
        }
    }

    var icon: String {
        switch self {
        case .idle: return "circle"
        case .working: return "bolt.fill"
        case .waiting: return "hourglass"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var color: String {
        switch self {
        case .idle: return "secondary"
        case .working: return "blue"
        case .waiting: return "orange"
        case .error: return "red"
        }
    }
}

/// Extensible key-value metadata for a workspace (ports, PR links, etc.).
struct WorkspaceMetadataEntry: Codable {
    let key: String
    let value: String
    let icon: String?    // SF Symbol name
    let url: String?     // Clickable link (e.g. PR URL)
}

/// A live workspace in GhosttyIDE. Each workspace holds a named split layout
/// with metadata. Surfaces are lazily created on first visit.
final class IDEWorkspace: Identifiable, ObservableObject {
    let id: UUID

    // Identity
    @Published var name: String
    @Published var project: String
    @Published var color: NSColor?
    @Published var emoji: String?

    // Split tree — nil until first visit (lazy creation)
    @Published var splitTree: SplitTree<Ghostty.SurfaceView>?
    @Published var focusedSurface: Ghostty.SurfaceView?

    /// Raw tree JSON from session restore, decoded lazily on first switchTo().
    var pendingSurfaceTreeData: Data?
    /// UUID of focused surface to restore after tree decode.
    var pendingFocusedSurfaceId: UUID?

    /// Whether this workspace has been visited (surfaces created).
    var isVisited: Bool { splitTree != nil }

    // Status
    @Published var gitBranch: String?
    /// Raw agent status string (e.g. "idle", "working", "reading", "editing", "waiting").
    @Published var agentStatus: String?
    @Published var unreadNotifications: Int = 0

    // Process & port monitoring
    @Published var processSnapshot: WorkspaceProcessSnapshot?

    // Extensible metadata (ports, PR links, custom key-values)
    @Published var metadata: [String: WorkspaceMetadataEntry] = [:]

    init(
        id: UUID = UUID(),
        name: String,
        project: String,
        color: NSColor? = nil,
        emoji: String? = nil
    ) {
        self.id = id
        self.name = name
        self.project = project
        self.color = color
        self.emoji = emoji
    }

    /// Display label: "emoji name" or just "name".
    var displayName: String {
        if let emoji {
            return "\(emoji) \(name)"
        }
        return name
    }

    /// Set an extensible metadata entry.
    func setMetadata(key: String, value: String, icon: String? = nil, url: String? = nil) {
        metadata[key] = WorkspaceMetadataEntry(key: key, value: value, icon: icon, url: url)
    }

    /// Remove a metadata entry.
    func clearMetadata(key: String) {
        metadata.removeValue(forKey: key)
    }
}
