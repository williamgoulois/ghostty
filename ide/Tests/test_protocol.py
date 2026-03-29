"""Socket protocol tests: help, errors, edge cases."""

import json


def test_help(send):
    resp = send({"command": "help"})
    assert resp["ok"]
    commands = resp["data"]["commands"]
    for cmd in ["help", "app.version", "app.pid", "pane.list", "pane.split",
                "pane.focus", "pane.focus-direction", "pane.close", "pane.send-text",
                "project.save", "project.restore", "project.list", "project.delete",
                "project.close-all", "project.switch", "project.rename",
                "workspace.new", "workspace.switch", "workspace.next",
                "workspace.previous", "workspace.move-next", "workspace.move-previous",
                "workspace.break-pane", "workspace.list", "workspace.rename",
                "workspace.remove", "workspace.meta.set", "workspace.meta.clear",
                "notify.send", "notify.list", "notify.clear", "notify.status",
                "status.set", "status.clear", "status.list",
                "session.save", "session.info"]:
        assert cmd in commands, f"Missing command: {cmd}"


def test_app_version(send):
    resp = send({"command": "app.version"})
    assert resp["ok"]
    assert "version" in resp["data"]
    assert "build" in resp["data"]


def test_app_pid(send):
    resp = send({"command": "app.pid"})
    assert resp["ok"]
    assert isinstance(resp["data"]["pid"], int)
    assert resp["data"]["pid"] > 0


def test_unknown_command(send):
    resp = send({"command": "nonexistent.command"})
    assert not resp["ok"]
    assert "Unknown command" in resp["error"]


def test_invalid_json(send_raw):
    data = send_raw(b"this is not json{{{")
    resp = json.loads(data)
    assert not resp["ok"]
    assert "Invalid JSON" in resp["error"]


def test_oversized_message(send_raw):
    """Messages > 1 MB should be dropped (no response)."""
    big_value = "x" * (1_048_577 + 100)
    payload = json.dumps({"command": "help", "args": {"data": big_value}}).encode()
    data = send_raw(payload)
    assert len(data) == 0, f"Expected empty response for oversized message, got {len(data)} bytes"
