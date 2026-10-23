"""Tests for document upload and the guest document routes.

Regressions covered:
- Authenticated and guest uploads succeed (previously every upload 500'd on the
  UUID/str id mismatch and the missing ``is_guest`` column).
- The uploaded filename is sanitised: path components never reach the disk.
- A failed DB step leaves no orphan file behind.
- ``/documents/guest/{id}`` routes serve only anonymous guest documents, never
  a registered user's document, and do not leak storage internals.
- Guest AI routes are metered like the other AI routes.
"""

import uuid

import pytest
from sqlalchemy import select

from app.core.config import settings
from app.core.security import decode_token
from app.models.document import Document, DocumentStatus, DocumentType

PDF = b"%PDF-1.4 test"


async def _register(client, email):
    resp = await client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": "password123", "full_name": "Doc User"},
    )
    assert resp.status_code == 201, resp.text
    return resp.json()["access_token"]


def _hdr(token):
    return {"Authorization": f"Bearer {token}"}


@pytest.fixture
def upload_dir(tmp_path, monkeypatch):
    monkeypatch.setattr(settings, "UPLOAD_DIR", str(tmp_path))
    return tmp_path


def _files(root):
    return [p for p in root.rglob("*") if p.is_file()]


async def test_authenticated_upload_succeeds(client, upload_dir, session_maker):
    token = await _register(client, "up1@example.com")
    resp = await client.post(
        "/api/v1/documents/upload",
        headers=_hdr(token),
        files={"file": ("report.pdf", PDF, "application/pdf")},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    doc_id = uuid.UUID(body["id"])
    assert body["original_filename"] == "report.pdf"
    assert body["document_type"] == "pdf"

    stored = _files(upload_dir)
    assert len(stored) == 1 and stored[0].read_bytes() == PDF

    get = await client.get(f"/api/v1/documents/{doc_id}", headers=_hdr(token))
    assert get.status_code == 200, get.text
    assert get.json()["form_fields"] == []


async def test_guest_upload_succeeds_and_is_readable_as_guest(client, upload_dir):
    resp = await client.post(
        "/api/v1/documents/guest/upload",
        files={"file": ("guest.pdf", PDF, "application/pdf")},
    )
    assert resp.status_code == 201, resp.text
    doc_id = resp.json()["id"]
    assert len(_files(upload_dir)) == 1

    get = await client.get(f"/api/v1/documents/guest/{doc_id}")
    assert get.status_code == 200, get.text
    data = get.json()
    assert data["original_filename"] == "guest.pdf"
    # The response model never exposes storage internals.
    for leaked in ("file_path", "owner_id", "extracted_text"):
        assert leaked not in data


@pytest.mark.parametrize("name", ["../../x.pdf", "a/b/c.pdf", "..\\..\\evil.pdf", "عقد.pdf"])
async def test_upload_filename_is_sanitised(client, upload_dir, name):
    token = await _register(client, "up2@example.com")
    resp = await client.post(
        "/api/v1/documents/upload",
        headers=_hdr(token),
        files={"file": (name, PDF, "application/pdf")},
    )
    assert resp.status_code == 201, resp.text
    stored = _files(upload_dir)
    assert len(stored) == 1
    # Stored inside the user's own directory, no traversal, ASCII-only name.
    assert stored[0].parent.parent == upload_dir
    assert stored[0].name.isascii()
    assert "/" not in resp.json()["filename"] and "\\" not in resp.json()["filename"]


async def test_upload_db_failure_leaves_no_orphan_file(client, upload_dir, monkeypatch):
    token = await _register(client, "up3@example.com")
    from sqlalchemy.ext.asyncio import AsyncSession

    async def boom(self, *a, **kw):
        raise RuntimeError("db down")

    monkeypatch.setattr(AsyncSession, "flush", boom)
    with pytest.raises(RuntimeError):
        await client.post(
            "/api/v1/documents/upload",
            headers=_hdr(token),
            files={"file": ("x.pdf", PDF, "application/pdf")},
        )
    assert _files(upload_dir) == []


async def test_upload_write_failure_removes_partial_file(client, upload_dir, monkeypatch):
    token = await _register(client, "up4@example.com")
    from pathlib import Path

    def failing_write(self, data):
        Path.open(self, "wb").write(data[:1])
        raise OSError("disk full")

    monkeypatch.setattr(Path, "write_bytes", failing_write)
    resp = await client.post(
        "/api/v1/documents/upload",
        headers=_hdr(token),
        files={"file": ("x.pdf", PDF, "application/pdf")},
    )
    assert resp.status_code == 500
    assert _files(upload_dir) == []


async def _seed_owned_document(session_maker, token, tmp_path):
    doc_id = uuid.uuid4()
    async with session_maker() as s:
        s.add(
            Document(
                id=doc_id,
                owner_id=uuid.UUID(decode_token(token)["sub"]),
                filename="f",
                original_filename="secret.pdf",
                file_path=str(tmp_path / "x"),
                file_size=1,
                mime_type="application/pdf",
                document_type=DocumentType.PDF,
                status=DocumentStatus.ANALYZED,
                ai_summary="SSN 123-45-6789",
            )
        )
        await s.commit()
    return doc_id


async def test_guest_routes_cannot_read_registered_users_document(client, session_maker, tmp_path, monkeypatch):
    token = await _register(client, "owner@example.com")
    doc_id = await _seed_owned_document(session_maker, token, tmp_path)

    from app.services.ai.understanding import understanding_service
    from app.services.pipeline.orchestrator import pipeline

    async def must_not_run(*a, **kw):
        raise AssertionError("AI must not run for a non-guest document")

    monkeypatch.setattr(pipeline, "process", must_not_run)
    monkeypatch.setattr(understanding_service, "ask_about_document", must_not_run)

    get = await client.get(f"/api/v1/documents/guest/{doc_id}")
    assert get.status_code == 404
    assert "SSN" not in get.text

    analyze = await client.post(f"/api/v1/documents/guest/{doc_id}/analyze")
    assert analyze.status_code == 404

    ask = await client.post(f"/api/v1/documents/guest/{doc_id}/ask", params={"question": "What is the SSN?"})
    assert ask.status_code == 404

    async with session_maker() as s:
        doc = (await s.execute(select(Document).where(Document.id == doc_id))).scalar_one()
        assert doc.status == DocumentStatus.ANALYZED  # untouched

    # The owner still reads it through the authenticated route.
    own = await client.get(f"/api/v1/documents/{doc_id}", headers=_hdr(token))
    assert own.status_code == 200


async def test_guest_ask_is_metered(client, upload_dir, monkeypatch):
    monkeypatch.setattr(settings, "AI_FREE_DAILY_LIMIT", 1)
    from app.services.ai.understanding import understanding_service

    async def fake_ask(**kw):
        return "ANSWER"

    monkeypatch.setattr(understanding_service, "ask_about_document", fake_ask)
    doc_id = (
        await client.post(
            "/api/v1/documents/guest/upload",
            files={"file": ("g.pdf", PDF, "application/pdf")},
        )
    ).json()["id"]

    first = await client.post(f"/api/v1/documents/guest/{doc_id}/ask", params={"question": "q"})
    assert first.status_code == 200, first.text
    second = await client.post(f"/api/v1/documents/guest/{doc_id}/ask", params={"question": "q"})
    assert second.status_code == 429
