import ArgumentParser
import Foundation

struct Status: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage per-pane status entries.",
        subcommands: [Set_.self, Clear.self, List.self]
    )

    struct Set_: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "set",
            abstract: "Set a status entry for a pane."
        )

        @Argument(help: "Status key (e.g. 'agent').")
        var key: String

        @Argument(help: "Status value (e.g. 'idle').")
        var value: String

        @Option(name: .long, help: "Target pane UUID. Defaults to focused pane.")
        var pane: String?

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            var args: [String: Any] = ["key": key, "value": value]
            if let pane { args["pane_id"] = pane }

            let resp = try SocketClient.send(command: "status.set", args: args, socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            if resp.ok {
                print("Status set: \(key) = \(value)")
            } else {
                Output.print(response: resp, json: false)
                throw ExitCode.failure
            }
        }
    }

    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Clear status entries.")

        @Argument(help: "Status key to clear. Omit to clear all.")
        var key: String?

        @Option(name: .long, help: "Target pane UUID. Omit to clear all panes.")
        var pane: String?

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            var args: [String: Any] = [:]
            if let key { args["key"] = key }
            if let pane { args["pane_id"] = pane }

            let resp = try SocketClient.send(command: "status.clear", args: args, socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            if resp.ok {
                print("Status cleared")
            } else {
                Output.print(response: resp, json: false)
                throw ExitCode.failure
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List status entries."
        )

        @Option(name: .long, help: "Filter by pane UUID.")
        var pane: String?

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            var args: [String: Any] = [:]
            if let pane { args["pane_id"] = pane }

            let resp = try SocketClient.send(command: "status.list", args: args, socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any],
                  let statuses = data["statuses"] as? [[String: Any]] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            if statuses.isEmpty {
                print("No status entries")
                return
            }
            for s in statuses {
                let key = s["key"] as? String ?? "?"
                let value = s["value"] as? String ?? ""
                let paneId = s["pane_id"] as? String ?? ""
                print("\(paneId)  \(key) = \(value)")
            }
        }
    }
}
