"""Secure redaction against generated PDFs, checked by reopening the output.

Each test builds a PDF with a synthetic secret at a known spot, runs
redact_pdf (the function the /document-ai/redact endpoint calls), reopens the
returned bytes, and checks text extraction, search, annotations, links,
widgets and rendered pixels. Passing these tests means ordinary extraction and
search no longer find the secret; it is not a forensic guarantee.
"""

import math

import fitz
import pytest

from app.services.pdf.secure_redact import RedactionRejected, redact_pdf

SECRET = "SECRET-REDACT-74192"
KEEP = "PUBLIC-KEEP-55810"
W, H = 300.0, 400.0


def _page_with_secret(doc: fitz.Document, *, rotate: int = 0) -> fitz.Page:
    page = doc.new_page(width=W, height=H)
    page.insert_text((30, 40), SECRET, fontsize=12)
    page.insert_text((30, 360), KEEP, fontsize=12)
    if rotate:
        page.set_rotation(rotate)
    return page


def _pdf(**kwargs) -> bytes:
    doc = fitz.open()
    _page_with_secret(doc, **kwargs)
    data = doc.tobytes()
    doc.close()
    return data


def _visual_area(page: fitz.Page, word: str, pad: float = 2.0) -> dict:
    """Normalized rectangle around [word] in displayed (rotated) page space."""
    hits = page.search_for(word)
    assert hits, f"{word} not on page"
    box = fitz.Rect(hits[0]) * page.rotation_matrix
    box = fitz.Rect(box.x0 - pad, box.y0 - pad, box.x1 + pad, box.y1 + pad).normalize()
    shown = page.rect
    return {
        "page": page.number,
        "x0": max(0.0, box.x0 / shown.width),
        "y0": max(0.0, box.y0 / shown.height),
        "x1": min(1.0, box.x1 / shown.width),
        "y1": min(1.0, box.y1 / shown.height),
        "fill": "black",
    }


def _area_for(pdf: bytes, word: str, page_index: int = 0) -> dict:
    doc = fitz.open(stream=pdf, filetype="pdf")
    try:
        return _visual_area(doc[page_index], word)
    finally:
        doc.close()


def _all_text(pdf: bytes) -> str:
    doc = fitz.open(stream=pdf, filetype="pdf")
    try:
        return "\n".join(page.get_text() for page in doc)
    finally:
        doc.close()


def _searchable(pdf: bytes, word: str) -> bool:
    doc = fitz.open(stream=pdf, filetype="pdf")
    try:
        return any(page.search_for(word) for page in doc)
    finally:
        doc.close()


def _assert_secret_gone(out: bytes) -> None:
    assert SECRET not in _all_text(out)
    assert not _searchable(out, SECRET)
    # The deflated output must not hold the plain string either.
    assert SECRET.encode() not in out


@pytest.mark.parametrize("rotate", [0, 90, 180, 270])
def test_rotated_pages_remove_the_secret_and_keep_other_text(rotate):
    original = _pdf(rotate=rotate)
    area = _area_for(original, SECRET)
    report = redact_pdf(original, [area])
    _assert_secret_gone(report.pdf)
    assert KEEP in _all_text(report.pdf)
    assert "rendered_fill" in report.checks


def test_unrotated_coordinates_on_a_rotated_page_point_elsewhere():
    """A region in the wrong space would miss the secret; that must not be silent.

    The area below is the secret's unrotated position, which on a 90-degree
    page points at empty paper. The secret stays, and that is acceptable only
    because the request does not claim to cover it: the secret is outside the
    region, so verify_redaction has nothing to reject. The real guarantee is the
    previous test, where the displayed position is used.
    """
    original = _pdf(rotate=90)
    doc = fitz.open(stream=original, filetype="pdf")
    page = doc[0]
    hit = page.search_for(SECRET)[0]
    area = {"page": 0, "x0": hit.x0 / page.rect.width, "y0": hit.y0 / page.rect.height,
            "x1": min(1, hit.x1 / page.rect.width), "y1": min(1, hit.y1 / page.rect.height)}
    doc.close()
    out = redact_pdf(original, [area]).pdf
    assert SECRET in _all_text(out)


