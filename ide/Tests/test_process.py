"""Process and port command tests: process.kill, port.list, enriched pane.list."""

import pytest


class TestPaneListEnriched:
    """Verify pane.list now includes process_category, ports, foreground_pid."""

    def test_pane_list_has_process_category(self, send):
        resp = send({"command": "pane.list"})
        assert resp["ok"]
        for pane in resp["data"]["panes"]:
            assert "process_category" in pane
            assert pane["process_category"] in [
                "shell", "agent", "longRunning", "editor", "unknown",
            ]

    def test_pane_list_has_ports_array(self, send):
        resp = send({"command": "pane.list"})
        assert resp["ok"]
        for pane in resp["data"]["panes"]:
            assert "ports" in pane
            assert isinstance(pane["ports"], list)

    def test_pane_list_has_foreground_pid(self, send):
        resp = send({"command": "pane.list"})
        assert resp["ok"]
        for pane in resp["data"]["panes"]:
            assert "foreground_pid" in pane
            assert isinstance(pane["foreground_pid"], int)


class TestProcessKill:
    def test_kill_missing_pid(self, send):
        resp = send({"command": "process.kill"})
        assert not resp["ok"]
        assert "pid" in resp["error"].lower()

    def test_kill_nonexistent_pid(self, send):
        resp = send({"command": "process.kill", "args": {"pid": 99999}})
        assert not resp["ok"]
        assert "not found" in resp["error"].lower()

    def test_kill_invalid_pid(self, send):
        resp = send({"command": "process.kill", "args": {"pid": -1}})
        assert not resp["ok"]


class TestPortList:
    def test_port_list_returns_structure(self, send):
        resp = send({"command": "port.list"})
        assert resp["ok"]
        assert "ports" in resp["data"]
        for port in resp["data"]["ports"]:
            for key in ["port", "pid", "process", "tls", "pane_id", "workspace"]:
                assert key in port

    def test_port_list_filtered_by_workspace(self, send):
        resp = send({"command": "port.list", "args": {"workspace": "nonexistent"}})
        assert resp["ok"]
        assert resp["data"]["ports"] == []
