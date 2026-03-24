import Foundation

/// In-memory per-pane key-value status store.
/// All access must be on the main thread (socket commands dispatch there).
final class StatusStore {
    static let shared = StatusStore()

    struct StatusEntry {
        let key: String
        let value: String
        let paneId: String
        let updatedAt: Date
    }

    /// Outer key = pane_id, inner key = status key.
    private var statuses: [String: [String: StatusEntry]] = [:]

    /// Set or update a status entry.
    func set(paneId: String, key: String, value: String) {
        let entry = StatusEntry(key: key, value: value, paneId: paneId, updatedAt: Date())
        statuses[paneId, default: [:]][key] = entry
    }

    /// Clear a specific key for a pane, or all keys if key is nil.
    func clear(paneId: String?, key: String?) {
        if let paneId {
            if let key {
                statuses[paneId]?[key] = nil
            } else {
                statuses[paneId] = nil
            }
        } else {
            statuses.removeAll()
        }
    }

    /// List status entries, optionally filtered by pane.
    func list(paneId: String? = nil) -> [[String: Any]] {
        let formatter = ISO8601DateFormatter()
        var result: [[String: Any]] = []

        let paneIds = paneId.map { [$0] } ?? Array(statuses.keys)
        for pid in paneIds {
            guard let entries = statuses[pid] else { continue }
            for entry in entries.values {
                result.append([
                    "key": entry.key,
                    "value": entry.value,
                    "pane_id": entry.paneId,
                    "updated_at": formatter.string(from: entry.updatedAt),
                ])
            }
        }
        return result
    }
}
