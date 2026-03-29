"""Session command tests: save, info."""


def test_session_save(send):
    resp = send({"command": "session.save"})
    assert resp["ok"]
    assert "saved_at" in resp["data"]
    assert isinstance(resp["data"]["workspace_count"], int)


def test_session_info(send):
    send({"command": "session.save"})
    resp = send({"command": "session.info"})
    assert resp["ok"]
    assert resp["data"]["exists"] is True
    for key in ["saved_at", "version", "workspace_count", "active_project", "active_workspace"]:
        assert key in resp["data"]


def test_session_info_structure(send):
    send({"command": "session.save"})
    resp = send({"command": "session.info"})
    assert resp["ok"]
    assert isinstance(resp["data"]["workspaces"], list)
    assert isinstance(resp["data"]["projects"], list)
    assert resp["data"]["version"] == 1


def test_session_save_idempotent(send):
    resp1 = send({"command": "session.save"})
    assert resp1["ok"]
    resp2 = send({"command": "session.save"})
    assert resp2["ok"]
