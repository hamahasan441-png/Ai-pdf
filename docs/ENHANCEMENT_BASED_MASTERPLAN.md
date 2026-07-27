# Enhancement-Based Masterplan — AI-PDF (Pdoczy)

**Date:** 2026-07-27 UTC  
**Branch:** `arena/019fa435-ai-pdf` (from `main` @ 5e11108)  
**Repo:** `hamahasan441-png/Ai-pdf`  
**Philosophy:** Build on what ships, additively, verifiably, never rewrite.

> This is the **single enhancement operating plan**. It does not propose a rewrite to Kotlin/Compose/Hilt/Room (debunked in `CTO_REVIEW.md` — 10.8k lines of working Flutter = moat). It assumes the stack in `README.md` and `DEVELOPMENT.md`: Flutter 3.29 + Riverpod + GoRouter + pdfx/pdf + ML Kit + BM25 + FastAPI + PostgreSQL + Redis + Play Billing.

---

## 0. Executive Summary

The app today (see `PROJECT_STATUS.md`) is **P0–P3 done** for editor core, forms, and intelligence:
- 25+ editor data services, Command-pattern history `domain/history/`, `annotation_persistence_service.dart`, `inline_text_editor.dart`, RTL render `rtl_text_renderer.dart`, font embedding `pdf_unicode_fonts.dart`, image/stamp/form-field annotations, background pre-render, tile zoom, text-layer extraction.
- Backend: 210 tests, tiered metering `usage_limiter.py + quota_tiers.py` across **15+ AI endpoints** (`document_ai.py`, `extract_dates.py`, `extract_actions.py`, `suggest_questions.py`, `suggest_edits.py`, `multi_doc_chat.py`, `document_compare.py`, `document_outline.py`, `forms.py`), AcroForm read/fill, `understand-form`, map-reduce summarizer, teams, API keys, webhooks, admin dashboard.

**What “enhancement-based” means here:**
1. **Additive, not destructive:** every change extends existing APIs, files, contracts. No silent contract break for the 25+ services depending on `PageLayer`, `EditorAnnotation.id`, `AnnotationDraw`.
2. **Measured, not guessed:** no perf work without a number. No UX work without a journey.
3. **Review-gated AI:** server proposes, client shows accept/reject cards, never silently mutates — contract already established in `suggest_edits.py` and `editor_smart_fill_review_sheet.dart`.
4. **Offline-first stays offline-first:** heavy ops via `compute()` in `core/image/image_ops.dart`, ML Kit and `bm25_retriever.dart` remain zero-network.

This plan identifies **8 pillars**, 42 concrete enhancements (E-n.m), sequenced into 90-day execution with clear **files touched, acceptance, and verification**.

---

## 1. Principles of Enhancement-Based Development

| Principle | Rule | Enforcement |
|-----------|------|-------------|
| **Additive** | No file deletion without migration; extend `TextAnnotation` with new optional fields, don't change `size` semantics (pt) | `git diff --stat` < 400 lines per PR |
| **One Render Path** | `annotation_draw.dart::text()` is canvas truth; `editor_export_service.dart` must call same path. Latin + non-Latin both vector when font asset exists, raster fallback only when missing | `export_fidelity_checker.dart` must pass |
| **Isolate Heavy Work** | Any O(W*H) loop → `compute()` top-level function | Review checklist + `performance` label |
| **Tiered Metering Everywhere** | All AI endpoints use `get_quota()` + `check_and_increment_tiered()` — never `is_pro` binary | `grep -R "is_pro" app/api` must be 0 after |
| **Encrypted by Default** | PII → Fernet (`core/security.py`), profile fields, `UserProfileService` | `test_security.py` covers |
| **Green Main** | Each commit: `ruff --select F && python -m compileall -q app tests && pytest -q` + `flutter analyze` when toolchain present | `backend-ci.yml` |
| **Small PRs** | One pillar item per PR, includes test | PR template |
| **Privacy Contract** | Managed AI sees only retrieved passages by default (`bm25_retriever.dart`), never whole doc unless user opts in | Code review + `docs/DATA_SAFETY.md` |

---

## 2. Baseline — What Ships Today (Grounded Audit)

### Frontend (`frontend/lib/`)
- **Editor:** `features/editor/` — `domain/entities/annotation.dart` (stable `id`, `opacity/locked/visible/zIndex/metadata`, `TextRun` for rich text), `domain/services/selection_service.dart`, `page_coordinate_transform.dart`, `application/editor_controller.dart`, `presentation/widgets/editor_canvas.dart` + `editor_toolbar.dart` + `inline_text_editor.dart` + `editor_page_thumbnail_strip.dart` + `editor_layer_panel.dart` + `editor_bookmarks_panel.dart` + `editor_search_bar.dart` + `editor_compare_view.dart` + `editor_split_view.dart`.
- **AI:** `features/ai/presentation/ai_chat_screen.dart` (Understand + Fill Form modes, quick-action pills), `core/services/bm25_retriever.dart` (Okapi BM25, page-cited), `core/services/ocr_service.dart` (ML Kit).
- **Tools (18):** `features/tools/` — compress/merge/split/rotate/watermark/page numbers/stamp/readAloud/import + `batch_process_screen.dart`, `bates_numbering_screen.dart`, `qr_code_screen.dart`, `custom_stamp_creator_screen.dart`, `template_gallery_screen.dart`, `voice_note_screen.dart`.
- **Core:** `core/image/image_ops.dart` isolate-safe, `core/ads/`, `features/subscription/` (Play Billing), `core/config/router.dart` 25+ routes, `l10n/` EN/ES/AR/DE, dark mode toggle.

