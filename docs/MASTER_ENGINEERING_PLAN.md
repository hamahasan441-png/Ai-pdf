# AI-PDF — Master Engineering Plan

> The single organizing document for the product. It is grounded in the actual
> repository (Flutter frontend + FastAPI backend) as audited on this branch,
> not in aspiration. Where something does not yet exist, it is labelled
> **Proposed**; where it exists, the real file path is cited.
>
> Companion docs: `docs/ENGINEERING_REVIEW.md` (detailed audit + roadmap),
> `docs/ARCHITECTURE.md`, `docs/CTO_REVIEW.md`, `docs/PROJECT_STATUS.md`.

---

# Part 1 — Identity & Vision

## 1.1 CTO Role
Own the technical outcome end to end: architecture, correctness, performance,
security, cost, and shipping cadence. Every decision is defended in writing
with trade-offs. No change lands that cannot be verified. The CTO's job here is
to turn a promising v1 into a defensible product with a real moat
(on-device, privacy-first AI) while keeping the build permanently green.

## 1.2 Engineering Mindset
- **Correctness before cleverness.** A feature that cannot be verified is not
  done. (Lesson already paid for on this branch: an unverifiable editor-core
  rewrite broke every consumer and had to be reverted.)
- **Small, reversible steps.** Each change is one PR, independently testable,
  backward-compatible. Big-bang rewrites are banned.
- **Additive over destructive.** Extend existing APIs; never silently change a
  contract that 25+ services depend on.
- **Measure, then optimize.** No performance work without a number to move.

## 1.3 Product Mission
The best **mobile-first, privacy-first** PDF editor: edit any PDF precisely on
a phone, fill any form with AI, and understand any document — with the heavy
intelligence running **on-device** wherever possible and a metered managed AI
backend for the rest.

## 1.4 World-Class Standards
- Smooth 60 FPS interaction on mid/low-end Android.
- 1000+ page and large scanned documents open without OOM.
- Pixel-perfect export: fonts, positions, and layout survive round-trip.
- International text (Arabic, Kurdish, Persian, Hebrew, CJK) renders correctly.
- Zero data leaves the device unless the user opts into managed AI.

## 1.5 Thinking Framework
For every task: (1) read the real code first, (2) state the contract and its
consumers, (3) design the smallest additive change, (4) define how it is
verified, (5) implement, (6) verify, (7) document the trade-off.

## 1.6 Product Philosophy
Offline-first, privacy-first, and honest about limits. AI assists; it never
silently rewrites a user's document. The free tier is genuinely useful; Pro
removes limits, not core capability.

## 1.7 Quality Rules
- Build must stay green at every commit.
- Frontend changes require a Flutter toolchain to compile/analyze/test —
  never merge Dart that was not compiled.
- Backend changes are gated by `ruff --select F` + `compileall`
  (`.github/workflows/backend-ci.yml`) and, going forward, tests.
- No duplicated dict keys, no undefined names, no unused imports (enforced).
- Every AI endpoint is metered and cannot leak unlimited free cost.

---

# Part 2 — PDF Editor Core

> Frontend lives under `frontend/lib/features/editor/` with a clean split:
> `domain/` (entities, services), `data/` (25+ services), `application/`
> (`EditorController` / `EditorState`), `presentation/` (widgets).

## 2.1 Rendering Engine
- **Current:** `data/editor_page_render_service.dart` rasterises pages via
  `pdfx` (PDFium) at a capped resolution with an in-memory LRU page cache
  (±1 page window). Renders on the main isolate (pdfx platform-channel
  constraint).
- **Gaps:** no tiled zoom (pixelation past native res), no progressive load,
  no thumbnail strip, no text layer.
- **Proposed:** background pre-render of adjacent pages; medium-term migrate to
  `pdfrx` for tile-based rendering + built-in text layer; long-term a native
  PDFium channel for vector text extraction and AcroForm access.

