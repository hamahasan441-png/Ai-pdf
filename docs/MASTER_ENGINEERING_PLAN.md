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
| Inline text editing | ✅ | ✅ `inline_text_editor.dart` | ✅ Done |
| AcroForm fill | ✅ | ✅ `/forms/acroform/read+fill` | ✅ Done |
| Font embedding / RTL export | ✅ | ✅ `rtl_text_renderer.dart`, `pdf_unicode_fonts.dart` | ✅ Done |
| Unlimited undo/redo | ✅ | ✅ Command-pattern `domain/history/` | ✅ Done |
| Image / stamp objects | ✅ | ✅ `image_annotation.dart`, `stamp_annotation.dart` | ✅ Done |
| Annotation persistence | ✅ | ✅ `annotation_persistence_service.dart` | ✅ Done |
| On-device AI RAG (offline) | ❌ | ✅ | ✅ moat |
| Privacy-first / offline-first | ⚡ | ✅ | ✅ moat |
| Profile-based AI autofill | ❌ | ✅ | ✅ moat |
| Semantic form understanding | ❌ | ✅ `/forms/understand-form` | ✅ Done |
| Multi-doc reasoning + compare | ⚡ | ✅ `multi_doc_chat.py`, `document_compare.py` | ✅ Done |
| Document insights (analyze) | ✅ | ✅ `/document-ai/analyze` | ✅ Done |

**Where AI-PDF wins:** offline on-device intelligence, privacy, and profile
autofill — none of the desktop incumbents offer this on mobile. Do not copy
their desktop UX; win on privacy + AI + mobile ergonomics.

## 3.2 Repository Audit (as-is)
- **Frontend:** Flutter, Riverpod, GoRouter; `pdfx`; ML Kit OCR
  (`core/services/ocr_service.dart`); on-device BM25
  (`core/services/bm25_retriever.dart`); strong service decomposition. Dart
  tests cover image ops, entitlements, observability, and theme controller.
- **Backend:** FastAPI + async SQLAlchemy + PostgreSQL; JWT
  (`core/security.py`); OpenRouter provider (`services/ai/provider.py`) with a
  model router; understanding/vision/form-filler/field-mapper services; managed
  AI (`api/v1/ai.py`) + Document AI (`api/v1/document_ai.py`) with a tiered
  metering module (`services/ai/usage_limiter.py` + `services/billing/quota_tiers.py`);
  **210 backend tests** in `backend/tests/` covering auth, AI metering, document
  AI, forms (AcroForm + understand-form + batch), teams, admin, webhooks,
  API keys, chat history, multi-doc chat, signature detection, and more.

## 3.3 Architecture Review
- **Strengths:** feature-first layout, small services, clear domain/data split,
  privacy-first defaults, tiered quota metering across all AI endpoints.
- **Risks:** some editor logic still partly lives in `pick_edit_screen.dart`;
  cloud sync is not yet implemented.

## 3.4 Refactoring Strategy
Strictly incremental and backward-compatible — **all steps below are done:**
1. ✅ Additive annotation metadata + `toJson/fromJson`.
2. ✅ Command-pattern history beside existing methods (`domain/history/`).
3. ✅ New annotation types (image/stamp/form-field).
4. ✅ Renderer + export extensions (RTL, font embedding).
5. ✅ Persistence + crash recovery (`annotation_persistence_service.dart`).
6. ✅ Inline text editing (`inline_text_editor.dart`).

## 3.5 Implementation Status

**P0 — Completed ✅**
- Annotation serialisation + persistence.
- Command-pattern history (`domain/history/`).
- `PageCoordinateTransform` for inline editing.

**P1 — Completed ✅**
- `/document-ai/analyze` structured insights.
- Inline text editor overlay with caret/selection.
- RTL render + font embedding (Arabic/Kurdish/Persian searchable export).
- AcroForm read/fill engine (`/forms/acroform/read+fill`).
- Semantic form understanding fallback (`/forms/understand-form`).
- Image/Stamp/FormField annotation objects.
- Background page pre-rendering.
- Complete backend auth (register/login/refresh/me/change-password).

**P2 — Completed ✅**
- Multi-document RAG + compare (`multi_doc_chat.py`, `document_compare.py`).
- Document outline/TOC extraction.
- Map-reduce summarisation for large PDFs.
- Tile-based zoom service + PDF text layer extraction.
- Form validation + cross-field logic + reusable form profiles.
- Suggest-edits (review-first AI editing, accept/reject cards).
- Extract dates + extract action items.
- Suggest questions (AI-driven chat primer).

**P3 — Completed ✅**
- Revision history service (local, privacy-preserving).
- AI signature detection service.
- Developer platform: API keys, webhooks, chat history persistence.
- Enterprise: teams + shared templates + audit export + admin dashboard.
- Plugin registry (metadata-only, client-driven).
- Tiered quota metering: all 15+ AI endpoints use `get_quota` consistently.

**Proposed (future work)**
- On-device semantic embeddings (beyond BM25).
- SSO + per-team AI quotas.
- On-prem managed-AI proxy.
- Third-party/remote plugins.
- Cloud sync (opt-in, encrypted).

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
Backend `document_ai` supports rewrite/translate/extract.
**Done (P6):** review-first **suggest-edits** — `POST /api/v1/document-ai/suggest-edits`
(`api/v1/suggest_edits.py`) returns a list of discrete, reviewable suggestions
(each with the exact `original` span, `suggestion`, `reason`, and `category`)
instead of a whole rewritten blob, so the client can present accept/reject cards
and apply only what the user approves. The server applies nothing and stores
nothing; metering and the Pro bypass match the other Document AI endpoints. The
response parser tolerates both `{"edits": [...]}` and bare-array model output and
drops no-op/malformed suggestions. **Proposed:** inline anchored diffs in-canvas.

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
- **Auth is complete:** `api/v1/auth.py` exposes `/register`, `/login`,
  `/refresh` (token rotation), `/me`, and `/change-password`. All paths are
  covered by `backend/tests/test_auth.py` (register/login/refresh/me/change-password).
