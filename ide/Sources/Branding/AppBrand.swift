import Foundation

/// Centralized brand constants for user-visible strings.
/// Under `#if GHOSTTY_IDE`, surfaces "GhosttyIDE" instead of "Ghostty".
enum AppBrand {
    #if GHOSTTY_IDE
    static let name = "GhosttyIDE"
    static let tagline = "CLI-first IDE built on Ghostty"
    static let githubURL = URL(string: "https://github.com/williamgoulois/ghostty")
    #else
    static let name = "Ghostty"
    static let tagline = "Fast, native, feature-rich terminal \nemulator pushing modern features."
    static let githubURL = URL(string: "https://github.com/ghostty-org/ghostty")
    #endif
}
