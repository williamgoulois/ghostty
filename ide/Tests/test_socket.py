#!/usr/bin/env python3
"""Integration tests for the GhosttyIDE socket server.

Usage:
    1. Launch GhosttyIDE.app
    2. Run: python3 ide/Tests/test_socket.py

Tests connect to /tmp/ghosttyide.sock and exercise the command protocol.
"""

import json
import os
import shutil
import socket
import subprocess
import sys
import time
import uuid

SOCKET_PATH = "/tmp/ghosttyide.sock"
passed = 0
failed = 0

# Unique prefix per run to avoid conflicts between test runs
RUN_ID = uuid.uuid4().hex[:8]


def send_command(cmd: dict, sock_path: str = SOCKET_PATH) -> dict:
    """Send a JSON command to the socket and return the parsed response."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect(sock_path)
    sock.sendall(json.dumps(cmd).encode())
    sock.shutdown(socket.SHUT_WR)  # Signal end of request
    data = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    sock.close()
    return json.loads(data)


def test(name: str, fn):
    """Run a test and track pass/fail."""
    global passed, failed
    try:
        fn()
        print(f"  PASS  {name}")
        passed += 1
    except Exception as e:
        print(f"  FAIL  {name}: {e}")
        failed += 1


def assert_eq(actual, expected, msg=""):
    if actual != expected:
        raise AssertionError(f"{msg}expected {expected!r}, got {actual!r}")


# --- Tests ---


def test_help():
    resp = send_command({"command": "help"})
    assert_eq(resp["ok"], True)
    commands = resp["data"]["commands"]
    assert isinstance(commands, list), f"Expected list, got {type(commands)}"
    for required in ["help", "app.version", "app.pid", "pane.list", "pane.split",
                      "project.save", "project.restore", "project.list", "project.delete",
                      "project.close-all", "project.switch",
                      "workspace.new", "workspace.switch", "workspace.next",
                      "workspace.previous", "workspace.list", "workspace.rename",
                      "workspace.meta.set", "workspace.meta.clear",
                      "notify.send", "notify.list", "notify.clear",
                      "status.set", "status.clear", "status.list",
                      "session.save", "session.info"]:
        assert required in commands, f"Missing command: {required}"


def test_app_version():
    resp = send_command({"command": "app.version"})
    assert_eq(resp["ok"], True)
    assert "version" in resp["data"], "Missing 'version' key"
    assert "build" in resp["data"], "Missing 'build' key"


def test_app_pid():
    resp = send_command({"command": "app.pid"})
    assert_eq(resp["ok"], True)
    pid = resp["data"]["pid"]
    assert isinstance(pid, int), f"PID should be int, got {type(pid)}"
    assert pid > 0, f"PID should be positive, got {pid}"


def test_pane_list():
    resp = send_command({"command": "pane.list"})
    assert_eq(resp["ok"], True)
    panes = resp["data"]["panes"]
    assert isinstance(panes, list), f"Expected list, got {type(panes)}"
    # At least one pane should exist if a window is open
    if panes:
        pane = panes[0]
        for key in ["id", "title", "pwd", "window_id", "focused"]:
            assert key in pane, f"Missing key '{key}' in pane"


def test_unknown_command():
    resp = send_command({"command": "nonexistent.command"})
    assert_eq(resp["ok"], False)
    assert resp["error"] is not None, "Expected error message"
    assert "Unknown command" in resp["error"]


def test_invalid_json():
    """Send malformed data and expect a failure response."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect(SOCKET_PATH)
    sock.sendall(b"this is not json{{{")
    sock.shutdown(socket.SHUT_WR)
    data = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    sock.close()
    resp = json.loads(data)
    assert_eq(resp["ok"], False)
    assert "Invalid JSON" in resp["error"]


def test_pane_split_invalid_direction():
    resp = send_command({"command": "pane.split", "args": {"direction": "diagonal"}})
    assert_eq(resp["ok"], False)
    assert "Invalid direction" in resp["error"]


def test_pane_focus_missing_id():
    resp = send_command({"command": "pane.focus"})
    assert_eq(resp["ok"], False)


def test_pane_close_bad_id():
    resp = send_command({"command": "pane.close", "args": {"id": "not-a-uuid"}})
    assert_eq(resp["ok"], False)


def test_pane_focus_nonexistent():
    resp = send_command({"command": "pane.focus", "args": {"id": "00000000-0000-0000-0000-000000000000"}})
    assert_eq(resp["ok"], False)
    assert "not found" in resp["error"].lower()


