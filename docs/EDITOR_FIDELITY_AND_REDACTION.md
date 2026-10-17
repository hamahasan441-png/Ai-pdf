# Editor: redaction, export fidelity and RTL text

What the Pdoczy editor does today, what the tests prove, and what is still
missing. Keep this in step with the code; do not describe a limitation here as
fixed until a test shows it.

## Redaction

There are two operations, and the editor asks which one the user wants each
time a box is drawn with the Redact tool
(`editor_redaction_choice_dialog.dart`).

**Visual cover.** A black rectangle (`visualCoverKey`). It is burned into the
exported page image. The original PDF on disk is unchanged and still holds the
text. This is not redaction.

**Secure redaction.** Only after the user taps *Upload and redact*:

1. The drawn box is mapped back to the source page
   (`RedactionService.toSourcePageRect`), undoing the user's session rotation;
   the display index is mapped to the source page through `_sourcePages`.
2. The working PDF is uploaded to `POST /api/v1/document-ai/redact` as
   `document.pdf` (the device file name is not sent).
3. `backend/app/services/pdf/secure_redact.py` validates every area (finite,
   inside 0..1, non-empty, page in range, valid fill) and rejects the whole
   request on any error. It maps the area through `page.derotation_matrix`,
   deletes annotations, links and form widgets that overlap it (and clears the
   deleted fields' values from `/AcroForm`), then runs PyMuPDF
   `apply_redactions` with image pixels blanked under the area and touched line
   art removed.
4. The output is reopened from its bytes and checked: same page count, no
   character centre inside any area, no annotation, link or widget overlapping
   it, no new off-page form field holding a value, and the rendered area shows
   the fill colour. Any failure returns an error and no PDF.
5. The response lists the passed checks in `X-Redaction-Verified`. The app
   accepts the file only if it starts with `%PDF-` and lists every check in
   `RedactionService.requiredServerChecks`, then swaps it in as the working
   document (same page count required) and keeps all marks, page order and
   rotations. The original file is not modified.

Inserted blank pages and image documents have no source PDF page, so only the
visual cover is offered there. There is no on-device secure redaction: `pdf`
3.11 and `pdfx` cannot remove existing content.

### Evidence

- `backend/tests/test_secure_redact_fixtures.py`: generated PDFs with
  `SECRET-REDACT-74192`; rotations 0/90/180/270, CropBox offsets, several pages,
  overlapping areas, images, invisible OCR text, FreeText, links, filled form
  fields; NaN/inf/out-of-range/non-numeric/empty areas, encrypted PDFs, garbage
  bytes, an engine exception and an engine that silently does nothing. Each
  successful case reopens the output and checks `get_text`, `search_for` and
  the raw bytes; unrelated text and images must survive.
- Run against the previous engine, 14 of these fail, including the rotated
  pages (the old code redacted the wrong rectangle and returned 200 with the
  secret intact).
- Passes on PyMuPDF 1.24.10 / Python 3.11 (the CI pins) and 1.28.2 / 3.13.
- `frontend/test/editor/secure_redaction_client_test.dart`: the client's
  acceptance rules, coordinate mapping for 0–3 quarter turns, and refusal of
  bad regions before any upload.

### Limits

- The checks cover ordinary text extraction, search, annotations, links, form
  fields and the rendered area. They are not a forensic guarantee.
- Document metadata, XMP, bookmarks and attachments are not scrubbed.
- A value stored on a parent form field shared by widgets outside the area is
  kept, because it is still shown there.
- The UI flow (dialog → upload → swap) has no widget test; the parts are tested
  separately and the client was run once by hand against a local backend.

## Export

`EditorExportService` renders every page to a bitmap, paints the marks on it
and wraps the bitmaps in a new PDF. The output therefore loses the source's
text layer (original text is not selectable or searchable), vector objects,
links, annotations, form fields, bookmarks and metadata. `pdf` 3.11 can only
create documents and `pdfx` can only render them, so there is no way to carry
source objects across with the current engines. Preserving them needs a PDF
engine that edits existing files (for example a PDFium or MuPDF binding);
that is not done.

Because the source text is not copied, a visual cover in an export does hide
the covered text in that exported file. It does not touch the original.

Fixed in this pass:

- A page that cannot be rendered, rotated, or composited (including an
  undecodable inserted image) now stops the export with `ExportPageException`
  naming the page. It used to be skipped, giving a shorter PDF.
- Vector text is placed in the same box as the preview and the raster path
  (anchored at its position, shrink-wrapped until it wraps). A one-line RTL
  label used to be pushed to the right margin.
- On-screen re-renders use the source page and the session rotation. After a
  delete, duplicate, insert or rotate, a page evicted from the 3-page cache
  used to come back as the wrong PDF page or unrotated.

### Evidence

- `frontend/test/golden/export_page_golden_test.dart` compares the export
  compositor's page image pixel by pixel (0.5 % tolerance) with Sorani,
  Arabic, mixed RTL/LTR, digits, bold, rotated Latin text, a coloured
  background, a table and both kinds of black box, plus a rotated page.
  Removing the black-box burn-in fails both goldens (3.0–3.4 % difference).
- The source page in these goldens is a synthetic bitmap: `pdfx` cannot open a
  PDF under `flutter test`. Rendering real PDFs end to end is not covered.

## RTL and Unicode text

Fonts are bundled; see `frontend/assets/fonts/README.md` for licences,
checksums and measured glyph coverage.

Vector (searchable) export is used only when `pdf` 3.11 can shape the text
correctly: every character is in the chosen font, every Arabic-script letter
has presentation forms in `pdf`'s shaper, and the text does not mix RTL and
Latin letters. Sorani text almost always contains ڕ ڵ ێ ە or ۊ, which that
shaper cannot join, so Sorani is painted into the page image: correct shapes,
not searchable. Exported vector Arabic is stored as presentation forms; it
extracts, and matches after NFKC normalisation, but plain PyMuPDF
`search_for` with base letters does not find it.

## Not done

- Native editing of existing PDF text. Edits are overlays (a box covering the
  old text plus new text) and the UI says so.
- Preserving source PDF objects on export (see above).
- A full open → edit → undo/redo → save → reopen widget test.
- Translations for the new redaction strings (English only; other locales fall
  back to English).