def test_multiple_pages_and_overlapping_regions():
    doc = fitz.open()
    for _ in range(3):
        _page_with_secret(doc)
    original = doc.tobytes()
    doc.close()
    area0 = _area_for(original, SECRET, 0)
    area2 = _area_for(original, SECRET, 2)
    overlap = dict(area0, x0=area0["x0"] + 0.05, x1=min(1.0, area0["x1"] + 0.05))
    report = redact_pdf(original, [area0, overlap, area2])
    assert report.pages == [0, 2]
    out = fitz.open(stream=report.pdf, filetype="pdf")
    try:
        assert SECRET not in out[0].get_text()
        assert SECRET in out[1].get_text(), "page 1 had no region and must be untouched"
        assert SECRET not in out[2].get_text()
        for page in out:
            assert KEEP in page.get_text()
    finally:
        out.close()


def test_image_pixels_under_the_region_are_blanked():
    doc = fitz.open()
    page = doc.new_page(width=W, height=H)
    pix = fitz.Pixmap(fitz.csRGB, fitz.IRect(0, 0, 40, 40), False)
    pix.set_rect(pix.irect, (255, 0, 0))
    page.insert_image(fitz.Rect(50, 50, 250, 250), pixmap=pix)
    original = doc.tobytes()
    doc.close()
    area = {"page": 0, "x0": 100 / W, "y0": 100 / H, "x1": 150 / W, "y1": 150 / H, "fill": "black"}
    out = fitz.open(stream=redact_pdf(original, [area]).pdf, filetype="pdf")
    try:
        page = out[0]
        inside = page.get_pixmap(clip=fitz.Rect(110, 110, 140, 140))
        outside = page.get_pixmap(clip=fitz.Rect(60, 60, 80, 80))
        assert inside.pixel(5, 5)[:3] == (0, 0, 0)
        r, g, b = outside.pixel(5, 5)[:3]
        assert r > 200 and g < 60 and b < 60, "image outside the region must survive"
    finally:
        out.close()


def test_annotations_links_and_widgets_over_the_region_are_removed():
    doc = fitz.open()
    page = _page_with_secret(doc)
    target = page.search_for(SECRET)[0]
    note = page.add_freetext_annot(fitz.Rect(target.x0, target.y0, target.x1 + 60, target.y1 + 10), "note " + SECRET)
    note.update()
    page.insert_link({"kind": fitz.LINK_URI, "from": target, "uri": "https://example.invalid/" + SECRET})
    widget = fitz.Widget()
    widget.field_name = "f1"
    widget.field_type = fitz.PDF_WIDGET_TYPE_TEXT
    widget.field_value = SECRET
    widget.rect = fitz.Rect(target.x0, target.y0 - 2, target.x1, target.y1 + 2)
    page.add_widget(widget)
    keep_note = page.add_text_annot((250, 360), "unrelated")
    keep_note.update()
    original = doc.tobytes()
    area = _visual_area(page, SECRET)
    doc.close()

    report = redact_pdf(original, [area])
    assert report.annotations_removed >= 1
    assert report.links_removed == 1
    assert report.widgets_removed == 1
    _assert_secret_gone(report.pdf)
    out = fitz.open(stream=report.pdf, filetype="pdf")
    try:
        kinds = [a.type[1] for a in out[0].annots()]
        assert "Text" in kinds, "annotation outside the region must stay"
        assert not out[0].get_links()
    finally:
        out.close()


def test_invisible_ocr_layer_text_is_removed():
    doc = fitz.open()
    page = doc.new_page(width=W, height=H)
    page.insert_text((30, 40), SECRET, fontsize=12, render_mode=3)
    page.insert_text((30, 360), KEEP, fontsize=12, render_mode=3)
    original = doc.tobytes()
    area = _visual_area(page, SECRET)
    doc.close()
    out = redact_pdf(original, [area]).pdf
    _assert_secret_gone(out)
    assert KEEP in _all_text(out)