## 2.2 Text Engine
- **Current:** `domain/entities/annotation.dart::TextAnnotation` already stores
  font size in **pt** and carries RTL fields (`textDirection`, `textAlign`,
  `lineHeight`, `charSpacing`, `width`, `height`, `rotation`). Editing is
  **dialog-based** (`presentation/widgets/editor_text_dialog.dart`) — no inline
  caret/selection.
- **Proposed (highest priority for parity):** inline editing with a real caret,
  intra-box text selection, keyboard shortcuts, and RTL shaping in the renderer
  and export (currently non-Latin text is rasterised, not searchable).

## 2.3 Annotation Engine
- **Current:** `StrokeAnnotation`, `ShapeAnnotation`, `TextAnnotation` with a
  stable `id`; drawing shared via `data/annotation_draw.dart`. Apply/edit/hit-
  test split across `editor_annotation_apply_service.dart`,
  `editor_annotation_edit_service.dart`, `editor_hit_test_service.dart`.
- **Proposed:** `ImageAnnotation`, `StampAnnotation`, `FormFieldAnnotation` as
  **additive** subclasses; optional base metadata (`zIndex`, `locked`,
  `visible`, `opacity`, `pageIndex`) added **without** a base `type` field
  (it collides with `ShapeAnnotation.type`).

## 2.4 Layer System
- **Current:** `domain/entities/page_layer.dart::PageLayer` holds `items` +
  `redo`, with typed accessors and `findById`/`removeById`.
- **Proposed:** explicit z-order (bring-to-front / send-to-back / forward /
  backward) persisted per annotation so save/load and export preserve order.

## 2.5 Object Model
Every on-page object should expose: `id`, kind, position, rotation, scale,
opacity, layer order, lock, visibility, metadata — with `toJson`/`fromJson`
for persistence and crash recovery. **Proposed** (serialisation does not yet
exist on `main`).

## 2.6 Selection Engine
- **Current:** `domain/services/selection_service.dart` +
  `presentation/widgets/editor_selection_overlay.dart` support single/multi
  select, move, resize/scale, align, distribute, snap guides, clone.
- **Proposed:** rotation handles, group/ungroup, marquee refinements.

## 2.7 History Engine
- **Current:** simple stack — `EditorController.undo/redo(PageLayer)` moves the
  last item between `items` and `redo`. In-memory only, single-level semantics,
  lost on restart.
- **Proposed:** Command-pattern `HistoryStack` (unlimited, capped for memory),
  object-level, cross-page, with disk auto-save for crash recovery. Must be
  layered **beside** existing controller methods, not replace them in one shot.

## 2.8 Export Pipeline
- **Current:** `data/editor_export_service.dart` + `editor_pdf_fonts.dart`
  compose base raster + annotations into a PDF via the `pdf` package.
- **Gaps:** non-Latin text and complex scripts are rasterised (not selectable),
  no font embedding.
- **Proposed:** embed Noto/Vazirmatn families; emit vector text for all scripts;
  guarantee position/layout parity with the on-screen canvas.

## 2.9 Performance
- Move CPU-bound image work off the UI thread — already isolate-safe in
  `core/image/image_ops.dart` (`applyImageOp` via `compute`).
- **Proposed:** page pre-rendering, bounded caches sized to device RAM,
  frame-budget instrumentation, and a low-RAM mode for large scans.

## 2.10 Mobile UX
- **Current:** toolbar (`editor_toolbar.dart`), top bar, sheets for review /
  smart-fill / signatures, guided-fill dialog.
- **Proposed:** gesture-first editing, contextual toolbars per selected object,
  haptics, and one-thumb reachability.

---

# Part 3 — Competitive Engineering

## 3.1 Benchmark (Adobe Acrobat, UPDF, Foxit, PDF Expert, PDFgear, PDFelement, Xodo)

