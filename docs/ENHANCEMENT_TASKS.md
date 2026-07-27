# Enhancement Tasks — Checkout List (from ENHANCEMENT_BASED_MASTERPLAN.md)

**Branch:** `arena/019fa435-ai-pdf`  
**How to use:** Each task is one PR, <400 lines, with test. Copy ID into PR title: `[E1.1] Rich text per-run UI`.

---

## Phase 1 — Weeks 1-3 (Editor + Forms Quick Wins)

### E1.1 Rich Text Per-Run UI
- **Files:** `frontend/lib/features/editor/presentation/widgets/inline_text_editor.dart`, `data/editor_rich_text_service.dart`, `presentation/widgets/editor_rich_text_toolbar.dart`, `domain/entities/annotation.dart`
- **Steps:** Wire toolbar selection change → slice TextRun; keep single EditTextCommand undo.
- **Accept:** Bold word inside box → export vector bold preserved.
- **Test:** Unit test `test/editor_rich_text_test.dart` slice logic.

### E1.2 Snap Guides V2
- **Files:** `domain/services/selection_service.dart`, `data/annotation_bounds_service.dart`, `presentation/widgets/editor_canvas_painter.dart`
- **Steps:** Compute nearest edge/center <8dp, show guides, haptic.
- **Accept:** Drag near other → snap line + haptic.
- **Test:** `selection_service` snap unit test.

### E1.4 Grouping + Layer Reorder Persistence
- **Files:** `domain/services/annotation_group_service.dart`, `presentation/widgets/editor_layer_panel.dart`, `data/annotation_persistence_service.dart`
- **Steps:** Drag reorder → update zIndex + PageLayer order + autosave.
- **Accept:** Group move as one, undo restores, persists after restart.

### E3.2 Validation UI
- **Files:** `presentation/widgets/editor_form_review_panel.dart`, `backend/app/api/v1/form_validate.py`
- **Steps:** Show inline errors red border, focus next invalid, block Place.
- **Accept:** Invalid email blocks.

### E3.4 Profiles Manager
- **Files:** `features/tools/presentation/form_profile_manager_screen.dart`, `core/services/user_profile_service.dart`, `data/form_profile_service.dart`
- **Steps:** CRUD per doc type, export/import JSON encrypted.
- **Accept:** Save profile → next form autofill faster.

### E3.5 Fill-from-Anything Preview
- **Files:** `presentation/widgets/editor_smart_fill_source_sheet.dart`, `core/services/form_memory_service.dart`
- **Steps:** Upload ID → OCR match confidence → review before place → remember resolved answers per label.
- **Accept:** Passport upload suggests name/dob.

### E4.4 Auto-Backup Hardening
- **Files:** `core/services/auto_backup_service.dart`, `presentation/widgets/editor_recovery_dialog.dart`
- **Steps:** 3 rolling backups per hash, list with timestamp+diff.
- **Accept:** Kill app → recovery offers backup.

---

## Phase 2 — Weeks 4-6 (Intelligence + Perf)

### E2.2 Map-Reduce Streaming
- **Backend:** `services/ai/map_reduce_summarizer.py`, `api/v1/document_ai.py` add `?stream=true` SSE + `page_citations[]`
- **Frontend:** `editor_summarizer_panel.dart` progressive + cancel
- **Test:** `test_document_ai.py` stream param + citations field.

### E2.3 Chat History UI
- **Backend:** `api/v1/chat_history.py` exists
- **Frontend:** `features/library/presentation/` list by doc hash, restore context
- **Test:** `test_chat_history.py` already 210; add frontend widget test.

### E2.4 Multi-Doc RAG E2E
- **Backend:** `api/v1/multi_doc_chat.py` + `services/ai/multi_doc_index.py` exists
- **Frontend:** `tools_screen.dart` → select 2-10 PDFs → index → chat with [doc, page] cite; `editor_multi_doc_chat_panel.dart` wiring
- **Accept:** Answer cites Doc B p12 + Doc C p4.

### E2.6 Suggested Q/A UI
- **Files:** `features/ai/presentation/ai_chat_screen.dart`, `api/v1/suggest_questions.py`, `extract_actions.py`
- **Steps:** Render actionable checklists after `analyze`, page jump, local tasks opt-in.

### E4.1 Progressive Open
- **Files:** `data/editor_page_render_service.dart`, `data/background_page_renderer.dart`, `data/page_preloader_service.dart`, `presentation/widgets/editor_loading_overlay.dart`
- **Steps:** First page <1.5s, thumbs ±5 low-res then high-res.
- **Accept:** 1000-page first page <1.5s mid device.

