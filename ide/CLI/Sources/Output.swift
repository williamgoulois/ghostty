import Foundation

/// Handles formatting and printing of command responses.
enum Output {
    static func print(response: SocketClient.Response, json jsonMode: Bool) {
        if jsonMode {
            if let str = String(data: response.raw, encoding: .utf8) {
                Swift.print(str)
            }
            return
        }

        if !response.ok {
            fputs("Error: \(response.error ?? "unknown error")\n", stderr)
            return
        }

        guard let data = response.data else {
            Swift.print("OK")
            return
        }

        printValue(data, indent: 0)
    }

    private static func printValue(_ value: Any, indent: Int) {
        let prefix = String(repeating: "  ", count: indent)
        switch value {
        case let dict as [String: Any]:
            for (key, val) in dict.sorted(by: { $0.key < $1.key }) {
                if let nested = val as? [String: Any] {
                    Swift.print("\(prefix)\(key):")
                    printValue(nested, indent: indent + 1)
                } else if let array = val as? [[String: Any]] {
                    Swift.print("\(prefix)\(key):")
                    for item in array {
                        printValue(item, indent: indent + 1)
                        Swift.print()
                    }
                } else if let array = val as? [Any] {
                    Swift.print("\(prefix)\(key): \(array.map { "\($0)" }.joined(separator: ", "))")
                } else {
                    Swift.print("\(prefix)\(key): \(val)")
                }
            }
        case let array as [Any]:
            for item in array {
                printValue(item, indent: indent)
            }
        default:
            Swift.print("\(prefix)\(value)")
        }
    }
}