def test_pane_focus_direction_left():
    resp = send_command({"command": "pane.focus-direction", "args": {"direction": "left"}})
    # May fail with "No active terminal surface" if GhosttyIDE isn't the key window
    # (e.g., when tests run from another terminal). Both ok=true and this specific
    # error are acceptable.
    if not resp["ok"]:
        assert "no active terminal surface" in resp["error"].lower(), f"Unexpected error: {resp['error']}"
    else:
        assert "direction" in resp["data"], "Missing 'direction' in response"
        assert_eq(resp["data"]["direction"], "left")


def test_pane_focus_direction_invalid():
    resp = send_command({"command": "pane.focus-direction", "args": {"direction": "diagonal"}})
    assert_eq(resp["ok"], False)
    assert "invalid direction" in resp["error"].lower()


def test_pane_focus_direction_missing():
    resp = send_command({"command": "pane.focus-direction"})
    assert_eq(resp["ok"], False)
    assert "missing" in resp["error"].lower()


# --- Project tests ---

TEMP_PROJECT = f"_test_project_{RUN_ID}_"


def test_project_save():
    resp = send_command({"command": "project.save", "args": {"name": TEMP_PROJECT}})
    assert_eq(resp["ok"], True)
    assert "windows" in resp["data"], "Missing 'windows' key"
    assert "panes" in resp["data"], "Missing 'panes' key"
    assert "saved_at" in resp["data"], "Missing 'saved_at' key"
    assert resp["data"]["windows"] >= 1, "Expected at least 1 window"


def test_project_list():
    resp = send_command({"command": "project.list"})
    assert_eq(resp["ok"], True)
    projects = resp["data"]["projects"]
    assert isinstance(projects, list), f"Expected list, got {type(projects)}"
    names = [p["name"] for p in projects]
    assert TEMP_PROJECT in names, f"Saved project not found in list: {names}"


def test_project_restore():
    resp = send_command({"command": "project.restore", "args": {"name": TEMP_PROJECT}})
    assert_eq(resp["ok"], True)
    assert resp["data"]["windows_created"] >= 1, "Expected at least 1 window created"


def test_project_delete():
    resp = send_command({"command": "project.delete", "args": {"name": TEMP_PROJECT}})
    assert_eq(resp["ok"], True)
    # Verify it's gone
    resp2 = send_command({"command": "project.list"})
    names = [p["name"] for p in resp2["data"]["projects"]]
    assert TEMP_PROJECT not in names, f"Project still in list after delete: {names}"


def test_project_save_missing_name():
    resp = send_command({"command": "project.save"})
    assert_eq(resp["ok"], False)


def test_project_save_empty_name():
    resp = send_command({"command": "project.save", "args": {"name": ""}})
    assert_eq(resp["ok"], False)


def test_project_save_invalid_name():
    resp = send_command({"command": "project.save", "args": {"name": "bad/name"}})
    assert_eq(resp["ok"], False)


def test_project_save_invalid_name_spaces():
    resp = send_command({"command": "project.save", "args": {"name": "bad name"}})
    assert_eq(resp["ok"], False)


def test_project_restore_not_found():
    resp = send_command({"command": "project.restore", "args": {"name": "nonexistent_project_xyz"}})
    assert_eq(resp["ok"], False)
    assert "not found" in resp["error"].lower()


def test_project_delete_not_found():
    resp = send_command({"command": "project.delete", "args": {"name": "nonexistent_project_xyz"}})
    assert_eq(resp["ok"], False)
    assert "not found" in resp["error"].lower()


# --- Workspace tests ---

TEMP_WORKSPACE = f"_test_ws_{RUN_ID}_"
TEMP_WS_PROJECT = f"_test_ws_proj_{RUN_ID}_"


def test_workspace_new():
    resp = send_command({"command": "workspace.new", "args": {"name": TEMP_WORKSPACE, "project": TEMP_WS_PROJECT}})
    assert_eq(resp["ok"], True)
    assert_eq(resp["data"]["name"], TEMP_WORKSPACE)
    assert_eq(resp["data"]["project"], TEMP_WS_PROJECT)
    assert "id" in resp["data"], "Missing 'id' key"


def test_workspace_new_with_options():
    resp = send_command({"command": "workspace.new", "args": {
        "name": TEMP_WORKSPACE + "2",
        "project": TEMP_WS_PROJECT,
        "color": "#2ECC71",
        "emoji": "snake",
    }})
    assert_eq(resp["ok"], True)
    assert_eq(resp["data"]["name"], TEMP_WORKSPACE + "2")


def test_workspace_new_missing_name():
    resp = send_command({"command": "workspace.new", "args": {"project": TEMP_WS_PROJECT}})
    assert_eq(resp["ok"], False)


def test_workspace_new_empty_name():
    resp = send_command({"command": "workspace.new", "args": {"name": "", "project": TEMP_WS_PROJECT}})
    assert_eq(resp["ok"], False)


