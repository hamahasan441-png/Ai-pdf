"""Build the synthetic PDFs used by the source-preserving export tests.

Run from the repository root:

    python3 frontend/test/fixtures/pdf/make_fixtures.py

Requires PyMuPDF. Every file is generated here from synthetic text; no real
documents are included. The generated PDFs are committed so the Dart tests do
not need Python. Licence: same as the repository.
"""

from __future__ import annotations

import pathlib
import zlib

import pymupdf as fitz

OUT = pathlib.Path(__file__).resolve().parent

KEEP = "ORIGINAL-SEARCHABLE-TEXT"
SECRET = "SECRET-REDACT-74192"


def rich(path: pathlib.Path, *, objstm: bool) -> None:
    """Three pages: links, a note, a filled form field, an outline, metadata.

    Page 1 is A4 portrait, page 2 is /Rotate 90 letter, page 3 has a CropBox
    offset. Page 2 holds the secret used by the flatten and delete tests.
    """
    doc = fitz.open()
    p1 = doc.new_page(width=595, height=842)
    p1.insert_text((72, 100), f"{KEEP} page one", fontsize=14)
    p1.draw_rect(fitz.Rect(72, 150, 300, 250), color=(0, 0, 1), width=2)
    p1.draw_line((72, 300), (500, 320), color=(0, 0.6, 0), width=3)
    p1.insert_link({"kind": fitz.LINK_URI, "from": fitz.Rect(72, 85, 300, 105), "uri": "https://example.com/pdoczy"})
    note = p1.add_text_annot((520, 60), "existing note")
    note.update()
    widget = fitz.Widget()
    widget.field_name = "name"
    widget.field_type = fitz.PDF_WIDGET_TYPE_TEXT
    widget.field_value = "Form Value Kept"
    widget.rect = fitz.Rect(72, 400, 300, 430)
    p1.add_widget(widget)

    p2 = doc.new_page(width=612, height=792)
    p2.insert_text((72, 100), f"{SECRET} on page two", fontsize=14)
    p2.insert_text((72, 140), f"{KEEP} page two", fontsize=14)
    p2.set_rotation(90)

    p3 = doc.new_page(width=600, height=800)
    p3.insert_text((350, 450), f"{KEEP} page three", fontsize=12)
    p3.set_cropbox(fitz.Rect(300, 400, 600, 800))
    p3.insert_link({"kind": fitz.LINK_GOTO, "from": fitz.Rect(350, 435, 550, 455), "page": 0})

    doc.set_toc([[1, "First", 1], [1, "Second", 2], [1, "Third", 3]])
    doc.set_metadata({"title": "Pdoczy Fixture", "author": "Pdoczy Tests", "subject": "fixture"})
    if objstm:
        doc.save(path, garbage=4, deflate=True, use_objstms=1)
    else:
        doc.save(path, garbage=4, deflate=True)
    doc.close()


def incremental(path: pathlib.Path) -> None:
    """A file with an incremental update, so the xref has a /Prev chain."""
    base = OUT / "_tmp_base.pdf"
    doc = fitz.open()
    page = doc.new_page(width=400, height=400)
    page.insert_text((40, 60), f"{KEEP} first revision", fontsize=12)
    doc.save(base)
    doc.close()
    doc = fitz.open(base)
    doc[0].insert_text((40, 120), f"{KEEP} second revision", fontsize=12)
    doc.saveIncr()
    doc.close()
    path.write_bytes(base.read_bytes())
    base.unlink()


def inherited(path: pathlib.Path) -> None:
    """Hand-written PDF: MediaBox, Resources and Rotate live on the Pages node."""
    content = f"BT /F1 18 Tf 50 300 Td ({KEEP} inherited) Tj ET".encode()
    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R] /Count 1 /MediaBox [0 0 500 400] /Rotate 180"
        b" /Resources << /Font << /F1 5 0 R >> >> >>",
        b"<< /Type /Page /Parent 2 0 R /Contents 4 0 R >>",
        b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream",
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    ]
    out = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for i, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % i + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for off in offsets:
        out += b"%010d 00000 n \n" % off
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)
    path.write_bytes(bytes(out))


