import Foundation
import OSLog

/// Watches `~/.config/ghosttyide/config` for changes and reloads keybindings.
///
/// Uses GCD `DispatchSource` to monitor the file descriptor for write/rename/delete events.
final class IDEConfigWatcher {
    static let shared = IDEConfigWatcher()
    private static let logger = IDELogger.make(for: IDEConfigWatcher.self)

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    /// Start watching the config file.
    func start() {
        stop()

        let path = IDEKeybindConfig.configPath
        guard FileManager.default.fileExists(atPath: path) else {
            Self.logger.debug("Config file not found, skipping watch: \(path)")
            return
        }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else {
            Self.logger.error("Failed to open config file for watching: \(path)")
            return
        }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            IDEConfigWatcher.logger.info("Config file changed, reloading keybindings")
            IDEKeybindRegistry.shared.reload()

            // If the file was deleted or renamed, restart watching
            // (editors like vim write to a temp file then rename)
            let flags = source.data
            if flags.contains(.delete) || flags.contains(.rename) {
                self?.restart()
            }
        }

        source.setCancelHandler {
            close(fd)
        }

        source.resume()
        self.source = source
    }

    /// Stop watching.
    func stop() {
        source?.cancel()
        source = nil
        fileDescriptor = -1
    }

    /// Restart watching (after file delete/rename).
    private func restart() {
        Self.logger.debug("Config file deleted/renamed, scheduling re-watch")
        stop()
        // Small delay to let the editor finish writing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.start()
        }
    }
}
