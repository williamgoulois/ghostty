"""Shared pytest fixtures for GhosttyIDE integration tests."""

import datetime
import json
import os
import signal
import socket
import subprocess
import time
import uuid

import glob

import pytest

SOCKET_PATH = "/tmp/ghosttyide.sock"
RUN_ID = uuid.uuid4().hex[:8]
CLI_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "CLI")
DERIVED_DATA = os.path.expanduser("~/Library/Developer/Xcode/DerivedData")


def _find_app_path() -> str | None:
    """Find the GhosttyIDE.app path. Uses GHOSTTYIDE_APP env var if set,
    otherwise finds the most recent Release build in DerivedData."""
    env_path = os.environ.get("GHOSTTYIDE_APP")
    if env_path and os.path.isdir(env_path):
        return env_path
    candidates = glob.glob(os.path.join(DERIVED_DATA, "Ghostty-*/Build/Products/Release/GhosttyIDE.app"))
    if not candidates:
        return None
    # Most recently modified
    return max(candidates, key=os.path.getmtime)


# --- Core fixtures ---


def _send_command(cmd: dict, sock_path: str = SOCKET_PATH, retries: int = 2) -> dict:
    """Send a JSON command to the socket and return the parsed response."""
    for attempt in range(retries + 1):
        try:
            sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            sock.settimeout(5)
            sock.connect(sock_path)
            sock.sendall(json.dumps(cmd).encode())
            sock.shutdown(socket.SHUT_WR)
            data = b""
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                data += chunk
            sock.close()
            return json.loads(data)
        except OSError:
            if attempt < retries:
                time.sleep(0.1)
                continue
            raise


def _send_raw(payload: bytes, sock_path: str = SOCKET_PATH) -> bytes:
    """Send raw bytes and return raw response (for protocol-level tests)."""
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(5)
    sock.connect(sock_path)
    try:
        sock.sendall(payload)
        sock.shutdown(socket.SHUT_WR)
    except (BrokenPipeError, ConnectionResetError, OSError):
        sock.close()
        return b""
    data = b""
    while True:
        chunk = sock.recv(4096)
        if not chunk:
            break
        data += chunk
    sock.close()
    return data


@pytest.fixture(scope="session")
def send(preflight):
    """Session-scoped command sender."""
    return _send_command


@pytest.fixture(scope="session")
def send_raw(preflight):
    """Session-scoped raw sender for protocol tests."""
    return _send_raw


# --- Preflight ---


