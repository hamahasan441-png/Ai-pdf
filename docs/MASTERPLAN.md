# Pdoczy — MASTERPLAN (Single Source of Truth)

> This file **replaces** all previous plan/review/status docs
> (EDITOR_AND_INTELLIGENCE_MASTERPLAN, ENHANCEMENT_BASED_MASTERPLAN, ENHANCEMENT_TASKS,
> MASTER_ENGINEERING_PLAN, ENGINEERING_REVIEW, CTO_REVIEW, PROJECT_STATUS, RELEASE_NOTES_PHASE5).
> Derived from the full multi-perspective audit (Android engineer, Play reviewer, UX, PM,
> QA, security, performance, accessibility, growth). It is the authoritative plan to
> **fix, improve, and ship** the app. Keep it updated; do not re-fork planning into new files.

**Verdict:** Strong architecture (command-pattern editor, on-device RAG AI), but **not
Play-ready**. Blockers are mostly wiring + release-pipeline, not rewrites. Estimated
**~3–5 focused weeks** to a credible launch.

**Guiding principles:** build additively, small verifiable PRs, privacy-first, and
**never advertise a feature a user cannot reach**.

---

## Phase 0 — Ship Blockers (P0, must fix before ANY Play upload)

| ID | Fix | Evidence | Done-when |
|----|-----|----------|-----------|
| P0-1 | **Release signing** — CI decode step never runs (`if: env.KEYSTORE_BASE64` is step-scoped). Move to `secrets`/job-level; app falls back to debug key otherwise. | `.github/workflows/build-apk.yml`, `android/app/build.gradle` | `apksigner verify --print-certs` shows the real upload cert. |
| P0-2 | **Real AdMob App ID** — manifest hardcodes Google TEST id; `--dart-define` can't override a manifest literal. | `AndroidManifest.xml`, `ad_config.dart` | Prod app-id + prod unit IDs + `ADS_TEST=false` in release build. |
| P0-3 | **Wire or delete ~15 orphan screens** — built but unreachable (grep = self-refs only): PdfProtect, AppLock, Batch, Bates, CustomStamp, ExportHtml, HeaderFooter, QrCode, TemplateGallery, VoiceNote, WifiTransfer, SignRequest, DocumentActivity, ContinuousScroll. | `router.dart` vs `features/**` | Every advertised feature is reachable; the rest are removed. |
| P0-4 | **Non-destructive compression** — `compressPdf()` rasterizes each page to JPEG on forced A4, killing text/forms/links. | `offline_pdf_service.compressPdf` | Text stays selectable; page size preserved; or feature relabeled "Flatten to images" + a true compressor added. |
| P0-5 | **Play Data Safety + privacy policy** must match actual SDKs (AdMob, ML Kit, analytics, secure storage). | `DATA_SAFETY.md`, `PRIVACY_POLICY.md` | Console form matches shipped SDKs/data flows. |

---

## Phase 1 — Launch Quality (P1, before public launch)

| ID | Fix | Evidence | Done-when |
|----|-----|----------|-----------|
| P1-1 | **Show onboarding** via GoRouter `redirect` when `onboarding_completed==false`. | `router.dart`, `onboarding_service.dart` | First launch → onboarding → value action. |
| P1-2 | **Contextual permissions** — request photos/storage/camera at point-of-use, not on Home init. | `permission_service.dart`, `home_screen.dart` | No upfront camera prompt; grant rates rise. |
| P1-3 | **PDF `VIEW` + `SEND` intent filters** so the app opens/receives PDFs from other apps. | `AndroidManifest.xml` | "Open with Pdoczy" + share-to works. |
| P1-4 | **i18n parity** — en=446 keys; ar/de/es=341; fa/ku=101. Complete ar/de/es; hide fa/ku from `supportedLocales` until ready. | `lib/l10n/*.arb` | No English fallback in shipped locales. |
| P1-5 | **Accessibility** — `A11y`/`Semantics` used nowhere. Add labels to tool cards, app-bar actions, editor canvas; TalkBack + large-font pass. | `a11y_wrapper.dart` (unused) | TalkBack can navigate & label every control. |
| P1-6 | **Trial via Play offer** — local `trial_used` resets on clear-data; not a real Play trial. | `subscription_controller.dart`, `entitlement_store.dart` | Trial is a server-verified Play subscription offer with auto-conversion. |
| P1-7 | **Server-verify Pro** — grant is client-side/optimistic when no backend. | `subscription_controller._grant`, `billing_verifier.dart` | Purchases verified (Play Developer API / RTDN) before unlocking. |
| P1-8 | **Remove embedded OpenRouter key** from public APK build. | `build-apk.yml`, `app_config.dart` | No credential extractable from the APK. |
| P1-9 | **Bottom navigation + global search** (Home / Files / Tools / AI). | `home_screen.dart`, `router.dart` | Competitor-parity navigation. |
| P1-10 | **Remove leaked internal codes & hardcoded strings** ("(E3.4)/(E2.3)", 'Scan Document'…). | `tools_screen.dart` | All user text localized, no dev jargon. |

---

## Phase 2 — Polish & Hardening (P2)

- Make `flutter analyze` a **hard CI gate** (currently advisory/`|| true`).
- Implement notifications natively (+ `POST_NOTIFICATIONS`) **or** remove `NotificationService` (currently a no-op: no native channel).
- Refresh backend AI model defaults (`gemini-2.0-flash-exp:free` is stale) + add `/health/ai`.
- De-duplicate dead/duplicate code: `auto_backup_service` vs `_v2`, `recent_files_service` vs `encrypted_recent_files_service`, `bm25_retriever` vs `hybrid_retriever`.
- Friendly error messages (stop showing `e.toString()`); route detail to crash reporter.
- Wire `app_rating_service` (in-app review after successful export).
- Empty-state illustrations + primary CTA on every tool screen.
- `--split-per-abi` / App Bundle + upload R8 mapping for readable crashes.
- Backend: require a real 32-byte Fernet key (no single-SHA256 passphrase); pin `intl`.

---

## Phase 3 — Competitive Differentiation (P3, roadmap)

- **Non-destructive PDF engine**: stream-level image downsampling, real recompression.
- **AcroForm fill** (native form fields), and **open password-protected PDFs**.
- **Inline text editing** (caret + selection) to match Adobe/Xodo.
- **Optional cloud connectors** (Drive/Dropbox/OneDrive) + account backup — kept opt-in to preserve privacy-first stance.
- **Multi-document RAG**, on-device small-LLM option.
- **Sentry/Crashlytics** backend (the `Crash.setReporter` hook already exists).
- Home screen widget / quick-scan tile.

---

## Known Strengths (preserve, don't regress)

- Command-pattern editor undo/redo with per-page history + gesture transactions (`editor_controller.dart`).
- On-device AI: capped-res page render → BM25 retrieval → page-cited answers → place-on-form (`ai_chat_screen.dart`, `bm25_retriever.dart`).
- Global crash handling + friendly error widget (`main.dart`).
- Coherent Material 3 "calm" theme; solid paywall state handling.
- Secure per-provider key storage (`flutter_secure_storage`); backend production-secret guard; bcrypt(12).
- Native low-RAM detection + capped/isolate image ops (memory safety).

---

## Scorecard (baseline — update as phases complete)

Overall **58/100** · UI 68 · UX 55 · Perf 70 · Security 52 · A11y 30 · Features 60 · Play-readiness 35 · Monetization 45.

**Definition of "launch-ready": Phase 0 + Phase 1 complete, Play-readiness ≥ 80.**
