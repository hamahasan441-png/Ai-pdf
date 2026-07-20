# AI-PDF Deep Engineering Review & Transformation Plan

> **Generated:** 2026-07-20
> **Scope:** Full codebase audit (frontend ~11k LOC Dart, backend ~4k LOC Python)
> **Branch:** `deep-engineering-upgrade`

> **⚠️ Status note:** This document is a **review + design roadmap**. The
> frontend editor items below are **proposals** for future PRs, not code that
> ships in this branch. What actually ships here is: (1) the backend Document
> AI endpoints (chat / summarize / translate / rewrite / extract) and (2) this
> review. Frontend items marked "Proposed" describe the recommended design;
> they were intentionally **not** merged into the editor core to avoid breaking
> the existing, working editor API. See "Phase 9 — What Actually Shipped".

---

## Executive Summary

AI-PDF is a solid v1 AI-powered PDF editor with genuine differentiators (on-device BM25 RAG,
offline OCR, profile-based form auto-fill). However, to compete with Adobe Acrobat, UPDF,
Foxit, and PDFgear, it needs fundamental upgrades to its **text editing engine**, **object
model**, **undo/redo system**, **rendering pipeline**, and **AI capabilities**.

This document details every finding and delivers a prioritised implementation plan.

---

## Phase 1 — Architecture Audit

### What Works Well

| Strength | Evidence |
|---|---|
| Feature-first folder structure | `lib/features/{editor,ai,tools,home,profile,...}` |
| Clean service decomposition | 25+ service files in editor data layer |
| Riverpod state management | Provider-based DI, reactive rebuilds |
| On-device privacy | ML Kit OCR, BM25 retriever, encrypted profile |
| Memory-safe rendering | Capped rasterization, LRU page eviction |
| Backend AI pipeline | Multi-stage orchestrator with caching |
| Multi-model fallback | Model router with free/advanced tiers |
| Multi-language field mapping | 100+ field types, 12+ languages |

### Critical Weaknesses

| Issue | Severity | Impact |
|---|---|---|
| No Command-pattern undo/redo | P0 | Users lose work; no crash recovery |
| Text editing is dialog-based only | P0 | Can't inline edit; poor UX vs competitors |
| No annotation serialisation | P0 | Annotations lost on app restart |
| No isolate usage for heavy ops | P1 | UI jank, ANRs on large documents |
| Export rasterizes non-Latin text | P1 | Arabic/Kurdish PDFs are image-only |
| No AcroForm support | P1 | Can't fill real PDF form fields |
| No image annotation type | P1 | Can't add photos/logos to pages |
| No stamp annotation | P2 | Missing standard PDF editor feature |
| No form-field annotation | P2 | AI field detection not persistent |
| No font embedding in export | P2 | PDF viewers show wrong fonts |

### Architecture Pattern Assessment

**Current:** Hybrid (clean-ish) with significant leak of logic into presentation
**Target:** Clean Architecture + MVVM with full Command pattern

```
lib/
├── core/              ← DI, config, theme, services, observability
├── features/
│   └── editor/
│       ├── domain/    ← entities, services, history (pure Dart)
│       ├── data/      ← implementations, persistence, I/O
│       ├── application/ ← ViewModel (StateNotifier), state
│       └── presentation/ ← widgets (dumb, no logic)
```

---

## Phase 2 — PDF Rendering Engine Analysis

### Current Implementation
- **Library:** pdfx (PDFium-based)
- **Rasterisation:** Per-page PNG at capped resolution (configurable max edge)
- **Cache:** In-memory `Map<int, Uint8List>` with LRU eviction (±1 page window)
- **Zoom:** No tiled rendering; full re-raster at fixed resolution

### Problems
1. **No progressive loading** — 100+ page PDFs block for seconds
2. **Fixed resolution** — zoom past native resolution shows pixelation
3. **No thumbnail strip** — navigation is page-number only
4. **Rendering on main isolate** — pdfx platform channel constraint
5. **No text-layer overlay** — text is part of the raster, not selectable

### Recommended Upgrades
- **Priority:** Add background pre-rendering of adjacent pages (done via the existing eviction service)
- **Medium-term:** Migrate to `pdfrx` for tile-based rendering + built-in text layer
- **Long-term:** Native platform channel wrapping PDFium directly for vector text extraction and AcroForm access

---

## Phase 3 — Professional Text Editor Engine