def test_workspace_list():
    # Switch to the test project first
    send_command({"command": "project.switch", "args": {"name": TEMP_WS_PROJECT}})
    resp = send_command({"command": "workspace.list"})
    assert_eq(resp["ok"], True)
    workspaces = resp["data"]["workspaces"]
    assert isinstance(workspaces, list), f"Expected list, got {type(workspaces)}"
    names = [w["name"] for w in workspaces]
    assert TEMP_WORKSPACE in names, f"Workspace not found in list: {names}"
    # Validate returned fields
    ws = next(w for w in workspaces if w["name"] == TEMP_WORKSPACE)
    for key in ["id", "name", "project", "is_active", "is_visited"]:
        assert key in ws, f"Missing key '{key}' in workspace"
    assert_eq(ws["project"], TEMP_WS_PROJECT)


def test_workspace_switch():
    resp = send_command({"command": "workspace.switch", "args": {"name": TEMP_WORKSPACE}})
    assert_eq(resp["ok"], True)
    assert_eq(resp["data"]["name"], TEMP_WORKSPACE)


def test_workspace_visited_after_switch():
    """After switching to a workspace, is_visited should be true (surface tree created)."""
    send_command({"command": "project.switch", "args": {"name": TEMP_WS_PROJECT}})
    send_command({"command": "workspace.switch", "args": {"name": TEMP_WORKSPACE}})
    resp = send_command({"command": "workspace.list"})
    assert_eq(resp["ok"], True)
    ws = next(w for w in resp["data"]["workspaces"] if w["name"] == TEMP_WORKSPACE)
    assert_eq(ws["is_visited"], True, "Workspace should be visited after switch ")


def test_workspace_switch_not_found():
    resp = send_command({"command": "workspace.switch", "args": {"name": "nonexistent_ws_xyz"}})
    assert_eq(resp["ok"], False)
    assert "not found" in resp["error"].lower()


def test_workspace_next():
    # First ensure we're on the known workspace
    send_command({"command": "workspace.switch", "args": {"name": TEMP_WORKSPACE}})
    resp = send_command({"command": "workspace.next"})
    assert_eq(resp["ok"], True)
    assert "name" in resp["data"]
    # Should have switched away from TEMP_WORKSPACE (we have at least 2)
    assert resp["data"]["name"] != TEMP_WORKSPACE, "Next should switch to a different workspace"


def test_workspace_previous():
    resp = send_command({"command": "workspace.previous"})
    assert_eq(resp["ok"], True)
    assert "name" in resp["data"]
    # After next+previous we should be back
    assert_eq(resp["data"]["name"], TEMP_WORKSPACE)


def test_workspace_rename():
    new_name = TEMP_WORKSPACE + "_renamed"
    resp = send_command({"command": "workspace.rename", "args": {"name": TEMP_WORKSPACE, "new_name": new_name}})
    assert_eq(resp["ok"], True)
    assert_eq(resp["data"]["old_name"], TEMP_WORKSPACE)
    assert_eq(resp["data"]["new_name"], new_name)
    # Rename back for subsequent tests
    send_command({"command": "workspace.rename", "args": {"name": new_name, "new_name": TEMP_WORKSPACE}})


def test_workspace_rename_not_found():
    resp = send_command({"command": "workspace.rename", "args": {"name": "nonexistent_ws", "new_name": "foo"}})
    assert_eq(resp["ok"], False)


def test_workspace_meta_set():
    resp = send_command({"command": "workspace.meta.set", "args": {
        "workspace": TEMP_WORKSPACE,
        "key": "ports",
        "value": "3000, 8080",
        "icon": "network",
    }})
    assert_eq(resp["ok"], True)
    assert_eq(resp["data"]["key"], "ports")
    assert_eq(resp["data"]["value"], "3000, 8080")


def test_workspace_meta_set_with_url():
    resp = send_command({"command": "workspace.meta.set", "args": {
        "workspace": TEMP_WORKSPACE,
        "key": "pr",
        "value": "#123",
        "url": "https://github.com/example/pull/123",
    }})
    assert_eq(resp["ok"], True)


def test_workspace_meta_set_empty_key():
    resp = send_command({"command": "workspace.meta.set", "args": {
        "workspace": TEMP_WORKSPACE,
        "key": "",
        "value": "test",
    }})
    assert_eq(resp["ok"], False)


