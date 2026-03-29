"""Workspace command tests: new, switch, rename, meta, break-pane."""

import pytest
from conftest import RUN_ID


class TestWorkspaceNew:
    def test_new(self, send, make_workspace):
        name, proj, resp = make_workspace()
        assert resp["data"]["name"] == name

    def test_new_with_options(self, send, make_workspace):
        name, proj, resp = make_workspace(color="#FF0000", emoji="🔥")
        assert resp["data"]["name"] == name

    def test_new_missing_name(self, send):
        resp = send({"command": "workspace.new"})
        assert not resp["ok"]

    def test_new_empty_name(self, send):
        resp = send({"command": "workspace.new", "args": {"name": ""}})
        assert not resp["ok"]


class TestWorkspaceList:
    def test_list(self, send, make_workspace, switch_project):
        name, proj, _ = make_workspace()
        switch_project(proj)
        resp = send({"command": "workspace.list"})
        assert resp["ok"]
        names = [w["name"] for w in resp["data"]["workspaces"]]
        assert name in names

    def test_list_structure(self, send, make_workspace, switch_project):
        """Validate workspace.list response field structure."""
        name, proj, _ = make_workspace()
        switch_project(proj)
        resp = send({"command": "workspace.list"})
        assert resp["ok"]
        ws = next(w for w in resp["data"]["workspaces"] if w["name"] == name)
        for key in ["name", "project", "is_active"]:
            assert key in ws, f"Missing field '{key}' in workspace"
        assert isinstance(ws["is_active"], bool)
        assert ws["project"] == proj


class TestWorkspaceSwitch:
    def test_switch(self, send, make_workspace, switch_project):
        name, proj, _ = make_workspace()
        switch_project(proj)
        resp = send({"command": "workspace.switch", "args": {"name": name}})
        assert resp["ok"]

    def test_visited_after_switch(self, send, make_workspace, switch_project):
        name, proj, _ = make_workspace()
        switch_project(proj)
        send({"command": "workspace.switch", "args": {"name": name}})
        resp = send({"command": "workspace.list"})
        ws = next(w for w in resp["data"]["workspaces"] if w["name"] == name)
        assert ws.get("visited", ws.get("is_active", False)) is True, \
            "Workspace should be visited after switch"

    def test_switch_not_found(self, send):
        resp = send({"command": "workspace.switch", "args": {"name": "nonexistent_ws_xyz"}})
        assert not resp["ok"]

    def test_next(self, send, make_workspace, switch_project):
        _, proj, _ = make_workspace()
        make_workspace(project=proj)
        switch_project(proj)
        resp = send({"command": "workspace.next"})
        assert resp["ok"]

    def test_previous(self, send, make_workspace, switch_project):
        _, proj, _ = make_workspace()
        make_workspace(project=proj)
        switch_project(proj)
        resp = send({"command": "workspace.previous"})
        assert resp["ok"]


class TestWorkspaceMove:
    def test_move_next(self, send, make_workspace, switch_project):
        name_a, proj, _ = make_workspace()
        name_b, _, _ = make_workspace(project=proj)
        switch_project(proj)
        send({"command": "workspace.switch", "args": {"name": name_a}})
        resp = send({"command": "workspace.move-next"})
        assert resp["ok"]

    def test_move_previous(self, send, make_workspace, switch_project):
        name_a, proj, _ = make_workspace()
        name_b, _, _ = make_workspace(project=proj)
        switch_project(proj)
        send({"command": "workspace.switch", "args": {"name": name_b}})
        resp = send({"command": "workspace.move-previous"})
        assert resp["ok"]

    def test_move_next_single_workspace(self, send, make_workspace, switch_project):
        """Move-next with only one workspace — verifies app doesn't crash."""
        name, proj, _ = make_workspace()
        switch_project(proj)
        send({"command": "workspace.switch", "args": {"name": name}})
        try:
            resp = send({"command": "workspace.move-next"})
        except (ConnectionError, OSError):
            pytest.fail("workspace.move-next crashed the app with a single workspace")
        assert isinstance(resp.get("ok"), bool)

    def test_move_previous_single_workspace(self, send, make_workspace, switch_project):
        """Move-previous with only one workspace — verifies app doesn't crash."""
        name, proj, _ = make_workspace()
        switch_project(proj)
        send({"command": "workspace.switch", "args": {"name": name}})
        try:
            resp = send({"command": "workspace.move-previous"})
        except (ConnectionError, OSError):
            pytest.fail("workspace.move-previous crashed the app with a single workspace")
        assert isinstance(resp.get("ok"), bool)