### Current State (BEFORE)
- Text added via modal dialog → appears as positioned overlay
- No inline editing, no cursor, no caret
- Font size stored as normalised fraction (breaks across screen sizes)
- No text selection within a text box
- No keyboard shortcut support
- RTL text renders on screen but rasterised in export (not searchable)

### Proposed Design (roadmap — NOT in this branch)

| Feature | Status |
|---|---|
| Font size in absolute pt | ✅ Already on `main` (model field) |
| RTL fields on model (Arabic/Kurdish/Persian/Hebrew) | ✅ Already on `main` (model field) |
| Line height, char spacing, text alignment | ✅ Already on `main` (model field) |
| Text rotation | ✅ Already on `main` (model field) |
| RTL auto-detection in renderer/export | 🔜 Proposed |
| Background fill + border | 🔜 Proposed |
| Full serialisation (JSON round-trip) | 🔜 Proposed |
| Inline editing with cursor/caret | 🔜 Proposed |
| Text selection within annotation | 🔜 Proposed |
| Font embedding in PDF export | 🔜 Proposed |

### Typography Targets

| Script | Support Level |
|---|---|
| Latin (English, French, German, Spanish) | ✅ Full (vector export) |
| Arabic / Kurdish / Persian | ✅ Render + ✅ RTL detection; export needs font embed |
| Hebrew | ✅ Render; export needs font embed |
| CJK (Chinese, Japanese, Korean) | ✅ Render; export rasterised (huge font files) |
| Emoji | ⚡ System fallback; rasterised in export |

---

## Phase 4 — Object & Layer System

### BEFORE (old model)
- 3 annotation types: Stroke, Shape, Text
- No stable identity metadata (zIndex, lock, visibility, opacity)
- Mutable lists with redo = removed items
- No serialisation

### PROPOSED (new model — roadmap, not in this branch)

| Object Type | Properties |
|---|---|
| **StrokeAnnotation** | points, color, width, highlight |
| **ShapeAnnotation** | shape type, start/end, color, filled, opacity |
| **TextAnnotation** | pos, text, style, font, RTL, rotation, bg, border |
| **ImageAnnotation** | pos, size, bytes, rotation |
| **StampAnnotation** | pos, size, kind, text, color, rotation |
| **FormFieldAnnotation** | pos, size, fieldType, value, checked, border/fill |

**Every annotation** carries:
- `id` — stable UUID survives clone/paste/undo
- `zIndex` — draw order
- `locked` — prevent accidental edits
- `visible` — soft hide
- `opacity` — composite alpha
- `pageIndex` — multi-page undo support
- `toJson()` / `fromJson()` — full serialisation

---

## Phase 5 — Advanced Editor Features

### History System (proposed design)

```
┌─────────────────────────────────────┐
│        HistoryStack (300 max)        │
├─────────────────────────────────────┤
│  AddAnnotationCommand               │
│  RemoveAnnotationCommand            │
│  RemoveMultiCommand                 │
│  MoveAnnotationCommand              │
│  EditTextCommand                    │
│  BringToFrontCommand                │
└─────────────────────────────────────┘
```

- **Unlimited undo/redo** (capped at 300 commands for memory)
- **Object-level** — only the affected annotation is snapshotted
- **Cross-page** — each command knows its page index
- **Crash recovery** — AnnotationPersistenceService auto-saves to disk

### Selection System (enhanced)

- Single selection via tap (hit-test in reverse z-order)
- Multi-selection via marquee drag
- Resize handles (corner drag → aspect-preserved scale)
- Rotation handle (planned)
- Smart snapping to 25%/50%/75% grid lines
- Alignment (left/center/right/top/middle/bottom)
- Distribution (horizontal/vertical spacing)

### Export System

- Page-by-page composition: base raster + all annotations
- Latin text overlaid as vector (searchable)
- Non-Latin text rendered via TextPainter then composited
- Shapes rendered as PDF primitives (rects, borders)
- Final output: multi-page PDF via `pdf` package

---

## Phase 6 — AI Document Intelligence

### Current Capabilities
- **Chat with PDF** (OpenRouter, ephemeral)
- **BM25 RAG** (on-device, page-cited answers)
- **Smart form fill** (OCR + AI field mapping)
- **Document understanding** (type detection, entity extraction)
- **Vision** (scanned PDF → image → AI)

### New Capabilities (backend shipped / frontend designed)