def test_workspace_meta_visible_in_list():
    """Verify metadata set earlier appears in workspace.list."""
    send_command({"command": "project.switch", "args": {"name": TEMP_WS_PROJECT}})
    resp = send_command({"command": "workspace.list"})
    assert_eq(resp["ok"], True)
    ws = next(w for w in resp["data"]["workspaces"] if w["name"] == TEMP_WORKSPACE)
    assert "metadata" in ws, "Expected metadata in workspace list"
    assert "ports" in ws["metadata"], f"Expected 'ports' metadata, got keys: {list(ws['metadata'].keys())}"
    assert_eq(ws["metadata"]["ports"]["value"], "3000, 8080")


def test_workspace_meta_set_not_found():
    resp = send_command({"command": "workspace.meta.set", "args": {
        "workspace": "nonexistent_ws",
        "key": "foo",
        "value": "bar",
    }})
    assert_eq(resp["ok"], False)


def test_workspace_meta_clear():
    resp = send_command({"command": "workspace.meta.clear", "args": {
        "workspace": TEMP_WORKSPACE,
        "key": "ports",
    }})
    assert_eq(resp["ok"], True)


def test_workspace_meta_clear_not_found():
    resp = send_command({"command": "workspace.meta.clear", "args": {
        "workspace": "nonexistent_ws",
        "key": "foo",
    }})
    assert_eq(resp["ok"], False)


def test_project_switch():
    resp = send_command({"command": "project.switch", "args": {"name": TEMP_WS_PROJECT}})
    assert_eq(resp["ok"], True)
    assert_eq(resp["data"]["project"], TEMP_WS_PROJECT)
    assert "active_workspace" in resp["data"]


def test_project_switch_missing_name():
    resp = send_command({"command": "project.switch"})
    assert_eq(resp["ok"], False)


# --- Notify tests ---


def test_notify_send():
    resp = send_command({"command": "notify.send", "args": {"title": "Test Notification", "body": "Hello from tests"}})
    assert_eq(resp["ok"], True)
    assert "notification_id" in resp["data"], "Missing 'notification_id' key"
    assert resp["data"]["title"] == "Test Notification"


def test_notify_send_title_only():
    resp = send_command({"command": "notify.send", "args": {"title": "Title Only"}})
    assert_eq(resp["ok"], True)
    assert_eq(resp["data"]["title"], "Title Only")


def test_notify_send_with_pane():
    resp = send_command({"command": "notify.send", "args": {"title": "Pane Test", "pane_id": "00000000-0000-0000-0000-000000000000"}})
    assert_eq(resp["ok"], True)


def test_notify_send_missing_title():
    resp = send_command({"command": "notify.send"})
    assert_eq(resp["ok"], False)
    assert "title" in resp["error"].lower()


def test_notify_send_empty_title():
    resp = send_command({"command": "notify.send", "args": {"title": ""}})
    assert_eq(resp["ok"], False)


def test_notify_list():
    # Should have at least the notifications we just sent
    resp = send_command({"command": "notify.list"})
    assert_eq(resp["ok"], True)
    notifications = resp["data"]["notifications"]
    assert isinstance(notifications, list), f"Expected list, got {type(notifications)}"
    assert len(notifications) >= 1, "Expected at least 1 notification from prior test"
    n = notifications[-1]
    for key in ["id", "title", "body", "timestamp"]:
        assert key in n, f"Missing key '{key}' in notification"


def test_notify_clear():
    resp = send_command({"command": "notify.clear"})
    assert_eq(resp["ok"], True)
    # Verify list is now empty
    resp2 = send_command({"command": "notify.list"})
    assert_eq(len(resp2["data"]["notifications"]), 0)


def test_notify_tracks_pane_unread():
    """Sending a notification with pane_id should add it to unreadPaneIds."""
    send_command({"command": "notify.clear"})
    pane_id = "test-pane-notify-" + uuid.uuid4().hex[:8]
    send_command({"command": "notify.send", "args": {"title": "Pane unread", "pane_id": pane_id}})
    # @Published write is dispatched to main queue — give it a moment
    time.sleep(0.3)
    resp = send_command({"command": "notify.status"})
    assert_eq(resp["ok"], True)
    assert pane_id in resp["data"]["unread_pane_ids"], \
        f"Expected {pane_id} in unread_pane_ids, got {resp['data']['unread_pane_ids']}"
    assert_eq(resp["data"]["unread_count"], 1)
    send_command({"command": "notify.clear"})


def test_notify_clear_resets_pane_unread():
    """Clearing notifications should empty unreadPaneIds."""
    pane_id = "test-pane-clear-" + uuid.uuid4().hex[:8]
    send_command({"command": "notify.send", "args": {"title": "Clear test", "pane_id": pane_id}})
    time.sleep(0.3)
    send_command({"command": "notify.clear"})
    time.sleep(0.3)
    resp = send_command({"command": "notify.status"})
    assert_eq(resp["ok"], True)
    assert_eq(resp["data"]["unread_count"], 0)
    assert_eq(len(resp["data"]["unread_pane_ids"]), 0)