def images(path: pathlib.Path) -> None:
    """Hand-written two-page PDF with image XObjects the editor never decodes.

    Page 1 (400 x 300) draws a DCT (JPEG) image, a Flate RGB image with a
    Flate /SMask, a JBIG2 image with /JBIG2Globals and a vector path. The
    JBIG2 bytes are a marker, not a real JBIG2 stream: the export must copy
    them unread. Page 2 is a different size (200 x 500) with only a path.
    """
    pix = fitz.Pixmap(fitz.csRGB, fitz.IRect(0, 0, 8, 8), False)
    pix.set_rect(pix.irect, (200, 30, 30))
    jpeg = pix.tobytes("jpeg")
    rgb = zlib.compress(bytes([20, 120, 220]) * 16)
    alpha = zlib.compress(bytes([255, 0]) * 8)
    jbig2 = b"PDOCZY-JBIG2-MARKER\x00\x01\x02\xff"
    globals_ = b"PDOCZY-JBIG2-GLOBALS"
    content1 = (
        f"BT /F1 12 Tf 20 280 Td ({KEEP} images) Tj ET\n"
        "q 80 0 0 80 20 150 cm /ImJ Do Q\n"
        "q 80 0 0 80 120 150 cm /ImF Do Q\n"
        "q 80 0 0 80 220 150 cm /ImB Do Q\n"
        "0 0 1 RG 3 w 20 40 m 380 120 l 200 20 l h S\n"
    ).encode()
    content2 = b"1 0 0 rg 20 20 160 460 re f\n"

    def stream(head: bytes, data: bytes) -> bytes:
        return b"<< " + head + b" /Length %d >>\nstream\n" % len(data) + data + b"\nendstream"

    objects = [
        b"<< /Type /Catalog /Pages 2 0 R >>",
        b"<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 400 300] /Contents 5 0 R"
        b" /Resources << /Font << /F1 7 0 R >> /XObject << /ImJ 8 0 R /ImF 9 0 R /ImB 11 0 R >> >> >>",
        b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 200 500] /Contents 6 0 R /Resources << >> >>",
        stream(b"", content1),
        stream(b"", content2),
        b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
        stream(b"/Type /XObject /Subtype /Image /Width 8 /Height 8 /ColorSpace /DeviceRGB"
               b" /BitsPerComponent 8 /Filter /DCTDecode", jpeg),
        stream(b"/Type /XObject /Subtype /Image /Width 4 /Height 4 /ColorSpace /DeviceRGB"
               b" /BitsPerComponent 8 /Filter /FlateDecode /SMask 10 0 R", rgb),
        stream(b"/Type /XObject /Subtype /Image /Width 4 /Height 4 /ColorSpace /DeviceGray"
               b" /BitsPerComponent 8 /Filter /FlateDecode", alpha),
        stream(b"/Type /XObject /Subtype /Image /Width 8 /Height 8 /ColorSpace /DeviceGray"
               b" /BitsPerComponent 1 /Filter /JBIG2Decode /DecodeParms << /JBIG2Globals 12 0 R >>", jbig2),
        stream(b"", globals_),
    ]
    out = bytearray(b"%PDF-1.5\n%\xe2\xe3\xcf\xd3\n")
    offsets = []
    for i, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += b"%d 0 obj\n" % i + body + b"\nendobj\n"
    xref = len(out)
    out += b"xref\n0 %d\n0000000000 65535 f \n" % (len(objects) + 1)
    for off in offsets:
        out += b"%010d 00000 n \n" % off
    out += b"trailer\n<< /Size %d /Root 1 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objects) + 1, xref)
    path.write_bytes(bytes(out))


def radio_group(doc, page, name: str, states: list[str], *, selected: str, x: float, y: float) -> None:
    """A radio field [name] with one 18 pt widget per state, built from raw
    objects (PyMuPDF cannot group radio widgets). The parent's xref is left
    in doc._radio_parent for the caller to add to /AcroForm /Fields."""
    page_h = page.rect.height
    parent = doc.get_new_xref()
    kids = []
    for i, st in enumerate(states):
        on = doc.get_new_xref()
        doc.update_object(on, "<< /Type /XObject /Subtype /Form /BBox [0 0 18 18] >>")
        doc.update_stream(on, b"0 g 9 9 m 4 9 4 4 9 4 c 14 4 14 14 9 14 c 4 14 4 9 9 9 c f")
        off = doc.get_new_xref()
        doc.update_object(off, "<< /Type /XObject /Subtype /Form /BBox [0 0 18 18] >>")
        doc.update_stream(off, b"")
        w = doc.get_new_xref()
        x0 = x + 40 * i
        y0 = page_h - y - 18
        doc.update_object(
            w,
            f"<< /Type /Annot /Subtype /Widget /Rect [{x0} {y0} {x0 + 18} {y0 + 18}] /Parent {parent} 0 R "
            f"/P {page.xref} 0 R /AS /{st if st == selected else 'Off'} "
            f"/AP << /N << /{st} {on} 0 R /Off {off} 0 R >> >> /F 4 >>",
        )
        kids.append(w)
    doc.update_object(
        parent,
        f"<< /FT /Btn /Ff 49152 /T ({name}) /V /{selected} /Kids [{' '.join(f'{k} 0 R' for k in kids)}] >>",
    )
    annots = doc.xref_get_key(page.xref, "Annots")
    refs = " ".join(f"{k} 0 R" for k in kids)
    if annots[0] == "array":
        doc.xref_set_key(page.xref, "Annots", annots[1][:-1] + f" {refs}]")
    else:
        doc.xref_set_key(page.xref, "Annots", f"[{refs}]")
    doc._radio_parent = parent