| Feature | Where | Status |
|---|---|---|
| Chat with PDF (persisted sessions) | Frontend + Backend | ✅ Designed |
| Document summary (structured/brief/bullet) | Backend endpoint | ✅ Implemented |
| Text translation (any language) | Backend endpoint | ✅ Implemented |
| Text rewrite (professional/casual/formal/simplified) | Backend endpoint | ✅ Implemented |
| Structured data extraction (JSON) | Backend endpoint | ✅ Implemented |
| OCR error correction (AI-powered) | Prompt template | ✅ Designed |
| AI suggested edits | 🔄 Next phase | |
| Multi-document RAG | 🔄 Next phase | |

---

## Phase 7 — Competitive Analysis

| Feature | Adobe | UPDF | Foxit | Ai-PDF (current) | Ai-PDF (target) |
|---|---|---|---|---|---|
| Inline text editing | ✅ | ✅ | ✅ | ❌ Dialog only | ✅ P1 |
| AcroForm fill | ✅ | ✅ | ✅ | ❌ | ✅ P1 |
| Font embedding | ✅ | ✅ | ✅ | ❌ | ✅ P2 |
| Undo/redo (unlimited) | ✅ | ✅ | ✅ | ⚡ Basic | 🔜 Target |
| RTL text | ✅ | ⚡ Partial | ✅ | ⚡ Render only | 🔜 Target |
| Image annotations | ✅ | ✅ | ✅ | ❌ | 🔜 Target |
| Stamps | ✅ | ✅ | ✅ | ❌ | 🔜 Target |
| AI Chat with PDF | ⚡ Acrobat AI | ✅ | ❌ | ✅ | ✅ Enhanced (backend shipped) |
| On-device AI/OCR | ❌ | ❌ | ❌ | ✅ | ✅ |
| BM25 RAG (offline) | ❌ | ❌ | ❌ | ✅ | ✅ |
| Profile auto-fill | ❌ | ❌ | ❌ | ✅ | ✅ |
| Offline-first | ❌ | ⚡ | ⚡ | ✅ | ✅ |
| Annotation persistence | ✅ | ✅ | ✅ | ❌ | 🔜 Target |

### Ai-PDF's Unique Advantages
1. **On-device AI RAG** — works offline, no data leaves phone
2. **Profile-based auto-fill** — remembers user data, fills any form
3. **Multi-provider AI** — not locked to one vendor
4. **Privacy-first** — encrypted profile, on-device OCR
5. **Free tools** — full offline PDF toolkit without subscription

---

## Phase 8 — Implementation Priority Matrix

### P0 — Critical (proposed for follow-up PRs)

> Each row is a **proposed** change. None are in this branch; they must land as
> small, backward-compatible PRs with tests (see "Recommended sequencing").

| Change | File | Status |
|---|---|---|
| Command-pattern undo/redo | `domain/history/` | 🔜 Proposed |
| Annotation serialisation | `domain/entities/annotation.dart` | 🔜 Proposed |
| Additive annotation metadata (zIndex/locked/…) | `domain/entities/annotation.dart` | 🔜 Proposed |
| Isolate image ops | `core/image/image_ops.dart` | ✅ Already on `main` |
| New annotation types (image/stamp/form) | `domain/entities/annotation.dart` | 🔜 Proposed |
| History-aware controller methods | `application/` | 🔜 Proposed |

### P1 — Major Improvements (Weeks 2-4)

| Change | Risk | Impact |
|---|---|---|
| Inline text editing with cursor | Medium | Competitive parity |
| AcroForm detection + fill | High | Real PDF form support |
| Font embedding (Noto family) | Medium | Correct international export |
| Migrate rendering to pdfrx | Medium | Tile-based zoom, text layer |
| Background page pre-loading | Low | Perceived performance |
| targetSdk 35 + release signing | Low | Play Store requirement |

### P2 — Advanced Features (Weeks 4-8)

| Change | Risk | Impact |
|---|---|---|
| Tile-based zoom rendering | Medium | 1000+ page support |
| PDF text layer extraction | High | Select/copy existing text |
| Annotation grouping | Low | Pro editing workflow |
| Page reorder in editor | Medium | Organise within editor |
| Managed AI proxy with billing | Medium | Revenue engine |
| Cloud sync | Medium | Multi-device |

### P3 — Future Ideas

