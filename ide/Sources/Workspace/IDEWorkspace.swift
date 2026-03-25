import AppKit
import Foundation

/// State of an AI agent running in a workspace.
enum AgentState: String, Codable {
    case idle
    case working
    case waiting
    case error
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

    /// Whether this workspace has been visited (surfaces created).
    var isVisited: Bool { splitTree != nil }

    // Status
    @Published var gitBranch: String?
    @Published var agentState: AgentState?
    @Published var unreadNotifications: Int = 0

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
