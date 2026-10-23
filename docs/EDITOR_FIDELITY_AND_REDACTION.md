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
4. Copies of the redacted text outside the page content follow a fixed
   policy. The "redacted text" is the phrase under each area plus distinctive
   tokens (digits, `@`, `-`, `_`, or 10+ characters).
   - Scrubbed: document info metadata, XMP, bookmark titles, alternate or
     actual text (`/Alt`, `/ActualText`, `/E`), and attachments whose name,
     description or content contain it.
   - Counted, not changed: visible copies the user did not select (page
     text, other annotations, form values elsewhere). The count is returned in
     `X-Redaction-Occurrences-Elsewhere` and shown to the user.
5. The output is reopened from its bytes and checked: same page count, no
   character centre inside any area, no annotation, link or widget overlapping
   it, no new off-page form field holding a value, the rendered area shows the
   fill colour, and no hidden copy remains. Any failure returns an error and no
   PDF.
6. The response lists the passed checks in `X-Redaction-Verified`. The app
   accepts the file only if it starts with `%PDF-` and lists every check in
   `RedactionService.requiredServerChecks` (an older server without the
   hidden-copy check is not trusted), then swaps it in as the working document
   (same page count required) and keeps all marks, page order and rotations.
   The original file is not modified. If another file was opened or the pages
   changed during the upload, the result is discarded.
7. After the swap, page images and the text layer are rebuilt from the
   redacted file, recovery data moves to it, and any earlier redacted copy this
   session wrote is deleted. Undo hides the black box but cannot bring the
   removed content back: it is no longer in the working file.

The endpoint reads the upload in chunks and stops at `MAX_UPLOAD_SIZE_MB`,
refuses non-PDF bodies (415) and more than 500 areas, and runs the engine in a
threadpool so it does not block other requests. Errors never include document
text or library exception text.

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
- Hidden copies: a fixture with the secret in the title, XMP, a bookmark,
  `/Alt` text and an attachment, plus a visible copy on another page. All hidden
  copies are gone, the visible one is counted and left, unrelated metadata
  stays, and skipping the scrub makes verification reject the file.
- Passes on PyMuPDF 1.24.10 / Python 3.11 (the CI pins) and 1.28.2 / 3.13.
- `frontend/test/editor/secure_redaction_client_test.dart`: the client's
  acceptance rules, coordinate mapping for 0–3 quarter turns, and refusal of
  bad regions before any upload.

### Limits

- The checks cover ordinary text extraction, search, annotations, links, form
  fields and the rendered area. They are not a forensic guarantee.
- Hidden-copy matching is textual. A copy stored in another encoding, inside
  an image, or split across strings is not found.
- The policy errs towards removal: a short phrase under the box (for example
  one word) also removes that word from the title.
- A value stored on a parent form field shared by widgets outside the area is
  kept, because it is still shown there.
- The UI flow (dialog → upload → swap) has no widget test; the parts are tested
  separately and the client was run once by hand against a local backend.

## Export

There are two export paths.

**Keep original (default for PDFs).** `EditorExportService.renderPreservingPdfFile`
parses the working PDF (`pdf_source/pdf_object_store.dart`: classic xref,
xref streams with predictors, object streams, `/Prev` chains, inherited page
attributes, repair by scanning) and writes a new file
(`pdf_source/preserving_pdf_writer.dart`):

- Every kept page keeps its original objects: searchable text, vectors,
  images, links, annotations, form fields and their values. Bookmarks,
  metadata and the rest of the catalog are kept too.
- The user's marks are drawn on top as a Form XObject, mapped through the
  page's CropBox and `/Rotate`. Marks that are vector in the image export
  (searchable text, rectangles) stay vector.
- The page tree is rebuilt for deletes, inserts, duplicates, reordering and
  rotations.
- This is a full rewrite, not an incremental update. Only objects reachable
  from the new catalog are written, so deleted pages and earlier revisions are
  not in the file.
- References to removed pages become null or are dropped from lists.
  Bookmarks to a removed page lose their destination. A field whose widgets
  were all on removed pages is dropped with its value.
- Duplicated pages get copies of the original's annotations except form
  widgets. Page labels are dropped when the page order changed.
- Pages whose marks hide content (a whiteout, which overlay text edits use,
  or a visual cover without server redaction) are saved as images, so the text
  under the mark is not in the file. The app lists those pages and asks first.
  Bookmarks and links to such a page point at its image replacement.
