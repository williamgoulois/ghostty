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

## Phase 5: AI Agent Integration (Claude Code + OpenCode)

**Goal:** First-class support for AI coding agents running inside GhosttyIDE panes. Notifications, status tracking, and environment injection — like cmux but native.

### 5a: Environment injection

Export to every shell spawned by GhosttyIDE:

- `GHOSTTYIDE_SOCKET` — socket path
- `GHOSTTYIDE_PANE_ID` — current surface UUID
- `GHOSTTYIDE_WINDOW_ID` — window identifier

Agents use these to send commands back to the IDE without manual socket discovery.

### 5b: Notification system (socket + macOS)

Socket commands:

- `notify.send` — `{"title": "...", "body": "...", "pane_id": "..."}` → macOS `UNUserNotificationCenter`
- `notify.list` — list recent notifications
- `notify.clear` — clear all

CLI: `ide notify send "Title" --body "Body" [--pane <id>]`

macOS system notifications only (no custom in-app UI yet — designed in Phase 7). Sound support (system sounds).

### 5c: Status tracking

Socket commands:

- `status.set` — `{"key": "claude", "value": "Waiting for input", "pane_id": "..."}`
- `status.clear` — remove a status key
- `status.list` — all active statuses

CLI: `ide status set <key> <value> [--pane <id>]`

In-memory per-pane metadata (not persisted).

### 5d: Agent integration patterns

- Document how Claude Code hooks should call `ide notify` / `ide status set`
- Document OpenCode plugin pattern
- Provide example configs:
  ```json
  {
    "hooks": {
      "Notification": [
        {
          "matcher": "idle_prompt",
          "hooks": [
            {
              "type": "command",
              "command": "ide notify 'Claude Code' --body 'Waiting for input'"
            }
          ]
        }
      ]
    }
  }
  ```

```
ide/Sources/Notifications/
├── NotificationManager.swift    # UNUserNotificationCenter bridge
└── StatusStore.swift            # In-memory per-pane status

ide/Sources/Socket/Commands/
├── NotifyCommands.swift         # notify.send, notify.list, notify.clear
└── StatusCommands.swift         # status.set, status.clear, status.list

ide/CLI/Sources/Commands/
├── NotifyCommand.swift          # ide notify "Title" --body "Body"
└── StatusCommand.swift          # ide status set|clear|list
```

Tasks:

- [x] Inject `GHOSTTYIDE_*` env vars into shell surfaces
- [x] `NotificationManager`: macOS notification center bridge
- [x] `StatusStore`: in-memory per-pane key-value status
- [x] Socket commands: `notify.send`, `notify.list`, `notify.clear`, `status.set`, `status.clear`, `status.list`
- [x] CLI commands: `ide notify`, `ide status`
- [x] Document Claude Code hooks + OpenCode plugin patterns (see `ide/AGENTS.md`)

---

## Phase 6: IDE Commands in Command Palette

**Note:** Ghostty already has a production-ready command palette (Cmd+Shift+P) with fuzzy search, keyboard navigation, shortcuts display, and Siri/Shortcuts integration. Phase 6 extends it with IDE-specific commands rather than building from scratch.

**Existing infrastructure (upstream Ghostty):**

- `CommandPaletteView` — generic SwiftUI palette with filtering, keyboard nav, hover states
- `TerminalCommandPaletteView` — builds options from config entries + jump commands + update commands
- Toggle via `toggle_command_palette` action, default keybind Cmd+Shift+P

**IDE extension approach:** Inject IDE commands into `TerminalCommandPaletteView.commandOptions` under `#if GHOSTTY_IDE`. Dynamic project entries (restore/delete) are built from saved projects on disk.

```
ide/Sources/Palette/
└── IDECommandPaletteOptions.swift  # Builds [CommandOption] from IDE state
```

Tasks:

- [x] Inject IDE commands into existing palette under `#if GHOSTTY_IDE`
- [x] Dynamic project entries: Save, Restore — <name>, Delete — <name> per saved project
- [x] NSAlert-based name prompt for "Project: Save Current"
- [x] Static commands: Close All Windows, Clear Notifications, Mark All Read, Clear Status
- [x] Fix `UNUserNotificationCenter` delegate conflict (moved foreground handling to AppDelegate)

---

## Phase 7: Visual & UX Design

**Goal:** Define GhosttyIDE's visual identity. Chosen layout: **Top Bar + Bottom Bar**.

