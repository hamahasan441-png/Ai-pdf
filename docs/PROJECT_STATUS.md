# Project Status & Handoff

Snapshot for continuing work in a new session. The app is a **Flutter** Android
app (`frontend/`) with an optional **FastAPI** backend (`backend/`).

> Full CTO review, architecture, and roadmap: `docs/CTO_REVIEW.md`.
> Deploying the backend: `docs/DEPLOYMENT.md`.
> Master engineering plan (completed items): `docs/MASTER_ENGINEERING_PLAN.md`.

---

## Current branch: `arena/019fa435-ai-pdf`

**This branch implements the Enhancement-Based Masterplan (42 tasks, 8 pillars, 90-day roadmap):**
- `docs/ENHANCEMENT_BASED_MASTERPLAN.md` + `docs/ENHANCEMENT_TASKS.md` — NEW, 8 pillars
- Backend: 255 tests passing (was 210), all green in-memory SQLite, no network
  - E5.5 metering guard `check_metering.py` ✅
  - E6.1 RTDN re-verification `billing.py` (5 tests) ✅
  - E7.2 DLQ scaffold + V2 delivery attempts `admin.py` (5 tests) ✅
  - E7.1 API key scopes (allowlist, validation, GET /scopes) 4 tests ✅
  - E8.1 per-team quota (model + PUT /quota + get_quota_with_team + X-Team-Id enforcement) 5 tests ✅
  - E5.2 TOTP 2FA (RFC 6238 stdlib, recovery codes, 6 endpoints) 5 tests ✅
  - E5.4+E7.2 webhook delivery V2 (HMAC signing + retry + attempt log) 5 tests ✅
  - E2.2 streaming map-reduce (SSE + NDJSON, team quota) 2 tests ✅
  - E5.3 SSO OIDC Google/Apple/generic + team sso_required enforcement 5 tests ✅
  - E8.2 cloud sync opt-in encrypted annotation persistence (push/pull/list/delete/status) 4 tests ✅
- Frontend: 
  - E1.1 rich per-run UI already wired, E1.2 snap guides V2, E1.4 grouping/layer
  - E3.4 Form Profiles Manager UI `form_profile_manager_screen.dart` route `/tools/form-profiles`
  - E2.3 Chat History UI `chat_history_screen.dart` route `/ai/history`, history icon in AI chat, card in ToolsScreen
- README + MASTER_ENGINEERING_PLAN linked

Previous branch `copilot/continu-masterplan-building` had P0–P3 done, 210 tests. This branch is 255 + frontend.

---

## What's DONE (cumulative — this branch + previous merged work)