# --- Status tests ---


def test_status_set():
    resp = send_command({"command": "status.set", "args": {"key": "agent", "value": "idle", "pane_id": "test-pane-1"}})
    assert_eq(resp["ok"], True)
    assert_eq(resp["data"]["key"], "agent")
    assert_eq(resp["data"]["value"], "idle")
    assert_eq(resp["data"]["pane_id"], "test-pane-1")


def test_status_set_another():
    resp = send_command({"command": "status.set", "args": {"key": "build", "value": "running", "pane_id": "test-pane-2"}})
    assert_eq(resp["ok"], True)


def test_status_set_overwrite():
    # Set initial value
    send_command({"command": "status.set", "args": {"key": "agent", "value": "idle", "pane_id": "test-pane-1"}})
    # Overwrite with new value
    resp = send_command({"command": "status.set", "args": {"key": "agent", "value": "working", "pane_id": "test-pane-1"}})
    assert_eq(resp["ok"], True)
    assert_eq(resp["data"]["value"], "working")
    # Verify only one entry exists for this key
    resp2 = send_command({"command": "status.list", "args": {"pane_id": "test-pane-1"}})
    statuses = resp2["data"]["statuses"]
    agent_entries = [s for s in statuses if s["key"] == "agent"]
    assert_eq(len(agent_entries), 1, "Expected exactly 1 agent entry after overwrite, ")
    assert_eq(agent_entries[0]["value"], "working")


def test_status_set_missing_key():
    resp = send_command({"command": "status.set", "args": {"value": "idle"}})
    assert_eq(resp["ok"], False)
    assert "key" in resp["error"].lower()


def test_status_set_missing_value():
    resp = send_command({"command": "status.set", "args": {"key": "agent"}})
    assert_eq(resp["ok"], False)
    assert "value" in resp["error"].lower()


def test_status_list():
    resp = send_command({"command": "status.list"})
    assert_eq(resp["ok"], True)
    statuses = resp["data"]["statuses"]
    assert isinstance(statuses, list), f"Expected list, got {type(statuses)}"
    assert len(statuses) >= 2, f"Expected at least 2 statuses, got {len(statuses)}"
    for s in statuses:
        for key in ["key", "value", "pane_id", "updated_at"]:
            assert key in s, f"Missing key '{key}' in status"


def test_status_list_filtered():
    resp = send_command({"command": "status.list", "args": {"pane_id": "test-pane-1"}})
    assert_eq(resp["ok"], True)
    statuses = resp["data"]["statuses"]
    assert len(statuses) == 1, f"Expected 1 status for test-pane-1, got {len(statuses)}"
    assert_eq(statuses[0]["key"], "agent")


def test_status_clear_specific():
    resp = send_command({"command": "status.clear", "args": {"pane_id": "test-pane-1", "key": "agent"}})
    assert_eq(resp["ok"], True)
    # Verify it's gone
    resp2 = send_command({"command": "status.list", "args": {"pane_id": "test-pane-1"}})
    assert_eq(len(resp2["data"]["statuses"]), 0)


def test_status_clear_all():
    resp = send_command({"command": "status.clear"})
    assert_eq(resp["ok"], True)
    resp2 = send_command({"command": "status.list"})
    assert_eq(len(resp2["data"]["statuses"]), 0)


# --- Session tests ---


def test_session_save():
    resp = send_command({"command": "session.save"})
    assert_eq(resp["ok"], True)
    assert "saved_at" in resp["data"], "Missing 'saved_at' key"
    assert "workspace_count" in resp["data"], "Missing 'workspace_count' key"
    assert isinstance(resp["data"]["workspace_count"], int)


def test_session_info():
    # Ensure a save exists first
    send_command({"command": "session.save"})
    resp = send_command({"command": "session.info"})
    assert_eq(resp["ok"], True)
    assert_eq(resp["data"]["exists"], True)
    assert "saved_at" in resp["data"]
    assert "version" in resp["data"]
    assert "workspace_count" in resp["data"]
    assert "active_project" in resp["data"]
    assert "active_workspace" in resp["data"]


def test_session_info_structure():
    send_command({"command": "session.save"})
    resp = send_command({"command": "session.info"})
    assert_eq(resp["ok"], True)
    assert isinstance(resp["data"]["workspaces"], list), "workspaces should be a list"
    assert isinstance(resp["data"]["projects"], list), "projects should be a list"
    assert_eq(resp["data"]["version"], 1)


def test_session_save_idempotent():
    """Saving twice should succeed without error."""
    resp1 = send_command({"command": "session.save"})
    assert_eq(resp1["ok"], True)
    resp2 = send_command({"command": "session.save"})
    assert_eq(resp2["ok"], True)