def forms(path: pathlib.Path) -> None:
    """Two pages of AcroForm fields, the second page turned by /Rotate 90.

    Page 1: text "name" (pre-filled), multiline "address", read-only "id",
    check box "agree", radio group "size" (S/M/L), combo box "country",
    multi-select list "langs". Page 2: text "note".
    """
    doc = fitz.open()
    p1 = doc.new_page(width=595, height=842)
    p1.insert_text((72, 60), f"{KEEP} form", fontsize=14)

    def add(page, kind, name, rect, **kw):
        w = fitz.Widget()
        w.field_type = kind
        w.field_name = name
        w.rect = fitz.Rect(*rect)
        for k, v in kw.items():
            setattr(w, k, v)
        page.add_widget(w)
        return w

    add(p1, fitz.PDF_WIDGET_TYPE_TEXT, "name", (72, 100, 300, 124), field_value="Ada", text_fontsize=12)
    add(p1, fitz.PDF_WIDGET_TYPE_TEXT, "address", (72, 140, 300, 200), field_flags=fitz.PDF_TX_FIELD_IS_MULTILINE, text_fontsize=0)
    add(p1, fitz.PDF_WIDGET_TYPE_TEXT, "id", (320, 100, 500, 124), field_value="ID-7", field_flags=fitz.PDF_FIELD_IS_READ_ONLY)
    add(p1, fitz.PDF_WIDGET_TYPE_CHECKBOX, "agree", (72, 220, 90, 238), field_value=False)
    radio_group(doc, p1, "size", ["S", "M", "L"], selected="M", x=72, y=260)
    add(p1, fitz.PDF_WIDGET_TYPE_COMBOBOX, "country", (72, 300, 300, 322), choice_values=[("iq", "Iraq"), ("de", "Germany")], field_value="iq")
    add(p1, fitz.PDF_WIDGET_TYPE_LISTBOX, "langs", (72, 340, 300, 420), choice_values=["Kurdish", "Arabic", "English"], field_flags=fitz.PDF_CH_FIELD_IS_MULTI_SELECT)

    acro = doc.xref_get_key(doc.pdf_catalog(), "AcroForm")
    fields_owner = int(acro[1].split()[0]) if acro[0] == "xref" else doc.pdf_catalog()
    key = "Fields" if acro[0] == "xref" else "AcroForm/Fields"
    fields = doc.xref_get_key(fields_owner, key)[1]
    doc.xref_set_key(fields_owner, key, fields[:-1] + f" {doc._radio_parent} 0 R]")

    p2 = doc.new_page(width=400, height=600)
    add(p2, fitz.PDF_WIDGET_TYPE_TEXT, "note", (50, 500, 250, 530), text_fontsize=10)
    p2.set_rotation(90)
    doc.save(path, garbage=4, deflate=True)
    doc.close()


def edit_text(path: pathlib.Path) -> None:
    """Text to replace in place.

    Page 1 (A4): lines in embedded Noto Sans (a CID font with /W widths, as
    most real PDFs), one of them on a light blue band. Page 2 is turned by
    /Rotate 90 and holds a Noto line and a Helvetica line (no widths, so a
    replacement there must fall back to flattening the page).
    """
    font = OUT.parent.parent.parent / "assets" / "fonts" / "NotoSans-Regular.ttf"
    doc = fitz.open()
    p1 = doc.new_page(width=595, height=842)
    p1.insert_font(fontname="noto", fontfile=str(font))
    p1.insert_text((72, 100), "Invoice number 12345 due today", fontname="noto", fontsize=14)
    p1.draw_rect(fitz.Rect(60, 130, 400, 160), color=None, fill=(0.8, 0.9, 1.0))
    p1.insert_text((72, 150), "Total amount 999 EUR", fontname="noto", fontsize=14)
    p1.insert_text((72, 200), f"{KEEP} below", fontname="noto", fontsize=12)
    p2 = doc.new_page(width=400, height=600)
    p2.insert_font(fontname="noto", fontfile=str(font))
    p2.insert_text((50, 100), "Turned page word REPLACEME here", fontname="noto", fontsize=12)
    p2.insert_text((50, 200), "Helvetica line OLDWORD", fontname="helv", fontsize=12)
    p2.set_rotation(90)
    doc.subset_fonts()  # real PDFs embed only the glyphs they use
    doc.save(path, garbage=4, deflate=True)
    doc.close()


def encrypted(path: pathlib.Path) -> None:
    doc = fitz.open()
    doc.new_page().insert_text((72, 72), KEEP)
    doc.save(path, encryption=fitz.PDF_ENCRYPT_AES_256, user_pw="", owner_pw="owner")
    doc.close()


def main() -> None:
    rich(OUT / "rich_classic.pdf", objstm=False)
    rich(OUT / "rich_objstm.pdf", objstm=True)
    incremental(OUT / "incremental.pdf")
    inherited(OUT / "inherited.pdf")
    images(OUT / "images.pdf")
    forms(OUT / "forms.pdf")
    edit_text(OUT / "edit_text.pdf")
    encrypted(OUT / "encrypted.pdf")
    (OUT / "truncated.pdf").write_bytes((OUT / "rich_classic.pdf").read_bytes()[:900])


if __name__ == "__main__":
    main()
