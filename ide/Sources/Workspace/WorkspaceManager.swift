import AppKit
import Foundation

enum WorkspaceManagerError: LocalizedError {
    case noWindows
    case noApp
    case encodeFailed(String)
    case decodeFailed(String)
    case versionMismatch(found: Int, expected: Int)

    var errorDescription: String? {
        switch self {
        case .noWindows:
            return "No terminal windows open"
        case .noApp:
            return "Ghostty app not available"
        case .encodeFailed(let detail):
            return "Failed to encode: \(detail)"
        case .decodeFailed(let detail):
            return "Failed to decode: \(detail)"
        case .versionMismatch(let found, let expected):
            return "Incompatible project version: found \(found), expected \(expected)"
        }
    }
}

/// Bridges live app state and the project data model.
final class WorkspaceManager {
    static let shared = WorkspaceManager()

    private let store = WorkspaceStore.shared

    // MARK: - Save

    /// Save the current state of all terminal windows as a named project.
    func save(name: String) throws -> ProjectFile {
        let windowStates = try captureWindowStates()
        guard !windowStates.isEmpty else {
            throw WorkspaceManagerError.noWindows
        }

        let totalPanes = windowStates.reduce(0) { $0 + $1.panes.count }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        let project = ProjectFile(
            version: ProjectFile.currentVersion,
            name: name,
            savedAt: formatter.string(from: Date()),
            windows: windowStates,
            windowCount: windowStates.count,
            paneCount: totalPanes
        )

        try store.save(project)
        return project
    }

    // MARK: - Restore

    /// Restore a project from disk. Creates new windows additively.
    /// Returns the number of windows created.
    func restore(name: String) throws -> Int {
        let project = try store.load(name: name)

        guard project.version == ProjectFile.currentVersion else {
            throw WorkspaceManagerError.versionMismatch(
                found: project.version,
                expected: ProjectFile.currentVersion
            )
        }

        guard let appDelegate = NSApplication.shared.delegate as? AppDelegate,
              appDelegate.ghostty.app != nil else {
            throw WorkspaceManagerError.noApp
        }

        var windowsCreated = 0

        for (index, windowState) in project.windows.enumerated() {
            do {
                let tree = try decodeSurfaceTree(from: windowState.surfaceTree)
                let controller = TerminalController.newWindow(
                    appDelegate.ghostty,
                    tree: tree
                )

                // Restore focused surface
                if let focusedStr = windowState.focusedSurface {
                    for view in controller.surfaceTree where view.id.uuidString == focusedStr {
                        controller.focusedSurface = view
                        if let window = controller.window {
                            restoreFocus(to: view, inWindow: window)
                        }
                        break
                    }
                }

                windowsCreated += 1
            } catch {
                if windowsCreated > 0 {
                    // Partial failure: some windows created, report which one failed
                    throw WorkspaceManagerError.decodeFailed(
                        "Window \(index + 1) of \(project.windows.count): \(error.localizedDescription)"
                    )
                }
                throw error
            }
        }

        return windowsCreated
    }

    // MARK: - List / Delete

    func list() throws -> [ProjectSummary] {
        try store.list()
    }

    func delete(name: String) throws {
        try store.delete(name: name)
    }

    // MARK: - Close All

    /// Close all terminal windows. Returns the number of windows closed.
    func closeAll() -> Int {
        var closed = 0
        for window in NSApp.windows {
            guard window.windowController is BaseTerminalController else { continue }
            window.close()
            closed += 1
        }
        return closed
    }

    // MARK: - Private

    /// Capture the state of all terminal windows.
    private func captureWindowStates() throws -> [ProjectWindowState] {
        var states: [ProjectWindowState] = []

        for window in NSApp.windows {
            guard let controller = window.windowController as? BaseTerminalController else {
                continue
            }

            // Encode the live SplitTree to JSON, then decode as AnyCodable
            let treeData: Data
            do {
                treeData = try JSONEncoder().encode(controller.surfaceTree)
            } catch {
                throw WorkspaceManagerError.encodeFailed(error.localizedDescription)
            }

            let treeCodable: AnyCodable
            do {
                treeCodable = try JSONDecoder().decode(AnyCodable.self, from: treeData)
            } catch {
                throw WorkspaceManagerError.encodeFailed("AnyCodable roundtrip: \(error.localizedDescription)")
            }

            // Build pane summaries
            var panes: [PaneSummary] = []
            for surface in controller.surfaceTree {
                panes.append(PaneSummary(
                    id: surface.id.uuidString,
                    pwd: surface.pwd,
                    title: surface.title
                ))
            }

            states.append(ProjectWindowState(
                name: nil,
                surfaceTree: treeCodable,
                focusedSurface: controller.focusedSurface?.id.uuidString,
                panes: panes
            ))
        }

        return states
    }

    /// Decode a SplitTree from an AnyCodable (the roundtrip path).
    private func decodeSurfaceTree(from codable: AnyCodable) throws -> SplitTree<Ghostty.SurfaceView> {
        let data: Data
        do {
            data = try JSONEncoder().encode(codable)
        } catch {
            throw WorkspaceManagerError.decodeFailed("Re-encode: \(error.localizedDescription)")
        }

        do {
            return try JSONDecoder().decode(SplitTree<Ghostty.SurfaceView>.self, from: data)
        } catch {
            throw WorkspaceManagerError.decodeFailed(error.localizedDescription)
        }
    }

    /// Restore focus to a surface view, retrying until the view is attached to the window.
    private func restoreFocus(to view: Ghostty.SurfaceView, inWindow window: NSWindow, attempts: Int = 0) {
        let after: DispatchTime
        if attempts == 0 {
            after = .now()
        } else if attempts > 40 {
            return  // 2 seconds, give up
        } else {
            after = .now() + .milliseconds(50)
        }

        DispatchQueue.main.asyncAfter(deadline: after) { [weak self] in
            guard let viewWindow = view.window else {
                self?.restoreFocus(to: view, inWindow: window, attempts: attempts + 1)
                return
            }
            guard viewWindow == window else { return }
            window.makeFirstResponder(view)
        }
    }
}
