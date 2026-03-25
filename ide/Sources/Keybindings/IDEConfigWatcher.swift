import Foundation

/// Watches `~/.config/ghosttyide/config` for changes and reloads keybindings.
///
/// Uses GCD `DispatchSource` to monitor the file descriptor for write/rename/delete events.
final class IDEConfigWatcher {
    static let shared = IDEConfigWatcher()

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1

    /// Start watching the config file.
    func start() {
        stop()

        let path = IDEKeybindConfig.configPath
        guard FileManager.default.fileExists(atPath: path) else { return }

        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        fileDescriptor = fd

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )

        source.setEventHandler { [weak self] in
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
        stop()
        // Small delay to let the editor finish writing
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.start()
        }
    }
}