### Backend (`backend/app/`)
- **Auth:** `api/v1/auth.py` register/login/refresh/me/change-password — `test_auth.py` covers.
- **Document AI:** `document_ai.py` chat/summarize/translate/rewrite/extract/analyze/fix-ocr all via `_meter()` → tiered quotas; `document_compare.py`, `document_outline.py` (bookmarks → AI headings), `multi_doc_chat.py` + `services/ai/multi_doc_index.py` BM25 cross-cite, `extract_dates.py`, `extract_actions.py`, `suggest_questions.py`, `suggest_edits.py` (review-first cards), `text_layer.py`.
- **Forms:** `forms.py` acroform/read+fill (PyMuPDF), batch (50-doc cap), `understand-form` semantic fallback, `form_validate.py`, `services/ai/field_mapper.py` 100+ labels 12+ langs, `field_validator.py`, `form_filler.py`.
- **Platform:** `plugins.py` metadata-only registry, `teams.py` owner/admin/member + shared templates + audit export, `api_keys.py`, `webhooks.py`, `chat_history.py`, `billing/play_verifier.py`, `health_dashboard.py`, `admin.py` gated by `ADMIN_API_TOKEN`, `cache/document_cache.py`.
- **Billing/Metering:** `services/ai/usage_backend.py` memory|redis|auto, `usage_limiter.py` + `billing/quota_tiers.py` free=15/day, basic=100/day, pro=unlimited — consistent across all endpoints.
- **Tests:** 210 tests (`backend/tests/`) — in-memory SQLite, mocked provider, no network/Postgres.

### Gaps That Matter (from real use, not aspiration)
- **Editor:** rich per-run style exists in model (`TextRun`) but no UI; measurement/Bates/crop controllers exist but not wired consistently; revision history service exists but no timeline merge; export fidelity checker exists but no golden tests; thumbnail strip exists but drag-reorder not always wired; low-RAM mode for 1000+ page scans missing.
- **AI:** BM25 is excellent offline recall, but semantic embeddings would improve recall 30-40%; chat history persistence exists backend but no library UI; multi-doc panel exists but not linked to backend index; long-doc map-reduce exists but not streaming.
- **Forms:** XFA (legacy) not covered; cross-field logic service exists but no UI configurator; form profiles service exists but no management UX; fill-from-ID doc exists but no structured extraction preview.
- **Perf:** background pre-render + LRU ±1 exists, but no progressive file open (100+ pages blocks), no frame-budget telemetry, no automatic downscale for low-RAM devices.
- **Security:** 2FA missing, SSO missing, webhook signature verification missing retry, recent files JSON blob in `shared_preferences` not encrypted, rate-limit middleware exists but per-team quotas missing.
- **Growth:** billing verification exists but renewal/cancel/refund webhook re-verification missing; onboarding explains BYO-key but paywall A/B not instrumented; AdMob banner only on browse screens (good) but no lifecycle for Pro.
- **Enterprise:** teams done but per-team AI quota, SSO, SCIM missing; cloud sync opt-in encrypted missing; collaboration via command log proposed but not implemented.

---

## 3. User Journeys & Pain Points (What We Optimize For)

| Journey | Today | Pain | Enhancement Target |
|---------|-------|------|-------------------|
| **1. Fill a 10-page German government form** | AcroForm + heuristics + `understand-form` + profile match + review sheet | XFA not read, IBAN validation silent, date TT.MM.JJJJ fails on some OCR | Pillar 3 E3.1–E3.6 |
| **2. Edit a contract on phone** | Inline editor + select/resize/align/distribute + undo | No per-run bold inside box, no measure, no Bates, no persistent thumbnails | Pillar 1 E1.1–E1.8 |
| **3. Ask “what are the penalties? page cite” on 200-page scan** | ML Kit OCR + BM25 retriever + managed synthesis + page cite | BM25 keyword-only, big docs truncated, no chat history | Pillar 2 E2.1–E2.7 |
| **4. Merge 500-page PDFs from drive** | Offline merge via pdf package | UI thread jank, OOM risk, no progress, no cancel | Pillar 4 E4.1–E4.5 |
| **5. Pro purchase + team share** | Play Billing + verify + entitlement | No renewal webhook, no team quota, no SSO | Pillar 5+8 E5.4, E8.1–E8.4 |
| **6. Developer builds template workflow** | API keys + webhooks + plugins registry | Webhook no retry/sign, plugins no execution | Pillar 7 E7.1–E7.4 |

---

## 4. Enhancement Pillars — 42 Concrete Items

### Pillar 1 — Editor Professional Enhancement (E1)

**Intent:** Make on-phone editing feel like UPDF/PDFgear, while keeping one render path.

**Baseline:** `annotation.dart` stable `id`, `editor_canvas.dart`, `inline_text_editor.dart`, `selection_service.dart`, `annotation_persistence_service.dart`, `export_fidelity_checker.dart`.

#### E1.1 Rich Text Per-Run Styling UI (P0)
- **Gap:** `TextRun` model exists (`text`, `bold?`, `italic?`, `underline?`, `color?`, `fontFamily?`, `sizeScale?`) but UI only edits whole box.
- **Design:** Extend `inline_text_editor.dart` overlay to emit `TextRun` spans. Add `editor_rich_text_toolbar.dart` already present → wire to `editor_rich_text_service.dart`: when selection inside TextField changes, show bold/italic/color buttons; apply to `TextRun` slice, not whole annotation. Keep single `EditTextCommand` undo.
- **Files:** `presentation/widgets/inline_text_editor.dart`, `data/editor_rich_text_service.dart`, `domain/entities/annotation.dart` (already has runs field), `application/editor_controller.dart`.
- **Acceptance:** Select word inside box → bold → export → vector bold preserved in Latin + Arabic when font asset present.
- **Effort:** 3d, ROI High.

