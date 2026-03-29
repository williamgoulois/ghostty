"""Workflow integration tests — multi-step scenarios exercising real user/agent workflows."""

import json
import os
import time

import pytest
from conftest import RUN_ID, _send_command


class TestWorkspaceLifecycle:
    """Create -> list -> switch -> rename -> meta -> clear meta -> remove."""

    def test_full_lifecycle(self, send, make_workspace, switch_project):
        name, proj, resp = make_workspace(color="#FF5500", emoji="\U0001f527")
        switch_project(proj)

        # Verify in list
        resp = send({"command": "workspace.list"})
        ws = next(w for w in resp["data"]["workspaces"] if w["name"] == name)
        assert ws["project"] == proj
        assert ws["emoji"] == "\U0001f527"

        # Switch
        resp = send({"command": "workspace.switch", "args": {"name": name}})
        assert resp["ok"]

        # Rename
        renamed = name + "_ren"
        resp = send({"command": "workspace.rename", "args": {"name": name, "new_name": renamed}})
        assert resp["ok"]
        assert resp["data"]["new_name"] == renamed

        # Set metadata
        resp = send({"command": "workspace.meta.set", "args": {
            "workspace": renamed, "key": "branch", "value": "main",
        }})
        assert resp["ok"]

        # Verify metadata
        resp = send({"command": "workspace.list"})
        ws = next(w for w in resp["data"]["workspaces"] if w["name"] == renamed)
        assert ws["metadata"]["branch"]["value"] == "main"

        # Clear metadata
        resp = send({"command": "workspace.meta.clear", "args": {
            "workspace": renamed, "key": "branch",
        }})
        assert resp["ok"]

        # Remove
        resp = send({"command": "workspace.remove", "args": {"name": renamed}})
        assert resp["ok"]

        # Verify gone
        resp = send({"command": "workspace.list"})
        names = [w["name"] for w in resp["data"]["workspaces"]]
        assert renamed not in names


class TestSessionPersistence:
    """Save -> read JSON -> verify schema -> verify session.info."""

    def test_full_persistence(self, send):
        session_path = os.path.expanduser("~/.cache/ghosttyide/session.json")

        resp = send({"command": "session.save"})
        assert resp["ok"]
        assert isinstance(resp["data"]["workspace_count"], int)

        # Read JSON file directly
        assert os.path.isfile(session_path)
        with open(session_path) as f:
            session = json.load(f)

        # Verify schema
        assert session["version"] == 1
        assert isinstance(session["savedAt"], str)
        assert isinstance(session["activeProject"], str)
        assert isinstance(session["workspaces"], list)

        if session["workspaces"]:
            ws = session["workspaces"][0]
            for field in ["name", "project", "metadata"]:
                assert field in ws, f"Missing field '{field}'"

        # Verify session.info matches
        resp = send({"command": "session.info"})
        assert resp["ok"]
        assert resp["data"]["version"] == 1
        assert resp["data"]["workspace_count"] == len(session["workspaces"])

        # Idempotent
        assert send({"command": "session.save"})["ok"]


class TestNotificationLifecycle:
    """Clear -> send 3 -> list -> status -> clear -> verify empty."""

    def test_full_lifecycle(self, send):
        pane_id = f"wf-notify-{RUN_ID}"

        send({"command": "notify.clear"})

        # Send 3 notifications
        for args in [
            {"title": "Title Only"},
            {"title": "With Body", "body": "test body"},
            {"title": "With Pane", "body": "pane notif", "pane_id": pane_id},
        ]:
            assert send({"command": "notify.send", "args": args})["ok"]

        # Verify list
        resp = send({"command": "notify.list"})
        assert len(resp["data"]["notifications"]) >= 3
        for n in resp["data"]["notifications"][-3:]:
            for key in ["id", "title", "body", "timestamp"]:
                assert key in n

        # Verify pane tracking
        time.sleep(0.3)
        resp = send({"command": "notify.status"})
        assert resp["data"]["unread_count"] >= 1
        assert pane_id in resp["data"]["unread_pane_ids"]

        # Clear and verify
        send({"command": "notify.clear"})
        time.sleep(0.3)
        resp = send({"command": "notify.list"})
        assert len(resp["data"]["notifications"]) == 0
        resp = send({"command": "notify.status"})
        assert resp["data"]["unread_count"] == 0


class TestAgentStatusLifecycle:
    """Clear -> set -> overwrite -> list -> filter -> clear specific -> clear all."""

    def test_full_lifecycle(self, send):
        pane1, pane2 = f"wf-p1-{RUN_ID}", f"wf-p2-{RUN_ID}"

        send({"command": "status.clear"})

        # Set two panes
        assert send({"command": "status.set", "args": {
            "key": "agent", "value": "idle", "pane_id": pane1}})["ok"]
        assert send({"command": "status.set", "args": {
            "key": "build", "value": "running", "pane_id": pane2}})["ok"]

        # Overwrite
        resp = send({"command": "status.set", "args": {
            "key": "agent", "value": "working", "pane_id": pane1}})
        assert resp["data"]["value"] == "working"

        # List all
        resp = send({"command": "status.list"})
        assert len(resp["data"]["statuses"]) >= 2

        # Filter
        resp = send({"command": "status.list", "args": {"pane_id": pane1}})
        assert len(resp["data"]["statuses"]) == 1
        assert resp["data"]["statuses"][0]["value"] == "working"

        # Clear specific
        send({"command": "status.clear", "args": {"pane_id": pane1, "key": "agent"}})
        resp = send({"command": "status.list", "args": {"pane_id": pane1}})
        assert len(resp["data"]["statuses"]) == 0

        # Clear all
        send({"command": "status.clear"})
        resp = send({"command": "status.list"})
        assert len(resp["data"]["statuses"]) == 0


class TestCLILifecycle:
    """Full workspace lifecycle via CLI — human + JSON output modes."""

    def test_full_lifecycle(self, cli, send, switch_project):
        ws = f"_wf_cli_{RUN_ID}_"
        proj = f"_wf_cliproj_{RUN_ID}_"
        renamed = ws + "ren"

        try:
            # Create
            r = cli("workspace", "new", ws, "--project", proj)
            assert r.returncode == 0
            assert "Created workspace" in r.stdout

            switch_project(proj)

            # List (human + JSON)
            r = cli("workspace", "list")
            assert ws in r.stdout

            r = cli("workspace", "list", "--json")
            data = json.loads(r.stdout)
            assert ws in [w["name"] for w in data["data"]["workspaces"]]

            # Rename
            r = cli("workspace", "rename", ws, renamed)
            assert r.returncode == 0
            assert "Renamed" in r.stdout

            # Set meta + verify
            r = cli("workspace", "meta", "set", renamed, "ports", "8080")
            assert r.returncode == 0

            r = cli("workspace", "list", "--json")
            data = json.loads(r.stdout)
            ws_data = next(w for w in data["data"]["workspaces"] if w["name"] == renamed)
            assert "ports" in ws_data["metadata"]

            # Remove + verify gone
            send({"command": "workspace.remove", "args": {"name": renamed}})
            r = cli("workspace", "list", "--json")
            data = json.loads(r.stdout)
            assert renamed not in [w["name"] for w in data["data"]["workspaces"]]

            # Error exit code
            r = cli("workspace", "switch", "nonexistent_xyz_999")
            assert r.returncode != 0

        finally:
            for name in [ws, renamed]:
                try:
                    _send_command({"command": "workspace.remove", "args": {"name": name}})
                except Exception:
                    pass
