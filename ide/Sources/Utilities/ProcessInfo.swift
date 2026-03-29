import Darwin
import Foundation

/// Lightweight process information utilities using kernel APIs.
enum IDEProcessInfo {
    /// Get the base name of a process executable.
    ///
    /// Uses `sysctl(KERN_PROCARGS2)` to read the original `argv[0]` — this
    /// preserves symlink names (e.g. `/usr/local/bin/claude` even when the
    /// target is `/…/versions/2.1.87`). Falls back to `proc_pidpath()` then
    /// `proc_name()`. All are O(1) kernel calls with no process spawning.
    ///
    /// - Parameter pid: The process ID to query.
    /// - Returns: The executable basename, or `nil` if the PID is invalid.
    static func processName(for pid: pid_t) -> String? {
        // 1. sysctl KERN_PROCARGS2 → original argv[0] (preserves symlink name)
        if let name = executableNameViaSysctl(pid) {
            return name
        }

        // 2. proc_pidpath → resolved path basename
        var pathBuf = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let pathLen = proc_pidpath(pid, &pathBuf, UInt32(pathBuf.count))
        if pathLen > 0 {
            let fullPath = String(cString: pathBuf)
            let basename = (fullPath as NSString).lastPathComponent
            if !basename.isEmpty {
                return basename
            }
        }

        // 3. proc_name (kernel's cached name — can be truncated or wrong)
        var name = [CChar](repeating: 0, count: 256)
        let len = proc_name(pid, &name, UInt32(name.count))
        guard len > 0 else { return nil }
        return String(cString: name)
    }

    /// Read the original executable path from `sysctl(KERN_PROCARGS2)` and return its basename.
    ///
    /// The KERN_PROCARGS2 buffer layout is:
    ///   [4-byte argc] [executable_path\0] [argv[0]\0] [argv[1]\0] ...
    /// We extract `executable_path` which is the original unresolved path.
    private static func executableNameViaSysctl(_ pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: Int = 0

        // First call: get buffer size
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > 0 else { return nil }

        // Allocate and fetch
        var buf = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buf, &size, nil, 0) == 0 else { return nil }

        // Skip argc (first 4 bytes)
        guard size > 4 else { return nil }

        // Find the null terminator of the executable path
        let pathStart = 4
        guard let nullIdx = buf[pathStart...].firstIndex(of: 0) else { return nil }

        let pathBytes = Array(buf[pathStart..<nullIdx])
        guard !pathBytes.isEmpty else { return nil }

        let fullPath = String(bytes: pathBytes, encoding: .utf8) ?? ""
        guard !fullPath.isEmpty else { return nil }

        return (fullPath as NSString).lastPathComponent
    }
}
