import Darwin
import Foundation
import GhosttyKit
import OSLog

/// Scans all terminal panes, classifies foreground processes, discovers listening ports,
/// and produces per-workspace snapshots. Uses event-driven scanning via DispatchSource
/// process watchers + cheap periodic PID checks for battery efficiency.
final class ProcessScanner {
    static let shared = ProcessScanner()
    private static let logger = Logger(subsystem: "com.ghosttyide", category: "ProcessScanner")

    // MARK: - Classification

    private static let agentNames: Set<String> = [
        "claude", "opencode",
    ]

    private static let shellNames: Set<String> = [
        "zsh", "bash", "fish", "sh", "dash", "tcsh", "csh", "ksh", "nu", "nushell",
        "login", "sshd",
    ]

    /// Regex matching vim-like editors (reuse VimDetector's pattern).
    private static let editorPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"^g?(view|fzf|n?l?vim?x?|emacs)(diff)?(-wrapped)?$"#,
            options: .caseInsensitive
        )
    }()

    /// Classify a process name into a category.
    static func classify(_ name: String) -> ProcessCategory {
        let lower = name.lowercased()
        if agentNames.contains(lower) { return .agent }
        if shellNames.contains(lower) { return .shell }
        let range = NSRange(name.startIndex..., in: name)
        if editorPattern.firstMatch(in: name, range: range) != nil { return .editor }
        return .longRunning
    }

    // MARK: - Scanning

    private let scanQueue = DispatchQueue(label: "com.ghosttyide.process-scanner", qos: .utility)

    /// Cached result of the last scan, keyed by workspace ID.
    private(set) var lastSnapshot: [UUID: WorkspaceProcessSnapshot] = [:]

    /// Cached foreground PIDs from the last PID check, keyed by surface UUID.
    private(set) var cachedPids: [UUID: pid_t] = [:]

    // MARK: - Dispatch Source Watching

    /// Active dispatch sources watching foreground PIDs for lifecycle events.
    private var watchedSources: [pid_t: DispatchSourceProcess] = [:]

    /// Callback invoked when a watched process fires an event (fork/exec/exit).
    var onProcessEvent: ((pid_t, Bool) -> Void)?

    /// Start watching a PID for exit/fork/exec events via kernel kqueue.
    /// Zero CPU cost while waiting — kernel delivers events.
    func watchPid(_ pid: pid_t) {
        guard pid > 0, watchedSources[pid] == nil else { return }

        let source = DispatchSource.makeProcessSource(
            identifier: pid,
            eventMask: [.exit, .fork, .exec],
            queue: scanQueue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }
            let data = source.data
            let isExit = data.contains(.exit)

            if isExit {
                Self.logger.debug("Watched PID \(pid) exited")
                self.unwatchPid(pid)
                // Remove this PID's ports immediately from snapshot
                self.removePortsForPid(pid)
            } else {
                Self.logger.debug("Watched PID \(pid) fork/exec event")
            }

            DispatchQueue.main.async {
                self.onProcessEvent?(pid, isExit)
            }
        }

        source.setCancelHandler { [weak self] in
            self?.watchedSources.removeValue(forKey: pid)
        }

        watchedSources[pid] = source
        source.resume()
    }

    /// Stop watching a PID.
    func unwatchPid(_ pid: pid_t) {
        if let source = watchedSources.removeValue(forKey: pid) {
            source.cancel()
        }
    }

    /// Remove all watched sources.
    func unwatchAll() {
        for (_, source) in watchedSources {
            source.cancel()
        }
        watchedSources.removeAll()
    }

    // MARK: - Full Scan

    /// Perform a full scan of all panes. Captures surfaces on main thread,
    /// scans on background queue, delivers result on main thread.
    func scan(
        surfaces: [(Ghostty.SurfaceView, IDEWorkspace)],
        completion: @escaping ([UUID: WorkspaceProcessSnapshot]) -> Void
    ) {
        scanQueue.async { [weak self] in
            guard let self else { return }
            let result = self.performScan(surfaces: surfaces)
            self.lastSnapshot = result

            DispatchQueue.main.async {
                completion(result)
            }
        }
    }

    private func performScan(
        surfaces: [(Ghostty.SurfaceView, IDEWorkspace)]
    ) -> [UUID: WorkspaceProcessSnapshot] {
        // Build parent map once for all panes
        let parentMap = PortDiscovery.buildParentMap()

        var byWorkspace: [UUID: (processes: [DetectedProcess], ports: [DetectedPort])] = [:]

        for (surface, ws) in surfaces {
            guard let surfacePtr = surface.surface else { continue }
            let fgPid = ghostty_surface_foreground_pid(surfacePtr)
            guard fgPid > 0 else { continue }

            let pid = pid_t(fgPid)
            let name = IDEProcessInfo.processName(for: pid) ?? "unknown"
            let category = ProcessScanner.classify(name)

            var process = DetectedProcess(
                pid: pid,
                name: name,
                category: category,
                paneId: surface.id,
                workspaceId: ws.id,
                workspaceName: ws.name
            )

            // Merge agent status from StatusStore
            if category == .agent {
                let statuses = StatusStore.shared.list(paneId: surface.id.uuidString)
                if let agentEntry = statuses.first(where: { $0["key"] as? String == "agent" }) {
                    process.agentStatus = agentEntry["value"] as? String
                }
            }

            var entry = byWorkspace[ws.id, default: ([], [])]
            entry.processes.append(process)

            // Port discovery: walk the foreground process's descendant tree
            let descendants = PortDiscovery.descendantPids(of: pid, parentMap: parentMap)
            let allPids = [pid] + descendants
            var seenPorts: Set<UInt16> = []

            for treePid in allPids {
                let ports = PortDiscovery.listeningPorts(for: treePid)
                let treePidName = (treePid == pid) ? name
                    : (IDEProcessInfo.processName(for: treePid) ?? name)
                for port in ports where !seenPorts.contains(port) {
                    seenPorts.insert(port)
                    let tls = PortDiscovery.probeTLS(port: port)
                    entry.ports.append(DetectedPort(
                        port: port,
                        pid: treePid,
                        processName: treePidName,
                        paneId: surface.id,
                        workspaceId: ws.id,
                        workspaceName: ws.name,
                        tls: tls
                    ))
                }
            }

            byWorkspace[ws.id] = entry
        }

        // Build snapshots
        var result: [UUID: WorkspaceProcessSnapshot] = [:]
        for (wsId, data) in byWorkspace {
            let agentPanes = Set(data.processes.filter { $0.category == .agent }.map(\.paneId))
            let longPanes = Set(data.processes.filter { $0.category == .longRunning }.map(\.paneId))
            // Deduplicate ports by port number within workspace
            var uniquePorts: [UInt16: DetectedPort] = [:]
            for port in data.ports { uniquePorts[port.port] = port }

            result[wsId] = WorkspaceProcessSnapshot(
                workspaceId: wsId,
                processes: data.processes,
                ports: Array(uniquePorts.values).sorted { $0.port < $1.port },
                hasAgent: !agentPanes.isEmpty,
                agentPaneIds: agentPanes,
                longRunningPaneIds: longPanes
            )
        }

        return result
    }

    // MARK: - PID Change Check

    /// Cheap PID check: compare current foreground PIDs against cached values.
    /// Returns surface UUIDs where the PID changed.
    func checkForPidChanges(
        surfaces: [(Ghostty.SurfaceView, IDEWorkspace)]
    ) -> [UUID] {
        var changedSurfaces: [UUID] = []

        for (surface, _) in surfaces {
            guard let surfacePtr = surface.surface else { continue }
            let currentPid = pid_t(ghostty_surface_foreground_pid(surfacePtr))
            let cachedPid = cachedPids[surface.id]

            if cachedPid != currentPid {
                changedSurfaces.append(surface.id)
                cachedPids[surface.id] = currentPid

                // Update dispatch source watching
                if let old = cachedPid, old > 0 {
                    unwatchPid(old)
                }
                if currentPid > 0 {
                    watchPid(currentPid)
                }
            }
        }

        return changedSurfaces
    }

    // MARK: - Kill

    /// Kill a process by PID. Returns true if signal was sent successfully.
    @discardableResult
    func killProcess(pid: pid_t, signal: Int32 = SIGINT) -> Bool {
        let result = Darwin.kill(pid, signal)
        if result == 0 {
            Self.logger.info("Sent signal \(signal) to PID \(pid)")
        } else {
            Self.logger.error("Failed to kill PID \(pid): errno \(errno)")
        }
        return result == 0
    }

    // MARK: - Private Helpers

    /// Remove ports belonging to a specific PID from the cached snapshot.
    private func removePortsForPid(_ pid: pid_t) {
        for (wsId, snapshot) in lastSnapshot {
            let filteredPorts = snapshot.ports.filter { $0.pid != pid }
            let filteredProcesses = snapshot.processes.filter { $0.pid != pid }
            if filteredPorts.count != snapshot.ports.count
                || filteredProcesses.count != snapshot.processes.count {
                let agentPanes = Set(filteredProcesses.filter { $0.category == .agent }.map(\.paneId))
                let longPanes = Set(
                    filteredProcesses.filter { $0.category == .longRunning }.map(\.paneId))
                lastSnapshot[wsId] = WorkspaceProcessSnapshot(
                    workspaceId: wsId,
                    processes: filteredProcesses,
                    ports: filteredPorts,
                    hasAgent: !agentPanes.isEmpty,
                    agentPaneIds: agentPanes,
                    longRunningPaneIds: longPanes
                )
            }
        }
    }
}
