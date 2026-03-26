# CLI-First IDE on Ghostty — Implementation Plan

See `FORK.md` for fork purpose, architecture, remotes, rebase strategy, and directory structure.
See `CLAUDE.md` for build commands, key files, CLI usage, and testing.

---

## Phase 0: Fork Setup & Build Infrastructure ✅

**Goal:** Clean fork that builds, runs, and can track upstream.

- [x] Fork `ghostty-org/ghostty`, set up remotes
- [x] Verify macOS build, create `FORK.md`

---

## Phase 1: Project Skeleton ✅

**Goal:** Establish `ide/` directory structure. GhosttyIDE Xcode target reuses `macos/Sources/` with `#if GHOSTTY_IDE` and compiles `ide/Sources/` alongside.

- [x] Create `ide/` directory structure
- [x] Add GhosttyIDE target to Xcode project (reuses `macos/Sources/`, different bundle ID)
- [x] Verify IDE target builds and runs

---

## Phase 2: Socket Server ✅

**Goal:** Unix domain socket accepting JSON commands. POSIX listener on `/tmp/ghosttyide.sock`, `CommandRouter` dispatches to command handlers, wired into AppDelegate on launch.

- [x] Implement `SocketServer` — POSIX Unix domain socket listener
- [x] Define JSON command protocol (`{"command": "...", "args": {...}}` → `{"ok": true, "data": {...}}`)
- [x] Implement `CommandRouter` — deserialize, dispatch, serialize response
- [x] Wire socket server startup into AppDelegate
- [x] Implement initial commands: `pane.list`, `pane.split`, `pane.close`, `pane.focus`

---

## Phase 3: CLI Binary ✅

**Goal:** Standalone SPM package (`ide/CLI/`) using Swift ArgumentParser. Talks to socket, supports `--json` output.

- [x] Create CLI target using Swift ArgumentParser
- [x] Implement `SocketClient` — connect, send command, read response, print
- [x] Map CLI subcommands to socket commands (pane, app, raw)
- [x] Socket path discovery: `/tmp/ghosttyide.sock`, `GHOSTTYIDE_SOCKET`, `--socket` flag
- [x] JSON and plain-text output modes (`--json` flag)

---

## Phase 4: Project Save/Restore ✅

**Goal:** Named projects with layout persistence. Storage: tmux-resurrect pattern at `~/.cache/ghosttyide/projects/` (timestamped JSON files + symlinks). Key insight: Ghostty's `SplitTree<SurfaceView>` is fully Codable.

- [x] Define `ProjectFile` model: version, name, windows array with split tree + pane metadata
- [x] `WorkspaceStore`: disk I/O with timestamped files + symlinks
- [x] `WorkspaceManager`: capture window state, restore via `TerminalController.newWindow(_:tree:)`
- [x] Socket commands: `project.save`, `project.restore`, `project.list`, `project.delete`, `project.close-all`
- [x] CLI commands: `ide project save|restore|list|delete|close-all`
- [ ] Auto-save on quit, auto-restore on launch (deferred)

---

## Phase 5: AI Agent Integration ✅

**Goal:** First-class agent support — env injection, macOS notifications, in-memory per-pane status tracking. See `ide/AGENTS.md` for integration guide.

- [x] Inject `GHOSTTYIDE_*` env vars into shell surfaces
- [x] `NotificationManager`: macOS notification center bridge
- [x] `StatusStore`: in-memory per-pane key-value status
- [x] Socket commands: `notify.send`, `notify.list`, `notify.clear`, `status.set`, `status.clear`, `status.list`
- [x] CLI commands: `ide notify`, `ide status`
- [x] Document Claude Code hooks + OpenCode plugin patterns (see `ide/AGENTS.md`)

---

## Phase 6: IDE Commands in Command Palette ✅

**Goal:** Extend Ghostty's existing command palette (Cmd+Shift+P) with IDE commands under `#if GHOSTTY_IDE`. Dynamic project entries built from saved projects on disk.

- [x] Inject IDE commands into existing palette under `#if GHOSTTY_IDE`
- [x] Dynamic project entries: Save, Restore, Delete per saved project
- [x] NSAlert-based name prompt for "Project: Save Current"
- [x] Static commands: Close All Windows, Clear Notifications, Mark All Read, Clear Status
- [x] Fix `UNUserNotificationCenter` delegate conflict

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

## Phase 9e: Empty State UX

**Goal:** Define what the user sees when launching with no workspaces (fresh install or after closing everything).

**Current behavior (after stale project fix):** Top bar shows "No workspace", no project badge, bottom bar is empty. Terminal pane works but has no workspace association.

**Option A — Auto-bootstrap (recommended):**
- On launch, if `workspaces.isEmpty` after session restore, auto-create a "default" workspace in a "default" project for the initial terminal surface
- User always has at least one workspace — closer to tmux behavior (always in a session)
- `cmd+n` still creates additional workspaces; the auto-created one is just a starting point
- If the user renames the project/workspace, the rename sticks across restarts

**Option B — Welcome prompt:**
- Show a lightweight overlay or auto-open the project picker when no workspaces exist
- User picks or creates a project before the terminal is associated with a workspace
- More explicit but adds friction to first launch

Tasks:
- [ ] Decide approach (A or B)
- [ ] Implement chosen approach
- [ ] Ensure closing the auto-created workspace still works cleanly (no stale state)

---

## Phase 9f: Visual Polish

**Goal:** Refine bars, pills, and chrome for daily-driver quality.

- [ ] Top/bottom bar background: `Color(nsColor:).opacity(0.85)` → `.ultraThinMaterial`
- [ ] Add thin `Divider()` between bars and content
- [ ] Improve inactive pill contrast (too low against dark backgrounds)
- [ ] Add workspace pill hover state
- [ ] Deduplicate `agentIcon()`/`agentColor()` into `AgentState` extension

---

## Phase 9g: Logging + Error Handling

**Goal:** Add structured logging across all IDE components and harden the socket server.

- [ ] `IDELogger.swift` with per-component `Logger` instances (OSLog)
- [ ] Add logging to: GitBranchProvider, IDEConfigWatcher, WorkspaceStore, SocketServer silent failures
- [ ] Socket resilience: max message size (1MB), write() return check

---

## Phase 9h: Workflow Tests

**Goal:** Replace granular unit tests with real-workflow scenario tests.

- [ ] Workspace lifecycle workflow (create, switch, rename, meta, delete)
- [ ] Session persistence workflow (save, read JSON, verify structure)
- [ ] Notification workflow (send, list, clear, verify fields)
- [ ] Agent status workflow (set, overwrite, clear)
- [ ] CLI workflow tests (full lifecycle via CLI, --json flag, error codes)

---

## Phase 9i: IDE Framework Module (Optional)

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

