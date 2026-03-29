"""CLI binary integration tests."""

import json
import uuid

import pytest
from conftest import RUN_ID, _send_command


# --- App commands ---


def test_cli_help(cli):
    r = cli("--help")
    assert r.returncode == 0
    assert "pane" in r.stdout


def test_cli_app_version(cli):
    r = cli("app", "version")
    assert r.returncode == 0
    assert "GhosttyIDE" in r.stdout


def test_cli_app_version_json(cli):
    r = cli("app", "version", "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    assert data["ok"]
    assert "version" in data["data"]


def test_cli_commands(cli):
    r = cli("commands")
    assert r.returncode == 0
    assert "pane.list" in r.stdout
    assert "pane.focus-direction" in r.stdout


def test_cli_raw(cli):
    r = cli("raw", "app.pid", "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    assert data["ok"]


def test_cli_app_pid(cli):
    r = cli("app", "pid")
    assert r.returncode == 0
    # CLI outputs just the PID number
    assert r.stdout.strip().isdigit()


def test_cli_app_pid_json(cli):
    r = cli("app", "pid", "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    assert data["ok"]
    assert isinstance(data["data"]["pid"], int)


def test_cli_error_exit_code(cli):
    r = cli("pane", "focus", "bad-uuid")
    assert r.returncode != 0


# --- Pane commands ---


def test_cli_pane_list(cli):
    r = cli("pane", "list")
    assert r.returncode == 0


def test_cli_pane_list_json(cli):
    r = cli("pane", "list", "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    assert data["ok"]
    assert isinstance(data["data"]["panes"], list)


def test_cli_pane_split(cli):
    r = cli("pane", "split", "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    new_id = data["data"].get("new_pane_id") or data["data"].get("id")
    if new_id:
        cli("pane", "close", new_id)


def test_cli_pane_split_direction(cli):
    r = cli("pane", "split", "-d", "down", "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    new_id = data["data"].get("new_pane_id") or data["data"].get("id")
    if new_id:
        cli("pane", "close", new_id)


def test_cli_pane_focus(cli):
    r = cli("pane", "list", "--json")
    data = json.loads(r.stdout)
    panes = data["data"]["panes"]
    if panes:
        r2 = cli("pane", "focus", panes[0]["id"])
        assert r2.returncode == 0


def test_cli_pane_close_bad_id(cli):
    r = cli("pane", "close", "00000000-0000-0000-0000-000000000000")
    assert r.returncode != 0


def test_cli_pane_focus_direction(cli):
    r = cli("pane", "focus-direction", "left")
    # May fail if not key window
    if r.returncode != 0:
        assert "no active terminal surface" in (r.stderr + r.stdout).lower()


def test_cli_pane_focus_direction_missing(cli):
    r = cli("pane", "focus-direction")
    assert r.returncode != 0


# --- Project commands ---


def test_cli_project_save(cli):
    name = f"_cli_proj_{uuid.uuid4().hex[:8]}"
    r = cli("project", "save", name)
    assert r.returncode == 0
    assert "Saved project" in r.stdout
    cli("project", "delete", name)


def test_cli_project_save_json(cli):
    name = f"_cli_proj_{uuid.uuid4().hex[:8]}"
    r = cli("project", "save", name, "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    assert data["ok"]
    assert "windows" in data["data"]
    cli("project", "delete", name)


def test_cli_project_list(cli):
    name = f"_cli_proj_{uuid.uuid4().hex[:8]}"
    cli("project", "save", name)
    r = cli("project", "list")
    assert r.returncode == 0
    assert name in r.stdout
    cli("project", "delete", name)


def test_cli_project_list_json(cli):
    r = cli("project", "list", "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    assert data["ok"]


def test_cli_project_delete(cli):
    name = f"_cli_proj_{uuid.uuid4().hex[:8]}"
    cli("project", "save", name)
    r = cli("project", "delete", name)
    assert r.returncode == 0
    assert "Deleted" in r.stdout


def test_cli_project_rename(cli, send, make_workspace, switch_project):
    _, proj, _ = make_workspace()
    switch_project(proj)
    new_name = proj + "_cliren"
    r = cli("project", "rename", proj, new_name)
    assert r.returncode == 0
    assert new_name in r.stdout
    cli("project", "rename", new_name, proj)


def test_cli_project_rename_json(cli, send, make_workspace, switch_project):
    _, proj, _ = make_workspace()
    switch_project(proj)
    new_name = proj + "_cliren2"
    r = cli("project", "rename", proj, new_name, "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    assert data["ok"]
    assert data["data"]["new_name"] == new_name
    cli("project", "rename", new_name, proj)


# --- Notify commands ---


def test_cli_notify_send(cli):
    r = cli("notify", "send", "CLI Test", "--body", "Hello")
    assert r.returncode == 0
    assert "Notification sent" in r.stdout


def test_cli_notify_send_with_pane(cli):
    r = cli("notify", "send", "Pane CLI", "--body", "With pane", "--pane", "cli-pane-1")
    assert r.returncode == 0


def test_cli_notify_list_json(cli):
    r = cli("notify", "list", "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    assert "notifications" in data["data"]


def test_cli_notify_clear(cli):
    r = cli("notify", "clear")
    assert r.returncode == 0
    assert "cleared" in r.stdout.lower()


def test_cli_notify_status(cli):
    r = cli("notify", "status")
    assert r.returncode == 0
    assert "Unread panes:" in r.stdout


def test_cli_notify_status_json(cli):
    r = cli("notify", "status", "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    assert "unread_count" in data["data"]


# --- Status commands ---


def test_cli_status_set(cli):
    pane_id = f"cli-st-{uuid.uuid4().hex[:8]}"
    r = cli("status", "set", "test_key", "test_value", "--pane", pane_id)
    assert r.returncode == 0
    assert "Status set" in r.stdout


def test_cli_status_list_json(cli):
    r = cli("status", "list", "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    assert "statuses" in data["data"]


def test_cli_status_list_filtered(cli):
    pane_id = f"cli-st-{uuid.uuid4().hex[:8]}"
    cli("status", "set", "k", "v", "--pane", pane_id)
    r = cli("status", "list", "--pane", pane_id, "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    assert all(s["pane_id"] == pane_id for s in data["data"]["statuses"])


def test_cli_status_clear(cli):
    r = cli("status", "clear")
    assert r.returncode == 0
    assert "cleared" in r.stdout.lower()


# --- Workspace commands ---


def test_cli_workspace_new(cli, send):
    ws = f"_cli_ws_{uuid.uuid4().hex[:8]}"
    proj = f"_cli_proj_{uuid.uuid4().hex[:8]}"
    r = cli("workspace", "new", ws, "--project", proj)
    assert r.returncode == 0
    assert "Created workspace" in r.stdout
    try:
        send({"command": "workspace.remove", "args": {"name": ws}})
    except Exception:
        pass


def test_cli_workspace_list(cli, send, make_workspace, switch_project):
    name, proj, _ = make_workspace()
    switch_project(proj)
    r = cli("workspace", "list")
    assert r.returncode == 0
    assert name in r.stdout


def test_cli_workspace_list_json(cli, send, make_workspace, switch_project):
    name, proj, _ = make_workspace()
    switch_project(proj)
    r = cli("workspace", "list", "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    assert data["ok"]


def test_cli_workspace_switch(cli, send, make_workspace, switch_project):
    name, proj, _ = make_workspace()
    switch_project(proj)
    r = cli("workspace", "switch", name)
    assert r.returncode == 0
    assert "Switched" in r.stdout


def test_cli_workspace_rename(cli, send, make_workspace, switch_project):
    name, proj, _ = make_workspace()
    switch_project(proj)
    renamed = name + "ren"
    r = cli("workspace", "rename", name, renamed)
    assert r.returncode == 0
    assert "Renamed" in r.stdout
    try:
        send({"command": "workspace.remove", "args": {"name": renamed}})
    except Exception:
        pass


def test_cli_workspace_meta_set(cli, send, make_workspace, switch_project):
    name, proj, _ = make_workspace()
    switch_project(proj)
    r = cli("workspace", "meta", "set", name, "ports", "3000")
    assert r.returncode == 0
    assert "Set" in r.stdout


def test_cli_workspace_meta_clear(cli, send, make_workspace, switch_project):
    name, proj, _ = make_workspace()
    switch_project(proj)
    cli("workspace", "meta", "set", name, "ports", "3000")
    r = cli("workspace", "meta", "clear", name, "ports")
    assert r.returncode == 0
    assert "Cleared" in r.stdout


def test_cli_workspace_next(cli, send, make_workspace, switch_project):
    _, proj, _ = make_workspace()
    make_workspace(project=proj)
    switch_project(proj)
    r = cli("workspace", "next")
    assert r.returncode == 0


def test_cli_workspace_previous(cli, send, make_workspace, switch_project):
    _, proj, _ = make_workspace()
    make_workspace(project=proj)
    switch_project(proj)
    r = cli("workspace", "previous")
    assert r.returncode == 0


def test_cli_workspace_move_next(cli, send, make_workspace, switch_project):
    _, proj, _ = make_workspace()
    make_workspace(project=proj)
    switch_project(proj)
    r = cli("workspace", "move-next")
    assert r.returncode == 0


def test_cli_workspace_move_previous(cli, send, make_workspace, switch_project):
    _, proj, _ = make_workspace()
    make_workspace(project=proj)
    switch_project(proj)
    r = cli("workspace", "move-previous")
    assert r.returncode == 0


def test_cli_workspace_project_switch(cli, send, make_workspace):
    _, proj, _ = make_workspace()
    r = cli("workspace", "project-switch", proj)
    assert r.returncode == 0
    assert "Switched to project" in r.stdout


def test_cli_workspace_break_pane(cli, send, make_workspace, switch_project):
    _, proj, _ = make_workspace()
    switch_project(proj)
    r = cli("workspace", "break-pane")
    assert r.returncode == 0
    assert "Moved pane to new workspace" in r.stdout
    # Clean up the auto-created workspace
    r2 = cli("workspace", "list", "--json")
    if r2.returncode == 0:
        data = json.loads(r2.stdout)
        for ws in data["data"]["workspaces"]:
            if ws["name"].startswith("Pane-"):
                try:
                    send({"command": "workspace.remove", "args": {"name": ws["name"]}})
                except Exception:
                    pass


# --- Session commands ---


def test_cli_session_save(cli):
    r = cli("session", "save")
    assert r.returncode == 0
    assert "Session saved" in r.stdout


def test_cli_session_info(cli):
    cli("session", "save")
    r = cli("session", "info")
    assert r.returncode == 0
    assert "Session:" in r.stdout


def test_cli_session_info_json(cli):
    cli("session", "save")
    r = cli("session", "info", "--json")
    assert r.returncode == 0
    data = json.loads(r.stdout)
    assert data["ok"]
    assert data["data"]["exists"] is True