### Enhancement-Based Masterplan (NEW — this branch `arena/019fa435-ai-pdf` — 255 tests)
- **Masterplan docs:** `ENHANCEMENT_BASED_MASTERPLAN.md` + `ENHANCEMENT_TASKS.md` — 8 pillars, 42 tasks E1.1–E8.4, 90 days, additive, file-level designs, acceptance, risks
- **E5.5 Metering guard:** `scripts/check_metering.py` scans api/v1 for legacy is_pro, ensures tiered get_quota — PASS
- **E6.1 RTDN:** `billing.py` decodes Pub/Sub envelope, re-verifies, heuristic cancel/revoked/expired, upserts Entitlement — 5 tests `test_billing_rtdn.py`
- **E7.2 DLQ V1→V2:** `admin.py` GET /dlq lists failed attempts + inactive, POST /replay re-delivers via delivery service, GET /stats failed/success counts — enhanced from scaffold
- **E7.1 API key scopes:** `api_key.py` scopes TEXT + allowlist + validation, GET /api-keys/scopes, list/create include scopes — 4 tests `test_api_key_scopes.py`
- **E8.1 Per-team quota:** Team ai_daily_quota + sso_required, TeamResponse includes quota, PUT /quota owner/admin, quota_tiers get_team_quota + get_quota_with_team (team overrides user tier), _meter checks X-Team-Id header identity team:{id} — 5 tests `test_team_quota.py`
- **E5.2 TOTP 2FA:** User totp_secret_encrypted, enabled, recovery_codes, RFC 6238 stdlib, endpoints setup/verify/status/disable/recovery-codes + login/2fa — 5 tests `test_2fa.py`
- **E5.4+E7.2 Webhook delivery V2:** WebhookDeliveryAttempt model, delivery service HMAC signing + exponential backoff retry + replay, admin DLQ V2 — 5 tests `test_webhook_delivery.py`
- **E2.2 Streaming map-reduce:** stream_map_reduce_summarize() chunk events + final, POST /summarize/stream SSE + /summarize/stream/json NDJSON, team quota enforcement — 2 tests `test_summarize_stream.py`
- **E5.3 SSO OIDC:** `sso.py` Google/Apple/generic OIDC id_token unsafe decode for tests, creates/links user is_verified, team sso_required enforcement in add_member — 5 tests `test_sso.py`
- **E8.2 Cloud Sync:** DocumentSync model file_hash, encrypted_blob (client-side Fernet, server never plaintext), push/pull/list/delete/status, scoped owner_id, version++, last-write-wins — 4 tests `test_sync.py`
- **E3.4 Form Profiles Manager UI:** `form_profile_manager_screen.dart` list, view, export clipboard+share JSON temp file, import dialog, delete confirm, route /tools/form-profiles + card in ToolsScreen — frontend
- **E2.3 Chat History UI:** `chat_history_screen.dart` list sessions GET /chat-history, restore GET /{id}, delete, offline fallback, empty states, route /ai/history, history icon in AI chat AppBar, card in ToolsScreen — frontend
- **Docs linking:** README + MASTER_ENGINEERING_PLAN + PROJECT_STATUS updated

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
- Backend tests: `backend/tests/` (255 tests, all pass — includes RTDN, DLQ V2, scopes, team quota, 2FA, webhook delivery, streaming, SSO, sync)
- Enhancement plan: `docs/ENHANCEMENT_BASED_MASTERPLAN.md` + `docs/ENHANCEMENT_TASKS.md` (updated done status)
- Metering guard: `backend/scripts/check_metering.py` (E5.5) PASS
- Billing RTDN: `backend/app/api/v1/billing.py` `POST /billing/rtdn` + `test_billing_rtdn.py` (E6.1)
- Admin DLQ: `backend/app/api/v1/admin.py` `GET /admin/webhooks/dlq` + `/replay` + `/stats` + `models/webhook.py` WebhookDeliveryAttempt + `services/webhooks/delivery.py` (E5.4+E7.2)
- API key scopes: `models/api_key.py` + `api/v1/api_keys.py` + `test_api_key_scopes.py` (E7.1)
- Per-team quota: `models/team.py` ai_daily_quota + sso_required + `api/v1/teams.py` PUT /quota + `quota_tiers.py` get_team_quota + `test_team_quota.py` (E8.1)
- 2FA TOTP: `models/user.py` totp + `services/auth/totp.py` RFC 6238 + `api/v1/auth.py` 2fa endpoints + `test_2fa.py` (E5.2)
- SSO OIDC: `api/v1/sso.py` Google/Apple/generic + team sso_required enforcement + `test_sso.py` (E5.3)
- Streaming summarize: `api/v1/document_ai.py` /summarize/stream SSE + /stream/json + `map_reduce_summarizer.py` stream generator + `test_summarize_stream.py` (E2.2)
- Cloud sync: `models/sync.py` + `api/v1/sync.py` push/pull/list/delete/status + `test_sync.py` (E8.2)
- Form profiles manager UI: `frontend/.../form_profile_manager_screen.dart` + route `/tools/form-profiles` (E3.4)
- Chat history UI: `frontend/.../chat_history_screen.dart` + route `/ai/history` + history icon in AI chat (E2.3)
- Editor history: `frontend/lib/features/editor/domain/history/`
- Inline text editor: `frontend/lib/features/editor/presentation/widgets/inline_text_editor.dart`
- Annotation persistence: `frontend/lib/features/editor/data/annotation_persistence_service.dart`
- i18n: `frontend/lib/l10n/app_{en,es,ar}.arb`

## Conventions
- Push via the GitHub power tool (never `git push`); PRs only, never commit to `main`.
- Keep ARB keys in parity across en/es/ar (validate JSON before commit).
- Heavy PDF/image work runs in isolates (`core/image/image_ops.dart` + `compute`).
- All AI endpoints use `get_quota` + `check_and_increment_tiered` — never the binary `is_pro` pattern.
