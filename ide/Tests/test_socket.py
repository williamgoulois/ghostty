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

SOCKET_PATH = "/tmp/ghosttyide.sock"
passed = 0
failed = 0


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
                      "project.close-all"]:
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


# --- Project tests ---

TEMP_PROJECT = "_test_project_"


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


def test_cli_commands():
    r = run_cli("commands")
    assert r.returncode == 0, f"Exit code {r.returncode}: {r.stderr}"
    assert "pane.list" in r.stdout


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

    print("\n--- CLI tests ---")
    if find_cli_binary():
        test("cli --help", test_cli_help)
        test("cli app version", test_cli_app_version)
        test("cli app version --json", test_cli_app_version_json)
        test("cli pane list", test_cli_pane_list)
        test("cli commands", test_cli_commands)
        test("cli raw", test_cli_raw)
        test("cli error exit code", test_cli_error_exit_code)
        test("cli project save", test_cli_project_save)
        test("cli project save --json", test_cli_project_save_json)
        test("cli project list", test_cli_project_list)
        test("cli project list --json", test_cli_project_list_json)
        test("cli project delete", test_cli_project_delete)
    else:
        print("  SKIP  CLI not built (run: cd ide/CLI && swift build)")

    # close-all kills the app (macOS quits when last window closes), so run last
    print("\n--- Destructive tests (close-all) ---")
    print("  SKIP  project.close-all (closes all windows, app may quit)")

    print(f"\n{'='*40}")
    print(f"Results: {passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)