#### E1.2 Coordinate Transform Hardening + Snap Guides V2
- **Gap:** `page_coordinate_transform.dart` exists but snap only page quarters/center.
- **Design:** Add object-to-object snap (edges, centers) when dragging; extract `annotation_bounds_service.dart` + `selection_service.dart` to compute nearest snap lines < 8dp threshold. Show guides via `editor_canvas_painter.dart`.
- **Acceptance:** Drag box near another → snap line appears, haptic (`haptic_service.dart`), position quantized.
- **Effort:** 2d.

#### E1.3 Measurement, Bates, Header/Footer Wiring
- **Gap:** Domain services `measurement`, `bates`, `header_footer` exist but screens are disconnected.
- **Design:** Add `features/tools/presentation/bates_numbering_screen.dart` → toolbar action; reuse `editor_export_service.dart` preset pipeline `export_settings_service.dart`. Measurement overlay uses same `page_coordinate_transform`.
- **Acceptance:** Bates numbering adds `n` stamps, page numbers badge `n/total` vector.
- **Effort:** 3d.

#### E1.4 Annotation Grouping + Layer Panel V2
- **Gap:** `annotation_group_service.dart` exists; `editor_layer_panel.dart` shows list but no drag reorder, lock/visible toggle not persisted.
- **Design:** Layer panel: reorder via long-press drag → update `zIndex` + list order + `PageLayer.items` order; persist via `annotation_persistence_service.dart`. Group/ungroup → single command merging bounds.
- **Acceptance:** Group → move as one, undo restores.
- **Effort:** 2d.

