import AppKit
import Foundation

/// Direction for pane navigation.
enum IDEDirection: String {
    case left, right, up, down

    /// The Ghostty action string for `goto_split`.
    var ghosttyAction: String { "goto_split:\(rawValue)" }
}

/// An IDE action triggered by a keybinding.
enum IDEAction: Equatable {
    case workspaceNew
    case workspaceNext
    case workspacePrevious
    case workspaceGoto(Int) // 1-9
    case workspaceClose
    case workspaceMoveNext
    case workspaceMovePrevious
    case workspaceBreakPane
    case workspaceRename
    case focusDirection(IDEDirection) // vim-aware pane navigation
    case notificationsToggle
    case notificationsJumpUnread
    case projectSwitch
    case projectPicker
    case projectRename
    case ghosttyAction(String) // raw Ghostty action string
}

/// A parsed keybinding: modifiers + key → action.
struct IDEKeybinding {
    let modifiers: NSEvent.ModifierFlags
    let keyCode: UInt16
    let action: IDEAction

    /// Check if an NSEvent matches this keybinding.
    func matches(_ event: NSEvent) -> Bool {
        // Compare only the modifier keys we care about
        let mask: NSEvent.ModifierFlags = [.command, .control, .shift, .option]
        let eventMods = event.modifierFlags.intersection(mask)
        return eventMods == modifiers && event.keyCode == keyCode
    }
}

/// Parses `~/.config/ghosttyide/config` into IDE keybindings.
enum IDEKeybindConfig {
    static let configDir = "\(NSHomeDirectory())/.config/ghosttyide"
    static let configPath = "\(configDir)/config"

    /// Parse the config file, falling back to built-in defaults.
    static func parse() -> [IDEKeybinding] {
        if FileManager.default.fileExists(atPath: configPath),
           let contents = try? String(contentsOfFile: configPath, encoding: .utf8) {
            let parsed = parseLines(contents)
            return parsed.isEmpty ? defaultBindings() : parsed
        }
        return defaultBindings()
    }

