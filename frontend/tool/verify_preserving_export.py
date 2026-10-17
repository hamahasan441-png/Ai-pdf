"""Independent check of PDFs written by the source-preserving export tests.

    PDOCZY_EXPORT_OUT=/tmp/out flutter test test/editor/pdf_source/preserving_export_test.dart
    python3 tool/verify_preserving_export.py /tmp/out

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
    with pikepdf.open(path) as pdf:
        problems = pdf.check_pdf_syntax()
        if problems:
            errors.append(f"qpdf reports problems: {problems[:3]}")
    doc = fitz.open(path)
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
        if "red_at" in want:
            pix = page.get_pixmap(dpi=72)
            x, y = want["red_at"]
            px = pix.pixel(int(pix.width * x), int(pix.height * y))
            if not is_red(px):
                errors.append(f"page {i + 1}: no red mark at {want['red_at']} (pixel {px[:3]})")
            far = pix.pixel(int(pix.width * 0.7), int(pix.height * 0.85))
            if is_red(far):
                errors.append(f"page {i + 1}: red where no mark was drawn")
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
    expectations = json.loads((out / "expectations.json").read_text())
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
