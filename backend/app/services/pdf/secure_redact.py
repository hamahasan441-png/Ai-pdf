"""Remove PDF content with PyMuPDF. Fail closed: no partial success."""

from __future__ import annotations

import fitz


class RedactionRejected(Exception):
    def __init__(self, message: str, *, status: int = 422) -> None:
        super().__init__(message)
        self.status = status


def redact_pdf_bytes(pdf_bytes: bytes, areas: list[dict]) -> bytes:
    """Delete content under each normalized rectangle.

    Every area is applied, or the function raises [RedactionRejected] and the
    caller must not return a PDF. A black rectangle drawn by the client is not
    a substitute for this result.
    """
    if not pdf_bytes:
        raise RedactionRejected("Empty PDF")
    if not areas:
        raise RedactionRejected("No redaction areas")

    try:
        doc = fitz.open(stream=pdf_bytes, filetype="pdf")
    except Exception as exc:
        raise RedactionRejected(f"Invalid PDF: {exc}") from exc

    try:
        if doc.page_count == 0:
            raise RedactionRejected("PDF has no pages")

        touched: set[int] = set()
        for index, area in enumerate(areas):
            page_index = area.get("page")
            if not isinstance(page_index, int) or isinstance(page_index, bool):
                raise RedactionRejected(f"Area {index} has no integer page")
            if page_index < 0 or page_index >= doc.page_count:
                raise RedactionRejected(
                    f"Area {index} page {page_index} is outside the document "
                    f"({doc.page_count} pages). No page was redacted."
                )
            try:
                x0 = float(area["x0"])
                y0 = float(area["y0"])
                x1 = float(area["x1"])
                y1 = float(area["y1"])
            except (KeyError, TypeError, ValueError) as exc:
                raise RedactionRejected(f"Area {index} has invalid coordinates") from exc
            for name, value in (("x0", x0), ("y0", y0), ("x1", x1), ("y1", y1)):
                if value < 0 or value > 1:
                    raise RedactionRejected(f"Area {index} {name} is outside 0..1")
            if x0 > x1:
                x0, x1 = x1, x0
            if y0 > y1:
                y0, y1 = y1, y0
            if x1 - x0 <= 0 or y1 - y0 <= 0:
                raise RedactionRejected(f"Area {index} is empty")

            page = doc[page_index]
            box = page.rect
            pdf_rect = fitz.Rect(
                box.x0 + x0 * box.width,
                box.y0 + y0 * box.height,
                box.x0 + x1 * box.width,
                box.y0 + y1 * box.height,
            )
            fill = _fill_rgb(area.get("fill"))
            annot = page.add_redact_annot(pdf_rect, fill=fill)
            annot.update()
            touched.add(page_index)

        for page_index in sorted(touched):
            try:
                doc[page_index].apply_redactions(images=fitz.PDF_REDACT_IMAGE_REMOVE)
            except Exception as exc:
                raise RedactionRejected(
                    f"Redaction failed on page {page_index}: {exc}",
                    status=500,
                ) from exc

        out = doc.tobytes(garbage=3, deflate=True)
        if not out:
            raise RedactionRejected("Redaction produced an empty PDF", status=500)
        return out
    finally:
        doc.close()


def _fill_rgb(fill: object) -> tuple[float, float, float]:
    if not isinstance(fill, str) or not fill:
        return (0, 0, 0)
    name = fill.lower()
    if name == "white":
        return (1, 1, 1)
    if name == "black":
        return (0, 0, 0)
    hex_color = fill.lstrip("#")
    if len(hex_color) == 3:
        hex_color = "".join(ch * 2 for ch in hex_color)
    if len(hex_color) != 6:
        return (0, 0, 0)
    try:
        return tuple(int(hex_color[i : i + 2], 16) / 255.0 for i in (0, 2, 4))  # type: ignore[return-value]
    except ValueError:
        return (0, 0, 0)
