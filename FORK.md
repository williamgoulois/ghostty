# Ghostty IDE Fork

This is a fork of [Ghostty](https://github.com/ghostty-org/ghostty) being transformed into a CLI-first IDE.

## Fork Purpose

Build a scriptable, CLI-first IDE on top of Ghostty's terminal emulator core. The IDE adds:

- **Unix socket server** for full programmatic control
- **CLI binary** (`ide`) to control every aspect of the IDE from the terminal
- **WebKit browser panels** alongside terminal splits
- **Named workspaces** with layout persistence

## Architecture

- **Zig core (`src/`):** Never modify. Handles VT parsing, terminal state, Metal rendering.
- **macOS frontend (`macos/`):** Modify minimally. Only touch files under `#if GHOSTTY_IDE` guards.
- **IDE code (`ide/`):** All new code goes here. Socket server, CLI, browser panels, workspaces.

## Xcode Schemes

| Scheme | Bundle ID | What |
|---|---|---|
| **GhosttyIDE** | `com.ghosttyide.app` | IDE fork — compiles `macos/Sources/` + `ide/Sources/` with `GHOSTTY_IDE` flag |
| **Ghostty** | `com.mitchellh.ghostty` | Stock upstream — kept buildable for rebase safety |

Always use `GhosttyIDE` for this project.

## Remotes

| Remote     | Repository                          | Purpose             |
|------------|-------------------------------------|----------------------|
| `upstream` | `ghostty-org/ghostty`               | Upstream Ghostty     |
| `origin`   | `williamgoulois/ghostty`            | Fork with IDE code   |

## Rebase Strategy

This fork is designed for easy rebasing on upstream Ghostty:

1. **All new code is additive** — lives in `ide/`, a directory that doesn't exist upstream.
2. **Minimal edits to existing files** — guarded by `#if GHOSTTY_IDE`, plus Xcode project (new targets).
3. **Rebase workflow:**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```
4. **Expected conflicts** are limited to:
   - `macos/Ghostty.xcodeproj` (if targets were added)
   - `macos/Sources/App/macOS/AppDelegate.swift` (if socket hook was added)
   - `macos/Sources/Features/Splits/SplitTree.swift` (if leaf type was modified — Phase 10)

### Rebase Checklist

1. `git fetch upstream && git rebase upstream/main`
2. Resolve conflicts (see expected list above)
3. Build: see `CLAUDE.md`
4. Run tests: `python3 ide/Tests/test_socket.py`
5. Verify socket server: `ide pane list`

## Directory Structure

```
ghostty/
├── ide/                    # ALL new IDE code
│   ├── Sources/
│   │   ├── Socket/         # Unix socket server + command protocol
│   │   ├── Workspace/      # Workspace model + persistence
│   │   ├── Keybindings/    # IDE keybind system + vim detection
│   │   ├── UI/             # Top bar, bottom bar, notification panel
│   │   ├── Notifications/  # macOS notification center + status store
│   │   ├── Palette/        # IDE command palette entries
│   │   └── Branding/       # GhosttyIDE brand constants
│   ├── CLI/                # Standalone SPM package for `ide` CLI binary
│   └── Tests/
├── macos/                  # Ghostty's existing frontend (touch minimally)
└── src/                    # Ghostty's Zig core (never touch)
```