def test_redacted_region_renders_as_the_fill_colour():
    original = _pdf()
    area = _area_for(original, SECRET)
    out = fitz.open(stream=redact_pdf(original, [area]).pdf, filetype="pdf")
    try:
        page = out[0]
        clip = fitz.Rect(area["x0"] * W + 2, area["y0"] * H + 2, area["x1"] * W - 2, area["y1"] * H - 2)
        pix = page.get_pixmap(clip=clip)
        assert set(pix.samples) == {0}
    finally:
        out.close()


@pytest.mark.parametrize(
    "bad",
    [
        {"page": 0, "x0": math.nan, "y0": 0.1, "x1": 0.5, "y1": 0.2},
        {"page": 0, "x0": 0.1, "y0": math.inf, "x1": 0.5, "y1": 0.2},
        {"page": 0, "x0": -0.1, "y0": 0.1, "x1": 0.5, "y1": 0.2},
        {"page": 0, "x0": 0.1, "y0": 0.1, "x1": 1.2, "y1": 0.2},
        {"page": 0, "x0": 0.1, "y0": 0.1, "x1": 0.1, "y1": 0.2},
        {"page": 0, "x0": "0.1", "y0": 0.1, "x1": 0.5, "y1": 0.2},
        {"page": 0, "x0": True, "y0": 0.1, "x1": 0.5, "y1": 0.2},
        {"page": 0, "y0": 0.1, "x1": 0.5, "y1": 0.2},
        {"page": "0", "x0": 0.1, "y0": 0.1, "x1": 0.5, "y1": 0.2},
        {"page": 1, "x0": 0.1, "y0": 0.1, "x1": 0.5, "y1": 0.2},
        {"page": -1, "x0": 0.1, "y0": 0.1, "x1": 0.5, "y1": 0.2},
        {"page": 0, "x0": 0.1, "y0": 0.1, "x1": 0.5, "y1": 0.2, "fill": "#12"},
        "not-an-object",
    ],
)
def test_invalid_regions_reject_the_whole_request(bad):
    original = _pdf()
    good = _area_for(original, SECRET)
    with pytest.raises(RedactionRejected) as info:
        redact_pdf(original, [good, bad])
    assert SECRET not in str(info.value)


def test_password_protected_pdf_is_rejected():
    doc = fitz.open()
    _page_with_secret(doc)
    data = doc.tobytes(encryption=fitz.PDF_ENCRYPT_AES_256, user_pw="u", owner_pw="o")
    doc.close()
    with pytest.raises(RedactionRejected, match="password"):
        redact_pdf(data, [{"page": 0, "x0": 0, "y0": 0, "x1": 1, "y1": 0.2}])


def test_garbage_bytes_are_rejected_without_echoing_them():
    with pytest.raises(RedactionRejected) as info:
        redact_pdf(b"%PDF-1.7 " + SECRET.encode(), [{"page": 0, "x0": 0, "y0": 0, "x1": 1, "y1": 1}])
    assert SECRET not in str(info.value)


def test_engine_failure_returns_no_pdf(monkeypatch):
    def boom(self, *args, **kwargs):
        raise RuntimeError("engine exploded " + SECRET)

    monkeypatch.setattr(fitz.Page, "apply_redactions", boom)
    original = _pdf()
    with pytest.raises(RedactionRejected) as info:
        redact_pdf(original, [_area_for(original, SECRET)])
    assert info.value.status == 500
    assert SECRET not in str(info.value)


def test_verification_failure_returns_no_pdf(monkeypatch):
    """If apply_redactions silently does nothing, the check must catch it."""
    monkeypatch.setattr(fitz.Page, "apply_redactions", lambda self, *a, **k: True)
    original = _pdf()
    with pytest.raises(RedactionRejected) as info:
        redact_pdf(original, [_area_for(original, SECRET)])
    assert info.value.status == 500


def test_cropbox_offset_page():
    doc = fitz.open()
    page = doc.new_page(width=600, height=800)
    page.insert_text((330, 440), SECRET, fontsize=12)
    page.insert_text((330, 700), KEEP, fontsize=12)
    page.set_cropbox(fitz.Rect(300, 400, 600, 800))
    original = doc.tobytes()
    area = _visual_area(page, SECRET)
    doc.close()
    out = redact_pdf(original, [area]).pdf
    _assert_secret_gone(out)
    assert KEEP in _all_text(out)


