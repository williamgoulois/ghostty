import ArgumentParser
import Foundation

struct Pane: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage terminal panes.",
        subcommands: [List.self, Split.self, Focus.self, Close.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List all panes.")
        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(command: "pane.list", socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any],
                  let panes = data["panes"] as? [[String: Any]] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            if panes.isEmpty {
                print("No panes")
                return
            }
            for pane in panes {
                let id = pane["id"] as? String ?? "?"
                let title = pane["title"] as? String ?? ""
                let pwd = pane["pwd"] as? String ?? ""
                let focused = pane["focused"] as? Bool ?? false
                let marker = focused ? " *" : ""
                print("\(id)  \(title)  \(pwd)\(marker)")
            }
        }
    }

    struct Split: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Split the focused pane.")

        @Option(name: .shortAndLong, help: "Split direction: right, left, up, down.")
        var direction: String = "right"

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(
                command: "pane.split",
                args: ["direction": direction],
                socketPath: path
            )
            Output.print(response: resp, json: global.json)
            if !resp.ok { throw ExitCode.failure }
        }
    }

    struct Focus: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Focus a pane by ID.")

        @Argument(help: "Pane UUID.")
        var id: String

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(
                command: "pane.focus",
                args: ["id": id],
                socketPath: path
            )
            Output.print(response: resp, json: global.json)
            if !resp.ok { throw ExitCode.failure }
        }
    }

    struct Close: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Close a pane by ID.")

        @Argument(help: "Pane UUID.")
        var id: String

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(
                command: "pane.close",
                args: ["id": id],
                socketPath: path
            )
            Output.print(response: resp, json: global.json)
            if !resp.ok { throw ExitCode.failure }
        }
    }
}
