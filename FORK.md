# Ghostty IDE Fork

This is a fork of [Ghostty](https://github.com/ghostty-org/ghostty) being transformed into a CLI-first IDE.

## Fork Purpose

Build a scriptable, CLI-first IDE on top of Ghostty's terminal emulator core. The IDE adds:

- **Unix socket server** for full programmatic control
- **CLI binary** (`ide`) to control every aspect of the IDE from the terminal
- **WebKit browser panels** alongside terminal splits
- **Named workspaces** with layout persistence

All new code lives in `ide/`. Ghostty's Zig core (`src/`) is never modified. The macOS frontend (`macos/`) is touched minimally.

## Remotes

| Remote     | Repository                          | Purpose             |
|------------|-------------------------------------|----------------------|
| `upstream` | `ghostty-org/ghostty`               | Upstream Ghostty     |
| `origin`   | `williamgoulois/ghostty`            | Fork with IDE code   |

## Rebase Strategy

This fork is designed for easy rebasing on upstream Ghostty:

1. **All new code is additive** — lives in `ide/`, a directory that doesn't exist upstream.
2. **Minimal edits to existing files** — only `SplitTree.swift` (generic leaf type), `AppDelegate.swift` (socket hook), and the Xcode project (new targets).
3. **Rebase workflow:**
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```
4. **Expected conflicts** are limited to:
   - `macos/Sources/Features/Splits/SplitTree.swift` (if leaf type was modified)
   - `macos/GhosttyKit.xcodeproj` (if targets were added)
   - `macos/Sources/App/macOS/AppDelegate.swift` (if socket hook was added)

## Build

```bash
# 1. Build GhosttyKit xcframework
zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast

# 2. Build macOS app
cd macos && xcodebuild -scheme Ghostty -configuration Debug build
```

## Directory Structure

```
ghostty/
├── ide/                    # ALL new IDE code
│   ├── Sources/
│   │   ├── App/            # IDE app entry, AppDelegate extensions
│   │   ├── Socket/         # Unix socket server + command protocol
│   │   ├── CLI/            # CLI binary (separate target)
│   │   ├── Browser/        # WebKit browser panel
│   │   ├── Workspace/      # Workspace model + persistence
│   │   └── Extensions/     # Minimal hooks into Ghostty frontend
│   └── Tests/
├── macos/                  # Ghostty's existing frontend (touch minimally)
└── src/                    # Ghostty's Zig core (never touch)
```
