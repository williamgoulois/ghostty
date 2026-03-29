"""Notification command tests: send, list, clear, status."""

import time
import uuid

import pytest


@pytest.fixture(autouse=True)
def clear_notifications(send):
    """Clear all notifications before and after each test."""
    send({"command": "notify.clear"})
    yield
    send({"command": "notify.clear"})


class TestNotifySend:
    def test_send(self, send):
        resp = send({"command": "notify.send", "args": {"title": "Test", "body": "Hello"}})
        assert resp["ok"]
        assert "notification_id" in resp["data"]
        assert resp["data"]["title"] == "Test"

    def test_send_title_only(self, send):
        resp = send({"command": "notify.send", "args": {"title": "Title Only"}})
        assert resp["ok"]

    def test_send_with_pane(self, send):
        resp = send({"command": "notify.send", "args": {
            "title": "Pane Test", "pane_id": "00000000-0000-0000-0000-000000000000",
        }})
        assert resp["ok"]

    def test_send_missing_title(self, send):
        resp = send({"command": "notify.send"})
        assert not resp["ok"]
        assert "title" in resp["error"].lower()

    def test_send_empty_title(self, send):
        resp = send({"command": "notify.send", "args": {"title": ""}})
        assert not resp["ok"]


class TestNotifyList:
    def test_list(self, send):
        send({"command": "notify.send", "args": {"title": "For list test"}})
        resp = send({"command": "notify.list"})
        assert resp["ok"]
        assert isinstance(resp["data"]["notifications"], list)
        assert len(resp["data"]["notifications"]) == 1
        n = resp["data"]["notifications"][0]
        for key in ["id", "title", "body", "timestamp"]:
            assert key in n, f"Missing key '{key}'"


class TestNotifyClear:
    def test_clear(self, send):
        send({"command": "notify.send", "args": {"title": "To clear"}})
        resp = send({"command": "notify.clear"})
        assert resp["ok"]
        resp2 = send({"command": "notify.list"})
        assert len(resp2["data"]["notifications"]) == 0


class TestNotifyPaneTracking:
    def test_tracks_pane_unread(self, send):
        pane_id = f"test-pane-{uuid.uuid4().hex[:8]}"
        send({"command": "notify.send", "args": {"title": "Pane unread", "pane_id": pane_id}})
        time.sleep(0.3)  # @Published propagation
        resp = send({"command": "notify.status"})
        assert resp["ok"]
        assert pane_id in resp["data"]["unread_pane_ids"]
        assert resp["data"]["unread_count"] >= 1

    def test_clear_resets_pane_unread(self, send):
        pane_id = f"test-pane-{uuid.uuid4().hex[:8]}"
        send({"command": "notify.send", "args": {"title": "Clear test", "pane_id": pane_id}})
        time.sleep(0.3)
        send({"command": "notify.clear"})
        time.sleep(0.3)
        resp = send({"command": "notify.status"})
        assert resp["ok"]
        assert resp["data"]["unread_count"] == 0
        assert len(resp["data"]["unread_pane_ids"]) == 0
