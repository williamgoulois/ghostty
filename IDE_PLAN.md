# CLI-First IDE on Ghostty — Implementation Plan

## Guiding Principle: Minimal Fork Diff

Every change must be **additive** or **isolated** to make rebasing on upstream Ghostty painless. Never modify Ghostty's core files when you can extend them. Use separate directories for all new code.

---

## Phase 0: Fork Setup & Build Infrastructure

**Goal:** Clean fork that builds, runs, and can track upstream.

- [ ] Fork `ghostty-org/ghostty` to your GitHub org
- [ ] Set up remotes: `origin` = your fork, `upstream` = ghostty-org/ghostty
- [ ] Verify macOS build: `zig build -Demit-xcframework=true -Dxcframework-target=universal -Doptimize=ReleaseFast` then `xcodebuild`
- [ ] Run the app, confirm it works as stock Ghostty
- [ ] Create a `FORK.md` documenting your fork's purpose and rebase strategy
- [ ] Set up CI: build + test on every push, weekly upstream sync check

**Rebase strategy:**
- Keep a `upstream-tracking` branch that mirrors `ghostty-org/ghostty:main`
- Your work lives on `main` (or a `ide` branch)
- Rebase periodically: `git fetch upstream && git rebase upstream/main`
- Because your changes are additive (new directories, minimal edits to existing files), conflicts should be rare

---

## Phase 1: Project Skeleton — New Code Lives in `ide/`

**Goal:** Establish the directory structure for all IDE-specific code, separate from Ghostty's existing `macos/` frontend.

```
ghostty/
├── ide/                          # ALL new code goes here
│   ├── Sources/
│   │   ├── App/                  # IDE app entry point, AppDelegate extensions
│   │   ├── Socket/               # Unix socket server + command protocol
│   │   ├── CLI/                  # CLI binary (separate target)
│   │   ├── Browser/              # WebKit browser panel
│   │   ├── Workspace/            # Workspace model + persistence
│   │   └── Extensions/           # Minimal hooks into Ghostty's frontend
│   ├── Tests/
│   └── Package.swift             # Or Xcode project/targets
├── macos/                        # Ghostty's existing frontend (touch minimally)
└── src/                          # Ghostty's Zig core (never touch)
```

Tasks:
- [ ] Create `ide/` directory structure
- [ ] Decide build approach: extend Ghostty's Xcode project with new targets vs. standalone project linking `GhosttyKit.xcframework`
  - **Recommended:** Add targets to Ghostty's existing Xcode project — you get the existing Metal rendering, surface views, split tree for free
- [ ] Create an IDE app target that reuses Ghostty's `macos/Sources/` but with your own `AppDelegate` subclass/wrapper
- [ ] Verify IDE target builds and runs as a renamed Ghostty (different bundle ID, app name)

---

## Phase 2: Socket Server — Make It Scriptable

**Goal:** A Unix domain socket that accepts commands and returns results. This is the foundation for the CLI and all programmatic control.

```
ide/Sources/Socket/
├── SocketServer.swift            # Listen on /tmp/ide-{pid}.sock
├── CommandRouter.swift           # Parse incoming commands, dispatch
├── CommandProtocol.swift         # JSON command/response schema
└── Commands/
    ├── PaneCommands.swift        # split, close, focus, resize, list
    ├── WorkspaceCommands.swift   # create, switch, list, save, restore
    ├── BrowserCommands.swift     # open-url, back, forward, reload
    ├── TerminalCommands.swift    # send-keys, send-text, get-title, get-pwd
    └── AppCommands.swift         # quit, config-reload, version
```

Tasks:
- [ ] Implement `SocketServer` — async Unix domain socket listener (use NIO or raw POSIX)
- [ ] Define JSON command protocol:
  ```json
  {"command": "pane.split", "args": {"direction": "right"}}
  → {"ok": true, "data": {"pane_id": "abc-123"}}
  ```
- [ ] Implement `CommandRouter` — deserialize, dispatch, serialize response
- [ ] Wire socket server startup into AppDelegate (start on launch, write socket path to `/tmp/ide.sock`)
- [ ] Implement initial commands: `pane.list`, `pane.split`, `pane.close`, `pane.focus`
- [ ] Bridge to Ghostty actions: map socket commands → `ghostty_surface_*` calls + split tree mutations

---

## Phase 3: CLI Binary

**Goal:** A standalone CLI that talks to the socket. Every IDE action is a CLI command.

Implemented as a standalone SPM package (not an Xcode target) since the CLI only needs socket communication, no Ghostty/AppKit dependencies.

```
ide/CLI/                              # Standalone SPM package
├── Package.swift                     # swift-argument-parser dependency
└── Sources/
    ├── GhosttyIDE.swift              # @main entry point, global options
    ├── SocketClient.swift            # POSIX Unix socket client
    ├── Output.swift                  # JSON + plain-text formatters
    └── Commands/
        ├── PaneCommand.swift         # pane list|split|focus|close
        ├── AppCommand.swift          # app version|pid|quit
        ├── HelpCommand.swift         # commands (list server commands)
        └── RawCommand.swift          # raw <cmd> -a key=value
```

Build & run:
```bash
cd ide/CLI && swift build
swift run ide pane list
swift run ide app version --json
swift run ide raw app.pid --json
```

Tasks:
- [x] Create CLI target using Swift ArgumentParser
- [x] Implement `SocketClient` — connect, send command, read response, print
- [x] Map CLI subcommands to socket commands:
  ```
  ide pane split --direction right
  ide pane list
  ide pane focus <uuid>
  ide pane close <uuid>
  ide app version
  ide app pid
  ide app quit
  ide commands                    # list all server commands
  ide raw <command> -a key=value  # send arbitrary commands
  ```
