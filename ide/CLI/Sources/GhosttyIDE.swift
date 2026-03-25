import ArgumentParser
import Foundation

@main
struct GhosttyIDE: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ide",
        abstract: "Control GhosttyIDE from the command line.",
        subcommands: [
            Pane.self,
            App.self,
            Project.self,
            Workspace.self,
            Session.self,
            Notify.self,
            Status.self,
            Help_.self,
            Raw.self,
        ],
        defaultSubcommand: nil
    )

    struct GlobalOptions: ParsableArguments {
        @Option(name: .long, help: "Path to the Unix socket.")
        var socket: String?

        @Flag(name: .long, help: "Output raw JSON response.")
        var json: Bool = false

        /// Resolve the socket path from: --socket flag, env var, or well-known path.
        func resolvedSocketPath() throws -> String {
            if let path = socket { return path }
            if let env = ProcessInfo.processInfo.environment["GHOSTTYIDE_SOCKET"] { return env }
            let wellKnown = "/tmp/ghosttyide.sock"
            if FileManager.default.fileExists(atPath: wellKnown) { return wellKnown }
            throw ValidationError("No socket found. Is GhosttyIDE running? Use --socket or set GHOSTTYIDE_SOCKET.")
        }
    }
}
