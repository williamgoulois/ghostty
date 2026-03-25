import ArgumentParser
import Foundation

struct Session: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage session persistence.",
        subcommands: [Save.self, Info.self]
    )

    struct Save: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Save the current session to disk.")

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(
                command: "session.save",
                socketPath: path
            )
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            let count = data["workspace_count"] as? Int ?? 0
            print("Session saved (\(count) workspaces)")
        }
    }

    struct Info: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show session file info.")

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(
                command: "session.info",
                socketPath: path
            )
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            let exists = data["exists"] as? Bool ?? false
            if !exists {
                print("No session file found")
                return
            }
            let savedAt = data["saved_at"] as? String ?? ""
            let count = data["workspace_count"] as? Int ?? 0
            let activeProject = data["active_project"] as? String ?? ""
            let activeWorkspace = data["active_workspace"] as? String ?? ""
            print("Session: \(count) workspaces, saved \(savedAt)")
            print("Active: project=\(activeProject), workspace=\(activeWorkspace)")
        }
    }
}