#### E1.5 Export Fidelity Golden Tests (Frontend Toolchain Required)
- **Gap:** `export_fidelity_checker.dart` exists but no golden corpus.
- **Design:** Create `frontend/test/editor_export_golden/` with 5 PDFs (EN, DE form, AR, mixed, 100-page). Script renders screen `AnnotationDraw` vs export via `pdf` package and diffs bounding boxes (pixel + vector parity). Runs only when Flutter toolchain present — not in backend CI.
- **Acceptance:** CI job optional but dev can run `flutter test --tags=golden`.
- **Effort:** 2d, ROI Critical to prevent regressions (lesson from #85 export blank).

#### E1.6 Thumbnail Strip Drag-Reorder + Bookmarks + Outline Sync
- **Gap:** `editor_page_thumbnail_strip.dart` exists, `editor_outline_panel.dart` exists, but outline → jump + thumbnails reorder not bidirectional.
- **Design:** Thumbnail drag → `page_reorder_service.dart` + `PageLayer` page index remap; outline click → viewport scroll using `EditorDocumentViewport` stateful TransformationController.
- **Acceptance:** Reorder page 2→5, undo, bookmarks persist.
- **Effort:** 2d.

#### E1.7 Redaction V2 — True Redaction, Not Whiteout
- **Gap:** `redaction_service.dart` currently whiteout box (covers content). Real redaction must remove underlying text/images.
- **Design:** Backend `/convert` already uses PyMuPDF; add `POST /document-ai/redact` using PyMuPDF redact annotations to actually remove content, then return sanitized PDF. Frontend `editor_redaction_overlay.dart` marks areas, confirm sheet warns irreversible.
- **Acceptance:** Redacted PDF text not extractable via `text_layer.py`.
- **Effort:** 4d (backend + frontend).

#### E1.8 Revision History Timeline Merge + Visual Diff
- **Gap:** `revision_history_service.dart` + `editor_history_timeline_panel.dart` list commands, but no visual diff.
- **Design:** Store snapshots debounced (every 30s + on page change) in `annotation_serialization.dart`. Timeline shows diff count, preview. Revert creates new command (not destructive).
- **Acceptance:** Crash recovery dialog `editor_recovery_dialog.dart` offers latest snapshot.
- **Effort:** 3d.

---

### Pillar 2 — Document Intelligence & Retrieval Enhancement (E2)

**Intent:** Keep BM25 offline moat, add hybrid semantic recall, streaming, citation-grade answers.

#### E2.1 Hybrid Retrieval: BM25 + On-Device Embeddings
- **Gap:** `bm25_retriever.dart` pure Dart keyword-only; no embeddings.
- **Design:** Add Dart/Flutter ONNX runtime via `onnxruntime` or tflite (`flutter_tflite`). Ship MiniLM-L6-v2 quantized (20MB) as optional download (not bundled). `Bm25Retriever` → `HybridRetriever`: first BM25 top-20, then re-rank with cosine similarity from embeddings cached in `app_settings.dart`. Keep fully offline; fallback to BM25 if model missing. Backend already has `multi_doc_index.py` BM25 — add embedding column optional.
- **Files:** `core/services/bm25_retriever.dart` → new `hybrid_retriever.dart`, `core/services/ocr_service.dart`.
- **Acceptance:** Query “penalties” finds paraphrase “sanctions” without keyword match.
- **Effort:** 5d, ROI High.

#### E2.2 Map-Reduce Summarizer Streaming + Citation
- **Gap:** `map_reduce_summarizer.py` exists but returns final blob; no streaming, citations lost.
- **Design:** Extend `POST /document-ai/summarize` with `?stream=true` SSE: emit per-chunk summaries then final reduce. Include `page_citations[]` per bullet. Frontend `editor_summarizer_panel.dart` shows progressive load with cancel.
- **Files:** `services/ai/map_reduce_summarizer.py`, `api/v1/document_ai.py`, `features/editor/presentation/widgets/editor_summarizer_panel.dart`.
- **Acceptance:** 200-page doc summary streams in <10s first chunk, citations clickable.
- **Effort:** 3d.

#### E2.3 Chat History Persistence UI (Library)
- **Gap:** Backend `chat_history.py` + model `chat_history.py` exists; frontend ephemeral.
- **Design:** Add `features/library/` (already exists structure) — list past chats per document hash, restore retrieval context, delete. Use `api_client.dart` + `chat_history` schema. Offline fallback: `auto_backup_service.dart` local cache when backend unreachable.
- **Acceptance:** Close doc → reopen → chat history visible.
- **Effort:** 3d.

#### E2.4 Multi-Doc RAG Wiring End-to-End
- **Gap:** Backend `multi_doc_chat.py` + index exists; frontend `editor_multi_doc_chat_panel.dart` exists but not wired to backend index creation.
- **Design:** Frontend tool `tools_screen.dart` → “Compare / Q&A across docs” → select 2-10 PDFs → `POST /multi-doc/index` → `chat` with `[doc, page]` citations. Use existing `multi_doc_index.py` BM25.
- **Acceptance:** Ask across 3 contracts → answer cites Doc B p12 + Doc C p4.
- **Effort:** 3d.

#### E2.5 Fix-OCR V2 — Contextual Correction
- **Gap:** `fix-ocr` endpoint exists but prompt naive.
- **Design:** Enhance `understanding.py` + `document_ai.py` fix-ocr to use surrounding lines + language detection from `analyze`. Provide confidence + original vs corrected side-by-side (`editor_compare_view.dart` pattern).
- **Acceptance:** Arabic OCR mistakes (ي vs ى) corrected with >90% precision on test set.
- **Effort:** 2d.

#### E2.6 Suggested Questions + Action Items UI Polish
- **Gap:** `suggest_questions.py`, `extract_actions.py` exist but UI pills static.
- **Design:** In `ai_chat_screen.dart`, after `analyze` returns `suggested_questions[]` + `action_items[]`, render actionable checklists with page jump. Action items → local tasks (`notification_service.dart`) opt-in.
- **Acceptance:** Open invoice → suggested “What is total due?” tappable → answer with citation.
- **Effort:** 2d.

#### E2.7 Vision Understanding for Scanned Forms
- **Gap:** `vision.py` exists but not used for form detection.
- **Design:** When `ocr_field_detection_service.dart` confidence < threshold, crop field rect as image → send to `/forms/understand-form` with vision model list `AI_VISION_MODELS`. Use `AI_MODEL_ADVANCED` fallback. Keep heuristics first (offline).
- **Acceptance:** Handwritten checkbox detection via vision improves recall 20%.
- **Effort:** 4d.

---

### Pillar 3 — Forms & Workflow Automation Enhancement (E3)

#### E3.1 XFA + AcroForm Edge Cases
- **Gap:** `forms.py` handles AcroForm (PyMuPDF/pypdf); XFA (XML) not parsed.
- **Design:** Detect XFA via `doc.xfa` in PyMuPDF; parse XML → field graph; return same schema as AcroForm read. Add test `test_forms_xfa.py` with sample XFA.
- **Acceptance:** XFA sample field count parsed.
- **Effort:** 3d.

#### E3.2 Field Validation UI + Inline Errors
- **Gap:** `form_validate.py` + `field_validator.py` exist backend but frontend review sheet only badges.
- **Design:** `editor_form_review_panel.dart` + `smart_fill_review_sheet.dart` show validator messages (email/IBAN/date/phone) inline, red border, focus next invalid.
- **Acceptance:** Invalid email prevents “Place”.
- **Effort:** 2d.

#### E3.3 Cross-Field Logic Configurator
- **Gap:** `cross_field_logic_service.dart` exists but logic hardcoded.
- **Design:** Add JSON rule builder (e.g., `{"if": {"field":"total","gt":1000},"then": {"require":"approval"}}`). Backend `field_validator.py` evaluates. UI for Pro to save rules per template `form_profile_service.dart`.
- **Acceptance:** Rule “departure < return” flagged.
- **Effort:** 3d, ROI Enterprise.

#### E3.4 Form Profiles Management UX
- **Gap:** `form_profile_service.dart` exists but no CRUD screen.
- **Design:** New `features/tools/presentation/form_profile_manager_screen.dart`: list profiles per doc type (invoice, contract, government), edit mapping, export/import JSON. Persist encrypted via `user_profile_service.dart`.
- **Acceptance:** Save profile → next similar form autofills faster.
- **Effort:** 2d.

#### E3.5 Fill-from-Anything Preview
- **Gap:** `smart_fill_source_sheet.dart` lets upload ID/CV but extraction preview limited.
- **Design:** Upload doc → OCR on-device → `profile_field_matcher.dart` shows matched labels with confidence (already multi-signal scoring) → review sheet before place. Add `form_memory_service.dart` to remember resolved answers per label (privacy-first, device-only).
- **Acceptance:** Upload passport → name/dob/ID auto-suggested, user confirms.
- **Effort:** 2d.

#### E3.6 Batch Fill V2 — 50-doc Cap + Error Report
- **Gap:** `/forms/batch` 50-doc cap exists; no per-doc error summary.
- **Design:** Return `{doc, status, filled_count, errors[]}` for each; frontend shows progress bar + cancel (WorkManager pattern). Use `batch_processor.py` with bounded concurrency.
- **Acceptance:** 20 docs batch → 18 succeed, 2 error report.
- **Effort:** 2d.

---

### Pillar 4 — Performance, Reliability & Offline Enhancement (E4)

#### E4.1 Progressive File Open + Thumbnail Prioritization
- **Gap:** Large PDFs block for seconds (full decode).
- **Design:** `editor_page_render_service.dart` + `background_page_renderer.dart`: open first page immediately, then background isolate renders thumbs for ±5 pages low-res, then high-res current. Use `page_preloader_service.dart`. Add `editor_loading_overlay.dart` with page count + % + cancel.
- **Acceptance:** 1000-page opens first page < 1.5s on mid device, ANR 0.
- **Effort:** 4d.

#### E4.2 Low-RAM Mode + Bounded Caches
- **Gap:** LRU cap 3 exists but not adaptive to RAM.
- **Design:** Detect `ActivityManager.memoryInfo` via platform channel (existing `pdfimport` Kotlin plugins pattern). When low RAM < 2GB, cap LRU 1, downscale raster to 900 max edge (vs 1800), disable adjacent pre-render. Instrument via `analytics_service.dart`.
- **Acceptance:** 500MB device no OOM on 100-page scan.
- **Effort:** 2d.

#### E4.3 Frame-Budget Telemetry + Jank Detection
- **Gap:** No frame timing.
- **Design:** Add `core/observability/` frame timing: `WidgetsBinding.addTimingsCallback` logs slow frames (<55fps) with current page count + annotation count. Send to `crash_reporter.dart` / Sentry facade.
- **Acceptance:** Dashboard shows p95 frame time per screen.
- **Effort:** 2d.

#### E4.4 Auto-Backup Service Hardening
- **Gap:** `auto_backup_service.dart` exists but no versioning.
- **Design:** Keep 3 rolling backups per file hash under app docs dir, encrypted optional. On crash, `editor_recovery_dialog.dart` lists backups with timestamp + diff count.
- **Acceptance:** Kill app during edit → recovery offers backup.
- **Effort:** 2d.

#### E4.5 WorkManager for Large Jobs
- **Gap:** Merge/compress main isolate (some isolate-safe via `compute`).
- **Design:** Add `workmanager` package: for jobs > 50MB or > 200 pages, schedule background work with foreground notification (`notification_service.dart`), progress callback, cancel. Keep `image_ops.dart` isolate path for small jobs.
- **Acceptance:** Merge 500-page shows notification progress, UI stays 60fps.
- **Effort:** 3d.

---

### Pillar 5 — Privacy, Security & Compliance Enhancement (E5)

#### E5.1 Encrypted Recent Files + Migration
- **Gap:** `recent_files_service.dart` JSON blob in `shared_preferences` not encrypted.
- **Design:** Migrate to `flutter_secure_storage` + `Isar`/`drift` (chosen: `drift` per CTO review) for pagination. Existing blob migration: read old key, re-encrypt, delete. Add pagination (20/page) for 1000s.
- **Acceptance:** Recent files encrypted at rest, query < 16ms for 1k items.
- **Effort:** 3d.

#### E5.2 2FA TOTP
- **Gap:** Missing (noted in PROJECT_STATUS).
- **Design:** Backend `api/v1/auth.py` adds `/auth/2fa/setup` (secret + QR) + `/auth/2fa/verify` (TOTP). Model `user.py` adds `totp_secret` encrypted Fernet. Frontend `features/security/` adds setup/verify screens. Recovery codes 8x.
- **Acceptance:** Login with 2FA requires code; recovery works.
- **Effort:** 4d.

#### E5.3 SSO OIDC + Google/Apple
- **Gap:** Enterprise ask.
- **Design:** Add `authlib` or `python-jose` OIDC flow: `/auth/sso/{provider}` redirect. Map external sub → internal user. Per-team SSO enforcement flag `team.sso_required`. Frontend adds SSO buttons on login.
- **Acceptance:** Google login creates user, team SSO enforced.
- **Effort:** 5d.

#### E5.4 Webhook Security Hardening
- **Gap:** `webhooks.py` exists but no HMAC signing, no retry.
- **Design:** Add `webhook_secret` per webhook (`webhook.py`), sign body `HMAC-SHA256`, header `X-Webhook-Signature`. Retry with exponential backoff 3x via `services/cache/` or Celery-lite background task. Add `api/v1/webhooks` test `test_webhooks.py` already covers basic, extend for signature + retry.
- **Acceptance:** Tampered payload rejected, retry works on 500.
- **Effort:** 2d.

#### E5.5 Per-Route Authorization + Rate Limit Polish
- **Gap:** `middleware/rate_limit.py` + `audit_log.py` exist but no per-team rate.
- **Design:** Extend `rate_limit.py` to tier per API key tier (free/basic/pro) + per-team quota (proposed in `quota_tiers.py`). Add audit export already in teams, but add immutable hash chain.
- **Acceptance:** Team A 100/day basic enforced.
- **Effort:** 2d.

---

### Pillar 6 — Monetization, Growth & Engagement Enhancement (E6)

#### E6.1 Billing Webhook Re-Verification on Renewal/Cancel/Refund
- **Gap:** `billing/play_verifier.py` verifies at purchase, but no pub/sub for renewals.
- **Design:** Add Google Pub/Sub Real-Time Developer Notifications (RTDN) endpoint `POST /billing/rtdn` → parse `SUBSCRIPTION_PURCHASED/RENEWED/CANCELED/EXPIRED` → re-verify via `play_verifier.py` → update `entitlement.py`. Add `test_billing_rtdn.py`.
- **Acceptance:** Cancel → entitlement revoked within webhook latency.
- **Effort:** 4d, ROI Critical revenue accuracy.

#### E6.2 Paywall A/B + Onboarding V2
- **Gap:** `onboarding_service.dart` exists but no A/B.
- **Design:** Add `features/onboarding/` flows: explain BYO-key vs managed AI, show 3-day trial, two paywall variants (monthly emphasis vs lifetime). Instrument via `analytics_service.dart` (conversion). Local remote config JSON via `app_config.dart` before Firebase Remote Config.
- **Acceptance:** Onboarding completion rate + Pro CVR measurable.
- **Effort:** 3d.

#### E6.3 App Rating + Retention Nudges
- **Gap:** `app_rating_service.dart` exists but simplistic.
- **Design:** Trigger rating after 3 successful tool uses + 1 doc chat with citation (happy path). Use `notification_service.dart` for “resume editing?” after crash recovery. No spam.
- **Acceptance:** Rating prompt shows at right moment, opt-out.
- **Effort:** 1d.

#### E6.4 Ad Lifecycle Optimization
- **Gap:** Banner only on browse (good), interstitial after tool result (ok), but no frequency cap for free.
- **Design:** `ads_service.dart` adds freq cap: max 1 interstitial per 10 min, never after Pro, never in editor/AI. Add rewarded ad for Convert still (existing).
- **Acceptance:** Free user not spammed.
- **Effort:** 1d.

---

### Pillar 7 — Developer Platform & Extensibility Enhancement (E7)

#### E7.1 API Keys Tiered Rate + Scopes
- **Gap:** `api_keys.py` exists but no scopes.
- **Design:** Add `scopes: ["ai:read","forms:read","documents:write"]` to model `api_key.py`. Enforce via dep `auth.py`. Tiered rate by key tier using `usage_limiter.py`.
- **Acceptance:** Key with only `ai:read` cannot call `/forms/batch`.
- **Effort:** 2d.

#### E7.2 Webhook Retry + DLQ + Dashboard
- **Gap:** Retry missing (see E5.4).
- **Design:** Unified: retry + DLQ (failed events) → admin dashboard `GET /admin/webhooks/dlq` + manual replay `POST /admin/webhooks/{id}/replay` gated by `ADMIN_API_TOKEN`. Include in `health_dashboard.py` stats.
- **Acceptance:** DLQ visible, replay works.
- **Effort:** 2d.

#### E7.3 Plugin Registry Execution + Client-Driven Render
- **Gap:** `plugins.py` metadata-only (intentional per past PR), client renders tools dynamically.
- **Design:** Keep metadata-only but add `execution_type: "local"|"server"` + `route`. For `server`, client calls existing endpoints. Add icon pack + category filters already done. Add server-side plugin enable toggle via admin token.
- **Acceptance:** New tool added to registry → appears in `tools_screen.dart` without app update (if execution local already exists).
- **Effort:** 2d.

#### E7.4 OpenAPI Docs + SDK Generation
- **Gap:** `/api/docs` exists but no SDK.
- **Design:** Export OpenAPI JSON via FastAPI auto, generate Dart SDK via `openapi-generator` in `frontend/lib/core/network/` wrapper. Keep `api_client.dart` but type-safe.
- **Acceptance:** Generated client used for chat history, teams.
- **Effort:** 2d.

---

### Pillar 8 — Enterprise, Collaboration & Cloud Sync Enhancement (E8)

#### E8.1 Per-Team AI Quotas + Billing
- **Gap:** Teams done but quota per team missing.
- **Design:** Extend `team.py` + `quota_tiers.py`: `team_ai_quota_daily` overrides user quota when acting in team context (`X-Team-Id` header). Admin `GET /admin/usage` already shows metering config — extend to per-team usage.
- **Acceptance:** Team of 10 shares 500/day pool.
- **Effort:** 3d.

#### E8.2 Cloud Sync Opt-In Encrypted
- **Gap:** Requested in PROJECT_STATUS backlog.
- **Design:** Opt-in toggle in `settings`. Use S3/GCS encrypted (client-side Fernet, similar to profile) for `annotation_persistence_service.dart` JSON. Conflict resolution: last-write wins + revision history preserves both. Never sync original PDF bytes unless user opts “sync documents”. Default off for privacy.
- **Acceptance:** Two devices same account see same annotations after manual sync.
- **Effort:** 5d, ROI Enterprise.

#### E8.3 Real-Time Collaboration via Command Log (Local-First)
- **Gap:** Proposed in EDITOR_AND_INTELLIGENCE_MASTERPLAN.md P2 original improvement.
- **Design:** Because every mutation is `domain/history/editor_command.dart` serialized, we can ship command log via WebSocket (`/teams/{id}/collab/ws`) between devices of same team. Server is relay, not storage (privacy). CRDT-lite: last writer wins per annotation id, merge via `zIndex`.
- **Acceptance:** Two phones same doc → strokes appear in < 2s.
- **Effort:** 6d, future P3.

#### E8.4 Audit Export Hardening + SIEM
- **Gap:** `TeamAuditLog` append-only exists but no hash chain.
- **Design:** Add `prev_hash` chain in `team.py`, sign export `GET /teams/{id}/audit` as CSV + JSON, include admin dashboard filtering.
- **Acceptance:** Tamper evident.
- **Effort:** 2d.

---

## 5. Cross-Cutting Concerns

### i18n & RTL
- Keep ARB parity `app_en.arb`, `app_es.arb`, `app_ar.arb`, `app_de.arb` — validated via `scripts/validate_arb.py` (create if missing).
- RTL detection service `rtl_detection_service.dart` already; ensure all new screens use `Directionality` inherited, not hardcoded left/right.
- Font assets: NotoSans, NotoSansArabic, Vazirmatn shipped in `assets/fonts/` per `pubspec.yaml` whole-dir entry — new fonts picked up automatically.

### Accessibility
- All tap targets >=48dp, `Semantics` labels, dynamic font scaling not fixed sizes (see CTO_REVIEW.md UI/UX issues). Use `a11y_wrapper.dart`.
- Verify contrast via Material 3 tonal system `app_theme.dart`.

### Offline-First
- Every new feature must have offline degradation plan: e.g., hybrid retriever falls back BM25, forms heuristics first, AI chat shows “offline mode — on-device answers only” banner.

---

## 6. Implementation Roadmap — 90 Days (Additive Delivery)

### Phase 0 — Stabilize (Week 0) — This Branch
- [x] 210 backend tests pass (verified via `backend-ci.yml`)
- [ ] Ensure `grep -R "is_pro" app/api` → only in `usage_limiter.py`/`quota_tiers.py` (migration already done per PROJECT_STATUS)
- [ ] Create this masterplan doc + `docs/ENHANCEMENT_TASKS.md` checklist
- [ ] Add `docs/ENHANCEMENT_BASED_MASTERPLAN.md` link into `README.md` and `MASTER_ENGINEERING_PLAN.md` “Next” section

### Phase 1 — Editor & Forms Quick Wins (Weeks 1-3) — High ROI
- E1.1 Rich text per-run UI
- E1.2 Snap guides V2
- E1.4 Grouping + layer reorder persistence
- E3.2 Validation UI
- E3.4 Profiles manager
- E3.5 Fill-from-anything preview
- E4.4 Auto-backup hardening
- **Exit criteria:** 5 PRs merged, export golden manual run passes, no regression in `annotation_persistence_service.dart`.

### Phase 2 — Intelligence & Perf (Weeks 4-6)
- E2.2 Map-reduce streaming
- E2.3 Chat history UI
- E2.4 Multi-doc RAG wiring
- E2.6 Suggested Q/A UI
- E4.1 Progressive open
- E4.2 Low-RAM mode
- E4.5 WorkManager
- **Exit:** ANR rate ↓, p95 open <1.5s for 1000-page, chat history e2e.

### Phase 3 — Security & Monetization (Weeks 7-9)
- E5.1 Encrypted recent
- E5.4 Webhook signing+retry
- E6.1 Billing RTDN
- E6.2 Paywall A/B onboarding
- E7.1 API key scopes
- **Exit:** Entitlement accuracy 99.9%, webhook delivery >99.5%, ARB parity CI gate.

### Phase 4 — Platform & Enterprise (Weeks 10-12)
- E2.1 Hybrid embeddings (optional download)
- E5.2 2FA + E5.3 SSO
- E8.1 Per-team quotas
- E7.2 DLQ dashboard
- E8.2 Cloud sync opt-in (behind feature flag `app_config.dart`)
- **Exit:** Enterprise pilot ready, SDK generated.

### Phase 5 — Future (Post-90d)
- E1.7 True redaction (requires legal review)
- E1.5 Golden tests CI (needs Flutter toolchain runners)
- E2.7 Vision forms (needs vision model quota increase)
- E8.3 Real-time collab command log
- On-prem managed-AI proxy (`docs/DEPLOYMENT.md` extension)

---

## 7. Metrics & Success Criteria (North Stars)

| Metric | Baseline (est) | Target after Phase 4 | Instrumentation |
|--------|----------------|----------------------|----------------|
| **Time to first page** (1000-page) | ~5-8s | <1.5s | `analytics_service.dart` frame timing |
| **ANR rate** | unknown (no Crash) | <0.1% | `crash_reporter.dart` + Sentry |
| **Export fidelity** | manual | 100% golden pass on 5 corpus PDFs | `export_fidelity_checker.dart` + golden |
| **Form fill success** (profile → field) | ~70% heuristic | >85% with hybrid + validation | `form_memory_service.dart` logs local |
| **AI citation accuracy** (answer grounded) | BM25 keyword ~60% | Hybrid >80% paraphrase | human eval 50 Q/A |
| **Chat retention** (return to chat) | 0 (ephemeral) | >30% reuse history | backend `chat_history.py` count |
| **Pro CVR** (install→purchase) | unknown | +30% vs control via onboarding A/B | `analytics_service.dart` + Play Console |
| **Entitlement accuracy** | purchase-time only | 99.9% with RTDN | `billing/rtdn` tests + dashboard |
| **Recent files query p95** (1k items) | JSON blob O(n) | <16ms via drift | microbenchmark |
| **Webhook delivery** | at-least-once no retry | >99.5% with retry+DLQ | `health_dashboard.py` |

---

## 8. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Flutter toolchain not in CI → golden tests not enforceable | High | Medium | Make golden optional runner + local script `tools/check_export.py`; keep `export_fidelity_checker.dart` runtime check |
| ONNX runtime bloats APK > 150MB | Medium | High | Ship embeddings as optional download via `tool_handoff.dart` download manager, not bundled; fallback BM25 |
| Low-RAM devices OOM on high-res raster | High | High | Adaptive cap + WorkManager + progressive open (E4.1/E4.2) |
| Play Billing RTDN secret leak | Low | Critical | Store service-account JSON in `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON` env (KMS), never commit; validate in `config.py` guard |
| XFA parsing breaks pypdf | Medium | Medium | Feature-flagged behind `try/except`, returns empty list + log, not hard failure |
| True redaction legally irreversible | Low | High | Double confirm sheet, audit log entry, export copy not overwrite |
| Command-log collab conflict | Medium | Medium | Last-write wins per id + revision history preserves both; no auto-merge of concurrent edits same id |

---

## 9. Verification & Governance

### Per-PR Checklist (Add to `CONTRIBUTING.md` or PR template)
- [ ] Read real file first (no blind changes)
- [ ] Additive only unless migration script included
- [ ] `ruff check app tests --select F && python -m compileall -q app tests` passes
- [ ] `pytest -q` 210+ tests (or new count) pass — in-memory SQLite, no network
- [ ] If Dart changed: `flutter analyze` + `flutter test` when toolchain available (otherwise label `needs-flutter-ci`)
- [ ] All new AI endpoints use `get_quota()` + `check_and_increment_tiered()`
- [ ] Encrypted fields via Fernet, no PII in logs
- [ ] Heavy ops via `compute()` + cancellation
- [ ] ARB keys parity (if UI)
- [ ] Export fidelity manual check if touches `annotation_draw.dart` or `editor_export_service.dart`

### Backend CI (`.github/workflows/backend-ci.yml` — already static-checks + tests)
- Keep `static-checks` + `tests` jobs. Add optional `arb-parity` job (python JSON load all `app_*.arb` keys compare).

### Frontend CI (`.github/workflows/build-apk.yml` — already APK)
- Add `flutter analyze` step before build; fail on analysis errors.

### Documentation Updates Required per Pillar
- `README.md` capabilities table updated after each Pillar ships
- `docs/PROJECT_STATUS.md` cumulative DONE section + “still needs YOU” updated
- `docs/DATA_SAFETY.md` + `docs/PRIVACY_POLICY.md` if data flow changes (e.g., cloud sync opt-in)
- This doc’s Phase checkboxes updated.

---

## 10. Immediate Action Plan for This Branch `arena/019fa435-ai-pdf`

**Shippable now (without Flutter toolchain):**
1. Created this doc (`docs/ENHANCEMENT_BASED_MASTERPLAN.md`).
2. Next: create `docs/ENHANCEMENT_TASKS.md` — actionable checklist with owners, file pointers, estimate.
3. Backend quick-win: add missing `test_billing_rtdn.py` scaffold + `api/v1/billing_rtdn.py` placeholder (metering reuse intact) to unblock Pillar 6.
4. Backend: add `GET /admin/webhooks/dlq` placeholder list from in-memory + retry guard for E7.2.
5. Ensure `grep -R is_pro app/api` audit documented — already migrated per PROJECT_STATUS, but add guard script `backend/scripts/check_metering.py`.

**Requires Flutter toolchain (deferred to separate PR with build-apk.yml verification):**
- E1.1 Rich text toolbar wiring
- E4.1 Progressive open
- E5.1 Drift migration

---

## 11. Appendix — File Index & Dependencies

### Key File Map
```
frontend/lib/features/editor/
  domain/entities/annotation.dart — stable id, TextRun, opacity/locked/visible/zIndex
  domain/services/selection_service.dart — single/multi, move, resize, align, distribute
  domain/history/editor_command.dart — Command pattern
  data/annotation_persistence_service.dart — JSON autosave keyed by file hash
  data/editor_export_service.dart — compositor (raster + vector)
  data/annotation_draw.dart — ONE render path
  presentation/widgets/inline_text_editor.dart — caret overlay
  presentation/widgets/editor_thumbnail_strip.dart — paging
backend/app/
  api/v1/document_ai.py — chat/summarize/translate/rewrite/extract/analyze/fix-ocr (metered)
  api/v1/forms.py — acroform/read+fill/batch/understand-form (metered)
  api/v1/multi_doc_chat.py — multi-doc index+chat (metered)
  api/v1/billing.py — verify
  api/v1/teams.py — teams/roles/templates/audit
  services/ai/usage_limiter.py + usage_backend.py + billing/quota_tiers.py — tiered quotas
  services/ai/field_mapper.py — 100+ labels 12+ langs
  services/ai/multi_doc_index.py — BM25 cross-cited
  services/ai/map_reduce_summarizer.py — large doc summarize
  models/team.py — owner/admin/member, SharedTemplate, TeamAuditLog
frontend/lib/core/services/
  bm25_retriever.dart — offline RAG moat
  ocr_service.dart — ML Kit
  user_profile_service.dart — encrypted profile
  recent_files_service.dart — JSON blob (to be encrypted+drift)
```

### Dependency Order (Must-Respect)
```
page_coordinate_transform → inline_text_editor → rich_text → export_fidelity
ocr_field_detection → understand-form → validation → cross-field → profiles
bm25_retriever → hybrid_retriever → multi_doc_index → chat_history UI
annotation_persistence → revision_history → recovery_dialog → cloud_sync
usage_limiter → quota_tiers → billing verify → RTDN → per-team quota
```

---

## 12. Sources & Prior Art (Compliance: Summarized, Not Quoted)
- CTO_REVIEW.md, ENGINEERING_REVIEW.md, EDITOR_AND_INTELLIGENCE_MASTERPLAN.md, MASTER_ENGINEERING_PLAN.md — current internal masterplans (ground truth).
- Public competitive context summarized: UPDF mind-maps, ChatPDF cited answers, PDFgear free inline edit — used only to set parity targets, not implementation.
- Flutter & FastAPI docs for `compute()`, `drift`, `pdfx`, PyMuPDF redaction API.

---

**End of Enhancement-Based Masterplan.**  
*Next: see `docs/ENHANCEMENT_TASKS.md` for checkout-ready tasks, and start Phase 1 with E1.1 + E3.2 + E3.4 on a feature branch, keeping PRs <400 lines.*