@pytest.fixture(scope="session", autouse=True)
def preflight():
    """Verify GhosttyIDE is running, no stale instances, at least one window."""
    result = subprocess.run(["pgrep", "-xi", "ghosttyide"], capture_output=True, text=True)
    pids = [int(p) for p in result.stdout.strip().split("\n") if p.strip()]

    if len(pids) == 0:
        # Try to launch the specific build
        app_path = _find_app_path()
        if not app_path:
            pytest.exit("GhosttyIDE.app not found. Build it first or set GHOSTTYIDE_APP.", returncode=1)
        subprocess.run(["open", app_path], capture_output=True)
        time.sleep(3)
        result = subprocess.run(["pgrep", "-xi", "ghosttyide"], capture_output=True, text=True)
        pids = [int(p) for p in result.stdout.strip().split("\n") if p.strip()]
        if len(pids) == 0:
            pytest.exit("GhosttyIDE could not be launched.", returncode=1)

    if len(pids) > 1:
        pids.sort()
        for pid in pids[1:]:
            try:
                os.kill(pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        time.sleep(1)

    assert os.path.exists(SOCKET_PATH), f"Socket not found at {SOCKET_PATH}"

    resp = _send_command({"command": "app.pid"})
    assert resp["ok"], f"app.pid failed: {resp}"

    # Ensure at least one terminal window — wait for one to appear
    # (the app creates a window on launch, just may not be ready yet)
    for _ in range(10):
        resp = _send_command({"command": "pane.list"})
        if resp.get("data", {}).get("panes"):
            break
        time.sleep(0.5)
    else:
        # No windows — ask the app to open a new one
        app_path = _find_app_path()
        if app_path:
            subprocess.run(["open", app_path], capture_output=True)
            time.sleep(2)
        for _ in range(10):
            resp = _send_command({"command": "pane.list"})
            if resp.get("data", {}).get("panes"):
                break
            time.sleep(0.5)
        else:
            pytest.exit("GhosttyIDE has no terminal windows.", returncode=1)


# --- Cleanup ---


@pytest.fixture(scope="session")
def original_project():
    """Capture the active project before tests start."""
    resp = _send_command({"command": "session.info"})
    return resp.get("data", {}).get("active_project", "")


@pytest.fixture(scope="session", autouse=True)
def session_cleanup(original_project):
    """Close orphaned surfaces and restore project after all tests."""
    yield
    # Close all orphaned surfaces
    try:
        _send_command({"command": "project.close-all"})
    except Exception:
        pass
    # Restore project (skip test artifacts)
    restore = original_project
    if not restore or any(x in restore for x in ["_test_", "_wf_", "_cli_"]):
        restore = "default"
    try:
        _send_command({"command": "project.switch", "args": {"name": restore}})
    except Exception:
        pass
    # Save session so the on-disk state is clean (not polluted by test workspaces)
    try:
        _send_command({"command": "session.save"})
    except Exception:
        pass


# --- Resource factories ---


@pytest.fixture
def make_workspace(send):
    """Factory fixture: creates a workspace and removes it after the test."""
    created = []

    def _make(name=None, project=None, **kwargs):
        name = name or f"_t_ws_{RUN_ID}_{uuid.uuid4().hex[:4]}"
        project = project or f"_t_proj_{RUN_ID}"
        args = {"name": name, "project": project, **kwargs}
        resp = send({"command": "workspace.new", "args": args})
        assert resp["ok"], f"workspace.new failed: {resp}"
        created.append(name)
        return name, project, resp

    yield _make

    for name in created:
        try:
            _send_command({"command": "workspace.remove", "args": {"name": name}})
        except Exception:
            pass


@pytest.fixture
def switch_project(send, original_project):
    """Switch to a project for the test, restore afterwards."""
    switched_to = []

    def _switch(project_name):
        send({"command": "project.switch", "args": {"name": project_name}})
        switched_to.append(project_name)

    yield _switch

    # Restore
    restore = original_project
    if not restore or any(x in restore for x in ["_test_", "_wf_", "_cli_"]):
        restore = "default"
    try:
        _send_command({"command": "project.switch", "args": {"name": restore}})
    except Exception:
        pass


# --- CLI ---


@pytest.fixture(scope="session")
def cli():
    """Returns a function to run the CLI binary. Skips if not built."""
    candidate = os.path.join(CLI_DIR, ".build", "debug", "ide")
    if not os.path.isfile(candidate):
        pytest.skip("CLI not built (run: cd ide/CLI && swift build)")

    def _run(*args: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [candidate] + list(args),
            capture_output=True, text=True, timeout=10,
        )

    return _run


# --- Log capture ---


@pytest.fixture
def log_capture():
    """Captures OSLog errors during a test."""
    start_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    yield start_time
    # Check can be done in test body if needed


def check_log_errors(start_time: str) -> list[str]:
    """Query OSLog for errors since start_time."""
    try:
        result = subprocess.run(
            ["log", "show", "--predicate",
             'subsystem == "com.ghosttyide" AND level == error',
             "--start", start_time, "--style", "compact"],
            capture_output=True, text=True, timeout=10,
        )
        return [
            line for line in result.stdout.strip().split("\n")
            if line.strip() and not line.startswith("Filtering") and not line.startswith("Timestamp")
        ]
    except (subprocess.TimeoutExpired, FileNotFoundError, PermissionError):
        return []