### E4.2 Low-RAM Mode
- **Files:** Add Kotlin plugin `LowRamDetector.kt` via existing `pdfimport` pattern, `editor_page_render_service.dart`
- **Steps:** Detect RAM <2GB → cap LRU 1, raster 900 edge, disable pre-render.

### E4.5 WorkManager
- **Package:** `workmanager` + `flutter_local_notifications`
- **Files:** `core/services/permission_service.dart`, `features/tools/presentation/batch_process_screen.dart`
- **Accept:** Merge 500-page shows notification progress.

---

## Phase 3 — Weeks 7-9 (Security + Monetization)

### E5.1 Encrypted Recent + Drift
- **Files:** `core/services/recent_files_service.dart`, migrate to `drift` + `flutter_secure_storage`
- **Migration:** Read old `shared_preferences` key → encrypt → delete.
- **Test:** Benchmark <16ms for 1k items.

### E5.4 Webhook Signing + Retry
- **Files:** `models/webhook.py`, `api/v1/webhooks.py`, `services/cache/document_cache.py`
- **Steps:** `webhook_secret` HMAC-SHA256 header `X-Webhook-Signature`, retry 3x exponential.
- **Test:** Extend `test_webhooks.py`.

### E6.1 Billing RTDN
- **Files:** New `api/v1/billing_rtdn.py`, `services/billing/play_verifier.py`, `models/entitlement.py`
- **Steps:** POST `/billing/rtdn` parse SUBSCRIPTION_RENEWED/CANCELED/EXPIRED → re-verify → update entitlement.
- **Test:** `test_billing_rtdn.py`.

### E6.2 Paywall A/B Onboarding
- **Files:** `features/onboarding/`, `core/config/app_config.dart`, `core/observability/analytics_service.dart`
- **Steps:** Two variants monthly vs lifetime emphasis, local remote config JSON, instrument conversion.
- **Accept:** CVR measurable.

### E7.1 API Keys Scopes
- **Files:** `models/api_key.py`, `api/v1/api_keys.py`, `api/deps/auth.py` (API key dependency)
- **Steps:** Add scopes array, enforce.

---

## Phase 4 — Weeks 10-12 (Platform + Enterprise)

### E2.1 Hybrid BM25 + Embeddings (Optional Download)
- **Files:** New `core/services/hybrid_retriever.dart`, `tool_handoff.dart` download manager, `core/config/app_config.dart` flag
- **Model:** MiniLM-L6-v2 quantized 20MB optional, tflite/onnxruntime, fallback BM25.
- **Accept:** Paraphrase recall.

### E5.2 2FA TOTP
- **Files:** `api/v1/auth.py` `/auth/2fa/setup` + `/verify`, `models/user.py` `totp_secret` Fernet, `features/security/`
- **Accept:** Login requires code.

### E5.3 SSO OIDC
- **Files:** New `api/v1/sso.py`, `core/config.py` OIDC env, `models/team.py` `sso_required`
- **Accept:** Google login works.

### E8.1 Per-Team Quotas
- **Files:** `models/team.py` `team_ai_quota_daily`, `services/billing/quota_tiers.py`, `api/v1/teams.py` header `X-Team-Id`
- **Accept:** 10-member team shares 500/day.

### E7.2 DLQ Dashboard
- **Files:** `api/v1/admin.py` add `/admin/webhooks/dlq` + `/replay`, `health_dashboard.py` stats
- **Accept:** DLQ visible, replay works.

### E8.2 Cloud Sync Opt-In
- **Files:** `settings`, `data/annotation_persistence_service.dart`, `core/services/auto_backup_service.dart`
- **Design:** S3/GCS encrypted client-side Fernet, last-write wins + revision history.
- **Accept:** Two devices see same annotations after sync.

---

## Phase 5 — Future (Post 90d)

- **E1.7 True Redaction** — backend `POST /document-ai/redact` via PyMuPDF redact, frontend confirm.
- **E1.5 Golden Tests CI** — needs Flutter runner, corpus 5 PDFs.
- **E2.7 Vision Forms** — crop field rect image → `/forms/understand-form` vision models.
- **E8.3 Command-Log Collab** — WebSocket `/teams/{id}/collab/ws` relay.

---

## Guard Script — Metering Audit

Run before each backend PR:

```bash
cd backend
./scripts/check_metering.py
# Should output: 0 files use is_pro binary, all AI endpoints use get_quota
```

Script checks:
- `grep -R "is_pro" app/api` must be 0 outside `usage_limiter.py` + `quota_tiers.py`
- Every file in `app/api/v1/*` that imports `provider.py` must call `get_quota` + `check_and_increment_tiered`

