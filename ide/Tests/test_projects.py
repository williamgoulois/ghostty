"""Project command tests: save, restore, list, delete, rename."""

import uuid

import pytest
from conftest import RUN_ID, _send_command


class TestProjectCRUD:
    """Project save/list/restore/delete lifecycle.
    Uses make_workspace to ensure a terminal window exists before saving."""

    def test_save(self, send, make_workspace, switch_project):
        name = f"_t_proj_save_{uuid.uuid4().hex[:6]}"
        _, proj, _ = make_workspace()
        switch_project(proj)
        resp = send({"command": "project.save", "args": {"name": name}})
        assert resp["ok"]
        assert resp["data"]["name"] == name
        send({"command": "project.delete", "args": {"name": name}})

    def test_list(self, send, make_workspace, switch_project):
        name = f"_t_proj_list_{uuid.uuid4().hex[:6]}"
        _, proj, _ = make_workspace()
        switch_project(proj)
        send({"command": "project.save", "args": {"name": name}})
        resp = send({"command": "project.list"})
        assert resp["ok"]
        names = [p["name"] for p in resp["data"]["projects"]]
        assert name in names
        send({"command": "project.delete", "args": {"name": name}})

    def test_list_structure(self, send, make_workspace, switch_project):
        """Validate project.list response field structure."""
        name = f"_t_proj_struct_{uuid.uuid4().hex[:6]}"
        _, proj, _ = make_workspace()
        switch_project(proj)
        send({"command": "project.save", "args": {"name": name}})
        resp = send({"command": "project.list"})
        assert resp["ok"]
        proj_data = next(p for p in resp["data"]["projects"] if p["name"] == name)
        for key in ["name", "windows", "panes", "saved_at"]:
            assert key in proj_data, f"Missing field '{key}' in project"
        assert isinstance(proj_data["windows"], int)
        assert isinstance(proj_data["panes"], int)
        send({"command": "project.delete", "args": {"name": name}})

    def test_restore(self, send, make_workspace, switch_project):
        name = f"_t_proj_restore_{uuid.uuid4().hex[:6]}"
        _, proj, _ = make_workspace()
        switch_project(proj)
        send({"command": "project.save", "args": {"name": name}})
        send({"command": "project.close-all"})
        resp = send({"command": "project.restore", "args": {"name": name}})
        assert resp["ok"]
        send({"command": "project.delete", "args": {"name": name}})

    def test_delete(self, send, make_workspace, switch_project):
        name = f"_t_proj_del_{uuid.uuid4().hex[:6]}"
        _, proj, _ = make_workspace()
        switch_project(proj)
        send({"command": "project.save", "args": {"name": name}})
        resp = send({"command": "project.delete", "args": {"name": name}})
        assert resp["ok"]



class TestProjectValidation:
    """Project input validation and error handling."""

    @pytest.mark.parametrize("args,error_fragment", [
        ({}, "name"),                                          # missing name
        ({"name": ""}, ""),                                    # empty name
        ({"name": "bad/name"}, ""),                            # invalid chars
        ({"name": "has spaces"}, ""),                          # spaces
    ])
    def test_save_invalid(self, send, args, error_fragment):
        resp = send({"command": "project.save", "args": args})
        assert not resp["ok"]
        if error_fragment:
            assert error_fragment.lower() in resp["error"].lower()

    def test_restore_not_found(self, send):
        resp = send({"command": "project.restore", "args": {"name": "nonexistent_xyz"}})
        assert not resp["ok"]

    def test_delete_not_found(self, send):
        resp = send({"command": "project.delete", "args": {"name": "nonexistent_xyz"}})
        assert not resp["ok"]


class TestProjectRename:
    """Project rename operations."""

    def test_rename(self, send, make_workspace, switch_project):
        ws_name, proj, _ = make_workspace()
        switch_project(proj)
        new_name = proj + "_renamed"
        resp = send({"command": "project.rename", "args": {"name": proj, "new_name": new_name}})
        assert resp["ok"]
        assert resp["data"]["new_name"] == new_name
        # Rename back so workspace cleanup works
        send({"command": "project.rename", "args": {"name": new_name, "new_name": proj}})

    def test_rename_not_found(self, send):
        resp = send({"command": "project.rename", "args": {"name": "nonexistent_xyz", "new_name": "foo"}})
        assert not resp["ok"]

    def test_rename_missing_args(self, send):
        resp = send({"command": "project.rename"})
        assert not resp["ok"]

    def test_rename_same_name(self, send, make_workspace, switch_project):
        _, proj, _ = make_workspace()
        switch_project(proj)
        resp = send({"command": "project.rename", "args": {"name": proj, "new_name": proj}})
        assert not resp["ok"]


class TestProjectSwitch:
    def test_switch(self, send, make_workspace, switch_project):
        _, proj, _ = make_workspace()
        resp = send({"command": "project.switch", "args": {"name": proj}})
        assert resp["ok"]

    def test_switch_missing_name(self, send):
        resp = send({"command": "project.switch"})
        assert not resp["ok"]
