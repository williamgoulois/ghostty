import ArgumentParser
import Foundation

/// Lists all commands registered on the server.
struct Help_: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "commands",
        abstract: "List all server commands."
    )

    @OptionGroup var global: GhosttyIDE.GlobalOptions

    func run() throws {
        let path = try global.resolvedSocketPath()
        let resp = try SocketClient.send(command: "help", socketPath: path)
        if global.json {
            Output.print(response: resp, json: true)
            return
        }
        guard resp.ok, let data = resp.data as? [String: Any],
              let commands = data["commands"] as? [String] else {
            Output.print(response: resp, json: false)
            if !resp.ok { throw ExitCode.failure }
            return
        }
        print("Available server commands:")
        for cmd in commands {
            print("  \(cmd)")
        }
    }
}
