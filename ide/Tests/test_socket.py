#!/usr/bin/env python3
"""Integration tests for the GhosttyIDE socket server.

Usage:
    1. Launch GhosttyIDE.app
    2. Run: python3 ide/Tests/test_socket.py

Tests connect to /tmp/ghosttyide.sock and exercise the command protocol.
"""

import json
import os
import socket
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
    for required in ["help", "app.version", "app.pid", "pane.list", "pane.split"]:
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


if __name__ == "__main__":
    # Check socket exists
    if not os.path.exists(SOCKET_PATH):
        # Try PID-specific path
        print(f"Socket not found at {SOCKET_PATH}")
        print("Is GhosttyIDE running? Launch it first.")
        sys.exit(1)

    print(f"Testing socket at {SOCKET_PATH}\n")

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

    print(f"\n{'='*40}")
    print(f"Results: {passed} passed, {failed} failed")
    sys.exit(1 if failed else 0)
