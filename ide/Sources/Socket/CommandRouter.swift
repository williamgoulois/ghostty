import Foundation

/// Routes incoming commands to the appropriate handler.
final class IDECommandRouter {
    var handlers: [String: (IDECommand) -> IDEResponse] = [:]

    init() {
        registerAppCommands()
        registerPaneCommands()
    }

    func register(_ command: String, handler: @escaping (IDECommand) -> IDEResponse) {
        handlers[command] = handler
    }

    func dispatch(_ command: IDECommand) -> IDEResponse {
        guard let handler = handlers[command.command] else {
            return .failure("Unknown command: \(command.command)")
        }
        return handler(command)
    }
}
