import ArgumentParser
import Foundation

struct Notify: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Send and manage notifications.",
        subcommands: [Send.self, List.self, Clear.self, Status.self]
    )

    struct Send: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Send a notification.")

        @Argument(help: "Notification title.")
        var title: String

        @Option(name: .long, help: "Notification subtitle.")
        var subtitle: String?

        @Option(name: .long, help: "Notification body text.")
        var body: String?

        @Option(name: .long, help: "Target pane UUID.")
        var pane: String?

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            var args: [String: Any] = ["title": title]
            if let subtitle { args["subtitle"] = subtitle }
            if let body { args["body"] = body }
            if let pane { args["pane_id"] = pane }

            let resp = try SocketClient.send(command: "notify.send", args: args, socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            if resp.ok {
                print("Notification sent: \(title)")
            } else {
                Output.print(response: resp, json: false)
                throw ExitCode.failure
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List recent notifications."
        )

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(command: "notify.list", socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any],
                  let notifications = data["notifications"] as? [[String: Any]] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            if notifications.isEmpty {
                print("No notifications")
                return
            }
            for n in notifications {
                let title = n["title"] as? String ?? "?"
                let subtitle = n["subtitle"] as? String ?? ""
                let body = n["body"] as? String ?? ""
                let ts = n["timestamp"] as? String ?? ""
                let subtitleStr = subtitle.isEmpty ? "" : " [\(subtitle)]"
                let bodyStr = body.isEmpty ? "" : " — \(body)"
                print("\(ts)  \(title)\(subtitleStr)\(bodyStr)")
            }
        }
    }

    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Clear all notifications.")

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(command: "notify.clear", socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            if resp.ok {
                print("Notifications cleared")
            } else {
                Output.print(response: resp, json: false)
                throw ExitCode.failure
            }
        }
    }

    struct Status: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show notification unread status.")

        @OptionGroup var global: GhosttyIDE.GlobalOptions

        func run() throws {
            let path = try global.resolvedSocketPath()
            let resp = try SocketClient.send(command: "notify.status", socketPath: path)
            if global.json {
                Output.print(response: resp, json: true)
                return
            }
            guard resp.ok, let data = resp.data as? [String: Any] else {
                Output.print(response: resp, json: false)
                if !resp.ok { throw ExitCode.failure }
                return
            }
            let count = data["unread_count"] as? Int ?? 0
            let total = data["total_notifications"] as? Int ?? 0
            print("Unread panes: \(count), Total notifications: \(total)")
        }
    }
}
