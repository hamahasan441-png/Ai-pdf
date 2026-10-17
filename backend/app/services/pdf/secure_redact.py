"""Remove PDF content with PyMuPDF. Fail closed: no partial success.

Coordinates arrive normalized (0..1) against the page *as displayed*, which is
what the editor shows: the CropBox after `/Rotate` is applied. PyMuPDF wants
redaction rectangles in unrotated page space, so every rectangle is mapped
through `page.derotation_matrix`. Before that mapping existed, a region drawn
on a rotated page removed some other part of the page and the request still
returned 200 with the secret intact.

After redaction the output is reopened from its bytes and checked
independently. Any check that fails rejects the whole request; the caller gets
no PDF. The checks cover ordinary text extraction, annotations, links and
form widgets inside each region, and the rendered pixels of each region. 
Copies of the redacted text outside the page content are handled by policy
(see _scrub_residual_copies): hidden or derived copies (document info, XMP,
bookmark titles, alternate text, attachments) are scrubbed and re-checked;
visible text elsewhere in the document is counted and reported, not changed,
because the user did not select it. None of this proves that no forensic
method could recover anything.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field

import fitz

# Character centers inside a region after redaction mean the text survived.
# Edges are shrunk by this many points so a glyph that only touches the border
# of a neighbouring line is not counted.
_TEXT_EDGE_PT = 0.5
# Share of rendered pixels in a region that must match the fill colour.
_FILL_MATCH_RATIO = 0.97
_FILL_CHANNEL_TOLERANCE = 24
_CHECK_DPI = 72


class RedactionRejected(Exception):
    """The request cannot be honoured. No PDF may be returned.

    Messages are safe to show to the client: they never contain document
    text, file paths, or library exception text.
    """

    def __init__(self, message: str, *, status: int = 422) -> None:
        super().__init__(message)
        self.status = status


@dataclass
class RedactionReport:
    pdf: bytes
    page_count: int
    regions: int
    pages: list[int]
    annotations_removed: int = 0
    links_removed: int = 0
    widgets_removed: int = 0
    checks: list[str] = field(default_factory=list)
    scrubbed: dict[str, int] = field(default_factory=dict)
    occurrences_elsewhere: int = 0


@dataclass(frozen=True)
class _Region:
    index: int
    page: int
    # Unrotated page space, the space PyMuPDF uses for content and annots.
    rect: fitz.Rect
    fill: tuple[float, float, float]


def redact_pdf_bytes(pdf_bytes: bytes, areas: list[dict]) -> bytes:
    """Delete content under each normalized rectangle and return the PDF.

    Every area is applied and verified, or the function raises
    [RedactionRejected] and the caller must not return a PDF. A black
    rectangle drawn by the client is not a substitute for this result.
    """
    return redact_pdf(pdf_bytes, areas).pdf


def redact_pdf(pdf_bytes: bytes, areas: list[dict]) -> RedactionReport:
    if not isinstance(pdf_bytes, (bytes, bytearray)) or not pdf_bytes:
        raise RedactionRejected("Empty PDF")
    if not isinstance(areas, list) or not areas:
        raise RedactionRejected("No redaction areas")

    doc = _open(pdf_bytes)
    try:
        page_count = doc.page_count
        orphans_before = _orphan_field_values(doc)
        regions = [_parse_area(doc, index, area) for index, area in enumerate(areas)]
        pages = sorted({r.page for r in regions})
        needles = _redacted_needles(doc, regions)

        annots_removed = links_removed = 0
        field_xrefs: set[int] = set()
        for page_index in pages:
            page = doc[page_index]
            page_regions = [r for r in regions if r.page == page_index]
            a, l, w = _remove_overlapping_objects(page, [r.rect for r in page_regions])
            annots_removed += a
            links_removed += l
            field_xrefs |= w
            for region in page_regions:
                try:
                    page.add_redact_annot(region.rect, fill=region.fill)
                except Exception as exc:
                    raise RedactionRejected(
                        f"Area {region.index} could not be marked for redaction",
                        status=500,
                    ) from exc
            try:
                page.apply_redactions(**_apply_options())
            except Exception as exc:
                raise RedactionRejected(
                    f"Redaction failed on page {page_index}",
                    status=500,
                ) from exc

        _scrub_form_fields(doc, field_xrefs)
        widgets_removed = len(field_xrefs)
        scrubbed = _scrub_residual_copies(doc, needles)
        elsewhere = _count_visible_elsewhere(doc, needles)

        try:
            out = doc.tobytes(garbage=4, deflate=True)
        except Exception as exc:
            raise RedactionRejected("Redacted PDF could not be written", status=500) from exc
        if not out:
            raise RedactionRejected("Redaction produced an empty PDF", status=500)
    finally:
        doc.close()

    checks = verify_redaction(out, page_count, regions, orphan_limit=orphans_before, needles=needles)
    return RedactionReport(
        pdf=out,
        page_count=page_count,
        regions=len(regions),
        pages=pages,
        annotations_removed=annots_removed,
        links_removed=links_removed,
        widgets_removed=widgets_removed,
        checks=checks,
        scrubbed=scrubbed,
        occurrences_elsewhere=elsewhere,
    )


def verify_redaction(
    out: bytes,
    page_count: int,
    regions: list[_Region],
    orphan_limit: int = 0,
    needles: list[str] | None = None,
) -> list[str]:
    """Reopen [out] from bytes and confirm each region is empty.

    Raises [RedactionRejected] (500) on the first failure.
    """
    try:
        doc = fitz.open(stream=out, filetype="pdf")
    except Exception as exc:
        raise RedactionRejected("Redacted PDF could not be reopened", status=500) from exc
    try:
        if doc.page_count != page_count:
            raise RedactionRejected("Redacted PDF has a different page count", status=500)
        for region in regions:
            page = doc[region.page]
            if _text_inside(page, region.rect):
                raise RedactionRejected(
                    f"Text is still extractable inside area {region.index}", status=500
                )
            for annot in page.annots() or []:
                if annot.type[0] == fitz.PDF_ANNOT_REDACT:
                    raise RedactionRejected(
                        f"Unapplied redaction remains on page {region.page}", status=500
                    )
                if _intersects(annot.rect, region.rect):
                    raise RedactionRejected(
                        f"An annotation still overlaps area {region.index}", status=500
                    )
            for link in page.get_links():
                if _intersects(fitz.Rect(link["from"]), region.rect):
                    raise RedactionRejected(
                        f"A link still overlaps area {region.index}", status=500
                    )
            for widget in page.widgets() or []:
                if _intersects(widget.rect, region.rect):
                    raise RedactionRejected(
                        f"A form field still overlaps area {region.index}", status=500
                    )
            if not _region_is_filled(page, region):
                raise RedactionRejected(
                    f"Area {region.index} is not covered in the rendered page", status=500
                )
        # A field taken off its page must not survive with its value. Fields
        # that were already off-page in the input are left as they were.
        if _orphan_field_values(doc) > orphan_limit:
            raise RedactionRejected("A removed form field still holds a value", status=500)
        if needles and _hidden_copies(doc, needles):
            raise RedactionRejected("The redacted text is still in hidden document data", status=500)
    finally:
        doc.close()
    return [
        "page_count",
        "text_extraction",
        "annotations",
        "links",
        "form_fields",
        "rendered_fill",
        "hidden_copies",
    ]


# ─── Copies of the redacted text outside the redacted areas ──────────────────

# Keys whose string values are hidden or derived copies of page text.
_HIDDEN_TEXT_KEYS = {
    "Title": "bookmarks",  # outline items
    "Alt": "alt_text",
    "ActualText": "alt_text",
    "E": "alt_text",
}
_MIN_NEEDLE = 4


def _redacted_needles(doc: fitz.Document, regions: list[_Region]) -> list[str]:
    """Text that sits under the areas, before anything is removed.

    Each area's words in reading order form one phrase. Single words are
    added only when they are distinctive (digits, @, - or _, or long), so a
    common word under the box does not trigger edits elsewhere.
    """
    needles: set[str] = set()
    for region in regions:
        page = doc[region.page]
        words = []
        for x0, y0, x1, y1, word, *_ in page.get_text("words"):
            center = fitz.Point((x0 + x1) / 2, (y0 + y1) / 2)
            if region.rect.contains(center):
                words.append(word)
        phrase = " ".join(words).strip()
        if len(phrase) >= _MIN_NEEDLE:
            needles.add(phrase)
        for word in words:
            token = word.strip(".,;:()[]{}\"'")
            distinctive = any(ch.isdigit() or ch in "@-_" for ch in token) or len(token) >= 10
            if len(token) >= _MIN_NEEDLE and distinctive:
                needles.add(token)
    return sorted(needles, key=len, reverse=True)


def _contains(text: str, needles: list[str]) -> bool:
    low = text.lower()
    return any(n.lower() in low for n in needles)


def _replace_all(text: str, needles: list[str]) -> str:
    for n in needles:
        text = re.sub(re.escape(n), "[redacted]", text, flags=re.IGNORECASE)
    return text


def _scrub_residual_copies(doc: fitz.Document, needles: list[str]) -> dict[str, int]:
    """Remove hidden or derived copies of the redacted text. Returns counts."""
    counts = {"metadata": 0, "xmp": 0, "bookmarks": 0, "alt_text": 0, "attachments": 0}
    if not needles:
        return counts
    try:
        meta = dict(doc.metadata or {})
        changed = False
        for key, value in meta.items():
            if isinstance(value, str) and value and _contains(value, needles):
                meta[key] = _replace_all(value, needles)
                counts["metadata"] += 1
                changed = True
        if changed:
            doc.set_metadata({k: v for k, v in meta.items() if isinstance(v, str)})
        xmp = doc.get_xml_metadata() or ""
        if xmp and _contains(xmp, needles):
            doc.del_xml_metadata()
            counts["xmp"] += 1
        for xref in range(1, doc.xref_length()):
            for key, bucket in _HIDDEN_TEXT_KEYS.items():
                kind, value = doc.xref_get_key(xref, key)
                if kind == "string" and _contains(value, needles):
                    if key == "Title" and doc.xref_get_key(xref, "Parent")[0] == "null":
                        continue  # only outline items carry Title + Parent
                    doc.xref_set_key(xref, key, fitz.get_pdf_str(_replace_all(value, needles)))
                    counts[bucket] += 1
        for name in list(doc.embfile_names()):
            info = doc.embfile_info(name)
            labels = " ".join(str(info.get(k, "")) for k in ("name", "filename", "ufilename", "desc"))
            data = doc.embfile_get(name)
            if _contains(labels, needles) or _bytes_contain(data, needles):
                doc.embfile_del(name)
                counts["attachments"] += 1
    except RedactionRejected:
        raise
    except Exception as exc:
        raise RedactionRejected("Hidden copies of the text could not be removed", status=500) from exc
    return counts


def _bytes_contain(data: bytes, needles: list[str]) -> bool:
    for n in needles:
        for enc in ("utf-8", "utf-16-le", "utf-16-be", "latin-1"):
            try:
                if n.encode(enc) in data or n.lower().encode(enc) in data.lower():
                    return True
            except UnicodeEncodeError:
                continue
    return False


def _hidden_copies(doc: fitz.Document, needles: list[str]) -> bool:
    meta = doc.metadata or {}
    if any(isinstance(v, str) and _contains(v, needles) for v in meta.values()):
        return True
    if _contains(doc.get_xml_metadata() or "", needles):
        return True
    if any(_contains(title, needles) for _, title, *_ in doc.get_toc()):
        return True
    for xref in range(1, doc.xref_length()):
        for key in ("Alt", "ActualText", "E"):
            kind, value = doc.xref_get_key(xref, key)
            if kind == "string" and _contains(value, needles):
                return True
    for name in doc.embfile_names():
        if _bytes_contain(doc.embfile_get(name), needles):
            return True
    return False


def _count_visible_elsewhere(doc: fitz.Document, needles: list[str]) -> int:
    """Visible copies the user did not select: page text, notes, form values."""
    count = 0
    for page in doc:
        for n in needles:
            count += len(page.search_for(n))
        for annot in page.annots() or []:
            if _contains(annot.info.get("content", "") or "", needles):
                count += 1
        for widget in page.widgets() or []:
            if _contains(str(widget.field_value or ""), needles):
                count += 1
    return count


def _open(pdf_bytes: bytes) -> fitz.Document:
    try:
        doc = fitz.open(stream=bytes(pdf_bytes), filetype="pdf")
    except Exception as exc:
        raise RedactionRejected("Invalid PDF") from exc
    if not doc.is_pdf:
        doc.close()
        raise RedactionRejected("Invalid PDF")
    if doc.needs_pass:
        doc.close()
        raise RedactionRejected("PDF is password-protected. Remove the password first.")
    if doc.page_count == 0:
        doc.close()
        raise RedactionRejected("PDF has no pages")
    return doc


def _parse_area(doc: fitz.Document, index: int, area: object) -> _Region:
    if not isinstance(area, dict):
        raise RedactionRejected(f"Area {index} is not an object")
    page_index = area.get("page")
    if not isinstance(page_index, int) or isinstance(page_index, bool):
        raise RedactionRejected(f"Area {index} has no integer page")
    if page_index < 0 or page_index >= doc.page_count:
        raise RedactionRejected(
            f"Area {index} page {page_index} is outside the document "
            f"({doc.page_count} pages). No page was redacted."
        )
    coords: dict[str, float] = {}
    for name in ("x0", "y0", "x1", "y1"):
        raw = area.get(name)
        if isinstance(raw, bool) or not isinstance(raw, (int, float)):
            raise RedactionRejected(f"Area {index} has invalid coordinates")
        value = float(raw)
        if not math.isfinite(value):
            raise RedactionRejected(f"Area {index} {name} is not a finite number")
        if value < 0 or value > 1:
            raise RedactionRejected(f"Area {index} {name} is outside 0..1")
        coords[name] = value
    x0, x1 = sorted((coords["x0"], coords["x1"]))
    y0, y1 = sorted((coords["y0"], coords["y1"]))
    if x1 - x0 <= 0 or y1 - y0 <= 0:
        raise RedactionRejected(f"Area {index} is empty")

    page = doc[page_index]
    # page.rect is the CropBox as displayed, with /Rotate applied.
    shown = page.rect
    visual = fitz.Rect(
        shown.x0 + x0 * shown.width,
        shown.y0 + y0 * shown.height,
        shown.x0 + x1 * shown.width,
        shown.y0 + y1 * shown.height,
    )
    rect = (visual * page.derotation_matrix).normalize()
    if rect.is_empty or rect.is_infinite:
        raise RedactionRejected(f"Area {index} could not be mapped to the page")
    return _Region(index=index, page=page_index, rect=rect, fill=_fill_rgb(area.get("fill")))


def _apply_options() -> dict:
    options: dict = {}
    # Blank only the image pixels under the region instead of deleting every
    # image that touches it. Older PyMuPDF lacks the constant; fall back to
    # removing the whole image, which still removes the secret.
    pixels = getattr(fitz, "PDF_REDACT_IMAGE_PIXELS", None)
    options["images"] = pixels if pixels is not None else fitz.PDF_REDACT_IMAGE_REMOVE
    line_art = getattr(fitz, "PDF_REDACT_LINE_ART_REMOVE_IF_TOUCHED", None)
    if line_art is not None:
        options["graphics"] = line_art
    return options


def _remove_overlapping_objects(
    page: fitz.Page, rects: list[fitz.Rect]
) -> tuple[int, int, set[int]]:
    """Delete annotations, links and form widgets that overlap any region.

    apply_redactions removes page content only. A FreeText note or a filled
    form field above the region would otherwise keep the secret. Returns the
    xrefs of deleted widgets so [_scrub_form_fields] can clear their values.
    """
    annots = links = 0
    widgets: set[int] = set()
    for annot in list(page.annots() or []):
        if annot.type[0] == fitz.PDF_ANNOT_REDACT:
            continue
        if any(_intersects(annot.rect, r) for r in rects):
            page.delete_annot(annot)
            annots += 1
    for widget in list(page.widgets() or []):
        if any(_intersects(widget.rect, r) for r in rects):
            widgets.add(widget.xref)
            page.delete_widget(widget)
    for link in page.get_links():
        if any(_intersects(fitz.Rect(link["from"]), r) for r in rects):
            page.delete_link(link)
            links += 1
    return annots, links, widgets


_REF = re.compile(r"(\d+)\s+0\s+R")


def _scrub_form_fields(doc: fitz.Document, xrefs: set[int]) -> None:
    """Empty the deleted widgets' field objects and drop them from AcroForm.

    PyMuPDF 1.24 `delete_widget` removes the widget from the page but leaves
    the field, value included, in /AcroForm/Fields. A value stored on a
    parent field shared with widgets outside the region is not touched; that
    value is still shown elsewhere on purpose.
    """
    if not xrefs:
        return
    try:
        catalog = doc.pdf_catalog()
        kind, value = doc.xref_get_key(catalog, "AcroForm/Fields")
        if kind == "array":
            keep = [ref for ref in _REF.findall(value) if int(ref) not in xrefs]
            doc.xref_set_key(catalog, "AcroForm/Fields", "[" + " ".join(f"{r} 0 R" for r in keep) + "]")
        for xref in xrefs:
            doc.update_object(xref, "<<>>")
    except Exception as exc:
        raise RedactionRejected("Form fields in the area could not be removed", status=500) from exc


def _orphan_field_values(doc: fitz.Document) -> int:
    """Count AcroForm fields with a value that no page shows."""
    try:
        kind, value = doc.xref_get_key(doc.pdf_catalog(), "AcroForm/Fields")
    except Exception:
        return 0
    if kind != "array":
        return 0
    on_pages: set[int] = set()
    for page in doc:
        k, v = doc.xref_get_key(page.xref, "Annots")
        if k == "array":
            on_pages.update(int(r) for r in _REF.findall(v))
        elif k == "xref":
            # /Annots stored as an indirect array object.
            for ref in _REF.findall(v):
                on_pages.update(int(r) for r in _REF.findall(doc.xref_object(int(ref))))
    count = 0
    stack = [int(r) for r in _REF.findall(value)]
    seen: set[int] = set()
    while stack:
        xref = stack.pop()
        if xref in seen or xref <= 0 or xref >= doc.xref_length():
            continue
        seen.add(xref)
        kids_kind, kids = doc.xref_get_key(xref, "Kids")
        if kids_kind == "array":
            stack.extend(int(r) for r in _REF.findall(kids))
            continue
        v_kind, _ = doc.xref_get_key(xref, "V")
        if v_kind != "null" and xref not in on_pages:
            count += 1
    return count


def _intersects(a: fitz.Rect, b: fitz.Rect) -> bool:
    inter = fitz.Rect(a) & fitz.Rect(b)
    return not inter.is_empty and inter.width > 0 and inter.height > 0


def _text_inside(page: fitz.Page, rect: fitz.Rect) -> bool:
    inner = fitz.Rect(
        rect.x0 + _TEXT_EDGE_PT,
        rect.y0 + _TEXT_EDGE_PT,
        rect.x1 - _TEXT_EDGE_PT,
        rect.y1 - _TEXT_EDGE_PT,
    )
    if inner.is_empty:
        inner = rect
    raw = page.get_text("rawdict", clip=fitz.INFINITE_RECT())
    for block in raw.get("blocks", []):
        for line in block.get("lines", []):
            for span in line.get("spans", []):
                for char in span.get("chars", []):
                    if not char.get("c", "").strip():
                        continue
                    box = fitz.Rect(char["bbox"])
                    center = fitz.Point((box.x0 + box.x1) / 2, (box.y0 + box.y1) / 2)
                    if inner.contains(center):
                        return True
    return False


def _region_is_filled(page: fitz.Page, region: _Region) -> bool:
    """Render the region and require it to show the fill colour."""
    shown = region.rect * page.rotation_matrix
    clip = (shown & page.rect)
    if clip.is_empty:
        return False
    # Ignore anti-aliased edges.
    inset = min(1.0, clip.width / 4, clip.height / 4)
    clip = fitz.Rect(clip.x0 + inset, clip.y0 + inset, clip.x1 - inset, clip.y1 - inset)
    if clip.is_empty:
        return True
    zoom = _CHECK_DPI / 72
    pix = page.get_pixmap(matrix=fitz.Matrix(zoom, zoom), clip=clip, alpha=False, colorspace=fitz.csRGB, annots=True)
    samples = pix.samples
    n = pix.n
    total = pix.width * pix.height
    if total == 0:
        return True
    target = tuple(round(c * 255) for c in region.fill)
    match = 0
    for i in range(0, len(samples), n):
        if all(abs(samples[i + k] - target[k]) <= _FILL_CHANNEL_TOLERANCE for k in range(3)):
            match += 1
    return match / total >= _FILL_MATCH_RATIO


def _fill_rgb(fill: object) -> tuple[float, float, float]:
    if fill is None:
        return (0, 0, 0)
    if not isinstance(fill, str):
        raise RedactionRejected("Fill must be white, black, or #RRGGBB")
    name = fill.strip().lower()
    if name in ("", "black"):
        return (0, 0, 0)
    if name == "white":
        return (1, 1, 1)
    hex_color = name.lstrip("#")
    if len(hex_color) == 3:
        hex_color = "".join(ch * 2 for ch in hex_color)
    if len(hex_color) != 6:
        raise RedactionRejected("Fill must be white, black, or #RRGGBB")
    try:
        return tuple(int(hex_color[i : i + 2], 16) / 255.0 for i in (0, 2, 4))  # type: ignore[return-value]
    except ValueError as exc:
        raise RedactionRejected("Fill must be white, black, or #RRGGBB") from exc