# --- CLI tests (require `swift build` in ide/CLI first) ---

CLI_DIR = os.path.join(os.path.dirname(__file__), "..", "CLI")
CLI_BIN = None


def find_cli_binary():
    """Find the built CLI binary."""
    global CLI_BIN
    # Check if swift run is available
    candidate = os.path.join(CLI_DIR, ".build", "debug", "ide")
    if os.path.isfile(candidate):
        CLI_BIN = candidate
        return True
    return False


def run_cli(*args: str) -> subprocess.CompletedProcess:
    """Run the CLI binary with given arguments."""
    return subprocess.run(
        [CLI_BIN] + list(args),
        capture_output=True, text=True, timeout=10,
    )


def test_cli_help():
    r = run_cli("--help")
    assert r.returncode == 0, f"Exit code {r.returncode}"
    assert "ide" in r.stdout
    assert "pane" in r.stdout


def test_cli_app_version():
    r = run_cli("app", "version")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "GhosttyIDE" in r.stdout


def test_cli_app_version_json():
    r = run_cli("app", "version", "--json")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    data = json.loads(r.stdout)
    assert data["ok"] is True
    assert "version" in data["data"]


def test_cli_pane_list():
    r = run_cli("pane", "list")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"


def test_cli_pane_focus_direction():
    r = run_cli("pane", "focus-direction", "left")
    # May return error if GhosttyIDE isn't the key window (no active surface)
    if r.returncode != 0:
        assert "no active terminal surface" in r.stderr.lower() or "no active terminal surface" in r.stdout.lower(), \
            f"Unexpected error (exit {r.returncode}): {r.stderr or r.stdout}"


def test_cli_pane_focus_direction_missing():
    r = run_cli("pane", "focus-direction")
    assert r.returncode != 0, "Expected non-zero exit code for missing direction"


def test_cli_commands():
    r = run_cli("commands")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "pane.list" in r.stdout
    assert "pane.focus-direction" in r.stdout


def test_cli_raw():
    r = run_cli("raw", "app.pid", "--json")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    data = json.loads(r.stdout)
    assert data["ok"] is True


def test_cli_error_exit_code():
    r = run_cli("pane", "focus", "bad-uuid")
    assert r.returncode != 0, "Expected non-zero exit code for invalid UUID"


def test_cli_project_save():
    r = run_cli("project", "save", TEMP_PROJECT)
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Saved project" in r.stdout


def test_cli_project_save_json():
    r = run_cli("project", "save", TEMP_PROJECT, "--json")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    data = json.loads(r.stdout)
    assert data["ok"] is True
    assert "windows" in data["data"]
    assert "panes" in data["data"]


def test_cli_project_list():
    r = run_cli("project", "list")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert TEMP_PROJECT in r.stdout


def test_cli_project_list_json():
    r = run_cli("project", "list", "--json")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    data = json.loads(r.stdout)
    assert data["ok"] is True
    assert "projects" in data["data"]


def test_cli_project_delete():
    r = run_cli("project", "delete", TEMP_PROJECT)
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Deleted" in r.stdout


def test_cli_notify_send():
    r = run_cli("notify", "send", "CLI Test", "--body", "Hello from CLI")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Notification sent" in r.stdout


def test_cli_notify_list():
    r = run_cli("notify", "list", "--json")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    data = json.loads(r.stdout)
    assert data["ok"] is True
    assert "notifications" in data["data"]


def test_cli_notify_clear():
    r = run_cli("notify", "clear")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "cleared" in r.stdout.lower()


def test_cli_notify_send_with_pane():
    r = run_cli("notify", "send", "Pane CLI", "--body", "With pane", "--pane", "cli-pane-1")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Notification sent" in r.stdout


def test_cli_notify_status():
    r = run_cli("notify", "status")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Unread panes:" in r.stdout


def test_cli_notify_status_json():
    r = run_cli("notify", "status", "--json")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    data = json.loads(r.stdout)
    assert data["ok"] is True
    assert "unread_count" in data["data"]
    assert "unread_pane_ids" in data["data"]


def test_cli_status_set():
    r = run_cli("status", "set", "test_key", "test_value", "--pane", "cli-test-pane")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Status set" in r.stdout


def test_cli_status_list():
    r = run_cli("status", "list", "--json")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    data = json.loads(r.stdout)
    assert data["ok"] is True
    assert "statuses" in data["data"]


def test_cli_status_list_filtered():
    r = run_cli("status", "list", "--pane", "cli-test-pane", "--json")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    data = json.loads(r.stdout)
    assert data["ok"] is True
    statuses = data["data"]["statuses"]
    assert len(statuses) >= 1, f"Expected at least 1 status for cli-test-pane"
    assert all(s["pane_id"] == "cli-test-pane" for s in statuses), "Expected all statuses to be for cli-test-pane"


