import OSLog

/// Centralized Logger factory for IDE components.
/// Usage: `private static let logger = IDELogger.make(for: MyClass.self)`
enum IDELogger {
    static let subsystem = "com.ghosttyide"

    static func make<T>(for type: T.Type) -> Logger {
        Logger(subsystem: subsystem, category: String(describing: type))
    }
}
