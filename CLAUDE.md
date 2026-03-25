# Ghostty IDE Fork

This is a fork of [Ghostty](https://github.com/ghostty-org/ghostty) being turned into a CLI-first IDE.

## Project Goal

Build a clean, maintainable CLI-first IDE on top of Ghostty's terminal emulator core. Key features:
- Unix socket server for full scriptability
- CLI binary to control every aspect of the IDE
- WebKit browser panels alongside terminal splits
- Named workspaces with layout persistence
- Minimal fork diff to allow easy rebasing on upstream Ghostty

## Architecture

- **Zig core (libghostty):** Never modify. Handles VT parsing, terminal state, Metal rendering.
- **macOS frontend (`macos/`):** Modify minimally. Only touch `SplitTree.swift` (generic leaf type), `AppDelegate.swift` (socket hook), and Xcode project (new targets).
- **IDE code (`ide/`):** All new code goes here. Socket server, CLI, browser panels, workspaces.

## Plan

See `IDE_PLAN.md` for the full phased implementation plan.

## Upstream Tracking

- `upstream` remote = `ghostty-org/ghostty`
- `origin` remote = your fork
- Rebase on upstream regularly. Conflicts should be rare since changes are additive.

## Build

```bash
# Build GhosttyKit xcframework
zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast

# Build macOS app (debug — shows "debug build" warning banner, slower)
cd macos && xcodebuild -scheme GhosttyIDE -configuration Debug build

# Build macOS app (release — no warning, optimized, for daily use)
cd macos && xcodebuild -scheme GhosttyIDE -configuration Release build
```

Note: The "debug build" warning is driven by the **Zig** build mode (`ghostty_info.mode`), not Xcode's configuration. The `ReleaseFast` flag above already handles it. The Xcode Release configuration adds Swift optimizations and strips debug symbols.

## Key Files (Ghostty's existing architecture)

- `include/ghostty.h` — C API header (1.2K lines), the core-frontend interface
- `src/apprt/action.zig` — 65+ action types dispatched via callbacks
- `src/apprt/embedded.zig` — Embedded runtime (what macOS uses)
- `src/config/Config.zig` — Master config (10.9K lines)
- `macos/Sources/Ghostty/Ghostty.App.swift` — Swift wrapper for ghostty_app_t, callback bridge
- `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` — Metal rendering, input dispatch
- `macos/Sources/Features/Splits/SplitTree.swift` — Immutable binary split tree
- `macos/Sources/Features/Terminal/TerminalController.swift` — Window management
- `macos/Sources/Features/Terminal/BaseTerminalController.swift` — Base controller with split/focus logic
- `macos/Sources/App/macOS/AppDelegate.swift` — App lifecycle, menu, notifications

## Key Files (IDE additions)

- `ide/Sources/Socket/SocketServer.swift` — POSIX Unix socket listener on `/tmp/ghosttyide.sock`
- `ide/Sources/Socket/CommandRouter.swift` — JSON command dispatch
- `ide/Sources/Socket/CommandProtocol.swift` — Command/response types with AnyCodable
- `ide/Sources/Socket/Commands/PaneCommands.swift` — pane.list, pane.split, pane.focus, pane.focus-direction, pane.close
- `ide/Sources/Socket/Commands/AppCommands.swift` — app.version, app.pid, app.quit, help
- `ide/Sources/Socket/Commands/WorkspaceCommands.swift` — project.save/restore/list/delete/close-all + workspace.new/switch/next/previous/list/rename/meta.set/meta.clear + project.switch
- `ide/Sources/Socket/Commands/NotifyCommands.swift` — notify.send, notify.list, notify.clear
- `ide/Sources/Socket/Commands/StatusCommands.swift` — status.set, status.clear, status.list
- `ide/Sources/Workspace/Workspace.swift` — ProjectFile, ProjectWindowState, PaneSummary data model
- `ide/Sources/Workspace/WorkspaceStore.swift` — Disk I/O with timestamped files + symlinks
- `ide/Sources/Workspace/WorkspaceManager.swift` — Bridge live app state to data model (save/restore)
- `ide/Sources/Workspace/IDEWorkspace.swift` — Live workspace model (name, project, color, emoji, metadata, status)
- `ide/Sources/Workspace/WorkspaceController.swift` — Workspace list management, switching, project filter
- `ide/Sources/Workspace/GitBranchProvider.swift` — Background git branch detection
- `DESIGN.md` — Visual & UX design decisions (top+bottom bar layout, alternatives)
- `ide/Sources/Workspace/WorkspaceStatusBridge.swift` — Wires git branch, agent state, notifications to active workspace
- `ide/Sources/Notifications/NotificationManager.swift` — macOS UNUserNotificationCenter bridge + dock badge
- `ide/Sources/Notifications/StatusStore.swift` — In-memory per-pane key-value status
- `ide/Sources/Palette/IDECommandPaletteOptions.swift` — IDE commands injected into Ghostty's command palette
- `ide/Sources/UI/IDETopBarView.swift` — Top bar: workspace metadata, project name, notification badge, drag handle
- `ide/Sources/UI/IDEBottomBarView.swift` — Bottom bar: workspace pills with agent/notification indicators
- `ide/Sources/UI/NotificationPanelView.swift` — In-app notification panel (popover)
- `ide/Sources/UI/PaneNotificationOverlay.swift` — Pane border overlay for unread notifications
- `ide/CLI/` — Standalone SPM package for the `ide` CLI binary
- `ide/CLI/Sources/SocketClient.swift` — POSIX socket client (connect, send JSON, read response)
- `ide/CLI/Sources/Commands/ProjectCommand.swift` — ide project save|restore|list|delete|close-all
- `ide/CLI/Sources/Commands/WorkspaceCommand.swift` — ide workspace new|switch|next|previous|list|rename|meta|project-switch
- `ide/CLI/Sources/Commands/NotifyCommand.swift` — ide notify send|list|clear
- `ide/CLI/Sources/Commands/StatusCommand.swift` — ide status set|clear|list
- `ide/Sources/Keybindings/VimDetector.swift` — Detect vim/neovim in focused surface via title regex
- `ide/Sources/Keybindings/IDEKeybindConfig.swift` — Parse `~/.config/ghosttyide/config`, default bindings
- `ide/Sources/Keybindings/IDEKeybindRegistry.swift` — Match NSEvent → IDEAction
- `ide/Sources/Keybindings/IDEActionDispatcher.swift` — Execute IDE + Ghostty actions from keybindings (vim-aware pane nav, workspace prompts, Ghostty action forwarding)
- `ide/Sources/Keybindings/IDEConfigWatcher.swift` — Config file hot-reload via DispatchSource (handles vim-style atomic writes)
- `ide/Tests/test_socket.py` — Integration tests (socket + CLI + project + workspace + notify + status + keybindings)

## CLI Usage

```bash
# Build CLI
cd ide/CLI && swift build

# Run (from ide/CLI directory)
swift run ide pane list
swift run ide pane focus-direction left
swift run ide app version --json
swift run ide project save myproject
swift run ide project list
swift run ide project restore myproject
swift run ide project close-all
swift run ide workspace new main --project ENI --color "#2ECC71" --emoji snake
swift run ide workspace list
swift run ide workspace switch main
swift run ide workspace next
swift run ide workspace rename main primary
swift run ide workspace meta set main ports "3000, 8080"
swift run ide workspace meta clear main ports
swift run ide workspace project-switch PESAURUS
swift run ide notify send "Title" --body "Body"
swift run ide notify list
swift run ide status set agent idle --pane <uuid>
swift run ide status list
swift run ide raw <command> -a key=value

# Or run the built binary directly
ide/CLI/.build/debug/ide pane list
```

## Testing

```bash
# Integration tests (requires GhosttyIDE running + CLI built)
python3 ide/Tests/test_socket.py

# Tests cover (90 total):
# - Socket protocol (13 tests): help, app.version, app.pid, pane.list, pane.focus-direction, error cases
# - Project (10 tests): save, list, restore, delete, name validation
# - Workspace (20 tests): new, new with options, empty/missing name, list with field validation,
#     switch, next/previous with round-trip, rename, meta.set/clear/visible-in-list, project.switch
# - Notify (7 tests): send, title only, send with pane, missing/empty title, list, clear
# - Status (9 tests): set, set another, overwrite, missing key/value, list, list filtered, clear specific/all
# - CLI (31 tests): help, app, pane, pane focus-direction, project, workspace, notify, status, raw, --json, error codes
```