- **Proposed:** SSO; per-route authorisation tests; 2FA.

## 5.2 Monetization
- Free tier with a shared daily AI cap (`AI_FREE_DAILY_LIMIT`), Pro = unlimited,
  verified via purchase token (`services/ai/usage_limiter.is_pro` +
  `models/entitlement.py`, `services/billing/play_verifier.py`).
- **Done (P5):** the free-tier counter is now backed by a pluggable metering
  backend (`services/ai/usage_backend.py`) — `AI_METER_BACKEND=auto|memory|redis`.
  The Redis backend uses an atomic `INCR` + daily `EXPIRE` keyed identically so
  metering is correct across multiple instances, and fails **closed to
  in-memory** on a cache outage (AI never hard-fails on Redis). The Pro-bypass
  rule is unchanged.
- **Proposed:** server receipt validation hardening; per-plan quotas.

## 5.3 Offline-first Strategy
Full offline toolkit (`features/tools/`): compress, convert, split/merge,
rotate, OCR, stamps — plus on-device OCR + BM25. AI degrades gracefully to
on-device when offline.

## 5.4 Plugin Architecture
**Done (P5):** a declarative tool/AI-action registry
(`services/plugins/registry.py`) where each capability describes itself once
(id, name, description, kind, category, icon, route, entitlement, enabled, tags).
The catalogue is served read-only at `GET /api/v1/plugins` (with
kind/category/entitlement filters) and `GET /api/v1/plugins/{id}`, so the client
can render tools dynamically and gate features by entitlement in one place. The
registry is metadata-only; execution stays in the existing endpoints, keeping
the change additive. **Proposed:** third-party/remote plugins.

## 5.5 Testing
- **Backend:** 210 pytest tests (`backend/tests/`) covering security (JWT +
  password + encryption), the tiered AI usage limiter, the full auth flow
  (register/login/refresh/me/change-password), AI endpoint metering
  (503 / 429 / Pro-bypass / basic-tier), AcroForm read/fill/batch,
  semantic form understanding (`understand-form`), document AI (chat /
  summarize / translate / rewrite / extract / analyze / fix-ocr),
  multi-doc chat, document compare/outline, extract dates/actions,
  suggest questions/edits, teams, admin, API keys, webhooks, and chat
  history. Runs against in-memory SQLite with the AI provider mocked —
  no network, no Postgres, no secrets.
- **Frontend:** Dart tests cover image ops, entitlements, observability,
  and theme controller.
- **Proposed:** Flutter widget/golden tests for editor + export parity;
  broaden backend coverage to billing webhooks and PDF conversion.

## 5.6 CI/CD
- `.github/workflows/build-apk.yml` (Flutter test + APK).
- `.github/workflows/backend-ci.yml`: `static-checks` (ruff pyflakes +
  compileall) **and** `tests` (pip install + pytest) — both added.
- **Proposed:** add `flutter analyze`; release signing.

## 5.7 Play Store Readiness
- **Proposed:** target latest `targetSdk`, release signing config, privacy
  policy + data-safety form reflecting on-device processing, crash reporting
  (`core/observability/`) wired to a provider.

## 5.8 Enterprise Features
**Done (P5):**
- **Teams** with role-based membership (owner/admin/member) —
  `models/team.py`, `api/v1/teams.py`. Create/list/detail, add/remove members
  (managers only; the owner cannot be removed), with non-members getting 404
  (existence is not leaked).
- **Shared templates** owned by a team (`SharedTemplate`) — list/create/delete,
  where delete is restricted to the creator or a team manager.
- **Audit export** — team-scoped, append-only `TeamAuditLog` records
  member/template events; owners/admins export the trail at
  `GET /api/v1/teams/{id}/audit`.
- **Admin usage dashboard** — `GET /api/v1/admin/usage` (aggregate users, teams,
  members, templates, active entitlements, metering config), gated by a shared
  secret (`ADMIN_API_TOKEN` via the `X-Admin-Token` header; 503 when unset).

**Proposed:** SSO, per-team AI quotas/billing, and an on-prem managed-AI proxy.

## 5.9 Roadmap Status
1. ✅ Ship P0 editor foundation (history + serialisation + persistence).
2. ✅ Reach editing parity (inline text, AcroForm, RTL export, image/stamp).
3. ✅ Deepen the AI moat (multi-doc reasoning, suggest-edits, analyze, form AI).
4. ✅ Productionize (full auth, 210 tests, CI gates, tiered billing, developer platform).
5. ✅ Platform (plugins, enterprise/teams, audit export, admin dashboard, API keys, webhooks).
6. 🔜 Next: on-device embeddings; cloud sync; SSO; Flutter golden tests; 2FA.

---

## Verification & Governance
- This document is descriptive of intent and current state; it changes no code.
- Backend correctness is enforced by `backend-ci.yml`.
- Frontend items marked **Proposed** must be implemented with a Flutter
  toolchain (compile + `flutter analyze` + tests) — never merged unverified.
