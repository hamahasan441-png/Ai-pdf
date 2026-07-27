# Project Status & Handoff

Snapshot for continuing work in a new session. The app is a **Flutter** Android
app (`frontend/`) with an optional **FastAPI** backend (`backend/`).

> Full CTO review, architecture, and roadmap: `docs/CTO_REVIEW.md`.
> Deploying the backend: `docs/DEPLOYMENT.md`.
> Master engineering plan (completed items): `docs/MASTER_ENGINEERING_PLAN.md`.

---

## Current branch: `arena/019fa435-ai-pdf`

**This branch implements the Enhancement-Based Masterplan:**
- `docs/ENHANCEMENT_BASED_MASTERPLAN.md` (8 pillars, 42 tasks, 90-day roadmap) — NEW
- `docs/ENHANCEMENT_TASKS.md` (checkout-ready tasks with file pointers) — NEW
- Backend: RTDN re-verification `billing.py` E6.1 (5 tests), webhook DLQ scaffold `admin.py` E7.2 (3 tests), metering guard `backend/scripts/check_metering.py` E5.5
- 225 backend tests pass (was 210), all green with in-memory SQLite, no network
- README + MASTER_ENGINEERING_PLAN updated to link enhancement plan

Previous branch `copilot/continu-masterplan-building` had P0–P3 done, 210 tests. This branch builds additively on it.

---

## What's DONE (cumulative — this branch + previous merged work)

### Enhancement-Based Masterplan (NEW — this branch `arena/019fa435-ai-pdf`)
- **Masterplan docs:** `ENHANCEMENT_BASED_MASTERPLAN.md` + `ENHANCEMENT_TASKS.md` — 8 pillars (Editor, Intelligence, Forms, Perf, Security, Growth, Platform, Enterprise), 42 concrete tasks E1.1–E8.4, sequenced 90 days, additive principles, file-level designs, acceptance criteria, verification, risks
- **Backend E6.1 Billing RTDN re-verification:** `api/v1/billing.py` now decodes Pub/Sub push envelope (base64 JSON), extracts `subscriptionNotification` / `oneTimeProductNotification` / `voidedPurchaseNotification`, re-verifies via `play_verifier.py` when configured, else heuristic for cancel/revoked/expired (3,12,13), upserts `Entitlement` — 5 tests `test_billing_rtdn.py`
- **Backend E7.2 Webhook DLQ scaffold:** `api/v1/admin.py` adds `GET /admin/webhooks/dlq`, `POST /admin/webhooks/{id}/replay`, `GET /admin/webhooks/stats` — lists inactive webhooks as DLQ proxies, re-activates on replay, stats for health dashboard — 5 tests updated `test_admin.py`
- **Backend E5.5 Metering guard:** `backend/scripts/check_metering.py` — scans `app/api/v1/*.py` for legacy `is_pro` / `check_and_increment` and ensures tiered `get_quota` + `check_and_increment_tiered` on all AI endpoints
- **Docs linking:** `README.md` + `MASTER_ENGINEERING_PLAN.md` + `PROJECT_STATUS.md` updated to reference enhancement plan, 225 tests passing

### Backend (FastAPI) — prior P0–P3 cumulative
- **Auth (complete):** `/register`, `/login`, `/refresh` (token rotation), `/me`,
  `/change-password` — all paths covered by `test_auth.py`.
- **Document AI (tiered metering):** `chat`, `summarize`, `translate`, `rewrite`,
  `extract`, `analyze`, `fix-ocr` — all via `_meter()` helper using tiered quotas.
- **Secondary AI endpoints (tiered metering, upgraded this session):**
  `extract-dates`, `extract-actions`, `suggest-questions`, `suggest-edits`,
  `multi-doc/index+chat`, `compare`, `outline` — all migrated from binary
  `is_pro`/`check_and_increment` to `get_quota`/`check_and_increment_tiered`.
- **Forms (new this session):** `/forms/understand-form` — AI semantic fallback for
  ambiguous field labels (Pillar 3 hybrid detection). Metered via tiered quota.
