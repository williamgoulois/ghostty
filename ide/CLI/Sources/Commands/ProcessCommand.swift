import ArgumentParser
import Foundation

struct Process_: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "process",
        abstract: "Manage foreground processes in terminal panes.",
        subcommands: [Kill.self]
    )

    struct Kill: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Kill a foreground process by PID.")

        @Argument(help: "Process ID to kill.")
        var pid: Int

        @Option(name: .long, help: "Signal number (default: 2/SIGINT).")
        var signal: Int?

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            var args: [String: Any] = ["pid": pid]
            if let signal { args["signal"] = signal }

            let resp = try SocketClient.send(command: "process.kill", args: args, socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            if resp.ok {
                let sig = signal ?? 2
                print("Sent signal \(sig) to PID \(pid)")
            } else {
                Output.print(response: resp, json: false)
                throw ExitCode.failure
            }
        }
    }
}

struct Port: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect listening TCP ports.",
        subcommands: [List.self]
    )

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List listening ports across all panes.")

        @Option(name: .long, help: "Filter by workspace name.")
        var workspace: String?

        @Option(name: .long, help: "Filter by project name.")
        var project: String?

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            var args: [String: Any] = [:]
            if let workspace { args["workspace"] = workspace }
            if let project { args["project"] = project }

            let resp = try SocketClient.send(
                command: "port.list",
                args: args.isEmpty ? nil : args,
                socketPath: path
            )
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any],
                  let ports = data["ports"] as? [[String: Any]] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            if ports.isEmpty {
                print("No listening ports")
                return
            }
            for p in ports {
                let port = p["port"] as? Int ?? 0
                let process = p["process"] as? String ?? "?"
                let tls = p["tls"] as? Bool ?? false
                let workspace = p["workspace"] as? String ?? ""
                let scheme = tls ? "https" : "http"
                print(":\(port)  \(process)  \(workspace)  \(scheme)://localhost:\(port)")
            }
        }
    }
}
