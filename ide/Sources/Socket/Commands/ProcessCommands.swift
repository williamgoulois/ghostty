import Darwin
import Foundation

extension IDECommandRouter {
    func registerProcessCommands() {
        register("process.kill") { command in
            guard let pidValue = command.args?["pid"]?.value as? Int, pidValue > 0 else {
                return .failure("Missing or invalid 'pid' argument")
            }

            let signalNum = (command.args?["signal"]?.value as? Int) ?? Int(SIGINT)
            let pid = pid_t(pidValue)

            // Verify PID belongs to a foreground process in some pane
            let found = ProcessScanner.shared.lastSnapshot.values.contains { snapshot in
                snapshot.processes.contains { $0.pid == pid }
                    || snapshot.ports.contains { $0.pid == pid }
            }

            guard found else {
                return .failure("Process \(pidValue) not found in any pane")
            }

            let success = ProcessScanner.shared.killProcess(pid: pid, signal: Int32(signalNum))
            if success {
                return .success(["pid": pidValue, "signal": signalNum])
            } else {
                return .failure("Failed to kill PID \(pidValue): errno \(errno)")
            }
        }

        register("port.list") { command in
            let filterWorkspace = command.args?["workspace"]?.value as? String
            let filterProject = command.args?["project"]?.value as? String

            var results: [[String: Any]] = []

            for (_, snapshot) in ProcessScanner.shared.lastSnapshot {
                for port in snapshot.ports {
                    if let fw = filterWorkspace, port.workspaceName != fw { continue }
                    if let fp = filterProject {
                        // Look up workspace project from WorkspaceController
                        let wsProject = WorkspaceController.shared.workspaces
                            .first(where: { $0.id == port.workspaceId })?.project
                        if wsProject != fp { continue }
                    }

                    results.append([
                        "port": Int(port.port),
                        "pid": Int(port.pid),
                        "process": port.processName,
                        "tls": port.tls,
                        "pane_id": port.paneId.uuidString,
                        "workspace": port.workspaceName,
                    ])
                }
            }

            return .success(["ports": results.sorted { ($0["port"] as? Int ?? 0) < ($1["port"] as? Int ?? 0) }])
        }
    }
}
