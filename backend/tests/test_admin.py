"""Tests for the admin usage dashboard (Part 5.8) + webhook DLQ (E7.2)."""

AUTH = "/api/v1/auth"
TEAMS = "/api/v1/teams"
ADMIN = "/api/v1/admin/usage"
ADMIN_DLQ = "/api/v1/admin/webhooks/dlq"
ADMIN_STATS = "/api/v1/admin/webhooks/stats"
ADMIN_REPLAY = "/api/v1/admin/webhooks"


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
    # Enhancement-based masterplan new fields
    assert "active_webhooks" in body
    assert "ai_basic_daily_limit" in body
    assert body["meter_backend"] in {"memory", "redis", "auto"}


async def test_admin_webhook_dlq_and_stats(client, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "ADMIN_API_TOKEN", "s3cret")

    # No token -> 401
    r = await client.get(ADMIN_DLQ, headers={"X-Admin-Token": "wrong"})
    assert r.status_code == 401

    # Empty DLQ initially
    resp = await client.get(ADMIN_DLQ, headers={"X-Admin-Token": "s3cret"})
    assert resp.status_code == 200
    data = resp.json()
    assert "dlq_count" in data
    assert "items" in data
    assert data["dlq_count"] == len(data["items"])

    stats = await client.get(ADMIN_STATS, headers={"X-Admin-Token": "s3cret"})
    assert stats.status_code == 200
    s = stats.json()
    assert s["total_webhooks"] >= 0
    assert "active_webhooks" in s


async def test_admin_webhook_replay_404(client, monkeypatch):
    from app.core.config import settings

    monkeypatch.setattr(settings, "ADMIN_API_TOKEN", "s3cret")
    fake_id = "00000000-0000-0000-0000-000000000001"
    resp = await client.post(f"{ADMIN_REPLAY}/{fake_id}/replay", headers={"X-Admin-Token": "s3cret"})
    assert resp.status_code == 404

