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


# --- Security regressions: team pool membership + quota cap -----------------

import fitz  # noqa: E402

from app.core.config import settings  # noqa: E402

TRANSLATE = "/api/v1/document-ai/translate"
_TRANSLATE_BODY = {"text": "hi", "target_language": "German"}


async def _team_with_quota(client, owner_token, quota):
    team_id = (await client.post(TEAMS, headers=_hdr(owner_token), json={"name": "Pool"})).json()["id"]
    upd = await client.put(f"{TEAMS}/{team_id}/quota", headers=_hdr(owner_token), json={"ai_daily_quota": quota})
    assert upd.status_code == 200, upd.text
    return team_id


async def test_team_quota_above_max_rejected(client):
    token = await _register(client, "owner_cap@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(token), json={"name": "Cap"})).json()["id"]
    bad = await client.put(
        f"{TEAMS}/{team_id}/quota", headers=_hdr(token), json={"ai_daily_quota": 10**9}
    )
    assert bad.status_code == 422
    ok = await client.put(
        f"{TEAMS}/{team_id}/quota",
        headers=_hdr(token),
        json={"ai_daily_quota": settings.AI_TEAM_DAILY_QUOTA_MAX},
    )
    assert ok.status_code == 200


async def test_stored_team_quota_is_clamped(session_maker, monkeypatch):
    from app.models.team import Team
    from app.services.billing.quota_tiers import get_team_quota

    monkeypatch.setattr(settings, "AI_TEAM_DAILY_QUOTA_MAX", 50)
    async with session_maker() as s:
        import uuid

        team = Team(name="legacy", owner_id=uuid.uuid4(), ai_daily_quota=10**9)
        s.add(team)
        await s.commit()
        assert await get_team_quota(s, team.id) == 50


async def test_guest_cannot_use_team_quota(client, mock_ai):
    owner = await _register(client, "owner_pool1@example.com")
    team_id = await _team_with_quota(client, owner, 100)
    resp = await client.post(TRANSLATE, headers={"X-Team-Id": team_id}, json=_TRANSLATE_BODY)
    assert resp.status_code == 403


async def test_non_member_cannot_use_team_quota(client, mock_ai):
    owner = await _register(client, "owner_pool2@example.com")
    outsider = await _register(client, "outsider_pool2@example.com")
    team_id = await _team_with_quota(client, owner, 100)
    hdr = {**_hdr(outsider), "X-Team-Id": team_id}

    resp = await client.post(TRANSLATE, headers=hdr, json=_TRANSLATE_BODY)
    assert resp.status_code == 403

    vision = await client.post(
        "/api/v1/forms/vision-detect", headers=hdr, json={"fields": [{"label": "Name"}]}
    )
    assert vision.status_code == 403

    doc = fitz.open()
    doc.new_page()
    redact = await client.post(
        "/api/v1/document-ai/redact",
        headers=hdr,
        files={"file": ("a.pdf", doc.tobytes(), "application/pdf")},
        data={"areas_json": '[{"page":0,"x0":0.1,"y0":0.1,"x1":0.2,"y1":0.2}]'},
    )
    assert redact.status_code == 403


async def test_member_uses_shared_team_pool(client, mock_ai, monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    owner = await _register(client, "owner_pool3@example.com")
    await _register(client, "member_pool3@example.com")
    team_id = await _team_with_quota(client, owner, 3)
    await client.post(
        f"{TEAMS}/{team_id}/members",
        headers=_hdr(owner),
        json={"email": "member_pool3@example.com", "role": "member"},
    )
    login = await client.post(
        f"{AUTH}/login", json={"email": "member_pool3@example.com", "password": "password123"}
    )
    member = login.json()["access_token"]

    # Pool of 3 shared between owner and member, beyond the free limit of 1.
    r1 = await client.post(TRANSLATE, headers={**_hdr(member), "X-Team-Id": team_id}, json=_TRANSLATE_BODY)
    r2 = await client.post(TRANSLATE, headers={**_hdr(owner), "X-Team-Id": team_id}, json=_TRANSLATE_BODY)
    # Same team id in another spelling must hit the same counter.
    r3 = await client.post(
        TRANSLATE, headers={**_hdr(member), "X-Team-Id": team_id.upper()}, json=_TRANSLATE_BODY
    )
    r4 = await client.post(TRANSLATE, headers={**_hdr(owner), "X-Team-Id": team_id}, json=_TRANSLATE_BODY)
    assert [r.status_code for r in (r1, r2, r3, r4)] == [200, 200, 200, 429]


async def test_redact_audit_requires_team_membership(client):
    owner = await _register(client, "owner_audit@example.com")
    attacker = await _register(client, "attacker_audit@example.com")
    team_id = (await client.post(TEAMS, headers=_hdr(owner), json={"name": "AuditTeam"})).json()["id"]
    doc = fitz.open()
    doc.new_page()
    pdf = doc.tobytes()
    form = {"areas_json": '[{"page":0,"x0":0.1,"y0":0.1,"x1":0.2,"y1":0.2}]'}

    resp = await client.post(
        "/api/v1/document-ai/redact",
        headers={**_hdr(attacker), "X-Team-Id": team_id},
        files={"file": ("a.pdf", pdf, "application/pdf")},
        data=form,
    )
    assert resp.status_code == 403
    audit = await client.get(f"{TEAMS}/{team_id}/audit", headers=_hdr(owner))
    assert "document.redact" not in [e["action"] for e in audit.json()["entries"]]

    # A member's redaction is still audited.
    ok = await client.post(
        "/api/v1/document-ai/redact",
        headers={**_hdr(owner), "X-Team-Id": team_id},
        files={"file": ("a.pdf", pdf, "application/pdf")},
        data=form,
    )
    assert ok.status_code == 200, ok.text
    audit = await client.get(f"{TEAMS}/{team_id}/audit", headers=_hdr(owner))
    assert "document.redact" in [e["action"] for e in audit.json()["entries"]]
