import Foundation
import OSLog

/// Unix domain socket server for IDE control.
/// Listens on /tmp/ghosttyide-{pid}.sock and dispatches JSON commands.
final class IDESocketServer {
    static let shared = IDESocketServer()

    private let logger = Logger(subsystem: "com.ghosttyide", category: "SocketServer")
    private var serverFD: Int32 = -1
    private(set) var socketPath: String = ""
    private var running = false
    private let router = IDECommandRouter()
    private let acceptQueue = DispatchQueue(label: "com.ghosttyide.socket.accept", qos: .userInitiated)
    private let clientQueue = DispatchQueue(label: "com.ghosttyide.socket.client", qos: .userInitiated, attributes: .concurrent)

    var isRunning: Bool { running }

    /// Start listening. Call from main thread after app is ready.
    func start() {
        let pid = ProcessInfo.processInfo.processIdentifier
        socketPath = "/tmp/ghosttyide-\(pid).sock"

        // Also write a well-known symlink for easy discovery
        let wellKnownPath = "/tmp/ghosttyide.sock"

        acceptQueue.async { [self] in
            do {
                // Create symlink before blocking on accept loop
                try? FileManager.default.removeItem(atPath: wellKnownPath)
                try listen(at: socketPath)
            } catch {
                logger.error("Failed to start socket server: \(error)")
            }
        }
    }

    func stop() {
        running = false
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        try? FileManager.default.removeItem(atPath: socketPath)
        try? FileManager.default.removeItem(atPath: "/tmp/ghosttyide.sock")
        logger.info("IDE socket server stopped")
    }

    private func listen(at path: String) throws {
        // Remove stale socket
        try? FileManager.default.removeItem(atPath: path)

        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            throw SocketError.socketCreationFailed(errno)
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw SocketError.pathTooLong
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBufferPointer { buf in
                raw.copyMemory(from: buf.baseAddress!, byteCount: buf.count)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverFD, sockPtr, addrLen)
            }
        }
        guard bindResult == 0 else {
            close(serverFD)
            throw SocketError.bindFailed(errno)
        }

        guard Darwin.listen(serverFD, 5) == 0 else {
            close(serverFD)
            throw SocketError.listenFailed(errno)
        }

        running = true
        try? FileManager.default.createSymbolicLink(atPath: "/tmp/ghosttyide.sock", withDestinationPath: path)
        logger.info("IDE socket server listening on \(path)")

        while running {
            let clientFD = accept(serverFD, nil, nil)
            guard clientFD >= 0 else {
                if running { logger.warning("accept() failed: \(errno)") }
                continue
            }
            handleClient(clientFD)
        }
    }

    private func handleClient(_ fd: Int32) {
        clientQueue.async { [self] in
            defer { close(fd) }

            // Set a read timeout so we don't block forever
            var tv = timeval(tv_sec: 5, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

            guard let data = readAll(fd: fd) else { return }
            guard let command = try? JSONDecoder().decode(IDECommand.self, from: data) else {
                let resp = IDEResponse.failure("Invalid JSON command")
                writeResponse(fd: fd, response: resp)
                return
            }

            let response = DispatchQueue.main.sync {
                router.dispatch(command)
            }
            writeResponse(fd: fd, response: response)
        }
    }

    private func readAll(fd: Int32) -> Data? {
        var data = Data()
        let bufSize = 4096
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }

        while true {
            let n = read(fd, buf, bufSize)
            if n > 0 {
                data.append(buf, count: n)
                if n < bufSize { break }
            } else {
                break
            }
        }
        return data.isEmpty ? nil : data
    }

    private func writeResponse(fd: Int32, response: IDEResponse) {
        guard let data = try? JSONEncoder().encode(response) else { return }
        data.withUnsafeBytes { ptr in
            _ = write(fd, ptr.baseAddress!, ptr.count)
        }
    }

    enum SocketError: Error {
        case socketCreationFailed(Int32)
        case pathTooLong
        case bindFailed(Int32)
        case listenFailed(Int32)
    }
}
