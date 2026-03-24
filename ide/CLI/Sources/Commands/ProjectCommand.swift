import ArgumentParser
import Foundation

struct Project: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage projects (save/restore window layouts).",
        subcommands: [Save.self, Restore.self, List.self, Delete.self, CloseAll.self]
    )

    struct Save: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Save all windows as a named project.")

        @Argument(help: "Project name.")
        var name: String

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(
                command: "project.save",
                args: ["name": name],
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
            let windows = data["windows"] as? Int ?? 0
            let panes = data["panes"] as? Int ?? 0
            print("Saved project '\(name)' (\(windows) windows, \(panes) panes)")
        }
    }

    struct Restore: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Restore a saved project.")

        @Argument(help: "Project name.")
        var name: String

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(
                command: "project.restore",
                args: ["name": name],
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
            let windows = data["windows_created"] as? Int ?? 0
            print("Restored project '\(name)' (\(windows) windows)")
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List saved projects."
        )

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(command: "project.list", socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any],
                  let projects = data["projects"] as? [[String: Any]] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            if projects.isEmpty {
                print("No saved projects")
                return
            }
            for p in projects {
                let name = p["name"] as? String ?? "?"
                let windows = p["windows"] as? Int ?? 0
                let panes = p["panes"] as? Int ?? 0
                let savedAt = p["saved_at"] as? String ?? ""
                print("\(name)  \(windows) windows  \(panes) panes  \(savedAt)")
            }
        }
    }

    struct Delete: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Delete a saved project.")

        @Argument(help: "Project name.")
        var name: String

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(
                command: "project.delete",
                args: ["name": name],
                socketPath: path
            )
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            if resp.ok {
                print("Deleted project '\(name)'")
            } else {
                Output.print(response: resp, json: false)
                throw ExitCode.failure
            }
        }
    }

    struct CloseAll: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "close-all",
            abstract: "Close all terminal windows."
        )

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(command: "project.close-all", socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            let closed = data["closed"] as? Int ?? 0
            print("Closed \(closed) windows")
        }
    }
}