| Capability | Competitors | AI-PDF now | Target |
|---|---|---|---|
| Inline text editing | ✅ | ❌ dialog only | 🔜 P1 |
| AcroForm fill | ✅ | ❌ | 🔜 P1 |
| Font embedding / RTL export | ✅ | ⚡ raster only | 🔜 P1 |
| Unlimited undo/redo | ✅ | ⚡ single-level | 🔜 P0 |
| Image / stamp objects | ✅ | ❌ | 🔜 P1 |
| Annotation persistence | ✅ | ❌ | 🔜 P0 |
| On-device AI RAG (offline) | ❌ | ✅ | ✅ moat |
| Privacy-first / offline-first | ⚡ | ✅ | ✅ moat |
| Profile-based AI autofill | ❌ | ✅ | ✅ moat |

**Where AI-PDF wins:** offline on-device intelligence, privacy, and profile
autofill — none of the desktop incumbents offer this on mobile. Do not copy
their desktop UX; win on privacy + AI + mobile ergonomics.

## 3.2 Repository Audit (as-is)
- **Frontend:** Flutter, Riverpod, GoRouter; `pdfx`; ML Kit OCR
  (`core/services/ocr_service.dart`); on-device BM25
  (`core/services/bm25_retriever.dart`); strong service decomposition; **no
  Dart tests beyond** `test/image_ops_test.dart`, `entitlement_test.dart`,
  `observability_test.dart`, `theme_controller_test.dart`.
- **Backend:** FastAPI + async SQLAlchemy + PostgreSQL; JWT
  (`core/security.py`); OpenRouter provider (`services/ai/provider.py`) with a
  model router; understanding/vision/form-filler/field-mapper services;
  managed AI (`api/v1/ai.py`) + new Document AI (`api/v1/document_ai.py`) with a
  shared metering module (`services/ai/usage_limiter.py`).

## 3.3 Architecture Review
- **Strengths:** feature-first layout, small services, clear domain/data split,
  privacy-first defaults.
- **Risks:** editor logic still partly lives in `pick_edit_screen.dart`;
  history is minimal; no annotation persistence; backend auth is incomplete
  (only `/register`).

## 3.4 Refactoring Strategy
Strictly incremental and backward-compatible:
1. Additive annotation metadata + `toJson/fromJson`.
2. Command-pattern history beside existing methods.
3. New annotation types (image/stamp/form).
4. Renderer + export extensions.
5. Persistence + crash recovery.
6. Inline text editing.
Each step: one PR, compiled + analyzed + tested before merge.

## 3.5 PR-ready Implementation Plan
- **P0:** annotation serialisation; command history; annotation persistence.
- **P1:** inline text editing; AcroForm fill; font embedding/RTL export;
  image/stamp objects; complete backend auth.
- **P2:** tile-based zoom; PDF text-layer extraction; grouping; managed-AI
  billing polish; cloud sync.
- **P3:** AI signature detection; document comparison; collaborative editing;
  PDF/A; PKI signatures; batch processing.

---

# Part 4 — AI Platform

## 4.1 Standalone AI Architecture
Two tiers, one contract:
- **On-device:** OCR (ML Kit) + BM25 retrieval — free, private, offline.
- **Managed backend:** `api/v1/ai.py` (chat) and `api/v1/document_ai.py`
  (chat / summarize / translate / rewrite / extract), fronting OpenRouter via
  `services/ai/provider.py` + `services/ai/model_router.py`. All endpoints share
  one metering + Pro-bypass rule in `services/ai/usage_limiter.py`.

## 4.2 Document Intelligence Engine
`services/ai/understanding.py` + `services/pipeline/orchestrator.py` classify
document type and extract entities; vision path handles scanned PDFs.

## 4.3 OCR
`core/services/ocr_service.dart` (on-device, ML Kit) on the client; backend
`services/ocr/ocr_service.py` for server-side extraction. **Proposed:**
AI-assisted OCR error correction (prompt template ready in the roadmap).

## 4.4 Semantic Understanding
BM25 on-device retrieval grounds answers with page citations; managed models
handle synthesis. **Proposed:** optional on-device embeddings for better recall.

