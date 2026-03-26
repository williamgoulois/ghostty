import Foundation

enum WorkspaceStoreError: LocalizedError {
    case invalidName(String)
    case notFound(String)
    case directoryCreationFailed(String)
    case encodeFailed(String)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidName(let name):
            return "Invalid project name '\(name)': must be alphanumeric, dashes, underscores, or dots"
        case .notFound(let name):
            return "Project not found: \(name)"
        case .directoryCreationFailed(let path):
            return "Failed to create directory: \(path)"
        case .encodeFailed(let detail):
            return "Failed to encode project: \(detail)"
        case .decodeFailed(let detail):
            return "Failed to decode project: \(detail)"
        }
    }
}

/// Handles reading and writing project files to ~/.cache/ghosttyide/projects/.
/// Uses timestamped files with symlinks (tmux resurrect pattern).
final class WorkspaceStore {
    static let shared = WorkspaceStore()

    // swiftlint:disable:next force_try
    private let namePattern = try! NSRegularExpression(pattern: "^[a-zA-Z0-9._-]+$")

    private var baseDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/ghosttyide/projects")
    }

    // MARK: - Public API

    /// Save a project file to disk. Creates a timestamped file and updates the symlink.
    func save(_ project: ProjectFile) throws {
        try validateName(project.name)
        try ensureDirectory()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(project)
        } catch {
            throw WorkspaceStoreError.encodeFailed(error.localizedDescription)
        }

        // Write timestamped file
        let timestamp = ISO8601DateFormatter.fileTimestamp(from: Date())
        let filename = "\(project.name)_\(timestamp).json"
        let filePath = baseDir.appendingPathComponent(filename)
        try data.write(to: filePath, options: .atomic)

        // Update symlink: <name> -> <name>_<timestamp>.json
        let symlinkPath = baseDir.appendingPathComponent(project.name)
        let fm = FileManager.default
        // Remove existing symlink if present
        if fm.fileExists(atPath: symlinkPath.path) {
            try fm.removeItem(at: symlinkPath)
        }
        try fm.createSymbolicLink(at: symlinkPath, withDestinationURL: filePath)
    }

    /// Load a project file by name (follows symlink).
    func load(name: String) throws -> ProjectFile {
        try validateName(name)

        let symlinkPath = baseDir.appendingPathComponent(name)
        guard FileManager.default.fileExists(atPath: symlinkPath.path) else {
            throw WorkspaceStoreError.notFound(name)
        }

        let data: Data
        do {
            data = try Data(contentsOf: symlinkPath)
        } catch {
            throw WorkspaceStoreError.decodeFailed(error.localizedDescription)
        }

        do {
            return try JSONDecoder().decode(ProjectFile.self, from: data)
        } catch {
            throw WorkspaceStoreError.decodeFailed(error.localizedDescription)
        }
    }

    /// Delete a project: removes symlink and all timestamped files.
    func delete(name: String) throws {
        try validateName(name)

        let fm = FileManager.default
        let symlinkPath = baseDir.appendingPathComponent(name)
        guard fm.fileExists(atPath: symlinkPath.path) else {
            throw WorkspaceStoreError.notFound(name)
        }

        // Remove symlink
        try fm.removeItem(at: symlinkPath)

        // Remove all timestamped files matching <name>_*.json
        let contents = try fm.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: nil)
        for file in contents {
            let fname = file.lastPathComponent
            if fname.hasPrefix("\(name)_") && fname.hasSuffix(".json") {
                try fm.removeItem(at: file)
            }
        }
    }

    /// List all saved projects by reading symlinks in the directory.
    func list() throws -> [ProjectSummary] {
        let fm = FileManager.default

        guard fm.fileExists(atPath: baseDir.path) else {
            return []
        }

        let contents = try fm.contentsOfDirectory(at: baseDir, includingPropertiesForKeys: [.isSymbolicLinkKey])
        var summaries: [ProjectSummary] = []

        for item in contents {
            // Only look at symlinks (not the timestamped files themselves)
            let resourceValues = try item.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard resourceValues.isSymbolicLink == true else { continue }

            // Try to load and extract summary
            if let data = try? Data(contentsOf: item),
               let project = try? JSONDecoder().decode(ProjectFile.self, from: data) {
                summaries.append(ProjectSummary(
                    name: project.name,
                    windowCount: project.windowCount,
                    paneCount: project.paneCount,
                    savedAt: project.savedAt
                ))
            }
        }

        return summaries.sorted { $0.name < $1.name }
    }

    // MARK: - Private

    private func ensureDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: baseDir.path) {
            do {
                try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
            } catch {
                throw WorkspaceStoreError.directoryCreationFailed(baseDir.path)
            }
        }
    }

    private func validateName(_ name: String) throws {
        let range = NSRange(name.startIndex..., in: name)
        guard namePattern.firstMatch(in: name, range: range) != nil else {
            throw WorkspaceStoreError.invalidName(name)
        }
    }
}

// MARK: - ISO 8601 file-safe timestamp

private extension ISO8601DateFormatter {
    /// Produces a file-safe timestamp like "20260324T143810".
    static func fileTimestamp(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd'T'HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
}
