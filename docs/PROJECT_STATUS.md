# Project Status & Handoff

Snapshot for continuing work in a new session. The app is a **Flutter** Android
app (`frontend/`) with an optional **FastAPI** backend (`backend/`).

> Full CTO review, architecture, and roadmap: `docs/CTO_REVIEW.md`.
> Deploying the backend: `docs/DEPLOYMENT.md`.
> Master engineering plan (completed items): `docs/MASTER_ENGINEERING_PLAN.md`.

---

## Current branch: `copilot/continu-masterplan-building`

All P0–P3 items from the masterplan are **implemented and tested**.
210 backend tests pass. The branch is ready for PR review and merge.

---

## What's DONE (cumulative — this branch + previous merged work)

### Backend (FastAPI)
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

## Suggested next tasks (backlog)

- **SSO** + per-team AI quotas (enterprise tier).
- **On-device embeddings** for better recall than BM25.
- **Cloud sync** of documents (opt-in, encrypted).
- **Third-party/remote plugins** registry extension.
- **2FA** + per-route authorisation tests.
- **billing webhook** re-verification on renewal/cancel/refund.

---

## Key files / where things live

- Auth: `backend/app/api/v1/auth.py`
- AI metering: `backend/app/services/ai/usage_limiter.py` + `services/billing/quota_tiers.py`
- Document AI: `backend/app/api/v1/document_ai.py` (chat/summarize/translate/rewrite/extract/analyze/fix-ocr)
- Forms: `backend/app/api/v1/forms.py` (acroform/read, acroform/fill, batch, understand-form)
- Multi-doc: `backend/app/api/v1/multi_doc_chat.py`
- Backend tests: `backend/tests/` (210 tests, all pass)
- Editor history: `frontend/lib/features/editor/domain/history/`
- Inline text editor: `frontend/lib/features/editor/presentation/widgets/inline_text_editor.dart`
- Annotation persistence: `frontend/lib/features/editor/data/annotation_persistence_service.dart`
- i18n: `frontend/lib/l10n/app_{en,es,ar}.arb`

## Conventions
- Push via the GitHub power tool (never `git push`); PRs only, never commit to `main`.
- Keep ARB keys in parity across en/es/ar (validate JSON before commit).
- Heavy PDF/image work runs in isolates (`core/image/image_ops.dart` + `compute`).
- All AI endpoints use `get_quota` + `check_and_increment_tiered` — never the binary `is_pro` pattern.
