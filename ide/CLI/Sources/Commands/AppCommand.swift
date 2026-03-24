import ArgumentParser
import Foundation

struct App: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "App-level commands.",
        subcommands: [Version.self, Pid.self, Quit.self]
    )

    struct Version: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show app version.")
        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(command: "app.version", socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            let version = data["version"] as? String ?? "unknown"
            let build = data["build"] as? String ?? "0"
            print("GhosttyIDE \(version) (build \(build))")
        }
    }

    struct Pid: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show app process ID.")
        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(command: "app.pid", socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any],
                  let pid = data["pid"] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            print(pid)
        }
    }

    struct Quit: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Quit the app.")
        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(command: "app.quit", socketPath: path)
            Output.print(response: resp, json: global.json)
            if !resp.ok { throw ExitCode.failure }
        }
    }
}
