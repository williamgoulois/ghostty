# Agent Integration Guide

GhosttyIDE exports environment variables to every shell it spawns, making it scriptable by AI coding agents.

## Environment Variables

Every terminal pane gets:

| Variable | Description |
|----------|-------------|
| `GHOSTTYIDE_SOCKET` | Path to the Unix socket (e.g. `/tmp/ghosttyide-12345.sock`) |
| `GHOSTTYIDE_PANE_ID` | UUID of the current pane |
| `GHOSTTYIDE_WINDOW_ID` | Window number (may be empty if not yet attached) |

Agents can use these to send commands back to the IDE without manual socket discovery.

## Claude Code Hooks

Install the hook script to `~/.claude/hooks/ghosttyide/claude-code-notify.sh` (see the script in this repo's commit history or copy from a working install). The script reads Claude Code's transcript JSONL to extract the last assistant message for rich notifications.

Add to your Claude Code `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/ghosttyide/claude-code-notify.sh notification",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/ghosttyide/claude-code-notify.sh stop",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

The hook script:
- Exits immediately if `$GHOSTTYIDE_SOCKET` is not set (no-op outside GhosttyIDE)
- Reads the transcript path from Claude Code's hook JSON (stdin)
- Extracts the last assistant message via `jq` (with grep/sed fallback)
- Sends: `ide notify send "Claude Code" --subtitle "Waiting for input" --body "<last message>"`

This gives you:
- **Rich notifications** with the last assistant message in macOS Notification Center + in-app panel
- **Status tracking** (add `ide status set` hooks separately if desired)

## Notification Behaviors

**Title enrichment:** When `--pane` is provided, the notification title is automatically enriched with project/workspace context: `"Claude Code"` becomes `"Claude Code — myproject/hotfix"`. No agent-side changes needed.

**Focused-pane suppression:** Notifications are silently suppressed (not fired) when the target pane is currently focused and the app is active. This prevents redundant alerts when you're already looking at the agent's output. The response includes `"suppressed": true` so agents can detect this.

**Click-to-jump:** Clicking a macOS system notification or an in-app notification row jumps to the target pane — switching workspace and project if needed.

## OpenCode Integration

Install the plugin to `~/.config/opencode/plugins/ghosttyide-notify.js`. It listens for `session.idle`, `session.error`, and `permission.asked` events and sends rich notifications with event-specific context.

The plugin:
- Exits immediately if `$GHOSTTYIDE_SOCKET` is not set (no-op outside GhosttyIDE)
- Extracts permission details and error messages from event properties
- Sends: `ide notify send "OpenCode — <project>" --subtitle "Waiting for input" --body "<details>"`

## CLI Reference

### Notifications

```bash
# Send a notification (appears in macOS Notification Center + in-app panel)
ide notify send "Title" --subtitle "Optional subtitle" --body "Optional body" --pane <uuid>

# List recent notifications
ide notify list
ide notify list --json

# Clear all notifications
ide notify clear
```

### Status

```bash
# Set a status key for a pane (defaults to focused pane)
ide status set <key> <value> --pane <uuid>

# Examples:
ide status set claude "Waiting for input"
ide status set build "running"

# List all statuses
ide status list
ide status list --pane <uuid>
ide status list --json

# Clear statuses
ide status clear <key> --pane <uuid>   # clear specific key
ide status clear                        # clear everything
```

### Raw Socket

You can also send commands directly via the socket:

```bash
echo '{"command":"notify.send","args":{"title":"Hello","body":"World"}}' | socat - UNIX-CONNECT:$GHOSTTYIDE_SOCKET
echo '{"command":"status.set","args":{"key":"agent","value":"idle","pane_id":"'"$GHOSTTYIDE_PANE_ID"'"}}' | socat - UNIX-CONNECT:$GHOSTTYIDE_SOCKET
```
