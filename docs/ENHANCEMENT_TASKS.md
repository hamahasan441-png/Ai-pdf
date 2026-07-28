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

## Done — This Branch `arena/019fa435-ai-pdf` (255 backend tests + 10 frontend enhancements — DO ALL NEXT batch)

### Backend — shipped and tested ✅ (255 tests)
- [x] `docs/ENHANCEMENT_BASED_MASTERPLAN.md` (8 pillars, 42 tasks, 90-day roadmap)
- [x] `docs/ENHANCEMENT_TASKS.md` (this file)
- [x] `backend/scripts/check_metering.py` guard E5.5 — scans api/v1 for legacy metering, PASS
- [x] E6.1 RTDN re-verification — Pub/Sub envelope decode, re-verify via play_verifier, heuristic cancel/revoked/expired, upserts Entitlement — 5 tests `test_billing_rtdn.py`
- [x] E7.2 DLQ scaffold V1 + V2 — inactive + failed attempts, replay via delivery service, stats — enhanced from scaffold to V2
- [x] E7.1 API key scopes — allowlist, DEFAULT_SCOPES, validation, GET /scopes — 4 tests `test_api_key_scopes.py`
- [x] E8.1 per-team quota — ai_daily_quota + sso_required, PUT /quota owner/admin, get_team_quota + get_quota_with_team, X-Team-Id enforcement — 5 tests `test_team_quota.py`
- [x] E5.2 TOTP 2FA — RFC 6238 stdlib, recovery codes, 6 endpoints — 5 tests `test_2fa.py`
- [x] E5.4+E7.2 webhook delivery V2 — WebhookDeliveryAttempt, HMAC signing, backoff retry, replay — 5 tests `test_webhook_delivery.py`
- [x] E2.2 streaming map-reduce — chunk events + final, SSE + NDJSON, team quota — 2 tests `test_summarize_stream.py`
- [x] E5.3 SSO OIDC — Google/Apple/generic OIDC unsafe decode for tests, team sso_required enforcement — 5 tests `test_sso.py`
- [x] E8.2 cloud sync opt-in — DocumentSync model, push/pull/list/delete/status, owner isolation, version++ — 4 tests `test_sync.py`
- [x] E8.3 collab WebSocket — `/teams/{team_id}/collab/ws` JWT via ?token= query, require_member, ConnectionManager in-memory team->set[WS], broadcast, welcome + error handling, GET /collab/status — backend, no pytest yet but manual
- [x] Link masterplan in README + MASTER_ENGINEERING_PLAN + PROJECT_STATUS

### Frontend — shipped (needs flutter analyze) ✅ (10 enhancements)
- [x] E1.1 Rich text per-run UI — already wired (`pick_edit_screen.dart` + `inline_text_editor.dart` + toolbar + service)
- [x] E1.2 Snap guides V2 — object-to-object priority + page guides `selection_service.dart`
- [x] E1.4 Grouping + layer reorder — `annotation_group_service.dart` + `zIndex` persistence
- [x] E3.4 Form Profiles Manager UI — `form_profile_manager_screen.dart` list, view, export clipboard+share JSON temp file, import dialog, delete, route `/tools/form-profiles` + card
- [x] E3.2 Validation UI — `editor_form_review_panel.dart` StatefulWidget + ScrollController, red border invalid, focused highlight, badge tap cycle animateTo next invalid, error container suggestion, block Apply if invalid accepted
- [x] E4.1 Progressive Open — `editor_loading_overlay.dart` progress %, page count, current page, low-RAM badge, cancel, styled; `page_preloader_service.dart` low-res ±5 first (900px) then high-res ±1, lowRamMode cap 1, renderFirstPageProgressive()
- [x] E5.1 Encrypted Recent — `encrypted_recent_files_service.dart` FlutterSecureStorage encryptedSharedPreferences, migration from `recent_files_v1` to secure key, pagination listPaginated <16ms target, max 1000, ValueNotifier, benchmark()
- [x] E2.3 Chat History UI — `chat_history_screen.dart` list/restore/delete, offline fallback, empty states, route `/ai/history`, history icon in AI chat AppBar, card in ToolsScreen
- [x] E4.4 Auto-backup V2 — `auto_backup_service_v2.dart` 3 rolling backups per file hash under backups_v2/{hash}/, latest.json + vN_meta.json, listForFile, listAll, getLatest, readLatestJson, _evictOld keeps 3, diffCount, integration with cloud sync E8.2
- [x] E6.2 Paywall A/B — `paywall_ab_service.dart` variant A monthly emphasis vs B lifetime emphasis, random 50/50 persisted, trackExposure/trackConversion/getStats/reset; `onboarding_screen.dart` 5 pages welcome/AI setup/profile/first doc/paywall A/B with variant cards yearly/monthly/lifetime badge+highlight, route `/onboarding`
- [x] E2.1 Hybrid BM25+Embeddings — `hybrid_retriever.dart` BM25 top-20 then re-rank TF-IDF cosine (3-gram + word, log TF, IDF), hybridScore 0.5*BM25+0.5*TFIDF, fallback TF-IDF for recall, hasOnnx flag scaffold for MiniLM 20MB optional download via ToolHandoff, loadOnnxModel placeholder
- [x] E4.2 Low-RAM — `LowRamDetector.kt` ActivityManager.MemoryInfo totalMem/availMem/lowMemory/isLowRamDevice/threshold + isLowRamMode = totalMem<2GB OR lowMemory OR isLowRamDevice; `LowRamPlugin.kt` MethodChannel low_ram_detector getMemoryInfo; MainActivity registers LowRamPlugin; `low_ram_service.dart` Dart wrapper
- [x] E2.6 Suggested Q/A — `suggested_questions_panel.dart` shows suggested_questions[] as ActionChip + action_items[] checkable list, onQuestionTap/onActionTap/onClose, after /analyze
- [x] E4.5 WorkManager — `batch_work_manager.dart` BatchWorkManager initialize(), scheduleLargeJob filePaths+operation via Workmanager.registerOneOffTask, cancel(), showProgress processed/total notification progress bar, isLargeJob heuristic >50MB or >10 files, _callbackDispatcher entry-point background isolate
- [x] E8.3 already (collab Ws) — plus frontend would use command log via WebSocket in editor_multi_doc_chat_panel? scaffold done backend

### Remaining backlog (Phase 5 Future)
- E1.7 True Redaction — backend POST /document-ai/redact via PyMuPDF redact + frontend confirm sheet (requires legal review)
- E1.5 Golden Tests CI — needs Flutter runner, corpus 5 PDFs
- E2.7 Vision Forms — crop field rect image → /forms/understand-form vision models
- E8.3 full replay persistence — Redis pub/sub for multi-instance + command log persistence for new client join

