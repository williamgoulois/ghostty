import ArgumentParser
import Foundation

struct Workspace: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage live workspaces.",
        subcommands: [
            New.self, Switch.self, Next.self, Previous.self,
            List.self, Rename.self, Meta.self, ProjectSwitch.self,
        ]
    )

    struct New: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a new workspace.")

        @Argument(help: "Workspace name.")
        var name: String

        @Option(help: "Project name (defaults to active project).")
        var project: String?

        @Option(help: "Color hex (e.g. #2ECC71).")
        var color: String?

        @Option(help: "Emoji for the workspace.")
        var emoji: String?

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            var args: [String: Any] = ["name": name]
            if let project { args["project"] = project }
            if let color { args["color"] = color }
            if let emoji { args["emoji"] = emoji }

            let resp = try SocketClient.send(command: "workspace.new", args: args, socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            let wsName = data["name"] as? String ?? name
            let wsProject = data["project"] as? String ?? ""
            print("Created workspace '\(wsName)' in project '\(wsProject)'")
        }
    }

    struct Switch: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Switch to a workspace by name.")

        @Argument(help: "Workspace name.")
        var name: String

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(
                command: "workspace.switch",
                args: ["name": name],
                socketPath: path
            )
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            if resp.ok {
                print("Switched to workspace '\(name)'")
            } else {
                Output.print(response: resp, json: false)
                throw ExitCode.failure
            }
        }
    }

    struct Next: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Switch to the next workspace.")

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(command: "workspace.next", socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            let name = data["name"] as? String ?? ""
            print("Switched to workspace '\(name)'")
        }
    }

    struct Previous: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Switch to the previous workspace.")

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(command: "workspace.previous", socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            let name = data["name"] as? String ?? ""
            print("Switched to workspace '\(name)'")
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List workspaces in the active project."
        )

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(command: "workspace.list", socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any],
                  let workspaces = data["workspaces"] as? [[String: Any]] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            if workspaces.isEmpty {
                print("No workspaces")
                return
            }
            for ws in workspaces {
                let name = ws["name"] as? String ?? "?"
                let isActive = ws["is_active"] as? Bool ?? false
                let emoji = ws["emoji"] as? String
                let branch = ws["git_branch"] as? String
                let agent = ws["agent_state"] as? String
                let unread = ws["unread"] as? Int ?? 0

                var line = isActive ? "* " : "  "
                if let emoji { line += "\(emoji) " }
                line += name
                if let branch { line += "  (\(branch))" }
                if let agent { line += "  [\(agent)]" }
                if unread > 0 { line += "  \(unread) unread" }
                print(line)
            }
        }
    }

    struct Rename: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Rename a workspace.")

        @Argument(help: "Current workspace name.")
        var name: String

        @Argument(help: "New workspace name.")
        var newName: String

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(
                command: "workspace.rename",
                args: ["name": name, "new_name": newName],
                socketPath: path
            )
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            if resp.ok {
                print("Renamed '\(name)' -> '\(newName)'")
            } else {
                Output.print(response: resp, json: false)
                throw ExitCode.failure
            }
        }
    }

    struct Meta: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage workspace metadata.",
            subcommands: [Set.self, Clear.self]
        )

        struct Set: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Set a metadata key on a workspace.")

            @Argument(help: "Workspace name.")
            var workspace: String

            @Argument(help: "Metadata key.")
            var key: String

            @Argument(help: "Metadata value.")
            var value: String

            @Option(help: "SF Symbol icon name.")
            var icon: String?

            @Option(help: "Clickable URL.")
            var url: String?

            @OptionGroup var global: GhosttyIDE.GlobalOptions

            func run() throws {
                let path = try global.resolvedSocketPath()
                var args: [String: Any] = [
                    "workspace": workspace,
                    "key": key,
                    "value": value,
                ]
                if let icon { args["icon"] = icon }
                if let url { args["url"] = url }

                let resp = try SocketClient.send(
                    command: "workspace.meta.set",
                    args: args,
                    socketPath: path
                )
                if global.json {
                    Output.print(response: resp, json: true)
                    return
                }
                if resp.ok {
                    print("Set \(key)=\(value) on workspace '\(workspace)'")
                } else {
                    Output.print(response: resp, json: false)
                    throw ExitCode.failure
                }
            }
        }

        struct Clear: ParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Clear a metadata key from a workspace.")

            @Argument(help: "Workspace name.")
            var workspace: String

            @Argument(help: "Metadata key to clear.")
            var key: String

            @OptionGroup var global: GhosttyIDE.GlobalOptions

            func run() throws {
                let path = try global.resolvedSocketPath()
                let resp = try SocketClient.send(
                    command: "workspace.meta.clear",
                    args: ["workspace": workspace, "key": key],
                    socketPath: path
                )
                if global.json {
                    Output.print(response: resp, json: true)
                    return
                }
                if resp.ok {
                    print("Cleared \(key) from workspace '\(workspace)'")
                } else {
                    Output.print(response: resp, json: false)
                    throw ExitCode.failure
                }
            }
        }
    }

    struct ProjectSwitch: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "project-switch",
            abstract: "Switch the active project filter."
        )

        @Argument(help: "Project name to switch to.")
        var name: String

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(
                command: "project.switch",
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
            let activeWs = data["active_workspace"] as? String ?? ""
            print("Switched to project '\(name)' (active workspace: '\(activeWs)')")
        }
    }
}
