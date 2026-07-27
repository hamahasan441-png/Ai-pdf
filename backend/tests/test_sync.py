"""Tests for cloud sync opt-in — E8.2 Enhancement-Based Masterplan."""

import pytest

AUTH = "/api/v1/auth"
SYNC = "/api/v1/sync"


async def _register(client, email="sync@example.com"):
    resp = await client.post(
        f"{AUTH}/register",
        json={"email": email, "password": "password123", "full_name": "Sync User"},
    )
    assert resp.status_code == 201
    return resp.json()["access_token"]


def _hdr(token):
    return {"Authorization": f"Bearer {token}"}


@pytest.mark.asyncio
async def test_sync_push_and_pull(client):
    token = await _register(client, "sync_push_pull@example.com")
    file_hash = "abc123hash12345678"
    encrypted = "gAAAAABhencryptedblobexample"

    push = await client.post(
        f"{SYNC}/push",
        headers=_hdr(token),
        json={
            "file_hash": file_hash,
            "file_name": "contract.pdf",
            "encrypted_blob": encrypted,
            "device_id": "device-1",
        },
    )
    assert push.status_code == 200, push.text
    assert push.json()["file_hash"] == file_hash
    assert push.json()["version"] == 1

    # Pull
    pull = await client.get(f"{SYNC}/pull/{file_hash}", headers=_hdr(token))
    assert pull.status_code == 200
    data = pull.json()
    assert data["encrypted_blob"] == encrypted
    assert data["file_name"] == "contract.pdf"
    assert data["version"] == 1

    # Update (version should increment)
    encrypted2 = "gAAAAABhencryptedblob2"
    push2 = await client.post(
        f"{SYNC}/push",
        headers=_hdr(token),
        json={"file_hash": file_hash, "encrypted_blob": encrypted2, "device_id": "device-2"},
    )
    assert push2.json()["version"] == 2

    pull2 = await client.get(f"{SYNC}/pull/{file_hash}", headers=_hdr(token))
    assert pull2.json()["encrypted_blob"] == encrypted2
    assert pull2.json()["version"] == 2


@pytest.mark.asyncio
async def test_sync_list_and_delete(client):
    token = await _register(client, "sync_list@example.com")

    # Push two files
    for fh in ["hash1_12345678", "hash2_12345678"]:
        await client.post(
            f"{SYNC}/push",
            headers=_hdr(token),
            json={"file_hash": fh, "encrypted_blob": "blob_" + fh, "file_name": f"{fh}.pdf"},
        )

    lst = await client.get(f"{SYNC}/list", headers=_hdr(token))
    assert lst.status_code == 200
    items = lst.json()
    assert len(items) == 2

    # Delete one
    del_resp = await client.delete(f"{SYNC}/hash1_12345678", headers=_hdr(token))
    assert del_resp.status_code == 204

    lst2 = await client.get(f"{SYNC}/list", headers=_hdr(token))
    assert len(lst2.json()) == 1

    # Pull deleted should 410 or 404
    pull_deleted = await client.get(f"{SYNC}/pull/hash1_12345678", headers=_hdr(token))
    assert pull_deleted.status_code in (404, 410)


@pytest.mark.asyncio
async def test_sync_status(client):
    token = await _register(client, "sync_status@example.com")
    # Push one
    await client.post(
        f"{SYNC}/push",
        headers=_hdr(token),
        json={"file_hash": "status_hash_12345678", "encrypted_blob": "encrypted_data_123"},
    )
    status_resp = await client.get(f"{SYNC}/status", headers=_hdr(token))
    assert status_resp.status_code == 200
    data = status_resp.json()
    assert data["total_files"] == 1
    assert data["total_encrypted_bytes"] > 0
    assert "encrypted" in data["note"].lower()


@pytest.mark.asyncio
async def test_sync_isolation(client):
    # Two users should not see each other's syncs
    token_a = await _register(client, "sync_a@example.com")
    token_b = await _register(client, "sync_b@example.com")

    await client.post(
        f"{SYNC}/push",
        headers=_hdr(token_a),
        json={"file_hash": "isolated_hash_12345678", "encrypted_blob": "blob_a"},
    )

    lst_b = await client.get(f"{SYNC}/list", headers=_hdr(token_b))
    assert len(lst_b.json()) == 0

    pull_b = await client.get(f"{SYNC}/pull/isolated_hash_12345678", headers=_hdr(token_b))
    assert pull_b.status_code == 404