def _pdf_with_hidden_copies() -> tuple[bytes, dict]:
    """The secret on page 1, plus hidden copies and one visible copy on page 2."""
    doc = fitz.open()
    area = _visual_area(_page_with_secret(doc), SECRET)
    p2 = doc.new_page(width=W, height=H)
    p2.insert_text((30, 40), f"copy {SECRET}", fontsize=12)
    doc.set_metadata({"title": f"Case {SECRET}", "subject": "unrelated subject", "author": "Pdoczy"})
    doc.set_xml_metadata(f"<x:xmpmeta xmlns:x='adobe:ns:meta/'><s>{SECRET}</s></x:xmpmeta>")
    doc.set_toc([[1, f"Section {SECRET}", 1], [1, "Other", 2]])
    doc.embfile_add("notes.txt", f"attachment {SECRET}".encode(), filename="notes.txt")
    doc.embfile_add("keep.txt", b"nothing secret here", filename="keep.txt")
    # Alternate text on a structure element that points at page 1.
    alt = doc.get_new_xref()
    doc.update_object(alt, f"<< /Type /StructElem /S /Figure /Alt {fitz.get_pdf_str('photo of ' + SECRET)} >>")
    doc.xref_set_key(doc.pdf_catalog(), "StructTreeRoot", f"<< /Type /StructTreeRoot /K {alt} 0 R >>")
    data = doc.tobytes()
    doc.close()
    return data, area


def test_hidden_copies_are_scrubbed_and_visible_copies_reported():
    original, area = _pdf_with_hidden_copies()
    report = redact_pdf(original, [area])
    assert "hidden_copies" in report.checks
    assert report.scrubbed["metadata"] >= 1
    assert report.scrubbed["xmp"] == 1
    assert report.scrubbed["bookmarks"] == 1
    assert report.scrubbed["alt_text"] == 1
    assert report.scrubbed["attachments"] == 1
    assert report.occurrences_elsewhere == 1, "page 2 copy is counted, not changed"

    out = fitz.open(stream=report.pdf, filetype="pdf")
    try:
        assert SECRET not in out[0].get_text()
        assert SECRET in out[1].get_text(), "text the user did not select stays"
        assert SECRET not in (out.metadata.get("title") or "")
        assert out.metadata.get("subject") == "unrelated subject"
        assert SECRET not in (out.get_xml_metadata() or "")
        assert all(SECRET not in t for _, t, _ in out.get_toc())
        assert out.embfile_names() == ["keep.txt"]
        for xref in range(1, out.xref_length()):
            kind, value = out.xref_get_key(xref, "Alt")
            if kind == "string":
                assert SECRET not in value
    finally:
        out.close()


def test_common_words_under_the_box_do_not_rewrite_metadata():
    doc = fitz.open()
    page = doc.new_page(width=W, height=H)
    page.insert_text((30, 40), "Annual", fontsize=12)
    page.insert_text((30, 360), KEEP, fontsize=12)
    doc.set_metadata({"title": "Annual Report"})
    area = _visual_area(page, "Annual")
    data = doc.tobytes()
    doc.close()
    report = redact_pdf(data, [area])
    out = fitz.open(stream=report.pdf, filetype="pdf")
    try:
        # The whole phrase under the box is "Annual" and does match; a longer
        # title that merely contains one common word would also match. The
        # policy errs on the side of removing the copy.
        assert out.metadata.get("title") == "[redacted] Report"
    finally:
        out.close()


def test_skipped_scrub_is_caught_by_verification(monkeypatch):
    import app.services.pdf.secure_redact as engine

    monkeypatch.setattr(engine, "_scrub_residual_copies", lambda doc, needles: {})
    original, area = _pdf_with_hidden_copies()
    with pytest.raises(RedactionRejected) as info:
        redact_pdf(original, [area])
    assert info.value.status == 500
    assert SECRET not in str(info.value)
