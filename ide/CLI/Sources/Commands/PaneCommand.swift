import ArgumentParser
import Foundation

struct Pane: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage terminal panes.",
        subcommands: [List.self, Split.self, Focus.self, FocusDirection.self, Close.self, SendText.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List all panes.")

        @Option(name: .long, help: "Filter by project name.")
        var project: String?

        @Option(name: .long, help: "Filter by workspace name.")
        var workspace: String?

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            var args: [String: String] = [:]
            if let project { args["project"] = project }
            if let workspace { args["workspace"] = workspace }
            let resp = args.isEmpty
                ? try SocketClient.send(command: "pane.list", socketPath: path)
                : try SocketClient.send(command: "pane.list", args: args, socketPath: path)
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
                let process = pane["foreground_process"] as? String ?? ""
                let marker = focused ? " *" : ""
                let procTag = process.isEmpty ? "" : " [\(process)]"
                print("\(id)  \(title)  \(pwd)\(procTag)\(marker)")
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

    struct FocusDirection: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "focus-direction",
            abstract: "Focus the pane in a direction (left, right, up, down)."
        )

        @Argument(help: "Direction: left, right, up, down.")
        var direction: String

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(
                command: "pane.focus-direction",
                args: ["direction": direction],
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

    struct SendText: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "send-text",
            abstract: "Send text to a pane's terminal input."
        )

        @Argument(help: "Pane UUID.")
        var id: String

        @Argument(help: "Text to send. Use @path to send a file reference.")
        var text: String

        @Flag(name: .long, help: "Focus the target pane after sending.")
        var focus = false

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            var args: [String: String] = ["id": id, "text": text]
            if focus { args["focus"] = "true" }
            let resp = try SocketClient.send(
                command: "pane.send-text",
                args: args,
                socketPath: path
            )
            Output.print(response: resp, json: global.json)
            if !resp.ok { throw ExitCode.failure }
        }
    }
}
