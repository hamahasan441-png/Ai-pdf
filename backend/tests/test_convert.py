"""Tests for PDF -> Office conversion download headers."""

from urllib.parse import unquote

import pytest

from app.services.convert import converter


@pytest.mark.parametrize(
    "route, attr",
    [
        ("pdf-to-word", "pdf_to_docx"),
        ("pdf-to-excel", "pdf_to_xlsx"),
        ("pdf-to-ppt", "pdf_to_pptx"),
    ],
)
async def test_convert_non_latin1_filename(client, monkeypatch, route, attr):
    """An Arabic filename used to crash header encoding (UnicodeEncodeError 500)."""
    monkeypatch.setattr(converter, attr, lambda p: b"OUT")
    resp = await client.post(
        f"/api/v1/convert/{route}",
        files={"file": ("عقد.pdf", b"%PDF-1.4", "application/pdf")},
    )
    assert resp.status_code == 200, resp.text
    cd = resp.headers["content-disposition"]
    assert cd.isascii()
    assert 'filename="document.' in cd  # ASCII fallback
    encoded = cd.split("filename*=UTF-8''", 1)[1]
    assert unquote(encoded).startswith("عقد.")


async def test_convert_filename_cannot_inject_headers(client, monkeypatch):
    monkeypatch.setattr(converter, "pdf_to_docx", lambda p: b"OUT")
    resp = await client.post(
        "/api/v1/convert/pdf-to-word",
        files={"file": ('a"; x=1\r\nSet-Cookie: s=1.pdf', b"%PDF-1.4", "application/pdf")},
    )
    assert resp.status_code == 200
    assert "set-cookie" not in resp.headers
    fallback = resp.headers["content-disposition"].split('filename="', 1)[1].split('"', 1)[0]
    assert '"' not in fallback and ";" not in fallback
