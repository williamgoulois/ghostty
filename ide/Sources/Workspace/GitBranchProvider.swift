import Foundation
import OSLog

/// Detects the current git branch for a given directory.
/// Runs `git rev-parse --abbrev-ref HEAD` on a background queue.
final class GitBranchProvider {
    static let shared = GitBranchProvider()
    private static let logger = IDELogger.make(for: GitBranchProvider.self)

    private let queue = DispatchQueue(label: "ghosttyide.git-branch", qos: .utility)

    /// Asynchronously detect the git branch for a directory path.
    func detectBranch(at path: String, completion: @escaping (String?) -> Void) {
        queue.async {
            let branch = self.runGitBranch(at: path)
            DispatchQueue.main.async {
                completion(branch)
            }
        }
    }

    /// Synchronous git branch detection (call from background thread only).
    private func runGitBranch(at path: String) -> String? {
        let process = Process()
        // Use /usr/bin/env to resolve git from PATH (handles Homebrew, Xcode CLT, etc.)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "rev-parse", "--abbrev-ref", "HEAD"]
        process.currentDirectoryURL = URL(fileURLWithPath: path)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe() // suppress stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Self.logger.debug("git rev-parse failed at \(path): \(error.localizedDescription)")
            return nil
        }

        guard process.terminationStatus == 0 else {
            Self.logger.debug("git rev-parse exited with status \(process.terminationStatus) at \(path)")
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else { return nil }

        let branch = output.trimmingCharacters(in: .whitespacesAndNewlines)
        return branch.isEmpty ? nil : branch
    }
}
