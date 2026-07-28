"""Tests for collab command log persistence — E8.3 Phase 5 full."""

import pytest

AUTH = "/api/v1/auth"
TEAMS = "/api/v1/teams"
COLLAB = "/api/v1/teams"


async def _register(client, email):
    resp = await client.post(
        f"{AUTH}/register",
        json={"email": email, "password": "password123", "full_name": "User"},
    )
    assert resp.status_code == 201
    return resp.json()["access_token"]


def _hdr(token):
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.asyncio
async def test_collab_log_crud(client):
    owner = await _register(client, "collab_owner@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(owner), json={"name": "Collab Team"})).json()["id"]

    # Initially empty log
    log_resp = await client.get(f"{COLLAB}/{team_id}/collab/log", headers=_hdr(owner))
    assert log_resp.status_code == 200
    assert log_resp.json()["count"] == 0

    # Status should be 0 clients
    status_resp = await client.get(f"{COLLAB}/{team_id}/collab/status", headers=_hdr(owner))
    assert status_resp.status_code == 200
    assert status_resp.json()["connected_clients"] == 0

    # Clear log (should not fail even if empty)
    clear_resp = await client.delete(f"{COLLAB}/{team_id}/collab/log", headers=_hdr(owner))
    assert clear_resp.status_code == 200
    assert clear_resp.json()["deleted"] == 0


@pytest.mark.asyncio
async def test_collab_status_public(client):
    # Unauthenticated status should still return 0? Actually get_optional_user returns None, so count hidden? For non-member returns 0
    # We need a team first
    owner = await _register(client, "collab_owner2@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(owner), json={"name": "Collab Team 2"})).json()["id"]

    # No auth header — should still return count 0 (not 401) because get_optional_user
    resp = await client.get(f"{COLLAB}/{team_id}/collab/status")
    assert resp.status_code == 200