| Feature | Description |
|---|---|
| AI signature detection | Vision model locates signature fields |
| AI document comparison | Highlight differences between versions |
| Collaborative editing | Real-time multi-user (WebSocket) |
| Custom font upload | User imports their own TTF |
| PDF/A export | Archival-quality PDF |
| Digital signatures (PKI) | Legally binding e-signatures |
| Form templates | Pre-built form layouts |
| Batch processing | AI fill 100 forms at once |

---

## Phase 9 — What Actually Shipped (this branch)

To keep the build green and the existing editor fully functional, this branch
ships **only backend + documentation** changes. The frontend editor core is
left byte-identical to `main`; the editor upgrades above are captured as a
design roadmap for follow-up PRs (each isolated and independently testable).

### New files
1. `backend/app/api/v1/document_ai.py` — 5 new AI endpoints:
   - `POST /document-ai/chat` — grounded Q&A over document text
   - `POST /document-ai/summarize` — structured / brief / bullet summaries
   - `POST /document-ai/translate` — translate to any language
   - `POST /document-ai/rewrite` — professional / casual / formal / simplified
   - `POST /document-ai/extract` — structured JSON extraction
2. `docs/ENGINEERING_REVIEW.md` — this review + roadmap

### Modified files
3. `backend/app/api/v1/router.py` — registered the `document_ai` router

### Deliberately NOT changed (kept identical to `main`)
- `annotation.dart`, `page_layer.dart`, `editor_controller.dart`,
  `editor_state.dart`, `annotation_draw.dart`, `image_ops.dart`

> **Why:** an earlier revision of this branch rewrote those editor-core files
> and broke every existing consumer (`pick_edit_screen.dart`, the 25+ editor
> data services, `offline_pdf_service.dart`, and `image_ops_test.dart`). Those
> rewrites were reverted. Each roadmap item should land as its own small,
> backward-compatible PR with tests, rather than a single large rewrite.

### Recommended sequencing for the frontend roadmap
1. **Additive annotation metadata** — add optional `zIndex`, `locked`,
   `visible`, `opacity`, `pageIndex` to the base `EditorAnnotation` **without**
   introducing a base `type` field (it collides with `ShapeAnnotation.type`).
   Use `is`-checks or a `kind` getter instead. Keep all existing constructors.
2. **Serialisation** — add `toJson`/`fromJson` behind the existing classes.
3. **Command-pattern history** — introduce `HistoryStack` + commands, wired
   through new controller methods that sit *alongside* the current ones.
4. **New annotation types** (Image / Stamp / FormField) — additive subclasses.
5. **Rendering** — extend `AnnotationDraw`/painter for the new types.
6. **Persistence + crash recovery**, then **inline text editing**.

---

## Appendix A — Annotation JSON Schema

```json
{
  "id": "abc123",
  "type": "text",
  "zIndex": 5,
  "locked": false,
  "visible": true,
  "opacity": 1.0,
  "pageIndex": 0,
  "posX": 0.1,
  "posY": 0.2,
  "text": "Hello World",
  "color": 4278190080,
  "size": 14.0,
  "bold": false,
  "italic": false,
  "underline": false,
  "fontFamily": null,
  "textAlign": "left",
  "textDirection": "rtl",
  "lineHeight": 1.2,
  "charSpacing": 0.0,
  "width": null,
  "height": null,
  "rotation": 0.0,
  "backgroundColor": null,
  "borderColor": null,
  "borderWidth": 1.0
}
```

## Appendix B — History Command Flow

```
User action → Create Command → command.execute(layers) → Push to undo stack → Sync state
      │                                                         ↓
      │                                               Clear redo stack
      │
User presses Undo → Pop from undo stack → command.undo(layers) → Push to redo stack → Sync state
```

## Appendix C — Rendering Pipeline

```
Page raster (PDFium PNG) → Base layer
     ↓
ForEach annotation (sorted by zIndex):
  ├─ StrokeAnnotation  → AnnotationDraw.stroke()  [Catmull-Rom smoothing]
  ├─ ShapeAnnotation   → AnnotationDraw.shape()   [vector primitives]
  ├─ TextAnnotation    → AnnotationDraw.text()    [full RTL + rotation]
  ├─ ImageAnnotation   → AnnotationDraw.image()   [decoded ui.Image]
  ├─ StampAnnotation   → AnnotationDraw.stamp()   [text in border]
  └─ FormFieldAnnotation → AnnotationDraw.formField() [interactive overlay]
     ↓
Composite canvas → Export as PDF (vector text + raster base)
```