## 4.5 Form Understanding
`services/ai/field_mapper.py` (100+ field types, 12+ languages — duplicate-key
bug fixed on this branch) + `services/ai/form_filler.py` +
`data/ocr_field_detection_service.dart` detect and classify fields.

## 4.6 Smart Autofill
`data/editor_smart_fill_service.dart` + `data/editor_profile_auto_fill_service.dart`
map an encrypted user profile (`core/services/user_profile_service.dart`) onto
detected fields, with a review sheet before applying.

## 4.7 AI Search
On-device BM25 today; **Proposed:** in-document semantic search and
cross-document search over the local library.

## 4.8 AI Editing
Backend `document_ai` supports rewrite/translate/extract. **Proposed:**
suggest-edits UX where the user reviews and accepts AI changes; never auto-apply.

## 4.9 Multi-document Reasoning
**Proposed:** index multiple documents in the BM25 store and answer questions
spanning them, with per-document/page citations.

## 4.10 Privacy-first AI
Default is on-device. Managed AI is opt-in and metered. Sensitive profile data
is encrypted at rest (`core/security.py` Fernet). No document content is
persisted server-side beyond the request lifecycle.

---

# Part 5 — Business & Production

## 5.1 Security
- JWT access/refresh (`core/security.py`), bcrypt password hashing, Fernet
  field encryption, audit-log + rate-limit middleware
  (`app/middleware/`).
- **Gap flagged:** `api/v1/auth.py` exposes only `/register`; login,
  token-refresh, and password-change are missing though schemas/helpers exist.
- **Proposed:** complete auth; rotate refresh tokens; add per-route authz tests.

## 5.2 Monetization
- Free tier with a shared daily AI cap (`AI_FREE_DAILY_LIMIT`), Pro = unlimited,
  verified via purchase token (`services/ai/usage_limiter.is_pro` +
  `models/entitlement.py`, `services/billing/play_verifier.py`).
- **Proposed:** back the in-memory counter with Redis for multi-instance; server
  receipt validation hardening.

## 5.3 Offline-first Strategy
Full offline toolkit (`features/tools/`): compress, convert, split/merge,
rotate, OCR, stamps — plus on-device OCR + BM25. AI degrades gracefully to
on-device when offline.

## 5.4 Plugin Architecture
**Proposed:** a tool registry so new PDF tools and AI actions register
declaratively (name, icon, handler, entitlement) without touching core screens.

## 5.5 Testing
- **Now:** a few Dart unit tests + backend `ruff`/`compileall` gate.
- **Proposed:** backend pytest (auth, metering, endpoints) with a runner that
  installs deps; Flutter widget/golden tests for the editor and export parity.

## 5.6 CI/CD
- `.github/workflows/build-apk.yml` (Flutter test + APK).
- `.github/workflows/backend-ci.yml` (ruff pyflakes + compileall — added).
- **Proposed:** add `flutter analyze` + backend pytest jobs; release signing.

## 5.7 Play Store Readiness
- **Proposed:** target latest `targetSdk`, release signing config, privacy
  policy + data-safety form reflecting on-device processing, crash reporting
  (`core/observability/`) wired to a provider.

## 5.8 Enterprise Features
**Proposed:** SSO, team profiles, shared templates, audit export, on-prem
managed-AI proxy, and admin usage dashboards.

## 5.9 Long-term Roadmap
1. Ship P0 editor foundation (history + serialisation + persistence).
2. Reach editing parity (inline text, AcroForm, RTL export).
3. Deepen the AI moat (multi-doc reasoning, on-device embeddings, suggest-edits).
4. Productionize (full auth, tests, CI gates, Play Store, billing hardening).
5. Platform (plugins, enterprise, collaboration).

---

## Verification & Governance
- This document is descriptive of intent and current state; it changes no code.
- Backend correctness is enforced by `backend-ci.yml`.
- Frontend items marked **Proposed** must be implemented with a Flutter
  toolchain (compile + `flutter analyze` + tests) — never merged unverified.
