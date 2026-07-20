# AI‑PDF — Deep Masterplan: Editor · Text Editing · Smart Forms · Document Intelligence

> A focused, deep engineering plan for the four pillars the product must win on.
> Grounded in the real repository (Flutter frontend + FastAPI backend) and
> benchmarked against the strongest 2026 competitors. Every item is labelled
> **Now** (exists), **Fix** (bug/gap), or **Build** (new), with real file paths,
> algorithms, risk, and sequencing so each lands as a small, verifiable PR.
>
> Companion docs: `MASTER_ENGINEERING_PLAN.md` (whole product), `ENGINEERING_REVIEW.md`.

---

## 0. Strategy — where we win

The 2026 market has made AI assistance **table stakes**; incumbents differentiate
on multi‑file reasoning, cited answers, structured summaries/mind‑maps, and
Word‑like inline editing (see Sources). None of the mainstream mobile editors
lead on **privacy + offline + zero‑setup AI + personal‑profile autofill** — that
is our moat. The plan below deepens the four pillars *around that moat* rather
than copying desktop feature lists.

**Design tenets**
1. **On‑device first, managed AI second.** Everything that can run locally
   (OCR, BM25 retrieval, field ontology, autofill) does; the server adds only
   what needs a large model. This is our privacy + cost advantage.
2. **Never mutate the user's document silently.** AI proposes; the user reviews
   and accepts (review sheets already exist — keep that contract everywhere).
3. **One coordinate system, one render path.** Normalized 0..1 coords + a single
   `AnnotationDraw` used by screen *and* export (already true — protect it).
4. **Small, compiled, tested changes.** The editor refactor bugs we just fixed
   (blank export, inverted auto‑fit) came from large *uncompiled* changes. Never
   again: each PR compiles + `flutter analyze` + tests before merge.

---

## Pillar 1 — Professional Text Editing Engine

