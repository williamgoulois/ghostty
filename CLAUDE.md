# Ghostty IDE Fork — Development Reference

See `FORK.md` for fork purpose, remotes, rebase strategy, and directory structure.
See `IDE_PLAN.md` for the phased implementation plan.
See `DESIGN.md` for visual & UX design decisions (top+bottom bar layout, alternatives).
See `ide/AGENTS.md` for AI agent integration guide (env vars, Claude Code hooks, status tracking).
See `AGENTS.md` for upstream Ghostty's agent guide (zig build/test/fmt commands).
See `HACKING.md` for upstream Ghostty's development guide (Xcode versions, logging, linting).

## Architecture Rules

- **Zig core (`src/`):** Never modify (except the one `ghostty_surface_foreground_pid` addition in `embedded.zig`).
- **macOS frontend (`macos/`):** Modify minimally, always behind `#if GHOSTTY_IDE`.
- **IDE code (`ide/`):** All new code goes here.

## Build

```bash
# 1. Build GhosttyKit xcframework
DEVELOPER_DIR=/Applications/Xcode_26.3.app/Contents/Developer zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast

# 2. Build macOS app (release — optimized, for daily use)
cd macos && xcodebuild -scheme GhosttyIDE -configuration Release build

# 3. Codesign (required — Sparkle.framework needs matching signature)
codesign --force --deep --sign - /Users/William.Goulois/Library/Developer/Xcode/DerivedData/Ghostty-dpyhwfejdrctbtgasmyyxdbeuxjc/Build/Products/Release/GhosttyIDE.app

# 4. Build CLI
cd ide/CLI && swift build

# 5. Lint Swift code (must pass with 0 violations)
swiftlint lint
```

### Build Verification Marker

During development, a small build marker (e.g. `b1`, `b2`) is shown in the bottom-right corner of the bottom bar (`ide/Sources/UI/IDEBottomBarView.swift`). **Bump the marker** each rebuild so you can confirm the running app matches the latest build. Remove the marker once features are confirmed working.

Note: The "debug build" warning banner is driven by the **Zig** build mode (`ghostty_info.mode`), not Xcode's configuration. The `ReleaseFast` flag above already handles it. Use `-configuration Debug` only when you need Swift debug symbols.

### macOS 26 (Tahoe) Zig Workaround

Zig 0.15.2's linker cannot parse macOS 26 SDK `.tbd` files because Apple dropped `arm64` targets, only listing `arm64e`. Tracked as [Codeberg #31658](https://codeberg.org/ziglang/zig/issues/31658), fix in [PR #31673](https://codeberg.org/ziglang/zig/pulls/31673) (not merged as of 2026-03-26).