    /// Parse config lines into keybindings.
    static func parseLines(_ contents: String) -> [IDEKeybinding] {
        var bindings: [IDEKeybinding] = []
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            // Parse: keybind = <key>=<action>
            guard trimmed.hasPrefix("keybind"),
                  let eqIdx = trimmed.firstIndex(of: "=") else { continue }

            let afterFirst = trimmed[trimmed.index(after: eqIdx)...]
                .trimmingCharacters(in: .whitespaces)

            // Split on the SECOND '=' to get key and action
            guard let secondEq = afterFirst.firstIndex(of: "=") else { continue }
            let keyPart = afterFirst[..<secondEq].trimmingCharacters(in: .whitespaces)
            let actionPart = String(afterFirst[afterFirst.index(after: secondEq)...])
                .trimmingCharacters(in: .whitespaces)

            guard !keyPart.isEmpty, !actionPart.isEmpty else { continue }

            // Parse modifiers + key
            guard let (mods, code) = parseKey(keyPart) else { continue }

            // Parse action
            guard let action = parseAction(actionPart) else { continue }

            bindings.append(IDEKeybinding(modifiers: mods, keyCode: code, action: action))
        }
        return bindings
    }

    // MARK: - Key Parsing

    /// Parse a key string like "cmd+shift+h" into modifiers + keyCode.
    static func parseKey(_ keyStr: String) -> (NSEvent.ModifierFlags, UInt16)? {
        let parts = keyStr.lowercased().components(separatedBy: "+")
        var mods: NSEvent.ModifierFlags = []
        var keyName: String?

        for part in parts {
            switch part {
            case "cmd", "super", "command": mods.insert(.command)
            case "ctrl", "control": mods.insert(.control)
            case "shift": mods.insert(.shift)
            case "alt", "opt", "option": mods.insert(.option)
            default: keyName = part
            }
        }

        guard let name = keyName, let code = keyCodeMap[name] else { return nil }
        return (mods, code)
    }

    // MARK: - Action Parsing

    /// Parse an action string into an IDEAction.
    static func parseAction(_ actionStr: String) -> IDEAction? {
        if actionStr.hasPrefix("ide:") {
            return parseIDEAction(String(actionStr.dropFirst(4)))
        }
        // Raw Ghostty action string
        return .ghosttyAction(actionStr)
    }

    private static func parseIDEAction(_ str: String) -> IDEAction? {
        // Handle parameterized actions
        if str.hasPrefix("workspace_goto:") {
            guard let n = Int(str.dropFirst("workspace_goto:".count)), n >= 1, n <= 9 else {
                return nil
            }
            return .workspaceGoto(n)
        }
        if str.hasPrefix("focus_direction:") {
            guard let dir = IDEDirection(rawValue: String(str.dropFirst("focus_direction:".count))) else {
                return nil
            }
            return .focusDirection(dir)
        }

        switch str {
        case "workspace_new": return .workspaceNew
        case "workspace_next": return .workspaceNext
        case "workspace_previous": return .workspacePrevious
        case "workspace_close": return .workspaceClose
        case "workspace_move_next": return .workspaceMoveNext
        case "workspace_move_previous": return .workspaceMovePrevious
        case "workspace_break_pane": return .workspaceBreakPane
        case "workspace_rename": return .workspaceRename
        case "notifications_toggle": return .notificationsToggle
        case "notifications_jump_unread": return .notificationsJumpUnread
        case "project_switch": return .projectSwitch
        case "project_picker": return .projectPicker
        case "project_rename": return .projectRename
        default: return nil
        }
    }

    // MARK: - Default Bindings

    /// Built-in default keybindings when no config file exists.
    static func defaultBindings() -> [IDEKeybinding] {
        var b: [IDEKeybinding] = []

        // Workspace
        b.append(bind(.command, "n", .workspaceNew))
        b.append(bind(.command, "o", .workspaceNext))
        b.append(bind(.command, "i", .workspacePrevious))
        b.append(bind([.command, .shift], "w", .workspaceClose))
        b.append(bind([.command, .shift], "o", .workspaceMoveNext))
        b.append(bind([.command, .shift], "i", .workspaceMovePrevious))
        b.append(bind([.command, .shift], "n", .workspaceBreakPane))
        b.append(bind([.command, .shift], "r", .workspaceRename))

        // Workspace goto 1-9
        for n in 1...9 {
            b.append(bind(.command, "\(n)", .workspaceGoto(n)))
        }

        // Vim-aware pane navigation
        b.append(bind(.control, "h", .focusDirection(.left)))
        b.append(bind(.control, "j", .focusDirection(.down)))
        b.append(bind(.control, "k", .focusDirection(.up)))
        b.append(bind(.control, "y", .focusDirection(.right)))

        // Pane management (Ghostty actions)
        b.append(bind(.command, "t", .ghosttyAction("new_split:right")))
        b.append(bind([.command, .shift], "t", .ghosttyAction("new_split:down")))
        b.append(bind(.command, "w", .ghosttyAction("close_surface")))
        b.append(bind(.command, "f", .ghosttyAction("toggle_split_zoom")))
        b.append(bind([.command, .shift], "h", .ghosttyAction("resize_split:left,10")))
        b.append(bind([.command, .shift], "j", .ghosttyAction("resize_split:down,10")))
        b.append(bind([.command, .shift], "k", .ghosttyAction("resize_split:up,10")))
        b.append(bind([.command, .shift], "l", .ghosttyAction("resize_split:right,10")))

        // IDE UI (Ghostty actions)
        b.append(bind([.command, .shift], "p", .ghosttyAction("toggle_command_palette")))
        b.append(bind(.command, "slash", .ghosttyAction("start_search")))
        b.append(bind(.command, "comma", .ghosttyAction("open_config")))
        b.append(bind([.command, .shift], "comma", .ghosttyAction("reload_config")))

        // IDE UI (IDE actions)
        b.append(bind(.command, "p", .projectPicker))
        b.append(bind([.command, .shift], "m", .notificationsToggle))
        b.append(bind([.command, .shift], "u", .notificationsJumpUnread))

        return b
    }

    private static func bind(
        _ mods: NSEvent.ModifierFlags, _ key: String, _ action: IDEAction
    ) -> IDEKeybinding {
        IDEKeybinding(modifiers: mods, keyCode: keyCodeMap[key] ?? 0, action: action)
    }

    // MARK: - Key Code Map

    /// macOS virtual key codes for common keys.
    static let keyCodeMap: [String: UInt16] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03,
        "h": 0x04, "g": 0x05, "z": 0x06, "x": 0x07,
        "c": 0x08, "v": 0x09, "b": 0x0B, "q": 0x0C,
        "w": 0x0D, "e": 0x0E, "r": 0x0F, "y": 0x10,
        "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
        "4": 0x15, "5": 0x17, "6": 0x16, "7": 0x1A,
        "8": 0x1C, "9": 0x19, "0": 0x1D, "o": 0x1F,
        "u": 0x20, "i": 0x22, "p": 0x23, "l": 0x25,
        "j": 0x26, "k": 0x28, "n": 0x2D, "m": 0x2E,
        "slash": 0x2C, "comma": 0x2B, "period": 0x2F,
        "semicolon": 0x29, "backslash": 0x2A,
        "equal": 0x18, "minus": 0x1B, "bracket_left": 0x21,
        "bracket_right": 0x1E, "quote": 0x27, "grave": 0x32,
        "return": 0x24, "tab": 0x30, "space": 0x31,
        "escape": 0x35, "delete": 0x33,
    ]
}
