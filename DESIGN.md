# GhosttyIDE Visual & UX Design

## Chosen Layout: Top Bar + Bottom Bar

```
+------------------------------------------------------------------+
| main | feat/hotfix | ⚡ working | :3000 | PR#123  | ENI 🔔2     |
+------------------------------------------------------------------+
|                                                                  |
|    Terminal pane (left)                                           |
|                                          |                       |
|                                          |  pane (right-top)     |
|                                          |                       |
|                                          |-----------------------|
|                                          |                       |
|                                          |  pane (right-bottom)  |
|                                          |                       |
|                                                                  |
+------------------------------------------------------------------+
| [🐍 main] [🐍 hotfix●] [🐍 review] [🐍 kraken]                 |
+------------------------------------------------------------------+
```

### Top Bar (context — "what am I looking at")

- **Left**: active workspace metadata, flowing left to right:
  - Workspace name (bold)
  - Git branch (muted, if different from name)
  - Agent state icon + label (if active)
  - Extensible metadata: ports, PR link (clickable), custom key-values
- **Right**: project name + notification bell badge + drag handle area
- Height: ~20-24px

### Bottom Bar (navigation — "where can I go")

- **Left**: workspace pills for the active project
  - Format: `[emoji name]` per workspace
  - Active = accent/magenta, others = muted/yellow
  - Notification dot on workspaces with unread
  - Agent icon on workspaces with active agents
  - Scrollable if many workspaces
- **Right**: reserved for future use
- Height: ~20-24px

### Why This Layout

- Top = context (changes with workspace focus)
- Bottom = navigation (changes with project switch)
- Total chrome: ~44px. Rest is terminal.
- Top bar metadata is extensible — new types flow into the left side
- Bottom bar scales to ~8-10 visible pills, scrollable beyond

---

## Architecture

### Workspace Model

- **Project** = UI-only tag on workspaces (no backend lifecycle)
- **Workspace** = named split layout with metadata
- **Lazy creation**: surfaces spawned on first visit, alive forever after
- **Project switch** = instant filter change (no surface lifecycle)

```
IDEWorkspace:
  id, name, project, color, emoji
  splitTree (nil until first visit)
  gitBranch, agentState, unreadNotifications
  metadata: [key: {value, icon?, url?}]  -- extensible
```

### Three-Tier Memory (tiers 1-2 now, tier 3 later)

| Tier | State | Memory | Switch | Processes |
|------|-------|--------|--------|-----------|
| 1 | Not visited | 0 | ~0.5s | N/A |
| 2 | Background | Full | Instant | Alive |
| 3 | Unloaded (Phase 10) | 0 | ~1s | New shell |

### Window Chrome

Uses `macos-titlebar-style = hidden` (existing Ghostty behavior):
- No traffic lights (hidden, not removed)
- Rounded corners + shadows preserved
- Top bar right side provides custom drag handle
- Close/minimize/zoom via Cmd+W/Cmd+M/menu

---

## Notification Stack

| Layer | Where |
|-------|-------|
| macOS system notifications | Notification Center (existing) |
| In-app notification panel | Popover from bell badge |
| Pane visual indicators | Colored border/dot on panes with unread |
| Dock badge | Unread count on app icon |
| Workspace indicators | Dot on workspace pills in bottom bar |

---

## Workspace Switching

**Within project**: Cmd+I/O (prev/next), Cmd+1..9 (by index), command palette
**Between projects**: Command palette ("Project: Switch to ENI"), socket/CLI

---

## Alternative Approaches (considered, not chosen)

### A: Left Sidebar
Vertical workspace list. Rich metadata per workspace. Collapsible. Most chrome.

### C: Bottom Status Bar (tmux-style)
Single bottom bar with workspace pills + project info. Minimal. Most tmux-like.

Both kept as future options if the top+bottom bar approach needs revision.
