import AppKit
import Foundation

/// Holds parsed IDE keybindings and matches incoming NSEvents against them.
///
/// Loaded at app startup. Reloaded on config file change.
/// Checked in `performKeyEquivalent()` BEFORE Ghostty's Zig keybind system.
final class IDEKeybindRegistry {
    static let shared = IDEKeybindRegistry()

    private var bindings: [IDEKeybinding] = []
    private let lock = NSLock()

    /// Load keybindings from config file (or defaults).
    func load() {
        let parsed = IDEKeybindConfig.parse()
        lock.lock()
        bindings = parsed
        lock.unlock()
    }

    /// Reload keybindings from config file.
    func reload() {
        load()
    }

    /// Match an NSEvent against registered keybindings.
    ///
    /// - Parameter event: The key event from `performKeyEquivalent`.
    /// - Returns: The matched IDE action, or `nil` if no binding matches.
    func match(event: NSEvent) -> IDEAction? {
        lock.lock()
        defer { lock.unlock() }

        for binding in bindings where binding.matches(event) {
            return binding.action
        }
        return nil
    }

    /// Number of loaded bindings (for debugging/testing).
    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return bindings.count
    }
}
