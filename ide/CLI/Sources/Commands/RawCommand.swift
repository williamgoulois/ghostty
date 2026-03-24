import ArgumentParser
import Foundation

/// Send a raw JSON command to the server.
struct Raw: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send a raw command to the server."
    )

    @Argument(help: "Command name (e.g. pane.list).")
    var command: String

    @Option(name: .shortAndLong, parsing: .upToNextOption, help: "Key=value arguments.")
    var arg: [String] = []

    @OptionGroup var global: GhosttyIDE.GlobalOptions

    func run() throws {
        let path = try global.resolvedSocketPath()

        // Parse key=value args
        var args: [String: Any] = [:]
        for kv in arg {
            let parts = kv.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else {
                throw ValidationError("Invalid argument format '\(kv)'. Use key=value.")
            }
            args[String(parts[0])] = String(parts[1])
        }

        let resp = try SocketClient.send(
            command: command,
            args: args.isEmpty ? nil : args,
            socketPath: path
        )
        Output.print(response: resp, json: global.json)
        if !resp.ok { throw ExitCode.failure }
    }
}
