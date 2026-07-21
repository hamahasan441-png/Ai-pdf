"""Tests for the admin usage dashboard (Part 5.8)."""

AUTH = "/api/v1/auth"
TEAMS = "/api/v1/teams"
ADMIN = "/api/v1/admin/usage"


async def _register(client, email, password="password123", name="User"):
    resp = await client.post(
        f"{AUTH}/register",
        json={"email": email, "password": password, "full_name": name},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["access_token"]


async def test_admin_disabled_without_token(client, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "ADMIN_API_TOKEN", "")
    resp = await client.get(ADMIN)
    assert resp.status_code == 503


async def test_admin_rejects_wrong_token(client, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "ADMIN_API_TOKEN", "s3cret")
    resp = await client.get(ADMIN, headers={"X-Admin-Token": "wrong"})
    assert resp.status_code == 401

    missing = await client.get(ADMIN)
    assert missing.status_code == 401


async def test_admin_usage_reports_counts(client, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "ADMIN_API_TOKEN", "s3cret")

    owner = await _register(client, "owner@example.com")
    await _register(client, "member@example.com")
    team_id = (await client.post(TEAMS, headers={"Authorization": f"Bearer {owner}"}, json={"name": "Acme"})).json()["id"]
    await client.post(
        f"{TEAMS}/{team_id}/members",
        headers={"Authorization": f"Bearer {owner}"},
        json={"email": "member@example.com", "role": "member"},
    )
    await client.post(
        f"{TEAMS}/{team_id}/templates",
        headers={"Authorization": f"Bearer {owner}"},
        json={"name": "W-9", "content": {}},
    )

    resp = await client.get(ADMIN, headers={"X-Admin-Token": "s3cret"})
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["total_users"] == 2
    assert body["active_users"] == 2
    assert body["total_teams"] == 1
    assert body["total_team_members"] == 2
    assert body["total_shared_templates"] == 1
    assert body["active_entitlements"] == 0
    assert body["ai_free_daily_limit"] >= 1
