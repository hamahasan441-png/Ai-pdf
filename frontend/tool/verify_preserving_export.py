"""Independent check of PDFs written by the source-preserving export tests.

    PDOCZY_EXPORT_OUT=/tmp/out flutter test test/editor/pdf_source/preserving_export_test.dart
    python3 tool/verify_preserving_export.py /tmp/out   # reads every expectations*.json

Opens each file listed in expectations.json with PyMuPDF (MuPDF) and with
pikepdf (qpdf), so the result does not depend on the Dart parser that wrote
it. Checks qpdf syntax, page count, rotation, extracted text, links, form
widgets, bookmarks, metadata, and that a red overlay mark is rendered at the
expected place on the displayed page. Exits non-zero on any failure.
"""

from __future__ import annotations

import json
import pathlib
import sys

import pikepdf
import pymupdf as fitz


def is_red(rgb: tuple[int, ...]) -> bool:
    """Red or a red tint (editor shapes are filled at 25 % opacity)."""
    r, g, b = rgb[:3]
    return r > 150 and r - g > 30 and r - b > 30


def check(path: pathlib.Path, exp: dict) -> list[str]:
    errors: list[str] = []
    password = exp.get("password")
    if password is not None:
        # The file must be locked: no password and a wrong one both fail.
        for wrong in ("", password + "x"):
            try:
                pikepdf.open(path, password=wrong).close()
                errors.append(f"qpdf opened the file with password {wrong!r}")
            except pikepdf.PasswordError:
                pass
        locked = fitz.open(path)
        if not locked.needs_pass:
            errors.append("MuPDF opened the file without a password")
        elif locked.authenticate(password + "x"):
            errors.append("MuPDF accepted a wrong password")
        locked.close()
        if exp.get("encryption"):
            with pikepdf.open(path, password=password) as pdf:
                info = pdf.encryption
                method = f"{info.stream_method} {info.string_method} R{info.R} {info.bits}"
                if exp["encryption"].lower() not in method.lower():
                    errors.append(f"encrypted with {method}, expected {exp['encryption']}")
    with pikepdf.open(path, password=password or "") as pdf:
        problems = pdf.check_pdf_syntax()
        if problems:
            errors.append(f"qpdf reports problems: {problems[:3]}")
    doc = fitz.open(path)
    if password is not None and not doc.authenticate(password):
        errors.append("MuPDF rejected the right password")
    pages = exp.get("pages", [])
    if doc.page_count != len(pages):
        errors.append(f"page count {doc.page_count}, expected {len(pages)}")
    for i, (page, want) in enumerate(zip(doc, pages)):
        text = page.get_text()
        for t in want.get("text_contains", []):
            if t not in text:
                errors.append(f"page {i + 1}: text {t!r} not extractable")
            elif not page.search_for(t):
                errors.append(f"page {i + 1}: text {t!r} not found by search")
        for t in want.get("text_absent", []):
            if t in text:
                errors.append(f"page {i + 1}: text {t!r} should be gone")
        if "rotation" in want and page.rotation != want["rotation"]:
            errors.append(f"page {i + 1}: rotation {page.rotation}, expected {want['rotation']}")
        if "links" in want and len(page.get_links()) != want["links"]:
            errors.append(f"page {i + 1}: {len(page.get_links())} links, expected {want['links']}")
        if "widgets" in want and len(list(page.widgets())) != want["widgets"]:
            errors.append(f"page {i + 1}: {len(list(page.widgets()))} widgets, expected {want['widgets']}")
        if "images" in want and len(page.get_images()) != want["images"]:
            errors.append(f"page {i + 1}: {len(page.get_images())} images, expected {want['images']}")
        if "size" in want and [round(page.rect.width), round(page.rect.height)] != want["size"]:
            errors.append(f"page {i + 1}: size {page.rect.width}x{page.rect.height}, expected {want['size']}")
        if "red_at" in want:
            pix = page.get_pixmap(dpi=72)
            x, y = want["red_at"]
            px = pix.pixel(int(pix.width * x), int(pix.height * y))
            if not is_red(px):
                errors.append(f"page {i + 1}: no red mark at {want['red_at']} (pixel {px[:3]})")
            far = pix.pixel(int(pix.width * 0.7), int(pix.height * 0.85))
            if is_red(far):
                errors.append(f"page {i + 1}: red where no mark was drawn")
    want_fields = exp.get("fields", {})
    if want_fields:
        got = {}
        for page in doc:
            for w in page.widgets():
                if w.field_type in (fitz.PDF_WIDGET_TYPE_CHECKBOX, fitz.PDF_WIDGET_TYPE_RADIOBUTTON):
                    if w.field_value not in ("Off", False, None, ""):
                        got[w.field_name] = str(w.field_value)
                    else:
                        got.setdefault(w.field_name, "Off")
                else:
                    got[w.field_name] = w.field_value
        for name, value in want_fields.items():
            if got.get(name) != value:
                errors.append(f"field {name!r} is {got.get(name)!r}, expected {value!r}")
    kinds = {
        fitz.PDF_WIDGET_TYPE_TEXT: "text",
        fitz.PDF_WIDGET_TYPE_CHECKBOX: "checkbox",
        fitz.PDF_WIDGET_TYPE_COMBOBOX: "combobox",
        fitz.PDF_WIDGET_TYPE_LISTBOX: "listbox",
        fitz.PDF_WIDGET_TYPE_RADIOBUTTON: "radio",
        fitz.PDF_WIDGET_TYPE_SIGNATURE: "signature",
    }
    for name, want in exp.get("new_fields", {}).items():
        # A field the editor created: its kind, required flag, and where it
        # shows on the displayed page (0..1 from the top left).
        hits = [(p, w) for p in doc for w in p.widgets() if w.field_name == name]
        if len(hits) != 1:
            errors.append(f"field {name!r}: {len(hits)} widgets, expected 1")
            continue
        page, w = hits[0]
        kind = kinds.get(w.field_type, str(w.field_type))
        if kind != want["type"]:
            errors.append(f"field {name!r} is a {kind}, expected {want['type']}")
        if bool(w.field_flags & 2) != want.get("required", False):
            errors.append(f"field {name!r}: required is {bool(w.field_flags & 2)}")
        if page.number != want["page"]:
            errors.append(f"field {name!r} is on page {page.number + 1}, expected {want['page'] + 1}")
        shown = w.rect * page.rotation_matrix
        box = [shown.x0 / page.rect.width, shown.y0 / page.rect.height, shown.x1 / page.rect.width, shown.y1 / page.rect.height]
        if max(abs(x - y) for x, y in zip(box, want["rect"])) > 0.01:
            errors.append(f"field {name!r} shows at {[round(v, 3) for v in box]}, expected {want['rect']}")
    for name in exp.get("fields_drawn", []):
        hits = [(p, w) for p in doc for w in p.widgets() if w.field_name == name]
        if not hits:
            errors.append(f"field {name!r} not found")
            continue
        page, w = hits[0]
        pix = page.get_pixmap(dpi=144, clip=w.rect, annots=True)
        dark = sum(1 for i in range(pix.width * pix.height) if sum(pix.pixel(i % pix.width, i // pix.width)[:3]) < 300)
        if dark < 5:
            errors.append(f"field {name!r} shows no text")
    for want in exp.get("same_positions", []):
        # Words that were not edited must not move: compare with the source.
        src = fitz.open(pathlib.Path(__file__).resolve().parent.parent / "test" / "fixtures" / "pdf" / want["source"])
        a = {w[4]: w[:4] for w in src[want["source_page"]].get_text("words")}
        b = {w[4]: w[:4] for w in doc[want["page"]].get_text("words")}
        for word in want["words"]:
            if word not in b:
                errors.append(f"page {want['page'] + 1}: {word!r} missing")
            elif max(abs(x - y) for x, y in zip(a[word], b[word])) > 0.3:
                errors.append(f"page {want['page'] + 1}: {word!r} moved from {a[word]} to {b[word]}")
    for want in exp.get("color_at", []):
        page = doc[want["page"]]
        pix = page.get_pixmap(dpi=72)
        x, y = want["at"]
        px = pix.pixel(int(pix.width * x), int(pix.height * y))[:3]
        if max(abs(c - e) for c, e in zip(px, want["rgb"])) > want.get("tol", 16):
            errors.append(f"page {want['page'] + 1}: colour {px} at {want['at']}, expected {want['rgb']}")
    all_text = "".join(p.get_text() for p in doc)
    for t in exp.get("text_absent_everywhere", []):
        if t in all_text:
            errors.append(f"text {t!r} is still in the document")
    if "toc_entries" in exp and len(doc.get_toc()) != exp["toc_entries"]:
        errors.append(f"{len(doc.get_toc())} bookmarks, expected {exp['toc_entries']}")
    if "title" in exp and doc.metadata.get("title") != exp["title"]:
        errors.append(f"title {doc.metadata.get('title')!r}, expected {exp['title']!r}")
    doc.close()
    return errors


def main() -> int:
    out = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    # One expectations*.json per test file: the files run in parallel, so a
    # single shared list could lose entries.
    expectations = [e for f in sorted(out.glob("expectations*.json")) for e in json.loads(f.read_text())]
    if not expectations:
        print("No exported files to check.")
        return 1
    failed = 0
    for exp in expectations:
        errors = check(out / exp["file"], exp)
        status = "OK" if not errors else "FAIL"
        print(f"{status} {exp['file']}")
        for e in errors:
            print(f"  - {e}")
        failed += bool(errors)
    print(f"{len(expectations) - failed}/{len(expectations)} files passed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