**Design decisions (see `DESIGN.md`):**
- Top bar: left = workspace metadata (name, branch, agent, ports, PR), right = project name + notification badge + drag handle
- Bottom bar: left = workspace pills for current project (accent active, muted others)
- Project = UI-only grouping (tag + filter, instant switch, no lifecycle management)
- Lazy surface creation (0 memory until first visit, alive forever after)
- Three-tier memory: not-visited (0), background (alive), unloaded (deferred Phase 10)
- Extensible workspace metadata via socket/CLI (ports, PR links, custom key-values)
- Hidden titlebar (existing Ghostty behavior), navigation chrome provides drag handle
- Alternative approaches documented: left sidebar, bottom-only status bar

**Architecture:**
```
GhosttyIDE Window (single NSWindow)
├── IDETopBarView      (workspace metadata + project name + notification badge)
├── Content Area       (active workspace's SplitTree)
└── IDEBottomBarView   (workspace pills for current project)
```

Tasks:

- [x] Write `DESIGN.md` with chosen approach + alternatives + mockups
- [x] Build `IDEWorkspace` model (name, project, color, emoji, metadata, status)
- [x] Build `WorkspaceController` (workspace list, switching, project filter)
- [x] Build `GitBranchProvider` (background git branch detection)
- [x] Add socket commands: workspace.new, switch, next, previous, list, rename, meta.set, meta.clear, project.switch
- [x] Add CLI commands: ide workspace new|switch|next|previous|list|rename|meta|project-switch
- [x] Implement `IDETopBarView` (SwiftUI) — top bar with workspace metadata, project name, notification badge, drag handle
- [x] Implement `IDEBottomBarView` (SwiftUI) — bottom bar with workspace pills, agent/notification indicators
- [x] Embed bars in `TerminalView.swift` under `#if GHOSTTY_IDE`
- [x] Implement `NotificationPanelView` (popover) + `PaneNotificationOverlay` (border indicator) + dock badge
- [x] Build `WorkspaceStatusBridge` — wires git branch, agent state, notifications to active workspace
- [x] Wire git branch detection to active workspace via `GitBranchProvider`
- [x] Wire agent state from `StatusStore` to workspace display
- [x] Integration tests for workspace commands (17 socket + 10 CLI tests)

---

## Phase 8: Keybindings & Config

**Goal:** IDE-specific keybindings and configuration, layered on top of Ghostty's config.

Tasks:

- [x] Single overlay config file: `~/.config/ghosttyide/config` (handles all keybindings, both IDE and Ghostty actions)
- [x] IDE keybind system: `IDEKeybindConfig` parser, `IDEKeybindRegistry` matcher, `IDEActionDispatcher` executor
- [x] Vim-aware pane navigation: `VimDetector` uses `ghostty_surface_foreground_pid()` (tcgetpgrp, O(1)) + `proc_name()` — same approach as kitty
- [x] C API: `ghostty_surface_foreground_pid()` exposed in `ghostty.h` / `embedded.zig` (~5 lines)
- [x] Intercept in `performKeyEquivalent()` before Ghostty's Zig core (under `#if GHOSTTY_IDE`)
- [x] `pane.focus-direction` socket/CLI command for neovim mux-navigator integration
- [x] Neovim `mux-navigator.lua` updated with GhosttyIDE support (detects `GHOSTTYIDE_SOCKET` env var)
- [x] Karabiner config updated with GhosttyIDE bundle IDs
- [x] Config hot-reload via `IDEConfigWatcher` (DispatchSource file monitoring)
- [x] Default keybinding set: workspace (Cmd+N/O/I/1-9), pane (Cmd+T/W/F), resize (Cmd+Shift+HJKL), vim nav (Ctrl+HJKY)

---

## Phase 9a: Fix Workspace Tree Swapping

**Goal:** Workspaces currently all display the same terminal content. Fix so each workspace has its own split tree.

- [x] Add `terminalController` reference to `WorkspaceController`
- [x] Rewrite `switchTo()` to save/restore `surfaceTree` + `focusedSurface` per workspace
- [x] Wire controller reference in `TerminalController` under `#if GHOSTTY_IDE`
- [x] Verify: create 3 workspaces, type in each, switch — each shows its own content

---

## Phase 9b: Session Persistence

**Goal:** Auto-save workspace metadata on quit, silently restore on launch (tmux-resurrect style).