- Encrypted or unreadable PDFs are reported; the app asks before saving an
  image-only file instead. It never switches silently.
- The output is parsed again before success is reported, and is written to a
  `.partial` file that is renamed only when complete.

**Image only.** `renderToPdfFile` renders every page to a bitmap and wraps the
bitmaps in a new PDF. The source's text layer, vectors, links, annotations,
form fields, bookmarks and metadata are lost. It is used for image documents
and when the user chooses it after a keep-original export was not possible.

Also fixed:

- A page that cannot be rendered, rotated, or composited (including an
  undecodable inserted image) stops the export with `ExportPageException`
  naming the page. It used to be skipped, giving a shorter PDF.
- Vector text is placed in the same box as the preview and the raster path
  (anchored at its position, shrink-wrapped until it wraps). A one-line RTL
  label used to be pushed to the right margin.
- On-screen re-renders use the source page and the session rotation. After a
  delete, duplicate, insert or rotate, a page evicted from the 3-page cache
  used to come back as the wrong PDF page or unrotated.
- The in-app text extractor reads text inside Form XObjects, so Find works on
  marks in a keep-original export reopened in the app.

### Evidence

- `frontend/test/golden/export_page_golden_test.dart` compares the export
  compositor's page image pixel by pixel (0.5 % tolerance) with Sorani,
  Arabic, mixed RTL/LTR, digits, bold, rotated Latin text, a coloured
  background, a table and both kinds of black box, plus a rotated page.
  Removing the black-box burn-in fails both goldens (3.0–3.4 % difference).
- The source page in these goldens is a synthetic bitmap: `pdfx` cannot open a
  PDF under `flutter test`.
- `frontend/test/editor/pdf_source/preserving_export_test.dart` runs against
  synthetic PDFs from `frontend/test/fixtures/pdf/make_fixtures.py`: classic
  and object-stream xrefs, an incremental file, inherited attributes, an
  encrypted and a truncated file. It checks that original content streams are
  unchanged byte for byte, that deleted and flattened pages' content is not in
  the output, form field pruning, bookmark retargeting, overlay placement for
  all rotations, refusal of encrypted input, and that truncated or randomly
  corrupted input only ever parses or is refused (never crashes). A
  600-page document parses and is rewritten in reverse order in about 30 ms
  here.
- In CI the same tests keep their output, and
  `frontend/tool/verify_preserving_export.py` reopens it with MuPDF and qpdf. It
  checks syntax, text extraction and search, links, form widgets, rotation,
  bookmarks, metadata, and the rendered position of the marks.

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

## Undo, redo and recovery

History is per page (`EditorController`, `EditorHistory`). Fixed:

- Deleting, inserting or duplicating a page now moves each page's history
  with it (`shiftHistories`). Before, history stayed on the old index: after
  deleting page 1, undo on the new page 2 replayed the old page 2's commands
  against what had been page 3 and could insert one page's annotation into
  another.
- An annotation added to a page other than the current one (the redaction
  cover after an upload) is recorded on that page's history.
- The recovery file now stores the page order and rotations with the marks.
  Its page keys are positions in the edited document, so after a page edit
  and a crash the marks used to reopen on the wrong pages and rotations were
  lost. On open, the structure is restored with the marks; a recovery file
  whose structure or page keys do not fit the opened PDF is moved aside
  (`.corrupt`) instead of being applied. Files written before this change
  have no structure and are read in the PDF's own order.

Evidence: `frontend/test/editor/history_workflow_test.dart` (edit, restyle,
annotate, undo, redo, new edit clears redo, save, reopen, no duplicates;
empty history; repeated cycles; page isolation; history after page delete and
insert, which fails without the fix; structure round-trip, legacy files,
malformed and non-fitting structures). The screen's open path that applies the
structure has no widget test.

## Not done

- Native editing of existing PDF text. Edits are overlays (a box covering the
  old text plus new text) and the UI says so.
- Keep-original export of encrypted PDFs (the app asks before an image-only
  export instead).
- Removing the original text under an overlay edit while keeping the rest of
  the page as text: such pages are saved as images.
- A widget test of the editor screen itself (the workflow is tested at the
  controller and recovery-file level).
- Pre-existing translation gaps: 12 keys each in Arabic, German and Spanish,
  and most keys in Persian and Kurdish fall back to English. Every string added
  for redaction and export is translated in all six locales.
- Rendering and memory benchmarks on a device. Only the PDF parser and writer
  were timed, on this development machine.
