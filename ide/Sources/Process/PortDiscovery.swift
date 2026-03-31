import Darwin
import Foundation
import Network
import OSLog

/// Low-level macOS kernel APIs for discovering listening TCP ports and walking process trees.
/// Uses `proc_pidinfo` / `proc_pidfdinfo` — no subprocess spawning, ~1000x faster than lsof.
enum PortDiscovery {
    private static let logger = Logger(subsystem: "com.ghosttyide", category: "PortDiscovery")

    // MARK: - Listening Port Discovery

    /// Get all TCP ports in LISTEN state for the given PID.
    /// Returns empty array if PID is invalid or has no listeners.
    static func listeningPorts(for pid: pid_t) -> [UInt16] {
        // 1. Get required buffer size for FD list
        let fdInfoStride = MemoryLayout<proc_fdinfo>.stride
        let bufferSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bufferSize > 0 else { return [] }

        // 2. Allocate and populate FD list
        let fdCount = Int(bufferSize) / fdInfoStride
        var fdBuffer = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
        let actualSize = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &fdBuffer, bufferSize)
        guard actualSize > 0 else { return [] }
        let actualCount = Int(actualSize) / fdInfoStride

        // 3. Check each socket FD for TCP LISTEN state
        var ports: [UInt16] = []
        let socketInfoSize = Int32(MemoryLayout<socket_fdinfo>.stride)

        for i in 0..<actualCount {
            let fdInfo = fdBuffer[i]
            guard fdInfo.proc_fdtype == PROX_FDTYPE_SOCKET else { continue }

            var socketInfo = socket_fdinfo()
            let result = proc_pidfdinfo(
                pid,
                fdInfo.proc_fd,
                PROC_PIDFDSOCKETINFO,
                &socketInfo,
                socketInfoSize
            )
            guard result == socketInfoSize else { continue }

            // Must be AF_INET or AF_INET6, TCP, in LISTEN state
            let family = socketInfo.psi.soi_family
            guard family == AF_INET || family == AF_INET6 else { continue }
            guard socketInfo.psi.soi_type == SOCK_STREAM else { continue }
            guard socketInfo.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { continue }

            // Extract local port (network byte order → host byte order)
            let rawPort = socketInfo.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport
            let localPort = UInt16(bigEndian: UInt16(truncatingIfNeeded: rawPort))
            if localPort > 0 {
                ports.append(localPort)
            }
        }

        return ports
    }

    // MARK: - Process Tree Walking

    /// Build a parent map (pid → ppid) for all processes on the system.
    /// Call once per scan cycle, then use `descendantPids(of:parentMap:)` per pane.
    static func buildParentMap() -> [pid_t: pid_t] {
        // Get count of all PIDs
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [:] }

        // Allocate and populate PID list
        var allPids = [pid_t](repeating: 0, count: Int(count))
        let actual = proc_listallpids(&allPids, Int32(Int(count) * MemoryLayout<pid_t>.stride))
        guard actual > 0 else { return [:] }
        let pidCount = Int(actual)

        // Build pid → ppid map via sysctl
        var parentMap: [pid_t: pid_t] = [:]
        parentMap.reserveCapacity(pidCount)

        for i in 0..<pidCount {
            let pid = allPids[i]
            guard pid > 0 else { continue }

            var info = kinfo_proc()
            var size = MemoryLayout<kinfo_proc>.stride
            var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
            guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { continue }
            parentMap[pid] = info.kp_eproc.e_ppid
        }

        return parentMap
    }

    /// Find all descendant PIDs of a root PID using a pre-built parent map.
    /// Uses BFS — no additional syscalls.
    static func descendantPids(of rootPid: pid_t, parentMap: [pid_t: pid_t]) -> [pid_t] {
        // Build children map (inverted parent map) filtered to descendants
        var childrenMap: [pid_t: [pid_t]] = [:]
        for (child, parent) in parentMap {
            childrenMap[parent, default: []].append(child)
        }

        // BFS from rootPid
        var result: [pid_t] = []
        var queue: [pid_t] = [rootPid]
        var visited: Set<pid_t> = [rootPid]

        while !queue.isEmpty {
            let current = queue.removeFirst()
            if let children = childrenMap[current] {
                for child in children where !visited.contains(child) {
                    visited.insert(child)
                    result.append(child)
                    queue.append(child)
                }
            }
        }

        return result
    }

    // MARK: - TLS Probe

    /// Non-blocking TLS probe on localhost:port. Returns true if TLS handshake succeeds.
    /// Uses Network.framework with a 200ms timeout.
    static func probeTLS(port: UInt16) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var isTLS = false

        let tlsParams = NWProtocolTLS.Options()
        // Accept self-signed certs (localhost dev servers)
        sec_protocol_options_set_verify_block(
            tlsParams.securityProtocolOptions,
            { _, _, completionHandler in completionHandler(true) },
            DispatchQueue.global(qos: .utility)
        )

        let params = NWParameters(tls: tlsParams)
        let connection = NWConnection(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: port)!,
            using: params
        )

        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                isTLS = true
                semaphore.signal()
            case .failed, .cancelled:
                semaphore.signal()
            case .waiting:
                // Connection cannot proceed (e.g., not TLS)
                connection.cancel()
            default:
                break
            }
        }

        let probeQueue = DispatchQueue(label: "com.ghosttyide.tls-probe", qos: .utility)
        connection.start(queue: probeQueue)

        // 200ms timeout
        let timeout = DispatchTime.now() + .milliseconds(200)
        if semaphore.wait(timeout: timeout) == .timedOut {
            connection.cancel()
        } else {
            connection.cancel()
        }

        return isTLS
    }
}
