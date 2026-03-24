import AppKit

extension IDECommandRouter {
    func registerAppCommands() {
        register("app.version") { _ in
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
            return .success(["version": version, "build": build])
        }

        register("app.pid") { _ in
            .success(["pid": Int(ProcessInfo.processInfo.processIdentifier)])
        }

        register("app.quit") { _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
            return .success()
        }

        register("help") { [self] _ in
            let commands = handlers.keys.sorted()
            return .success(["commands": commands])
        }
    }
}
