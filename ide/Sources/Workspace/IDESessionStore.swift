import Foundation

// MARK: - Data Model

/// Persisted session state: workspace metadata, split layout, CWD, and project memory.
struct IDESessionFile: Codable {
    static let currentVersion = 1

    let version: Int
    let savedAt: String
    let activeProject: String
    let activeWorkspaceName: String?
    let lastActivePerProject: [String: String] // project name → workspace name
    let workspaces: [IDESessionWorkspace]
}

struct IDESessionWorkspace: Codable {
    let name: String
    let project: String
    let colorHex: String?
    let emoji: String?
    let metadata: [String: IDESessionMetadataEntry]
    let surfaceTree: AnyCodable?       // Encoded SplitTree (nil = unvisited workspace)
    let focusedSurfaceId: String?      // UUID string of focused surface
}

struct IDESessionMetadataEntry: Codable {
    let value: String
    let icon: String?
    let url: String?
}

// MARK: - Errors

enum IDESessionStoreError: LocalizedError {
    case directoryCreationFailed(String)
    case encodeFailed(String)
    case decodeFailed(String)
    case versionMismatch(found: Int, expected: Int)

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let path):
            return "Failed to create directory: \(path)"
        case .encodeFailed(let detail):
            return "Failed to encode session: \(detail)"
        case .decodeFailed(let detail):
            return "Failed to decode session: \(detail)"
        case .versionMismatch(let found, let expected):
            return "Session version mismatch: found \(found), expected \(expected)"
        }
    }
}

// MARK: - Store

/// Reads and writes the session file at ~/.cache/ghosttyide/session.json.
final class IDESessionStore {
    static let shared = IDESessionStore()

    private var baseDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/ghosttyide")
    }

    private var sessionFileURL: URL {
        baseDir.appendingPathComponent("session.json")
    }

    /// Whether a session file exists on disk.
    func exists() -> Bool {
        FileManager.default.fileExists(atPath: sessionFileURL.path)
    }

    /// Save a session to disk with atomic write.
    func save(_ session: IDESessionFile) throws {
        try ensureDirectory()

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data: Data
        do {
            data = try encoder.encode(session)
        } catch {
            throw IDESessionStoreError.encodeFailed(error.localizedDescription)
        }

        try data.write(to: sessionFileURL, options: .atomic)
    }

    /// Load the session from disk.
    func load() throws -> IDESessionFile {
        let data: Data
        do {
            data = try Data(contentsOf: sessionFileURL)
        } catch {
            throw IDESessionStoreError.decodeFailed(error.localizedDescription)
        }

        let session: IDESessionFile
        do {
            session = try JSONDecoder().decode(IDESessionFile.self, from: data)
        } catch {
            throw IDESessionStoreError.decodeFailed(error.localizedDescription)
        }

        guard session.version == IDESessionFile.currentVersion else {
            throw IDESessionStoreError.versionMismatch(
                found: session.version, expected: IDESessionFile.currentVersion)
        }

        return session
    }

    // MARK: - Private

    private func ensureDirectory() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: baseDir.path) {
            do {
                try fm.createDirectory(at: baseDir, withIntermediateDirectories: true)
            } catch {
                throw IDESessionStoreError.directoryCreationFailed(baseDir.path)
            }
        }
    }
}
