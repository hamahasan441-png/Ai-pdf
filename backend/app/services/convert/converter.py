"""PDF -> Office conversion (server-side, on-demand).

Heavy libraries are imported lazily inside each function so the API boots even
when an optional converter dependency is missing (the endpoint then returns a
clear 503 instead of crashing at startup).

- PDF -> Word (.docx): pdf2docx (layout-preserving, real editable text)
- PDF -> PowerPoint (.pptx): one rendered page image per slide (PyMuPDF)
- PDF -> Excel (.xlsx): table extraction (PyMuPDF find_tables) with a text
  fallback, one sheet per page
"""

from __future__ import annotations

import io
from pathlib import Path


def pdf_to_docx(pdf_path: str) -> bytes:
    """Convert a PDF to a Word document, preserving layout and editable text."""
    from pdf2docx import Converter  # lazy

    out_path = f"{pdf_path}.docx"
    cv = Converter(pdf_path)
    try:
        cv.convert(out_path)  # all pages
    finally:
        cv.close()
    try:
        return Path(out_path).read_bytes()
    finally:
        Path(out_path).unlink(missing_ok=True)


def pdf_to_pptx(pdf_path: str, dpi: int = 150) -> bytes:
    """Convert a PDF to PowerPoint: each page becomes a full-bleed slide image."""
    import fitz  # PyMuPDF, lazy
    from pptx import Presentation
    from pptx.util import Emu

    doc = fitz.open(pdf_path)
    try:
        prs = Presentation()
        blank = prs.slide_layouts[6]  # fully blank layout
        sw, sh = prs.slide_width, prs.slide_height
        for page in doc:
            pix = page.get_pixmap(dpi=dpi)
            png = pix.tobytes("png")
            slide = prs.slides.add_slide(blank)
            # Fit the page image to the slide (letterboxed, keep aspect ratio).
            iw, ih = pix.width, pix.height
            scale = min(sw / iw, sh / ih)
            w, h = Emu(int(iw * scale)), Emu(int(ih * scale))
            left, top = Emu(int((sw - w) / 2)), Emu(int((sh - h) / 2))
            slide.shapes.add_picture(io.BytesIO(png), left, top, width=w, height=h)
        buf = io.BytesIO()
        prs.save(buf)
        return buf.getvalue()
    finally:
        doc.close()


def pdf_to_xlsx(pdf_path: str) -> bytes:
    """Convert a PDF to Excel: extract tables per page (text fallback)."""
    import fitz  # lazy
    from openpyxl import Workbook

    doc = fitz.open(pdf_path)
    try:
        wb = Workbook()
        wb.remove(wb.active)  # start clean
        for i, page in enumerate(doc, start=1):
            ws = wb.create_sheet(title=f"Page {i}"[:31])
            wrote = False
            try:
                found = page.find_tables()
                for table in found.tables:
                    for row in table.extract():
                        ws.append([("" if c is None else str(c)) for c in row])
                        wrote = True
                    ws.append([])  # spacer between tables
            except Exception:
                pass
            if not wrote:
                for line in page.get_text().splitlines():
                    ws.append([line])
        if not wb.sheetnames:
            wb.create_sheet(title="Empty")
        buf = io.BytesIO()
        wb.save(buf)
        return buf.getvalue()
    finally:
        doc.close()
