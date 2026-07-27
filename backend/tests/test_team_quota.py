"""Tests for per-team AI quota — E8.1 Enhancement-Based Masterplan."""

AUTH = "/api/v1/auth"
TEAMS = "/api/v1/teams"


async def _register(client, email, password="password123", name="User"):
    resp = await client.post(
        f"{AUTH}/register",
        json={"email": email, "password": password, "full_name": name},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["access_token"]


def _hdr(token):
    return {"Authorization": f"Bearer {token}"}


async def test_team_quota_default_none(client):
    token = await _register(client, "owner_q@example.com")
    team = (await client.post(TEAMS, headers=_hdr(token), json={"name": "QuotaTeam"})).json()
    assert team["ai_daily_quota"] is None
    assert team["sso_required"] is False


async def test_team_quota_update(client):
    token = await _register(client, "owner_q2@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(token), json={"name": "QuotaTeam2"})).json()["id"]

    # Update quota to 500
    upd = await client.put(
        f"{TEAMS}/{team_id}/quota", headers=_hdr(token), json={"ai_daily_quota": 500}
    )
    assert upd.status_code == 200, upd.text
    assert upd.json()["ai_daily_quota"] == 500

    # Check detail
    detail = await client.get(f"{TEAMS}/{team_id}", headers=_hdr(token))
    assert detail.json()["ai_daily_quota"] == 500

    # List includes quota
    listed = await client.get(TEAMS, headers=_hdr(token))
    found = [t for t in listed.json() if t["id"] == team_id][0]
    assert found["ai_daily_quota"] == 500


async def test_team_quota_invalid(client):
    token = await _register(client, "owner_q3@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(token), json={"name": "QuotaTeam3"})).json()["id"]

    bad = await client.put(
        f"{TEAMS}/{team_id}/quota", headers=_hdr(token), json={"ai_daily_quota": 0}
    )
    # Should be 422 or 400
    assert bad.status_code in (400, 422)


async def test_team_quota_requires_manager(client):
    owner = await _register(client, "owner_q4@example.com")
    member = await _register(client, "member_q4@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(owner), json={"name": "QuotaTeam4"})).json()["id"]

    # Add member
    await client.post(
        f"{TEAMS}/{team_id}/members",
        headers=_hdr(owner),
        json={"email": "member_q4@example.com", "role": "member"},
    )
    # Member cannot update quota
    upd = await client.put(
        f"{TEAMS}/{team_id}/quota", headers=_hdr(member), json={"ai_daily_quota": 100}
    )
    assert upd.status_code in (401, 403)


async def test_team_sso_flag(client):
    token = await _register(client, "owner_sso@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(token), json={"name": "SSOTeam"})).json()["id"]

    upd = await client.put(
        f"{TEAMS}/{team_id}/quota", headers=_hdr(token), json={"sso_required": True}
    )
    assert upd.status_code == 200
    assert upd.json()["sso_required"] is True
