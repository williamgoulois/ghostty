import Foundation
import OSLog

/// Routes incoming commands to the appropriate handler.
final class IDECommandRouter {
    private static let logger = IDELogger.make(for: IDECommandRouter.self)

    var handlers: [String: (IDECommand) -> IDEResponse] = [:]

    init() {
        registerAppCommands()
        registerPaneCommands()
        registerWorkspaceCommands()
        registerNotifyCommands()
        registerStatusCommands()
        registerSessionCommands()
        registerProcessCommands()
    }

    func register(_ command: String, handler: @escaping (IDECommand) -> IDEResponse) {
        handlers[command] = handler
    }

    func dispatch(_ command: IDECommand) -> IDEResponse {
        Self.logger.debug("CMD \(command.command) args=\(String(describing: command.args))")

        guard let handler = handlers[command.command] else {
            Self.logger.warning("Unknown command: \(command.command)")
            return .failure("Unknown command: \(command.command)")
        }

        let response = handler(command)
        Self.logger.debug("CMD \(command.command) -> ok=\(response.ok)")
        return response
    }
}