### Current state (real files)
- `domain/entities/annotation.dart::TextAnnotation` already carries pt‑style
  fields: `textAlign`, `textDirection`, `lineHeight`, `charSpacing`, `width`,
  `height`, `rotation`, plus `id` (stable identity from PR #86/#88).
- Rendering: `data/annotation_draw.dart::text()` uses a `TextPainter` with
  `fontSize = size * canvasHeight` (size is **height‑normalized**, not pt — the
  doc comment is aspirational; the renderer and all callers agree on normalized).
- Editing is **modal**: `presentation/widgets/editor_text_dialog.dart` — no
  in‑canvas caret, no intra‑box selection.
- Export: `data/editor_export_service.dart` overlays Latin‑1 text as real vector
  `pw.Text` (selectable); non‑Latin is rasterized via `AnnotationDraw.text`.

### Gaps vs the best (Word‑like editing — PDFgear/UPDF/Acrobat)
| Capability | Us now | Target |
|---|---|---|
| Inline caret + edit in place | ❌ modal dialog | **Build** |
| Intra‑box text selection / caret navigation | ❌ | **Build** |
| RTL shaping in render + export (Arabic/Kurdish/Persian) | ⚡ render only | **Build** |
| Font embedding (Noto/Vazirmatn) → searchable non‑Latin export | ❌ raster | **Build** |
| Multi‑line paragraph reflow + wrapping | ⚡ painter wraps, no editing | **Build** |
| Per‑run styling (bold/italic within a box) | ❌ whole‑box only | **Build (P2)** |

### Deep design
1. **`InlineTextEditor` overlay (P1).** Replace the dialog with a positioned
   `EditableText`/`TextField` overlaid at the annotation's screen rect
   (`pdfToScreen` transform, see Pillar 2). Bind a `TextEditingController` to the
   `TextAnnotation.text`; live‑repaint via the existing painter. Commit on blur
   → push one `EditTextCommand` (from the DOM/History foundation, PR #88) so it's
   a single undo step. Caret, selection, copy/paste, and the system keyboard
   come for free from `EditableText`.
2. **Coordinate transform (P1 prerequisite).** Add
   `domain/services/page_coordinate_transform.dart` with
   `Offset screenToPdf(Offset, Size)` / `Rect pdfToScreen(Rect, Size)` and the
   current zoom/pan matrix from `InteractiveViewer`. The overlay editor needs
   the exact on‑screen rect of the box at any zoom.
3. **RTL + complex scripts (P1).** In `AnnotationDraw.text`, detect direction
   from the text runes (Arabic 0x0600–06FF, Hebrew 0x0590–05FF, etc.) when
   `textDirection == null`; pass to `TextPainter`. In export, stop treating
   "non‑Latin ⇒ raster": embed a Noto family and emit vector `pw.Text` with
   `textDirection`. Ship fonts as assets (`pubspec.yaml`): NotoSans,
   NotoSansArabic, Vazirmatn (Kurdish/Persian), NotoSansHebrew.
4. **Font registry (`editor_pdf_fonts.dart` extension).** Map family+bold+italic
   → embedded TTF once, reuse across pages (memory‑bounded).
5. **Original improvement (ours):** **AI‑assisted text tools inline** — with a
   text box selected, a mini‑bar offers *Rewrite / Translate / Fix grammar*
   using the on‑device→managed pipeline (Pillar 4). Competitors bolt AI onto a
   side chat; we put it on the object being edited, review‑gated.

### Risk / sequencing
`PageCoordinateTransform` → `InlineTextEditor` → RTL render → font embedding →
per‑run styling. Each independently testable with golden tests on export.

---

## Pillar 2 — Editor Core (object model, history, rendering, export)

### Current state
- Object model: Stroke/Shape/Text with stable `id`; `PageLayer{items, redo}`.
- History: flat `items.removeLast()` + `redo` list (single‑level, in‑memory).
  The Command‑pattern foundation exists (`domain/history/` from PR #88) but the
  editor screen still uses the flat path.
- Rendering: `EditorPageRenderService` (PNG + rounded dims — reliable on Android
  after the #85 follow‑up fix). Cache: ±1 page LRU, cap 3.
- Export: `EditorExportService` (PNG base now — matches viewer after our fix).

### Gaps / plan
| Item | State | Plan |
|---|---|---|
| Command‑pattern undo/redo wired into the screen | foundation only | **Build (P0)** — dispatch `Add/Remove/Move/EditText/Reorder` commands; unlimited, object‑level |
| Annotation persistence + crash recovery | ❌ | **Build (P0)** — `toJson/fromJson` + autosave to disk keyed by file hash; restore on reopen |
| Image / Stamp / Form‑field objects | ❌ | **Build (P1)** — additive subclasses (no base `type` clash with `ShapeAnnotation.type`) |
| Tile‑based zoom (1000+ pages, crisp) | ❌ fixed raster | **Build (P2)** — migrate viewer to `pdfrx` tiles + text layer |
| Background pre‑render of adjacent pages | ❌ | **Build (P1)** — perceived‑instant paging |
| Export fidelity golden tests | ❌ | **Build (P1)** — lock pixel/vector parity so refactors can't silently break export again |

### Deep design — persistence & crash recovery (P0)
`data/annotation_persistence_service.dart`: serialize `Map<int,PageLayer>` to
`{version, fileHash, pages:{i:[annJson…]}}` under app docs dir; debounced
autosave after each command; load on open before first render. This directly
counters the class of data‑loss users hate and no offline mobile competitor does
well.

### Original improvement (ours)
**Deterministic, replayable edit log.** Because every mutation is a serialized
command, we can (a) crash‑recover, (b) offer "revision history" without a server,
and (c) later enable *local, privacy‑preserving* collaboration by shipping the
command log — not the document — between devices.

---

## Pillar 3 — Smart Form Filling

### Current state (a genuine strength)
- On‑device detection: `data/ocr_field_detection_service.dart` (glyph +
  shape + keyword heuristics → checkbox/radio/text/date/signature).
- Ontology: `features/tools/services/form_ontology.dart` — 100+ labels, 12+
  languages, diacritic‑folding (ä→ae, ß→ss) for OCR‑tolerant matching.
- Matching: `profile_field_matcher.dart` + `smart_form_filler.dart` — multi‑signal
  scoring, checkbox option resolution, German date normalization (TT.MM.JJJJ).
- UX: instant tap‑to‑fill, type‑aware inputs, **review sheet before placing**,
  replicate‑to‑matching‑fields, auto‑fit (now correct after our aspect‑ratio fix).

### Gaps vs the best
| Capability | Us | Target |
|---|---|---|
| **True AcroForm** read/fill (native PDF fields) | ❌ overlay only | **Build (P1)** — read `/AcroForm`, fill real widgets, keep them interactive |
| Semantic field understanding beyond keywords | ⚡ ontology | **Build (P1)** — server `understand-form` (LLM) as fallback when heuristics are unsure |
| Field validation (email/IBAN/date/phone) with inline errors | ⚡ partial | **Build (P1)** |
| Cross‑field logic (e.g. total = sum, date ranges) | ❌ | **Build (P2)** |
| Save/reuse "form profiles" per document type | ❌ | **Build (P2)** |

### Deep design
1. **AcroForm engine (P1).** Backend `pypdf`/`PyMuPDF` can enumerate real form
   fields with rects + types. Add `/document-ai/acroform` → returns field graph;
   client fills native widgets so the output stays a *real* fillable PDF (what
   Acrobat/Foxit do). Keep the overlay path for scanned/flat PDFs.
2. **Hybrid detection (P1).** Heuristics first (instant, offline). When a field's
   confidence is low, batch the uncertain labels to `/document-ai/understand-form`
   (below) for semantic classification + suggested profile mapping. Cheap: only
   the labels, not the document.
3. **Validation layer.** Extend `FieldType` with validators; the review sheet
   flags invalid values before placing (extends the existing confidence badges).

### Original improvement (ours)
**"Fill from anything" + memory.** Combine profile + an uploaded info doc
(already possible) *and remember* the resolved answers per label so the next
similar form fills even faster — all on device, encrypted. Competitors require
cloud accounts; ours is private by construction.

---

## Pillar 4 — AI Document Intelligence

### Current state
- On‑device RAG: `core/services/bm25_retriever.dart` (BM25, page‑cited answers,
  no model download) + ML‑Kit OCR — the privacy/offline core.
- Managed backend (`api/v1/document_ai.py`): `chat`, `summarize`, `translate`,
  `rewrite`, `extract`, `fix-ocr` (this branch) — all metered via the shared
  `usage_limiter` (503 / 429 / Pro‑unlimited).

### Gaps vs the best (Claude/pdf.ai/ChatPDF/UPDF/Acrobat AI)
| Capability | Us | Target |
|---|---|---|
| Structured "insights" (type + entities + dates + amounts + actions) | ⚡ partial | **Build (P1)** — `analyze` (this branch) |
| Suggested questions / next actions | ❌ | **Build (P1)** — part of `analyze` |
| Multi‑document reasoning / compare | ❌ | **Build (P2)** — multi‑doc BM25 index + cross‑cite |
| Mind‑map / outline view of a document | ❌ | **Build (P2)** — from `analyze` outline |
| Long‑context handling for big PDFs | ⚡ top‑K chunks | **Build (P2)** — hierarchical map‑reduce summarize |
| On‑device semantic embeddings (better recall than BM25) | ❌ | **Build (P3)** — optional tiny embedder |

### Deep design
1. **`/document-ai/analyze` (P1, in this branch).** One grounded JSON call →
   `{document_type, language, summary, key_points[], entities{people,orgs,dates,
   amounts,ids}, action_items[], suggested_questions[]}`. Powers an "Insights"
   panel and seeds the chat's quick actions. Distinct from `summarize`/`extract`:
   it's the single structured "understand this document" call the UI needs.
2. **Multi‑document RAG (P2).** Generalize `Bm25Retriever` to index a small
   library; questions retrieve across docs with `[doc, page]` citations —
   matching the long‑context/multi‑file trend, but offline.
3. **Map‑reduce summaries (P2).** For big PDFs, summarize per chunk then reduce,
   so we don't lose the middle (the failure mode of naive context stuffing).

### Original improvement (ours)
**Grounded, private, cited by default.** Every answer cites `page N` from
on‑device retrieval; the managed model only sees the retrieved passages, never
the whole file unless the user opts in. This is a *privacy‑grade* alternative to
cloud‑upload assistants — a real, marketable difference.

---

## Consolidated roadmap (PR‑sized, sequenced)

**P0 — foundation (must, low‑risk)**
1. Wire Command‑pattern undo/redo into the editor screen.
2. Annotation serialization + autosave/crash‑recovery.
3. `PageCoordinateTransform` (unblocks inline editing).

**P1 — competitive parity + our AI edge**
4. `/document-ai/analyze` structured insights (**this branch**).
5. Inline text editor overlay (caret/selection).
6. RTL render + font embedding (Arabic/Kurdish/Persian searchable export).
7. AcroForm read/fill engine + `understand-form` semantic fallback.
8. Image/Stamp/Form‑field objects; background page pre‑render.
9. Export golden tests (lock fidelity).

**P2 — differentiation**
10. Multi‑document RAG + compare; mind‑map/outline; map‑reduce summaries.
11. Tile‑based zoom (`pdfrx`) + PDF text layer.
12. Form validation + cross‑field logic + reusable form profiles.

**P3 — future**
13. On‑device embeddings; local revision history; privacy‑preserving sync.

---

## Competitive benchmark (2026)

| Capability | Adobe Acrobat AI | UPDF | Foxit | PDFgear | ChatPDF / pdf.ai | **AI‑PDF (target)** |
|---|---|---|---|---|---|---|
| Chat w/ PDF + cited answers | ✅ | ✅ | ✅ | ⚡ | ✅ (cited) | ✅ **on‑device cited** |
| Structured insights/summary | ✅ | ✅ (mind‑map) | ✅ | ⚡ | ✅ | ✅ `analyze` + outline |
| Multi‑file reasoning | ⚡ | ⚡ | ⚡ | ❌ | ✅ (long‑ctx) | 🔜 multi‑doc RAG |
| Inline Word‑like text edit | ✅ | ✅ | ✅ | ✅ | ❌ | 🔜 inline editor |
| True AcroForm fill | ✅ | ✅ | ✅ | ✅ | ❌ | 🔜 AcroForm engine |
| RTL / Arabic‑Kurdish export | ✅ | ⚡ | ✅ | ⚡ | ❌ | 🔜 embedded + vector |
| Works fully offline | ❌ | ⚡ | ⚡ | ⚡ | ❌ | ✅ **core** |
| Zero‑setup AI (no key/account) | account | account | account | ⚡ | account | ✅ **managed + metered** |
| Private (no cloud upload) | ❌ | ❌ | ❌ | ⚡ | ❌ | ✅ **on‑device RAG** |
| Personal‑profile autofill | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ **unique** |

**Reading:** we will not out‑feature Acrobat/UPDF on desktop breadth. We win by
being the **private, offline, zero‑setup, forms‑and‑intelligence** app on mobile.

---

## Sources (2026 competitive context)
Competitor capabilities above were summarized (not quoted) from public
comparisons; content was rephrased for compliance with licensing restrictions:
- [UPDF vs Adobe Acrobat AI](https://updf.com/comparison/pl/adobe-acrobat-ai-vs-updf-ai/) — mind‑maps, structured summaries, chat‑with‑images.
- [Top AI PDF tools 2026 (guptadeepak.com)](https://guptadeepak.com/tools/top-5-ai-pdf-tools-2026/) — long‑context, multi‑file compare, structured extraction.
- [PDFgear](https://www.pdfgear.com/) — free, Word‑like text/image/form editing.
- [Foxit vs Adobe (pdnob)](https://www.pdnob.com/alternative/foxit-vs-adobe-acrobat.html) — Foxit ≈ most of Acrobat, cheaper.
- [Best PDF editors 2026 (PCWorld)](https://www.pcworld.com/article/407214/best-pdf-editors.html), [Product Hunt PDF editors](https://www.producthunt.com/categories/pdf-editor) — ChatPDF/pdf.ai = research Q&A + cited summaries.
