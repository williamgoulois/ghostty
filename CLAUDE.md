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

# Build macOS app
cd macos && xcodebuild -scheme Ghostty -configuration Debug build
```

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