- **Forms (existing):** `/forms/acroform/read+fill` (PyMuPDF, native widgets),
  `/forms/batch` (multi-form profile fill, 50-doc cap).
- **Form validation:** `form_validate.py` (email/IBAN/date/phone validators).
- **Suggest edits:** review-first, accept/reject card model — server proposes,
  never applies.
- **Multi-doc RAG:** `multi_doc_chat.py` + `multi_doc_index.py` (BM25, cross-cited).
- **Document compare:** diff summary + structured changes list.
- **Document outline:** native PDF bookmarks → AI heading fallback.
- **Map-reduce summarizer:** chunked summarisation for large documents.
- **Text layer:** server-side PDF text extraction (`text_layer.py`).
- **Plugin registry:** `plugins.py` — metadata-only, kind/category/entitlement filters.
- **Teams:** roles (owner/admin/member), shared templates, audit export.
- **Admin:** usage dashboard gated by `ADMIN_API_TOKEN`.
- **Metering backend:** pluggable `memory|redis|auto` via `AI_METER_BACKEND`.
- **Tiered quotas:** `free → AI_FREE_DAILY_LIMIT`, `basic → AI_BASIC_DAILY_LIMIT`,
  `monthly/yearly/lifetime → unlimited` (all AI endpoints consistent).
- **Developer platform:** API keys (`api_keys.py`), webhooks (`webhooks.py`),
  chat history persistence (`chat_history.py`).
- **Health dashboard:** `/health/dashboard` — AI/DB/Redis config + uptime.
- **AI signature detection:** `services/ai/signature_detector.py`.
- **Test suite:** 210 tests in `backend/tests/` — all pass; no network/Postgres needed.

### Frontend (Flutter)
- **Command-pattern undo/redo:** `domain/history/editor_command.dart` +
  `editor_history.dart`.
- **Annotation persistence + crash recovery:** `data/annotation_persistence_service.dart`
  + `annotation_serialization.dart`.
- **Inline text editor:** `presentation/widgets/inline_text_editor.dart`.
- **RTL + complex scripts:** `data/rtl_text_renderer.dart`, `rtl_detection_service.dart`.
- **Font embedding:** `data/pdf_unicode_fonts.dart`, `font_registry.dart`,
  `editor_pdf_fonts.dart`.
- **Image / Stamp / FormField annotations:** `domain/entities/{image,stamp,form_field}_annotation.dart`.
- **Background page pre-rendering:** `data/background_page_renderer.dart`,
  `data/page_preloader_service.dart`.
- **Tile zoom:** `data/tile_zoom_service.dart`.
- **Text layer extraction:** `data/text_layer_extraction_service.dart`.
- **Cross-field logic:** `data/cross_field_logic_service.dart`.
- **Form profiles:** `data/form_profile_service.dart`.
- **Revision history:** `data/revision_history_service.dart`.
- **Coordinate transform:** `domain/services/page_coordinate_transform.dart`.
- **Selection:** `domain/services/selection_service.dart` (single/multi, move, resize,
  align, distribute, snap, clone).
- **Annotation groups:** `domain/services/annotation_group_service.dart`.
- **Rich text editing:** `data/editor_rich_text_service.dart`, `editor_text_runs.dart`.
- **Document search:** `data/document_search_service.dart`.
- **Redaction:** `data/redaction_service.dart`.
- **Watermark:** `domain/services/watermark_service.dart`.
- **Measurement / Bates / Page range:** specialist domain services.
- **Link detection:** `data/link_detection_service.dart`.
- **Export fidelity checker:** `data/export_fidelity_checker.dart`.
- **Export presets:** `data/export_settings_service.dart`.
- **Multi-doc chat panel:** `presentation/widgets/editor_multi_doc_chat_panel.dart`.
- **Signature verify panel:** `presentation/widgets/editor_signature_verify_panel.dart`.
- **History timeline panel:** `presentation/widgets/editor_history_timeline_panel.dart`.
- **Compare view / Split view:** dedicated presentation widgets.
- **Dark mode + full i18n:** system/light/dark toggle; EN/ES/AR + RTL.
- **Managed AI proxy:** backend `/ai/chat` with `X-Entitlement-Token`.
- **AdMob + in-app billing + free trial.**