def test_cli_status_clear():
    r = run_cli("status", "clear")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "cleared" in r.stdout.lower()


CLI_TEMP_WS = f"_cli_ws_{RUN_ID}_"
CLI_TEMP_PROJ = f"_cli_proj_{RUN_ID}_"


def test_cli_workspace_new():
    r = run_cli("workspace", "new", CLI_TEMP_WS, "--project", CLI_TEMP_PROJ)
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Created workspace" in r.stdout


def test_cli_workspace_list():
    # Switch to the test project
    run_cli("workspace", "project-switch", CLI_TEMP_PROJ)
    r = run_cli("workspace", "list")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert CLI_TEMP_WS in r.stdout


def test_cli_workspace_list_json():
    r = run_cli("workspace", "list", "--json")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    data = json.loads(r.stdout)
    assert data["ok"] is True
    assert "workspaces" in data["data"]


def test_cli_workspace_switch():
    r = run_cli("workspace", "switch", CLI_TEMP_WS)
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Switched" in r.stdout


def test_cli_workspace_rename():
    renamed = CLI_TEMP_WS + "ren"
    r = run_cli("workspace", "rename", CLI_TEMP_WS, renamed)
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Renamed" in r.stdout
    # Rename back
    run_cli("workspace", "rename", renamed, CLI_TEMP_WS)


def test_cli_workspace_meta_set():
    r = run_cli("workspace", "meta", "set", CLI_TEMP_WS, "ports", "3000")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Set" in r.stdout


def test_cli_workspace_meta_clear():
    r = run_cli("workspace", "meta", "clear", CLI_TEMP_WS, "ports")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Cleared" in r.stdout


def test_cli_workspace_next():
    r = run_cli("workspace", "next")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Switched" in r.stdout


def test_cli_workspace_project_switch():
    r = run_cli("workspace", "project-switch", CLI_TEMP_PROJ)
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Switched to project" in r.stdout


def test_cli_session_save():
    r = run_cli("session", "save")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Session saved" in r.stdout


def test_cli_session_info():
    run_cli("session", "save")  # ensure file exists
    r = run_cli("session", "info")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "Session:" in r.stdout
    assert "Active:" in r.stdout


def test_cli_session_info_json():
    run_cli("session", "save")
    r = run_cli("session", "info", "--json")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    data = json.loads(r.stdout)
    assert data["ok"] is True
    assert data["data"]["exists"] is True
    assert "workspace_count" in data["data"]


