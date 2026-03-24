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

Add to your Claude Code `settings.json` (or `.claude/settings.json`):

```json
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "ide notify send 'Claude Code' --body 'Waiting for input'"
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
            "command": "ide status set claude idle --pane $GHOSTTYIDE_PANE_ID"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "ide status set claude working --pane $GHOSTTYIDE_PANE_ID"
          }
        ]
      }
    ]
  }
}
```

This gives you:
- **System notification** when Claude Code needs input (like cmux's `cmux notify`)
- **Status tracking** showing whether Claude is working or idle in each pane

## OpenCode Integration

OpenCode can use the socket directly or shell out to the CLI. Example plugin pattern:

```bash
# In your OpenCode config, add a post-action hook:
ide notify send "OpenCode" --body "Task complete" --pane $GHOSTTYIDE_PANE_ID
ide status set opencode "done" --pane $GHOSTTYIDE_PANE_ID
```

## CLI Reference

### Notifications

```bash
# Send a notification (appears in macOS Notification Center)
ide notify send "Title" --body "Optional body" --pane <uuid>

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