**Workaround:** Install Xcode 26.3 alongside 26.4 (download from [developer.apple.com/download/all](https://developer.apple.com/download/all/), extract with `xip -x`, rename to `/Applications/Xcode_26.3.app`). Use `DEVELOPER_DIR` to point Zig at it — no system-wide changes needed. The `xcodebuild` step uses default Xcode 26.4.

**Remove this workaround** once Zig 0.15.3+ or 0.16.0 ships with the arm64e TBD fix.

## Key Files (Ghostty core)

- `include/ghostty.h` — C API header, the core-frontend interface
- `src/apprt/embedded.zig` — Embedded runtime (what macOS uses)
- `src/config/Config.zig` — Master config
- `macos/Sources/Ghostty/Ghostty.App.swift` — Swift wrapper for ghostty_app_t
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` — Metal rendering, input dispatch
- `macos/Sources/Features/Splits/SplitTree.swift` — Immutable binary split tree
- `macos/Sources/Features/Terminal/TerminalController.swift` — Window management
- `macos/Sources/Features/Terminal/BaseTerminalController.swift` — Base controller with split/focus logic
- `macos/Sources/App/macOS/AppDelegate.swift` — App lifecycle, menu, notifications

## Key Files (IDE additions)

- `ide/Sources/Logging/IDELogger.swift` — Centralized Logger factory (OSLog, subsystem `com.ghosttyide`)
- `ide/Sources/Socket/SocketServer.swift` — POSIX Unix socket listener on `/tmp/ghosttyide.sock`
- `ide/Sources/Socket/CommandRouter.swift` — JSON command dispatch
- `ide/Sources/Socket/CommandProtocol.swift` — Command/response types with AnyCodable
- `ide/Sources/Socket/Commands/PaneCommands.swift` — pane.list, pane.split, pane.focus, pane.focus-direction, pane.close
- `ide/Sources/Socket/Commands/AppCommands.swift` — app.version, app.pid, app.quit, help
- `ide/Sources/Socket/Commands/WorkspaceCommands.swift` — project + workspace socket commands
- `ide/Sources/Socket/Commands/NotifyCommands.swift` — notify.send, notify.list, notify.clear, notify.status
- `ide/Sources/Socket/Commands/StatusCommands.swift` — status.set, status.clear, status.list
- `ide/Sources/Socket/Commands/SessionCommands.swift` — session.save, session.info
- `ide/Sources/Workspace/Workspace.swift` — ProjectFile, ProjectWindowState, PaneSummary data model
- `ide/Sources/Workspace/WorkspaceStore.swift` — Disk I/O with timestamped files + symlinks
- `ide/Sources/Workspace/WorkspaceManager.swift` — Bridge live app state to data model
- `ide/Sources/Workspace/IDEWorkspace.swift` — Live workspace model (name, project, color, emoji, metadata, status)
- `ide/Sources/Workspace/WorkspaceController.swift` — Workspace list, switching, project filter, surfaceTree swap
- `ide/Sources/Workspace/WorkspaceStatusBridge.swift` — Wires git branch, agent state, notifications to workspace
- `ide/Sources/Workspace/GitBranchProvider.swift` — Background git branch detection
- `ide/Sources/Workspace/IDESessionStore.swift` — Session data model + disk I/O
- `ide/Sources/Notifications/NotificationManager.swift` — macOS notification center bridge + dock badge
- `ide/Sources/Notifications/StatusStore.swift` — In-memory per-pane key-value status
- `ide/Sources/Keybindings/VimDetector.swift` — Detect vim/neovim via foreground PID
- `ide/Sources/Keybindings/IDEKeybindConfig.swift` — Parse `~/.config/ghosttyide/config`
- `ide/Sources/Keybindings/IDEKeybindRegistry.swift` — Match NSEvent to IDEAction
- `ide/Sources/Keybindings/IDEActionDispatcher.swift` — Execute IDE + Ghostty actions (vim-aware)
- `ide/Sources/Keybindings/IDEConfigWatcher.swift` — Config file hot-reload via DispatchSource
- `ide/Sources/UI/IDETopBarView.swift` — Top bar: workspace metadata, project name, notification bell
- `ide/Sources/UI/IDEBottomBarView.swift` — Bottom bar: workspace pills
- `ide/Sources/UI/NotificationPanelView.swift` — In-app notification panel
- `ide/Sources/UI/PaneNotificationOverlay.swift` — Pane border overlay for unread notifications
- `ide/Sources/UI/IDEProjectPickerView.swift` — Cmd+P project picker
- `ide/Sources/Branding/AppBrand.swift` — Brand constants (GhosttyIDE vs Ghostty)
- `ide/Sources/Palette/IDECommandPaletteOptions.swift` — IDE commands in command palette
- `ide/CLI/Sources/SocketClient.swift` — POSIX socket client
- `ide/CLI/Sources/Commands/` — CLI command implementations
- `ide/Tests/test_socket.py` — Integration tests
- `DESIGN.md` — Visual & UX design decisions

## Files Modified in Upstream Ghostty

| File | Change |
|---|---|
| `macos/Ghostty.xcodeproj` | GhosttyIDE target |
| `macos/Sources/App/macOS/AppDelegate.swift` | Socket/keybind/watcher init |
| `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` | IDE keybind interception + env vars |
| `macos/Sources/Features/Terminal/TerminalView.swift` | Top/bottom bar + notification env |
| `macos/Sources/Features/Terminal/TerminalController.swift` | Workspace tree bridge |
| `macos/Sources/Features/Splits/TerminalSplitTreeView.swift` | Pane notification overlay |
| `macos/Sources/Features/Command Palette/TerminalCommandPalette.swift` | IDE palette entries |
| `include/ghostty.h` | `ghostty_surface_foreground_pid()` |
| `src/apprt/embedded.zig` | Export foreground PID function |

## CLI Usage

```bash
# Run from ide/CLI directory, or use the built binary at ide/CLI/.build/debug/ide
swift run ide pane list
swift run ide pane focus-direction left
swift run ide app version --json
swift run ide project save|restore|list|delete|close-all|rename
swift run ide workspace new|switch|next|previous|list|rename|meta|project-switch
swift run ide notify send "Title" --body "Body"
swift run ide notify list|clear|status
swift run ide status set|clear|list
swift run ide session save|info
swift run ide raw <command> -a key=value
```

## Logging

All IDE components log via Apple's `os.log` (OSLog) under subsystem `com.ghosttyide`. Each component has its own category (e.g. `IDESocketServer`, `IDECommandRouter`, `WorkspaceController`).

```bash
# Stream all IDE logs in real time
log stream --predicate 'subsystem == "com.ghosttyide"'

# Filter by component
log stream --predicate 'subsystem == "com.ghosttyide" AND category == "IDECommandRouter"'

# Search recent logs (last 5 minutes)
log show --predicate 'subsystem == "com.ghosttyide"' --last 5m

# Filter by level (debug, info, default, error, fault)
log stream --predicate 'subsystem == "com.ghosttyide"' --level debug
```

**Log levels used:** `.debug` for command tracing and expected failures (git in non-git dirs), `.info` for lifecycle events (config reload, project save), `.warning` for client mistakes (unknown commands, bad config lines), `.error` for actual failures (write errors, decode failures).

**Note:** `.debug` messages are only captured when streaming live (`log stream`) or when explicitly enabled. They are not persisted to disk by default.

## Testing

```bash
# Integration tests (requires GhosttyIDE running + CLI built)
python3 ide/Tests/test_socket.py

# 115 tests: socket protocol (14), project (10), workspace (25),
# notify (9), status (10), session (4), CLI (43)
```
