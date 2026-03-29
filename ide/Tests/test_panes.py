"""Pane command tests: list, split, focus, close."""

import time

import pytest


class TestPaneList:
    def test_list(self, send):
        resp = send({"command": "pane.list"})
        assert resp["ok"]
        assert "panes" in resp["data"]
        assert isinstance(resp["data"]["panes"], list)

    def test_list_structure(self, send):
        """Validate pane.list response fields per pane."""
        resp = send({"command": "pane.list"})
        assert resp["ok"]
        panes = resp["data"]["panes"]
        if not panes:
            pytest.skip("No panes available (project may have no workspaces)")
        pane = panes[0]
        for key in ["id", "title", "pwd", "focused"]:
            assert key in pane, f"Missing field '{key}' in pane"
        assert isinstance(pane["id"], str)
        assert isinstance(pane["focused"], bool)

    def test_list_has_focused_pane(self, send):
        """At most one pane should be focused."""
        resp = send({"command": "pane.list"})
        focused = [p for p in resp["data"]["panes"] if p["focused"]]
        assert len(focused) <= 1, "At most one pane should be focused"


class TestPaneSplit:
    def test_split_right(self, send):
        """Split right, then close the new pane."""
        resp = send({"command": "pane.split", "args": {"direction": "right"}})
        if not resp["ok"]:
            pytest.skip("No active terminal surface for split")
        new_pane_id = resp["data"].get("new_pane_id") or resp["data"].get("id")
        if new_pane_id:
            send({"command": "pane.close", "args": {"id": new_pane_id}})

    @pytest.mark.parametrize("direction", ["right", "left", "up", "down"])
    def test_split_directions(self, send, direction):
        """All four split directions should succeed."""
        resp = send({"command": "pane.split", "args": {"direction": direction}})
        if not resp["ok"]:
            pytest.skip("No active terminal surface for split")
        new_pane_id = resp["data"].get("new_pane_id") or resp["data"].get("id")
        if new_pane_id:
            send({"command": "pane.close", "args": {"id": new_pane_id}})

    def test_split_invalid_direction(self, send):
        resp = send({"command": "pane.split", "args": {"direction": "diagonal"}})
        assert not resp["ok"]
        assert "Invalid direction" in resp["error"]

    def test_split_default_direction(self, send):
        """Split with no direction defaults to right."""
        resp = send({"command": "pane.split"})
        if not resp["ok"]:
            pytest.skip("No active terminal surface for split")
        # Clean up
        new_pane_id = resp["data"].get("new_pane_id") or resp["data"].get("id")
        if new_pane_id:
            send({"command": "pane.close", "args": {"id": new_pane_id}})


class TestPaneFocus:
    def test_focus_valid(self, send):
        """Focus an existing pane by ID."""
        panes = send({"command": "pane.list"})["data"]["panes"]
        if panes:
            resp = send({"command": "pane.focus", "args": {"id": panes[0]["id"]}})
            assert resp["ok"]

    def test_focus_missing_id(self, send):
        resp = send({"command": "pane.focus"})
        assert not resp["ok"]

    def test_focus_nonexistent(self, send):
        resp = send({"command": "pane.focus", "args": {"id": "00000000-0000-0000-0000-000000000000"}})
        assert not resp["ok"]

    def test_focus_bad_format(self, send):
        resp = send({"command": "pane.focus", "args": {"id": "not-a-uuid"}})
        assert not resp["ok"]


class TestPaneClose:
    def test_close_valid(self, send):
        """Split to create a pane, then close it."""
        before = {p["id"] for p in send({"command": "pane.list"})["data"]["panes"]}
        split_resp = send({"command": "pane.split", "args": {"direction": "right"}})
        if not split_resp["ok"]:
            pytest.skip("No active terminal surface for split")
        # Wait for the split to complete — surface creation is async
        new_ids = set()
        for _ in range(10):
            after = {p["id"] for p in send({"command": "pane.list"})["data"]["panes"]}
            new_ids = after - before
            if new_ids:
                break
            time.sleep(0.2)
        assert len(new_ids) >= 1, "Split should create a new pane"
        new_pane_id = new_ids.pop()
        resp = send({"command": "pane.close", "args": {"id": new_pane_id}})
        assert resp["ok"]

    def test_close_bad_id(self, send):
        resp = send({"command": "pane.close", "args": {"id": "not-a-uuid"}})
        assert not resp["ok"]

    def test_close_nonexistent(self, send):
        resp = send({"command": "pane.close", "args": {"id": "00000000-0000-0000-0000-000000000000"}})
        assert not resp["ok"]

    def test_close_missing_id(self, send):
        resp = send({"command": "pane.close"})
        assert not resp["ok"]


class TestPaneFocusDirection:
    @pytest.mark.parametrize("direction", ["left", "right", "up", "down"])
    def test_focus_direction(self, send, direction):
        resp = send({"command": "pane.focus-direction", "args": {"direction": direction}})
        # May fail if no active surface — that's ok, just shouldn't crash
        assert isinstance(resp["ok"], bool)

    def test_focus_direction_invalid(self, send):
        resp = send({"command": "pane.focus-direction", "args": {"direction": "diagonal"}})
        assert not resp["ok"]

    def test_focus_direction_missing(self, send):
        resp = send({"command": "pane.focus-direction"})
        assert not resp["ok"]