if __name__ == "__main__":
    # Check socket exists
    if not os.path.exists(SOCKET_PATH):
        print(f"Socket not found at {SOCKET_PATH}")
        print("Is GhosttyIDE running? Launch it first.")
        sys.exit(1)

    print(f"Testing socket at {SOCKET_PATH}\n")

    print("--- Socket protocol tests ---")
    test("help", test_help)
    test("app.version", test_app_version)
    test("app.pid", test_app_pid)
    test("pane.list", test_pane_list)
    test("unknown command", test_unknown_command)
    test("invalid JSON", test_invalid_json)
    test("pane.split invalid direction", test_pane_split_invalid_direction)
    test("pane.focus missing id", test_pane_focus_missing_id)
    test("pane.close bad id", test_pane_close_bad_id)
    test("pane.focus nonexistent", test_pane_focus_nonexistent)
    test("pane.focus-direction left", test_pane_focus_direction_left)
    test("pane.focus-direction invalid", test_pane_focus_direction_invalid)
    test("pane.focus-direction missing", test_pane_focus_direction_missing)

    print("\n--- Project tests ---")
    test("project.save", test_project_save)
    test("project.list", test_project_list)
    test("project.restore", test_project_restore)
    test("project.delete", test_project_delete)
    test("project.save missing name", test_project_save_missing_name)
    test("project.save empty name", test_project_save_empty_name)
    test("project.save invalid name", test_project_save_invalid_name)
    test("project.save invalid name spaces", test_project_save_invalid_name_spaces)
    test("project.restore not found", test_project_restore_not_found)
    test("project.delete not found", test_project_delete_not_found)

    print("\n--- Workspace tests ---")
    test("workspace.new", test_workspace_new)
    test("workspace.new with options", test_workspace_new_with_options)
    test("workspace.new missing name", test_workspace_new_missing_name)
    test("workspace.new empty name", test_workspace_new_empty_name)
    test("workspace.list", test_workspace_list)
    test("workspace.switch", test_workspace_switch)
    test("workspace.visited after switch", test_workspace_visited_after_switch)
    test("workspace.switch not found", test_workspace_switch_not_found)
    test("workspace.next", test_workspace_next)
    test("workspace.previous", test_workspace_previous)
    test("workspace.rename", test_workspace_rename)
    test("workspace.rename not found", test_workspace_rename_not_found)
    test("workspace.meta.set", test_workspace_meta_set)
    test("workspace.meta.set with url", test_workspace_meta_set_with_url)
    test("workspace.meta.set empty key", test_workspace_meta_set_empty_key)
    test("workspace.meta.visible in list", test_workspace_meta_visible_in_list)
    test("workspace.meta.set not found", test_workspace_meta_set_not_found)
    test("workspace.meta.clear", test_workspace_meta_clear)
    test("workspace.meta.clear not found", test_workspace_meta_clear_not_found)
    test("project.switch", test_project_switch)
    test("project.switch missing name", test_project_switch_missing_name)

    print("\n--- Notify tests ---")
    test("notify.send", test_notify_send)
    test("notify.send title only", test_notify_send_title_only)
    test("notify.send with pane", test_notify_send_with_pane)
    test("notify.send missing title", test_notify_send_missing_title)
    test("notify.send empty title", test_notify_send_empty_title)
    test("notify.list", test_notify_list)
    test("notify.clear", test_notify_clear)
    test("notify.tracks pane unread", test_notify_tracks_pane_unread)
    test("notify.clear resets pane unread", test_notify_clear_resets_pane_unread)

    print("\n--- Status tests ---")
    test("status.set", test_status_set)
    test("status.set another", test_status_set_another)
    test("status.set overwrite", test_status_set_overwrite)
    test("status.set missing key", test_status_set_missing_key)
    test("status.set missing value", test_status_set_missing_value)
    test("status.list", test_status_list)
    test("status.list filtered", test_status_list_filtered)
    test("status.clear specific", test_status_clear_specific)
    test("status.clear all", test_status_clear_all)

    print("\n--- Session tests ---")
    test("session.save", test_session_save)
    test("session.info", test_session_info)
    test("session.info structure", test_session_info_structure)
    test("session.save idempotent", test_session_save_idempotent)

    print("\n--- CLI tests ---")
    if find_cli_binary():
        test("cli --help", test_cli_help)
        test("cli app version", test_cli_app_version)
        test("cli app version --json", test_cli_app_version_json)
        test("cli pane list", test_cli_pane_list)
        test("cli pane focus-direction", test_cli_pane_focus_direction)
        test("cli pane focus-direction missing", test_cli_pane_focus_direction_missing)
        test("cli commands", test_cli_commands)
        test("cli raw", test_cli_raw)
        test("cli error exit code", test_cli_error_exit_code)
        test("cli project save", test_cli_project_save)
        test("cli project save --json", test_cli_project_save_json)
        test("cli project list", test_cli_project_list)
        test("cli project list --json", test_cli_project_list_json)
        test("cli project delete", test_cli_project_delete)
        test("cli notify send", test_cli_notify_send)
        test("cli notify send --pane", test_cli_notify_send_with_pane)
        test("cli notify list --json", test_cli_notify_list)
        test("cli notify clear", test_cli_notify_clear)
        test("cli notify status", test_cli_notify_status)
        test("cli notify status --json", test_cli_notify_status_json)
        test("cli status set", test_cli_status_set)
        test("cli status list --json", test_cli_status_list)
        test("cli status list --pane", test_cli_status_list_filtered)
        test("cli status clear", test_cli_status_clear)
        test("cli workspace new", test_cli_workspace_new)
        test("cli workspace list", test_cli_workspace_list)
        test("cli workspace list --json", test_cli_workspace_list_json)
        test("cli workspace switch", test_cli_workspace_switch)
        test("cli workspace rename", test_cli_workspace_rename)
        test("cli workspace meta set", test_cli_workspace_meta_set)
        test("cli workspace meta clear", test_cli_workspace_meta_clear)
        test("cli workspace next", test_cli_workspace_next)
        test("cli workspace project-switch", test_cli_workspace_project_switch)
        test("cli session save", test_cli_session_save)
        test("cli session info", test_cli_session_info)
        test("cli session info --json", test_cli_session_info_json)
    else:
        print("  SKIP  CLI not built (run: cd ide/CLI && swift build)")

    # close-all kills the app (macOS quits when last window closes), so run last
    # Note: test workspaces are in-memory only (cleaned on app restart).
    # Each run uses a unique RUN_ID prefix to avoid collisions.
    print("\n--- Destructive tests (close-all) ---")
    print("  SKIP  project.close-all (closes all windows, app may quit)")

    print(f"\n{'='*40}")
    print(f"Results: {passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)