class TestWorkspaceRename:
    def test_rename(self, send, make_workspace, switch_project):
        name, proj, _ = make_workspace()
        switch_project(proj)
        new_name = name + "_ren"
        resp = send({"command": "workspace.rename", "args": {"name": name, "new_name": new_name}})
        assert resp["ok"]
        assert resp["data"]["new_name"] == new_name
        # Cleanup will try original name, also remove renamed
        try:
            send({"command": "workspace.remove", "args": {"name": new_name}})
        except Exception:
            pass

    def test_rename_not_found(self, send):
        resp = send({"command": "workspace.rename", "args": {"name": "nonexistent_ws", "new_name": "foo"}})
        assert not resp["ok"]


class TestWorkspaceMeta:
    def test_set(self, send, make_workspace, switch_project):
        name, proj, _ = make_workspace()
        switch_project(proj)
        resp = send({"command": "workspace.meta.set", "args": {
            "workspace": name, "key": "branch", "value": "main",
        }})
        assert resp["ok"]

    def test_set_with_url(self, send, make_workspace, switch_project):
        name, proj, _ = make_workspace()
        switch_project(proj)
        resp = send({"command": "workspace.meta.set", "args": {
            "workspace": name, "key": "pr", "value": "#42",
            "icon": "arrow.triangle.pull", "url": "https://github.com/test/42",
        }})
        assert resp["ok"]

    def test_set_empty_key(self, send, make_workspace, switch_project):
        name, proj, _ = make_workspace()
        switch_project(proj)
        resp = send({"command": "workspace.meta.set", "args": {
            "workspace": name, "key": "", "value": "test",
        }})
        assert not resp["ok"]

    def test_visible_in_list(self, send, make_workspace, switch_project):
        name, proj, _ = make_workspace()
        switch_project(proj)
        send({"command": "workspace.meta.set", "args": {
            "workspace": name, "key": "port", "value": "3000",
        }})
        resp = send({"command": "workspace.list"})
        ws = next(w for w in resp["data"]["workspaces"] if w["name"] == name)
        assert "port" in ws["metadata"]
        assert ws["metadata"]["port"]["value"] == "3000"

    def test_set_not_found(self, send):
        resp = send({"command": "workspace.meta.set", "args": {
            "workspace": "nonexistent_ws", "key": "k", "value": "v",
        }})
        assert not resp["ok"]

    def test_clear(self, send, make_workspace, switch_project):
        name, proj, _ = make_workspace()
        switch_project(proj)
        send({"command": "workspace.meta.set", "args": {
            "workspace": name, "key": "k", "value": "v",
        }})
        resp = send({"command": "workspace.meta.clear", "args": {
            "workspace": name, "key": "k",
        }})
        assert resp["ok"]

    def test_clear_not_found(self, send):
        resp = send({"command": "workspace.meta.clear", "args": {
            "workspace": "nonexistent_ws", "key": "k",
        }})
        assert not resp["ok"]


class TestWorkspaceRemove:
    def test_remove_falls_back(self, send, make_workspace, switch_project):
        """Remove active workspace -> falls back to another in same project."""
        proj = f"_t_fallback_{RUN_ID}"
        name_a, _, _ = make_workspace(project=proj)
        name_b, _, _ = make_workspace(project=proj)
        switch_project(proj)
        send({"command": "workspace.switch", "args": {"name": name_b}})

        resp = send({"command": "workspace.remove", "args": {"name": name_b}})
        assert resp["ok"]

        resp = send({"command": "workspace.list"})
        active = next((w for w in resp["data"]["workspaces"] if w["is_active"]), None)
        assert active is not None
        assert active["name"] == name_a

    def test_remove_nonexistent(self, send):
        resp = send({"command": "workspace.remove", "args": {"name": "nonexistent_ws_xyz_999"}})
        assert not resp["ok"]

    def test_remove_missing_name(self, send):
        resp = send({"command": "workspace.remove"})
        assert not resp["ok"]


class TestWorkspaceBreakPane:
    def test_break_pane(self, send, make_workspace, switch_project):
        name, proj, _ = make_workspace()
        switch_project(proj)
        send({"command": "workspace.switch", "args": {"name": name}})
        resp = send({"command": "workspace.break-pane"})
        assert resp["ok"]
        assert "workspace" in resp["data"]
        # Clean up the auto-created workspace
        new_ws = resp["data"]["workspace"]
        try:
            send({"command": "workspace.remove", "args": {"name": new_ws}})
        except Exception:
            pass

    def test_break_pane_response_format(self, send):
        resp = send({"command": "workspace.break-pane"})
        assert resp["ok"]
        assert isinstance(resp["data"]["workspace"], str)
        try:
            send({"command": "workspace.remove", "args": {"name": resp["data"]["workspace"]}})
        except Exception:
            pass
