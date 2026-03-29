import Foundation
@testable import GhosttyIDE

/// Convenience factory for creating test commands.
enum TestCommand {
    static func make(_ name: String, args: [String: Any]? = nil) -> IDECommand {
        let codableArgs = args?.mapValues { AnyCodable($0) }
        return IDECommand(command: name, args: codableArgs)
    }
}

/// Extract typed values from an IDEResponse's data dictionary.
extension IDEResponse {
    var dataDict: [String: Any]? {
        data?.value as? [String: Any]
    }
}
