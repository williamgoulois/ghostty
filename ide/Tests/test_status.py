"""Status command tests: set, list, clear."""

import uuid

import pytest


@pytest.fixture(autouse=True)
def clear_status(send):
    """Clear all statuses before and after each test."""
    send({"command": "status.clear"})
    yield
    send({"command": "status.clear"})


class TestStatusSet:
    def test_set(self, send):
        pane_id = f"st-{uuid.uuid4().hex[:8]}"
        resp = send({"command": "status.set", "args": {
            "key": "agent", "value": "idle", "pane_id": pane_id,
        }})
        assert resp["ok"]
        assert resp["data"]["key"] == "agent"
        assert resp["data"]["value"] == "idle"

    def test_overwrite(self, send):
        pane_id = f"st-{uuid.uuid4().hex[:8]}"
        send({"command": "status.set", "args": {
            "key": "agent", "value": "idle", "pane_id": pane_id,
        }})
        resp = send({"command": "status.set", "args": {
            "key": "agent", "value": "working", "pane_id": pane_id,
        }})
        assert resp["ok"]
        assert resp["data"]["value"] == "working"
        # Verify only one entry
        resp2 = send({"command": "status.list", "args": {"pane_id": pane_id}})
        agent_entries = [s for s in resp2["data"]["statuses"] if s["key"] == "agent"]
        assert len(agent_entries) == 1

    def test_missing_key(self, send):
        resp = send({"command": "status.set", "args": {"value": "idle"}})
        assert not resp["ok"]
        assert "key" in resp["error"].lower()

    def test_missing_value(self, send):
        resp = send({"command": "status.set", "args": {"key": "agent"}})
        assert not resp["ok"]
        assert "value" in resp["error"].lower()


class TestStatusList:
    def test_list(self, send):
        pane1 = f"st-{uuid.uuid4().hex[:8]}"
        pane2 = f"st-{uuid.uuid4().hex[:8]}"
        send({"command": "status.set", "args": {
            "key": "agent", "value": "idle", "pane_id": pane1,
        }})
        send({"command": "status.set", "args": {
            "key": "build", "value": "running", "pane_id": pane2,
        }})
        resp = send({"command": "status.list"})
        assert resp["ok"]
        assert len(resp["data"]["statuses"]) == 2
        for s in resp["data"]["statuses"]:
            for key in ["key", "value", "pane_id", "updated_at"]:
                assert key in s

    def test_list_filtered(self, send):
        pane1 = f"st-{uuid.uuid4().hex[:8]}"
        pane2 = f"st-{uuid.uuid4().hex[:8]}"
        send({"command": "status.set", "args": {
            "key": "agent", "value": "working", "pane_id": pane1,
        }})
        send({"command": "status.set", "args": {
            "key": "build", "value": "running", "pane_id": pane2,
        }})
        resp = send({"command": "status.list", "args": {"pane_id": pane1}})
        assert resp["ok"]
        assert len(resp["data"]["statuses"]) == 1
        assert resp["data"]["statuses"][0]["key"] == "agent"


class TestStatusClear:
    def test_clear_specific(self, send):
        pane_id = f"st-{uuid.uuid4().hex[:8]}"
        send({"command": "status.set", "args": {
            "key": "agent", "value": "idle", "pane_id": pane_id,
        }})
        resp = send({"command": "status.clear", "args": {"pane_id": pane_id, "key": "agent"}})
        assert resp["ok"]
        resp2 = send({"command": "status.list", "args": {"pane_id": pane_id}})
        assert len(resp2["data"]["statuses"]) == 0

    def test_clear_all(self, send):
        pane_id = f"st-{uuid.uuid4().hex[:8]}"
        send({"command": "status.set", "args": {
            "key": "x", "value": "y", "pane_id": pane_id,
        }})
        resp = send({"command": "status.clear"})
        assert resp["ok"]
        resp2 = send({"command": "status.list"})
        assert len(resp2["data"]["statuses"]) == 0