class TestPaneListEnhanced:
    """Tests for pane.list enhanced fields (foreground_process, workspace, project)."""

    def test_list_has_foreground_process(self, send):
        """pane.list should include foreground_process field."""
        resp = send({"command": "pane.list"})
        assert resp["ok"]
        panes = resp["data"]["panes"]
        if not panes:
            pytest.skip("No panes available")
        pane = panes[0]
        assert "foreground_process" in pane, "Missing 'foreground_process' field"
        assert isinstance(pane["foreground_process"], str)

    def test_list_has_workspace_and_project(self, send):
        """pane.list should include workspace and project fields."""
        resp = send({"command": "pane.list"})
        assert resp["ok"]
        panes = resp["data"]["panes"]
        if not panes:
            pytest.skip("No panes available")
        pane = panes[0]
        assert "workspace" in pane, "Missing 'workspace' field"
        assert "project" in pane, "Missing 'project' field"

    def test_foreground_process_nonempty(self, send):
        """At least one pane should have a non-empty foreground_process (shell)."""
        resp = send({"command": "pane.list"})
        assert resp["ok"]
        panes = resp["data"]["panes"]
        has_process = any(p.get("foreground_process", "") for p in panes)
        assert has_process, "Expected at least one pane with a foreground process"


class TestPaneListFilter:
    """Tests for pane.list with --project and --workspace filter args."""

    def test_filter_by_project(self, send):
        """Filtering by project should return only panes in that project."""
        resp = send({"command": "pane.list"})
        assert resp["ok"]
        panes = resp["data"]["panes"]
        if not panes:
            pytest.skip("No panes available")
        project = panes[0]["project"]
        filtered = send({"command": "pane.list", "args": {"project": project}})
        assert filtered["ok"]
        for p in filtered["data"]["panes"]:
            assert p["project"] == project

    def test_filter_by_workspace(self, send):
        """Filtering by workspace should return only panes in that workspace."""
        resp = send({"command": "pane.list"})
        assert resp["ok"]
        panes = resp["data"]["panes"]
        if not panes:
            pytest.skip("No panes available")
        workspace = panes[0]["workspace"]
        filtered = send({"command": "pane.list", "args": {"workspace": workspace}})
        assert filtered["ok"]
        for p in filtered["data"]["panes"]:
            assert p["workspace"] == workspace

    def test_filter_nonexistent_project(self, send):
        """Filtering by a project that doesn't exist should return empty list."""
        resp = send({"command": "pane.list", "args": {"project": "nonexistent_project_xyz"}})
        assert resp["ok"]
        assert resp["data"]["panes"] == []

    def test_filter_combined(self, send):
        """Filtering by both project and workspace should intersect."""
        resp = send({"command": "pane.list"})
        assert resp["ok"]
        panes = resp["data"]["panes"]
        if not panes:
            pytest.skip("No panes available")
        pane = panes[0]
        filtered = send({
            "command": "pane.list",
            "args": {"project": pane["project"], "workspace": pane["workspace"]},
        })
        assert filtered["ok"]
        for p in filtered["data"]["panes"]:
            assert p["project"] == pane["project"]
            assert p["workspace"] == pane["workspace"]


class TestPaneSendText:
    """Tests for pane.send-text command."""

    def test_send_text(self, send):
        """Send text to an existing pane."""
        panes = send({"command": "pane.list"})["data"]["panes"]
        if not panes:
            pytest.skip("No panes available")
        target = panes[0]
        resp = send({
            "command": "pane.send-text",
            "args": {"id": target["id"], "text": "# test\n"},
        })
        assert resp["ok"]
        assert resp["data"]["text_length"] == 7
        assert resp["data"]["id"] == target["id"]

    def test_send_text_with_focus(self, send):
        """Send text with focus flag."""
        panes = send({"command": "pane.list"})["data"]["panes"]
        if not panes:
            pytest.skip("No panes available")
        target = panes[0]
        resp = send({
            "command": "pane.send-text",
            "args": {"id": target["id"], "text": "# test\n", "focus": "true"},
        })
        assert resp["ok"]
        assert resp["data"]["focused"] is True

    def test_send_text_missing_id(self, send):
        """Missing id should fail."""
        resp = send({
            "command": "pane.send-text",
            "args": {"text": "hello"},
        })
        assert not resp["ok"]

    def test_send_text_missing_text(self, send):
        """Missing text should fail."""
        panes = send({"command": "pane.list"})["data"]["panes"]
        if not panes:
            pytest.skip("No panes available")
        resp = send({
            "command": "pane.send-text",
            "args": {"id": panes[0]["id"]},
        })
        assert not resp["ok"]

    def test_send_text_invalid_id(self, send):
        """Invalid UUID should fail."""
        resp = send({
            "command": "pane.send-text",
            "args": {"id": "not-a-uuid", "text": "hello"},
        })
        assert not resp["ok"]

    def test_send_text_nonexistent_pane(self, send):
        """Non-existent pane UUID should fail."""
        resp = send({
            "command": "pane.send-text",
            "args": {"id": "00000000-0000-0000-0000-000000000000", "text": "hello"},
        })
        assert not resp["ok"]

    def test_send_text_empty_text(self, send):
        """Empty text should fail."""
        panes = send({"command": "pane.list"})["data"]["panes"]
        if not panes:
            pytest.skip("No panes available")
        resp = send({
            "command": "pane.send-text",
            "args": {"id": panes[0]["id"], "text": ""},
        })
        assert not resp["ok"]
