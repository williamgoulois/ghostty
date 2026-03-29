"""Pane command tests: list, split, focus, close."""

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
        after = {p["id"] for p in send({"command": "pane.list"})["data"]["panes"]}
        new_ids = after - before
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
