import Foundation

/// Connects to the GhosttyIDE Unix socket, sends a command, and returns the response.
enum SocketClient {
    struct Response {
        let ok: Bool
        let data: Any?
        let error: String?
        let raw: Data
    }

    static func send(command: String, args: [String: Any]? = nil, socketPath: String) throws -> Response {
        var payload: [String: Any] = ["command": command]
        if let args { payload["args"] = args }

        let requestData = try JSONSerialization.data(withJSONObject: payload)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw CLIError.socketFailed("Failed to create socket: \(errno)")
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw CLIError.socketFailed("Socket path too long")
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBufferPointer { buf in
                raw.copyMemory(from: buf.baseAddress!, byteCount: buf.count)
            }
        }

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            throw CLIError.connectionRefused(socketPath)
        }

        // Send request
        requestData.withUnsafeBytes { ptr in
            _ = Foundation.write(fd, ptr.baseAddress!, ptr.count)
        }
        // Signal end of request
        shutdown(fd, SHUT_WR)

        // Read response
        var responseData = Data()
        let bufSize = 4096
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        while true {
            let n = read(fd, buf, bufSize)
            if n > 0 {
                responseData.append(buf, count: n)
            } else {
                break
            }
        }

        guard !responseData.isEmpty else {
            throw CLIError.emptyResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            throw CLIError.invalidResponse
        }

        return Response(
            ok: json["ok"] as? Bool ?? false,
            data: json["data"],
            error: json["error"] as? String,
            raw: responseData
        )
    }

    enum CLIError: LocalizedError {
        case socketFailed(String)
        case connectionRefused(String)
        case emptyResponse
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .socketFailed(let msg): return msg
            case .connectionRefused(let path): return "Connection refused at \(path). Is GhosttyIDE running?"
            case .emptyResponse: return "Empty response from server"
            case .invalidResponse: return "Invalid response from server"
            }
        }
    }
}