- [x] `IDESessionFile` data model (workspace names, projects, colors, emoji, metadata)
- [x] `IDESessionStore` — single `~/.cache/ghosttyide/session.json` with atomic writes
- [x] `WorkspaceController.captureSession()` / `restoreSessionMetadata()` / `activateRestoredSession()` methods
- [x] Hook into `applicationWillTerminate` (save) and `applicationDidFinishLaunching` (restore, two-phase)
- [x] Periodic auto-save via `NSBackgroundActivityScheduler` (10 min interval, energy-efficient)
- [x] Socket commands: `session.save`, `session.info`
- [x] CLI commands: `ide session save`, `ide session info`

---

## Phase 9c: Notification Wiring

**Goal:** Connect the notification system end-to-end with per-pane unread tracking.

- [x] `NotificationManager` → `ObservableObject` with `@Published unreadPaneIds: Set<String>`
- [x] `markPaneRead(paneId:)` for pane-level mark-as-read on focus
- [x] `WorkspaceStatusBridge` subscribes to `$unreadPaneIds` via Combine, recomputes workspace unread counts
- [x] `WorkspaceController.workspace(containingPaneId:)` + `countUnreadPanes()` helpers
- [x] `TerminalView` `#if GHOSTTY_IDE`: mark pane read on focus change, inject `NotificationManager` as environment object
- [x] `TerminalSplitLeaf` `#if GHOSTTY_IDE`: `@EnvironmentObject` + `PaneNotificationOverlay` on each leaf
- [x] Top bar bell badge → clickable button with popover hosting `NotificationPanelView`
- [x] Bell badge shows global count (`unreadPaneIds.count`) across all projects/workspaces
- [x] Bottom bar workspace pills show per-workspace red dot (derived from per-pane counts)
- [x] Wire `.ideToggleNotificationPanel` observer via `.onReceive` (Cmd+Shift+M keybinding)
- [x] Mark all read when notification panel opens
- [x] "Notifications: Show Panel" command palette entry
- [x] Polish `NotificationPanelView` empty state with bell.slash icon

---

## Phase 9d: Branding + Project Picker + Project Rename

**Goal:** Rebrand user-visible strings to "GhosttyIDE", add `Cmd+P` project picker with "New Project" creation, and add project rename.

Branding:
- [x] `AppBrand.swift` with `#if GHOSTTY_IDE` conditional name/tagline/URL constants
- [x] Programmatic menu rename in `applicationDidFinishLaunching` (recursive NSMenu walk, no XIB edit)
- [x] Replace hardcoded "Ghostty" in quit dialog, About view, update palette entry

Project picker (Cmd+P):
- [x] `IDEPaletteMode` / `IDEPaletteState` — shared mode flag so command palette shows project options
- [x] `IDEProjectPickerOptions` — builds project list (live projects, saved-but-not-loaded, "New Project...")
- [x] Reuses existing `CommandPaletteView` — no separate overlay (fixes click handling, multi-window scoping)
- [x] Custom placeholder ("Current: X — switch to…"), pre-selects active project alphabetically
- [x] `projectPicker` keybinding action dispatches `toggle_command_palette` per-surface (not global notification)
- [x] `CommandPaletteView` extended with `placeholder` and `preselectIndex` parameters

Project rename:
- [x] `WorkspaceController.renameProject()` — retags all workspaces, updates activeProject + lastActivePerProject
- [x] `project.rename` socket command + `ide project rename` CLI command
- [x] "Project: Rename", "Workspace: Rename", "Project: New" command palette entries
- [x] `projectPicker` + `projectRename` IDE keybinding actions
- [x] `workspace.remove` socket command (used for test cleanup)

Testing:
- [x] Integration tests: project.rename (4 socket + 2 CLI), workspace.remove, help list updated
- [x] Test cleanup section removes test workspaces via `workspace.remove` after all tests

---

## Phase 9e: Visual Polish

**Goal:** Refine bars, pills, and chrome for daily-driver quality.

- [ ] Top/bottom bar background: `Color(nsColor:).opacity(0.85)` → `.ultraThinMaterial`
- [ ] Add thin `Divider()` between bars and content
- [ ] Improve inactive pill contrast (too low against dark backgrounds)
- [ ] Add workspace pill hover state
- [ ] Deduplicate `agentIcon()`/`agentColor()` into `AgentState` extension

---

## Phase 9f: Logging + Error Handling

**Goal:** Add structured logging across all IDE components and harden the socket server.