---

## What still needs YOU (cannot be done in the sandbox)

1. **Deploy the backend** (hosting + `AI_API_KEY` + Play service-account JSON) —
   see `docs/DEPLOYMENT.md`. Then set the server URL in-app.
2. **Play Console**: create products `pro_monthly`, `pro_yearly`, `pro_lifetime`;
   upload keystore; Privacy Policy + Data-safety form.
3. **AdMob**: real App ID + unit IDs; link AdMob↔Play; app-ads.txt.
4. **Firebase/Sentry**: concrete backends behind the `Crash`/`Analytics` facades.
5. **Device smoke-test** the minified (R8) release APK before Play upload.
6. **Flutter golden tests** for editor export parity (needs a Flutter toolchain).

---

## Suggested next tasks (backlog — now organized in ENHANCEMENT_BASED_MASTERPLAN.md)

**Phase 1 (Weeks 1-3) — quick wins:**
- E1.1 Rich text per-run UI + E1.2 snap guides V2 + E1.4 grouping/layer reorder
- E3.2 validation UI + E3.4 profiles manager + E3.5 fill-from-anything preview
- E4.4 auto-backup hardening

**Phase 2 (Weeks 4-6):** E2.2 streaming summarize, E2.3 chat history UI, E4.1 progressive open, E4.2 low-RAM

**Phase 3 (Weeks 7-9):** E5.1 encrypted recent + drift, E6.2 paywall A/B, E7.1 API key scopes (E5.4 + E6.1 + E7.2 already done this branch)

**Phase 4 (Weeks 10-12):** E2.1 hybrid embeddings optional download, E5.2 2FA, E5.3 SSO, E8.1 per-team quotas, E8.2 cloud sync opt-in

**Future P5:** E1.7 true redaction, E1.5 golden tests CI, E2.7 vision forms, E8.3 command-log collab

Detailed file pointers + acceptance in `docs/ENHANCEMENT_TASKS.md`.

Legacy backlog (now mapped to pillars):
- SSO → E5.3, per-team AI quotas → E8.1, on-device embeddings → E2.1
- Cloud sync → E8.2, third-party plugins → E7.3, 2FA → E5.2
- billing webhook re-verification → E6.1 ✅ DONE this branch

---

## Key files / where things live

- Auth: `backend/app/api/v1/auth.py`
- AI metering: `backend/app/services/ai/usage_limiter.py` + `services/billing/quota_tiers.py`
- Document AI: `backend/app/api/v1/document_ai.py` (chat/summarize/translate/rewrite/extract/analyze/fix-ocr)
- Forms: `backend/app/api/v1/forms.py` (acroform/read, acroform/fill, batch, understand-form)
- Multi-doc: `backend/app/api/v1/multi_doc_chat.py`
- Backend tests: `backend/tests/` (225 tests, all pass — includes RTDN + DLQ)
- Enhancement plan: `docs/ENHANCEMENT_BASED_MASTERPLAN.md` + `docs/ENHANCEMENT_TASKS.md`
- Metering guard: `backend/scripts/check_metering.py` (E5.5)
- Billing RTDN: `backend/app/api/v1/billing.py` `POST /billing/rtdn` + `tests/test_billing_rtdn.py`
- Admin DLQ: `backend/app/api/v1/admin.py` `GET /admin/webhooks/dlq` + `/replay` + `/stats`
- Editor history: `frontend/lib/features/editor/domain/history/`
- Inline text editor: `frontend/lib/features/editor/presentation/widgets/inline_text_editor.dart`
- Annotation persistence: `frontend/lib/features/editor/data/annotation_persistence_service.dart`
- i18n: `frontend/lib/l10n/app_{en,es,ar}.arb`

## Conventions
- Push via the GitHub power tool (never `git push`); PRs only, never commit to `main`.
- Keep ARB keys in parity across en/es/ar (validate JSON before commit).
- Heavy PDF/image work runs in isolates (`core/image/image_ops.dart` + `compute`).
- All AI endpoints use `get_quota` + `check_and_increment_tiered` — never the binary `is_pro` pattern.