- [x] Socket path discovery: check `/tmp/ghosttyide.sock`, env var `GHOSTTYIDE_SOCKET`, or `--socket` flag
- [x] JSON and plain-text output modes (`--json` flag)

---

## Phase 4: Project Save/Restore

**Goal:** Named projects with layout persistence. A project = all windows saved as a group.

**Data model hierarchy:**
```
GhosttyIDE.app (1 process)
├── Project "myproject" (= all windows, saved/restored as a group)
│   ├── Window 1 (future: named workspace)
│   │   ├── Pane A (zsh, ~/project)
│   │   └── Pane B (vim, ~/project/src)
│   └── Window 2
│       └── Pane C (zsh, ~/project/ide)
```

**Storage:** tmux resurrect pattern at `~/.cache/ghosttyide/projects/`
```
~/.cache/ghosttyide/projects/
├── myproject -> myproject_20260324T143810.json   # symlink to latest
├── myproject_20260324T143810.json                # timestamped save
├── myproject_20260324T120000.json                # previous save (kept)
```

**Implementation:**
```
ide/Sources/Workspace/
├── Workspace.swift          # ProjectFile, ProjectWindowState, PaneSummary
├── WorkspaceStore.swift     # Disk I/O (timestamped files + symlinks)
└── WorkspaceManager.swift   # Bridge live app state ↔ data model

ide/Sources/Socket/Commands/
└── WorkspaceCommands.swift  # project.* socket commands

ide/CLI/Sources/Commands/
└── ProjectCommand.swift     # ide project save|restore|list|delete|close-all
```

Key insight: Ghostty's `SplitTree<SurfaceView>` is fully Codable. `SurfaceView.init(from:)` creates
real surfaces with decoded pwd. We serialize to JSON files instead of NSCoder.

Tasks:
- [x] Define `ProjectFile` model: version, name, windows array with split tree + pane metadata
- [x] `WorkspaceStore`: disk I/O with timestamped files + symlinks
- [x] `WorkspaceManager`: capture window state, restore via `TerminalController.newWindow(_:tree:)`
- [x] Socket commands: `project.save`, `project.restore`, `project.list`, `project.delete`, `project.close-all`
- [x] CLI commands: `ide project save|restore|list|delete|close-all`
- [ ] Auto-save on quit, auto-restore on launch (deferred)

**Future evolution** (data model supports from day 1):
- Project switching: `project.switch` hides/shows window groups without closing
- Per-window naming: optional `name` field in `ProjectWindowState` for workspace identity

---

## Phase 5: WebKit Browser Panel

**Goal:** Embed WKWebView as a split pane alongside terminals.

```
ide/Sources/Browser/
├── BrowserPanelView.swift        # NSView hosting WKWebView
├── BrowserPanel.swift            # Model: url, title, loading state, history
├── BrowserSplitNode.swift        # Adapter to fit in Ghostty's split tree
└── BrowserBar.swift              # Minimal URL bar + back/forward/reload
```

Tasks:
- [ ] Extend Ghostty's `SplitTree` to support heterogeneous leaf nodes (terminal OR browser)
  - This is the one area where you'll likely need to modify `macos/Sources/Features/Splits/SplitTree.swift`
  - Keep the change minimal: make the leaf type generic or use a protocol
- [ ] Implement `BrowserPanelView` wrapping `WKWebView`
- [ ] Handle focus transitions: keyboard focus between terminal and browser panes
- [ ] Wire into socket commands: `browser.open`, `browser.back`, `browser.forward`, `browser.reload`, `browser.url`
- [ ] DevTools toggle (WKWebView inspector)

---

## Phase 6: Extended Keybindings & Config

**Goal:** IDE-specific keybindings and configuration, layered on top of Ghostty's config.

Tasks:
- [ ] Add IDE-specific config file: `~/.config/ide/config` (loaded after Ghostty's config)
- [ ] IDE-specific keybindings for: workspace switching, browser panel, socket commands
- [ ] Extend Ghostty's action system with IDE actions (or use a parallel keybind layer that intercepts before Ghostty)
- [ ] Config hot-reload for IDE settings

---

## Phase 7: Polish & Hardening

- [ ] Session persistence: save/restore terminal working directories and shell state
- [ ] Error handling: socket disconnects, crashed panels, surface failures
- [ ] Logging: unified debug log for IDE components
- [ ] Documentation: CLI help, config reference, architecture guide
- [ ] Strip unused Ghostty features from your build (QuickTerminal, Sparkle, AppIntents — optional, reduces surface area)

---

## Rebase Checklist (run after each upstream sync)

1. `git fetch upstream && git rebase upstream/main`
2. Conflicts should only appear in:
   - `SplitTree.swift` (if you modified the leaf type — Phase 5)
   - Xcode project file (if you added targets)
   - `AppDelegate.swift` (if you hooked socket server startup)
3. Run build: `zig build ... && xcodebuild`
4. Run tests
5. Verify socket server still works: `ide pane list`

---

## File Touch Summary

**Files you will modify in Ghostty's existing code (keep minimal):**

| File | Change | Why |
|------|--------|-----|
| `macos/GhosttyKit.xcodeproj` | Add IDE targets | Build system |
| `macos/Sources/Features/Splits/SplitTree.swift` | Generic leaf type or protocol | Browser panels in split tree |
| `macos/Sources/App/macOS/AppDelegate.swift` | Hook socket server init | Socket lifecycle |

**Everything else is new code in `ide/`.** This is what makes rebasing safe.