- [ ] `IDELogger.swift` with per-component `Logger` instances (OSLog)
- [ ] Add logging to: GitBranchProvider, IDEConfigWatcher, WorkspaceStore, SocketServer silent failures
- [ ] Socket resilience: max message size (1MB), write() return check

---

## Phase 9g: Workflow Tests

**Goal:** Replace granular unit tests with real-workflow scenario tests.

- [ ] Workspace lifecycle workflow (create, switch, rename, meta, delete)
- [ ] Session persistence workflow (save, read JSON, verify structure)
- [ ] Notification workflow (send, list, clear, verify fields)
- [ ] Agent status workflow (set, overwrite, clear)
- [ ] CLI workflow tests (full lifecycle via CLI, --json flag, error codes)

---

## Phase 9h: IDE Framework Module (Optional)

**Goal:** Extract `ide/Sources/` into a separate Swift framework target for proper module boundaries.

**Why:** Currently all `ide/Sources/` files are compiled in the same target as `macos/Sources/` via Xcode file system synchronized groups. This works but means:
- No compile-time enforcement of module boundaries
- IDE types leak into the main app namespace
- Incremental builds recompile everything when any IDE file changes
- SourceKit relies on `xcode-build-server` + `buildServer.json` (current workaround, see below)

**Current workaround (Option A):** `buildServer.json` generated by `xcode-build-server` points sourcekit-lsp at the GhosttyIDE scheme. This gives working diagnostics without code changes. Files are gitignored since they contain machine-specific paths.

**Framework approach (Option B):**

- [ ] Create `GhosttyIDEKit.framework` target in the Xcode project
- [ ] Move `ide/Sources/` files into the framework target
- [ ] Mark shared types as `public` (`IDEWorkspace`, `WorkspaceController`, `NotificationManager`, etc.)
- [ ] Add `import GhosttyIDEKit` in app-level code (`AppDelegate`, `TerminalView`, etc.)
- [ ] GhosttyIDE app target links `GhosttyIDEKit.framework` + `GhosttyKit.xcframework`
- [ ] Main Ghostty target does NOT link the framework (clean separation)
- [ ] Update `#if GHOSTTY_IDE` guards to use `#if canImport(GhosttyIDEKit)` where appropriate

**Trade-offs:**
- Pro: Real module boundaries, faster incremental builds, native SourceKit support
- Pro: Enforces clean API surface between IDE and app layers
- Con: Every shared type needs `public` visibility — more boilerplate
- Con: Larger Xcode project diff vs upstream (harder rebasing)
- Con: Framework linking adds complexity to build phases

**Recommendation:** Defer until IDE code stabilizes. Option A is sufficient during active development.

---

## Phase 10: WebKit Browser Panel

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

## Rebase Checklist (run after each upstream sync)

1. `git fetch upstream && git rebase upstream/main`
2. Conflicts should only appear in:
   - `SplitTree.swift` (if you modified the leaf type — Phase 10)
   - Xcode project file (if you added targets)
   - `AppDelegate.swift` (if you hooked socket server startup)
3. Run build: `zig build ... && xcodebuild`
4. Run tests
5. Verify socket server still works: `ide pane list`

---

## File Touch Summary

**Files you will modify in Ghostty's existing code (keep minimal):**

| File                                                          | Change                                | Why                                |
| ------------------------------------------------------------- | ------------------------------------- | ---------------------------------- |
| `macos/GhosttyKit.xcodeproj`                                  | Add IDE targets                       | Build system                       |
| `macos/Sources/Features/Splits/SplitTree.swift`               | Generic leaf type or protocol         | Browser panels in split tree       |
| `macos/Sources/App/macOS/AppDelegate.swift`                   | Hook socket/keybind/watcher init      | Socket + keybind lifecycle         |
| `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` | IDE keybind interception + env vars   | `performKeyEquivalent()` hook      |
| `macos/Sources/Features/Terminal/TerminalView.swift`           | Top/bottom bar + notification env     | IDE chrome + pane-level mark-read  |
| `macos/Sources/Features/Splits/TerminalSplitTreeView.swift`   | Pane notification overlay             | Per-pane unread border indicator   |
| `macos/Sources/Features/Command Palette/TerminalCommandPalette.swift` | IDE command palette entries    | IDE commands in palette            |
| `include/ghostty.h`                                           | `ghostty_surface_foreground_pid()`    | Vim detection via tcgetpgrp        |
| `src/apprt/embedded.zig`                                      | Export foreground PID function         | C API for vim detection            |

**Everything else is new code in `ide/`.** This is what makes rebasing safe.
