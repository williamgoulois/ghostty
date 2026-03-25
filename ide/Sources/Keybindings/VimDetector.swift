import Darwin
import Foundation
import GhosttyKit

/// Detects whether vim/neovim is the foreground process in a terminal surface.
///
/// Uses `ghostty_surface_foreground_pid()` which calls `tcgetpgrp()` on the
/// PTY master fd — an O(1) kernel call. Same approach as kitty terminal.
/// Then checks the process name via `proc_name()`.
final class VimDetector {
    static let shared = VimDetector()

    /// Regex matching vim process names (same as tmux's is_vim pattern).
    /// Matches: vim, vi, nvim, lvim, gvim, gview, view, fzf, vimdiff, etc.
    private let vimPattern: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(
            pattern: #"^g?(view|fzf|n?l?vim?x?)(diff)?(-wrapped)?$"#,
            options: .caseInsensitive
        )
    }()

    /// Check if vim/neovim is the foreground process of the surface.
    ///
    /// - Parameter surface: The raw Ghostty surface pointer.
    /// - Returns: `true` if the foreground process matches a vim-like name.
    func isVimRunning(surface: ghostty_surface_t?) -> Bool {
        guard let surface else { return false }

        // O(1) kernel call via tcgetpgrp() on PTY master fd
        let pid = ghostty_surface_foreground_pid(surface)
        guard pid > 0 else { return false }

        // Get the process base name
        guard let name = processName(pid_t(pid)) else { return false }

        let range = NSRange(name.startIndex..., in: name)
        return vimPattern.firstMatch(in: name, range: range) != nil
    }

    /// Get the base name of a process executable via proc_name().
    private func processName(_ pid: pid_t) -> String? {
        // proc_name is a lightweight kernel call (no process spawn)
        var name = [CChar](repeating: 0, count: 256)
        let len = proc_name(pid, &name, UInt32(name.count))
        guard len > 0 else { return nil }
        return String(cString: name)
    }
}