---

## Done — This Branch `arena/019fa435-ai-pdf` (246 tests passing)

### Backend — shipped and tested ✅
- [x] `docs/ENHANCEMENT_BASED_MASTERPLAN.md` (8 pillars, 42 tasks, 90-day roadmap)
- [x] `docs/ENHANCEMENT_TASKS.md` (this file)
- [x] `backend/scripts/check_metering.py` guard E5.5 — scans api/v1 for legacy metering, PASS
- [x] `backend/app/api/v1/billing.py` RTDN re-verification E6.1 — Pub/Sub envelope decode, re-verify via play_verifier, heuristic for cancel/revoked/expired, upserts Entitlement — 5 tests `test_billing_rtdn.py`
- [x] `backend/app/api/v1/admin.py` DLQ scaffold V1 + V2 E7.2 — inactive + failed attempts, replay via delivery service, stats with failed/success counts
- [x] Link masterplan in `README.md` + `docs/MASTER_ENGINEERING_PLAN.md` + `PROJECT_STATUS.md`
- [x] `backend/app/models/api_key.py` + `api/v1/api_keys.py` scopes E7.1 — API_KEY_SCOPES allowlist, DEFAULT_SCOPES, validation, GET /api-keys/scopes, list/create include scopes — 4 tests `test_api_key_scopes.py`
- [x] `backend/app/models/team.py` + `api/v1/teams.py` + `quota_tiers.py` per-team quota E8.1 — ai_daily_quota Integer nullable + sso_required bool, TeamResponse includes quota, PUT /teams/{id}/quota owner/admin only, get_team_quota + get_quota_with_team (team quota overrides user tier), _meter checks X-Team-Id header and uses team:{id} identity — 5 tests `test_team_quota.py`
- [x] `backend/app/models/user.py` + `api/v1/auth.py` + `services/auth/totp.py` 2FA TOTP E5.2 — totp_secret_encrypted, enabled, recovery_codes, RFC 6238 stdlib (base32, HMAC-SHA1, ±1 window, recovery codes 8x 5-5), endpoints: setup (otpauth://), verify (enable + codes), status, disable, recovery-codes, login/2fa + login requires 2FA — 5 tests `test_2fa.py`
- [x] `backend/app/models/webhook.py` + `services/webhooks/delivery.py` webhook delivery V2 E5.4+E7.2 — WebhookDeliveryAttempt model, deliver_event() HMAC signing X-AI-PDF-Signature + X-Webhook-Signature, exponential backoff 1s,2s,4s 3 retries, replay_failed(), admin DLQ V2 shows real failed attempts — 5 tests `test_webhook_delivery.py`
- [x] `backend/app/api/v1/document_ai.py` + `services/ai/map_reduce_summarizer.py` streaming E2.2 — stream_map_reduce_summarize() generator yielding chunk {type,index,total,summary,page_citation} + final, POST /summarize/stream SSE and /summarize/stream/json NDJSON, team quota enforcement in _meter — 2 tests `test_summarize_stream.py`
- **Tests:** 246 passing (was 210) — see `backend/tests/`; all in-memory SQLite, mocked AI, no network

### Frontend — shipped (needs flutter analyze) ✅
- [x] E1.1 Rich text per-run UI — already wired in `pick_edit_screen.dart` + `inline_text_editor.dart` + `editor_rich_text_toolbar.dart` + `editor_rich_text_service.dart` (toolbar toggleBold/Italic/Underline/Color)
- [x] E1.2 Snap guides V2 — already in `selection_service.dart` snapSelected + _snapToObjects object-to-object priority + page guides
- [x] E1.4 Grouping + layer reorder — `annotation_group_service.dart` + `annotation_serialization.dart` zIndex persistence + `editor_layer_panel.dart` reorder
- [x] E3.4 Form Profiles Manager UI — new `form_profile_manager_screen.dart`: list saved FormProfile per form type, view fields, export clipboard + share JSON temp file, import JSON dialog, delete confirm, empty state, route `/tools/form-profiles` + card in ToolsScreen
- [ ] E3.2 Validation UI — show inline errors red border, focus next invalid, block Place (still TODO frontend)
- [ ] E4.1 Progressive open, E4.4 Auto-backup hardening — TODO (needs Flutter toolchain)
- [ ] E6.2 Paywall A/B onboarding — TODO

### Remaining backlog (organized in masterplan)
See Phase 1–4 sections above. Highest ROI next: E3.2 validation UI, E2.3 chat history UI, E4.1 progressive open, E5.1 encrypted recent drift, E6.2 paywall A/B, E2.1 hybrid embeddings.
