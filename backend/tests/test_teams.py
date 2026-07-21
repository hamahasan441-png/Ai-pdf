"""Integration tests for the team / enterprise endpoints (Part 5.8)."""

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


async def test_create_team_makes_creator_owner(client):
    token = await _register(client, "owner@example.com")
    resp = await client.post(TEAMS, headers=_hdr(token), json={"name": "Acme"})
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["name"] == "Acme"
    assert body["role"] == "owner"
    assert body["member_count"] == 1


async def test_list_teams_returns_memberships(client):
    token = await _register(client, "owner@example.com")
    await client.post(TEAMS, headers=_hdr(token), json={"name": "Acme"})
    await client.post(TEAMS, headers=_hdr(token), json={"name": "Beta"})
    resp = await client.get(TEAMS, headers=_hdr(token))
    assert resp.status_code == 200
    names = {t["name"] for t in resp.json()}
    assert names == {"Acme", "Beta"}


async def test_add_and_view_members(client):
    owner = await _register(client, "owner@example.com")
    await _register(client, "member@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(owner), json={"name": "Acme"})).json()["id"]

    add = await client.post(
        f"{TEAMS}/{team_id}/members",
        headers=_hdr(owner),
        json={"email": "member@example.com", "role": "member"},
    )
    assert add.status_code == 201, add.text

    detail = await client.get(f"{TEAMS}/{team_id}", headers=_hdr(owner))
    assert detail.status_code == 200
    emails = {m["email"] for m in detail.json()["members"]}
    assert emails == {"owner@example.com", "member@example.com"}


async def test_member_cannot_add_members(client):
    owner = await _register(client, "owner@example.com")
    member = await _register(client, "member@example.com")
    await _register(client, "third@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(owner), json={"name": "Acme"})).json()["id"]
    await client.post(
        f"{TEAMS}/{team_id}/members",
        headers=_hdr(owner),
        json={"email": "member@example.com", "role": "member"},
    )

    # A plain member (not owner/admin) may not add members.
    resp = await client.post(
        f"{TEAMS}/{team_id}/members",
        headers=_hdr(member),
        json={"email": "third@example.com", "role": "member"},
    )
    assert resp.status_code == 403


async def test_non_member_gets_404_not_403(client):
    owner = await _register(client, "owner@example.com")
    outsider = await _register(client, "outsider@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(owner), json={"name": "Acme"})).json()["id"]

    resp = await client.get(f"{TEAMS}/{team_id}", headers=_hdr(outsider))
    assert resp.status_code == 404


async def test_cannot_remove_owner(client):
    owner = await _register(client, "owner@example.com")
    created = (await client.post(TEAMS, headers=_hdr(owner), json={"name": "Acme"})).json()
    team_id = created["id"]
    owner_id = created["owner_id"]

    resp = await client.request(
        "DELETE", f"{TEAMS}/{team_id}/members/{owner_id}", headers=_hdr(owner)
    )
    assert resp.status_code == 403


async def test_remove_member(client):
    owner = await _register(client, "owner@example.com")
    await _register(client, "member@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(owner), json={"name": "Acme"})).json()["id"]
    add = await client.post(
        f"{TEAMS}/{team_id}/members",
        headers=_hdr(owner),
        json={"email": "member@example.com", "role": "member"},
    )
    member_uid = add.json()["user_id"]

    rm = await client.request(
        "DELETE", f"{TEAMS}/{team_id}/members/{member_uid}", headers=_hdr(owner)
    )
    assert rm.status_code == 204

    detail = await client.get(f"{TEAMS}/{team_id}", headers=_hdr(owner))
    assert {m["email"] for m in detail.json()["members"]} == {"owner@example.com"}


async def test_shared_templates_crud(client):
    owner = await _register(client, "owner@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(owner), json={"name": "Acme"})).json()["id"]

    create = await client.post(
        f"{TEAMS}/{team_id}/templates",
        headers=_hdr(owner),
        json={"name": "W-9", "description": "tax form", "content": {"fields": ["name"]}},
    )
    assert create.status_code == 201, create.text
    tpl = create.json()
    assert tpl["content"] == {"fields": ["name"]}

    listed = await client.get(f"{TEAMS}/{team_id}/templates", headers=_hdr(owner))
    assert listed.status_code == 200
    assert len(listed.json()) == 1

    delete = await client.request(
        "DELETE", f"{TEAMS}/{team_id}/templates/{tpl['id']}", headers=_hdr(owner)
    )
    assert delete.status_code == 204


async def test_audit_export_manager_only(client):
    owner = await _register(client, "owner@example.com")
    member = await _register(client, "member@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(owner), json={"name": "Acme"})).json()["id"]
    await client.post(
        f"{TEAMS}/{team_id}/members",
        headers=_hdr(owner),
        json={"email": "member@example.com", "role": "member"},
    )

    # Owner can export and sees recorded events (team.create + member.add).
    ok = await client.get(f"{TEAMS}/{team_id}/audit", headers=_hdr(owner))
    assert ok.status_code == 200
    body = ok.json()
    actions = {e["action"] for e in body["entries"]}
    assert "team.create" in actions
    assert "member.add" in actions

    # A plain member cannot export the audit log.
    forbidden = await client.get(f"{TEAMS}/{team_id}/audit", headers=_hdr(member))
    assert forbidden.status_code == 403


async def test_admin_can_be_promoted_and_manage(client):
    owner = await _register(client, "owner@example.com")
    await _register(client, "admin@example.com")
    await _register(client, "newbie@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(owner), json={"name": "Acme"})).json()["id"]

    # Add admin@ as an admin.
    await client.post(
        f"{TEAMS}/{team_id}/members",
        headers=_hdr(owner),
        json={"email": "admin@example.com", "role": "admin"},
    )
    admin_token = (await client.post(f"{AUTH}/login", json={"email": "admin@example.com", "password": "password123"})).json()["access_token"]

    # The admin can add another member.
    resp = await client.post(
        f"{TEAMS}/{team_id}/members",
        headers=_hdr(admin_token),
        json={"email": "newbie@example.com", "role": "member"},
    )
    assert resp.status_code == 201


async def test_requires_authentication(client):
    resp = await client.post(TEAMS, json={"name": "NoAuth"})
    assert resp.status_code in (401, 422)
