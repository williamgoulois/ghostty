import Foundation

/// A saved project: a named collection of window states.
struct ProjectFile: Codable {
    static let currentVersion = 1

    let version: Int
    let name: String
    let savedAt: String  // ISO 8601
    let windows: [ProjectWindowState]
    let windowCount: Int
    let paneCount: Int
}

/// The state of a single window within a project.
struct ProjectWindowState: Codable {
    /// Optional workspace name (nil for now, future: per-window naming).
    let name: String?

    /// The split tree, encoded as a raw JSON object via AnyCodable.
    /// This is the direct output of JSONEncoder on SplitTree<Ghostty.SurfaceView>.
    let surfaceTree: AnyCodable

    /// The UUID string of the focused surface, if any.
    let focusedSurface: String?

    /// Flat pane list for display purposes (not used during restore).
    let panes: [PaneSummary]
}

/// Summary of a single pane, for display in list/status commands.
struct PaneSummary: Codable {
    let id: String
    let pwd: String?
    let title: String
}

/// Summary returned by WorkspaceStore.list().
struct ProjectSummary {
    let name: String
    let windowCount: Int
    let paneCount: Int
    let savedAt: String
}
