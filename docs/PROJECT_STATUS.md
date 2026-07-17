# Project Status & Handoff

Snapshot for continuing work in a new session. The app is a **Flutter** Android
app (`frontend/`) with an optional **FastAPI** backend (`backend/`).

> Full CTO review, architecture, and roadmap: `docs/CTO_REVIEW.md`.
> Deploying the backend: `docs/DEPLOYMENT.md`.

---

## Open pull requests

| PR | Branch | Scope |
|----|--------|-------|
| **#53** | `feature/dark-mode-and-i18n` | All frontend work (see below) |
| **#54** | `feature/managed-backend-api` | Backend: managed AI, billing verify, PDF→Office, entitlements, deploy guide |

Both target `main`. `main` already contains earlier merged work (Play
ship-blockers, R8, security hardening, UX cleanup, Play Billing foundation,
isolate performance, observability facades — originally PRs #51/#52).

**Recommended merge order:** #54 (backend) then #53 (frontend), or either — they
touch disjoint files (Python vs Dart) so they won't conflict with each other.

---

## What's DONE

### Frontend (PR #53)
- **Dark Mode** — persisted System/Light/Dark toggle (`ThemeController`, AI Settings).
- **Full i18n** — English / Spanish / Arabic (+ RTL) across **every** screen; 322
  message keys, parity-validated. Pipeline: `flutter_localizations` + `gen_l10n`
  (`lib/l10n/*.arb`, `l10n.yaml`), `intl: any`. In-app **language switcher**
  (`LocaleController`).
- **Editor (`pick_edit_screen`)**: Fill & Sign marks (Check/Cross/Dot/Dash/
  Checkbox), **Signature Date**, **My Profile** insert, and **Edit Text**
  (OCR a page → tap a line → cover + editable box; overlay-based, not vector
  reflow). All toolbar labels + dialogs localized.
- **Read Aloud** (`/tools/read-aloud`) — OCR/extract text + `flutter_tts`.
- **Convert** (`/tools/convert`) — PDF→Word/Excel/PPT via backend; **Pro-gated**
  (free users: trial / watch rewarded ad / go Pro).
- **Managed AI provider** — "AI PDF (managed)" routes chat through backend
  `/ai/chat` (no user key). Sends `X-Entitlement-Token` for Pro bypass.
- **Purchase verification** — `BillingVerifier` calls `/billing/verify`;
  `SubscriptionController` verifies server-side before granting Pro (falls back
  to optimistic local grant if no server).
- **AdMob** (`core/ads/`) — tasteful: banners only on Tools hub + Recent Files;
  frequency-capped interstitial after a tool finishes (2-op warm-up); rewarded
  scaffolded; **zero ads for Pro**; UMP consent. Test unit IDs by default.
- **3-day free trial** — one-time (`ProTier.trial`), unlocks everything; paywall
  button + active banner.
- Observability facades (`Crash`, `Analytics`) already on `main`; console sinks.

### Backend (PR #54, `backend/`)
- `/api/v1/ai/chat` — managed AI proxy, free daily limit, **Pro bypass** via
  `X-Entitlement-Token`.
- `/api/v1/billing/verify` — Google Play purchase/subscription verification
  (service account); upserts an `Entitlement` (keyed by purchase token). `/rtdn` stub.
- `/api/v1/convert/pdf-to-word|excel|ppt` — `pdf2docx` / PyMuPDF+`python-pptx` /
  PyMuPDF+`openpyxl`. Threadpool; lazy imports → clean 503 if a dep is missing.
- `Entitlement` model; `init_db()` runs on startup (idempotent `create_all`).

---

## What's NOT done / needs YOU (can't be done from the sandbox)

1. **Deploy the backend** (hosting + `AI_API_KEY` + Play service-account JSON) —
   see `docs/DEPLOYMENT.md`. Then set the server URL in-app (AI Settings →
   managed) or bake `--dart-define=API_BASE_URL=...`.
2. **Play Console**: create products `pro_monthly`, `pro_yearly`, `pro_lifetime`
   (+ optional Play-native free-trial offer); upload keystore to CI secrets
   (`android/key.properties`); Privacy Policy + Data-safety form.
3. **AdMob**: real App ID (manifest) + unit IDs via `--dart-define ADS_TEST=false
   ADMOB_*_ID=...`; link AdMob↔Play; app-ads.txt.
4. **CI validation**: no Flutter SDK in the sandbox, so all frontend commits are
   verified by GitHub Actions (`.github/workflows/build-apk.yml`), which builds a
   release APK + runs unit tests. Backend verified by `py_compile` only — run
   `pip install` + a smoke test on deploy.
5. **Device smoke-test** the minified (R8) release APK before Play upload.

---

## Suggested next tasks (backlog, in rough priority)

- **Rewarded "bonus AI messages"** perk (watch ad → +N managed-AI calls; needs a
  server-side counter/grant tied to `X-Entitlement-Token` or an install id).
- **Entitlement follow-ups**: move the AI free-tier limiter to **Redis**
  (multi-instance) and wire the `/billing/rtdn` webhook to re-verify on
  renewal/cancel/refund.
- **Crashlytics/Sentry** concrete backends behind the `Crash`/`Analytics` facades
  (needs a Firebase/Sentry project + `google-services.json`).
- **Localize** the two remaining hardcoded spots: the AI Settings custom-endpoint
  labels; a few backend user-facing error strings.
- **True PDF text reflow** (vs. the current overlay Edit Text) — needs a
  commercial SDK (Syncfusion/PSPDFKit) or a server-side route.
- **Cloud sync** of documents (optional), and **tests** beyond the current
  entitlement/image-op/observability/theme unit tests.

---

## Key files / where things live

- Ads: `frontend/lib/core/ads/{ad_config,ads_service,ad_banner}.dart`
- Subscription: `frontend/lib/features/subscription/` (domain/data/application/presentation)
- Managed AI routing: `frontend/lib/core/network/openrouter_service.dart` (`_doManagedChat`)
- Backend routers: `backend/app/api/v1/{ai,billing,convert}.py`
- Backend services: `backend/app/services/{convert/converter,billing/play_verifier}.py`
- i18n: `frontend/lib/l10n/app_{en,es,ar}.arb`, `frontend/l10n.yaml`
- Observability: `frontend/lib/core/observability/{crash_reporter,analytics_service}.dart`

## Conventions
- Push via the GitHub power tool (never `git push`); PRs only, never commit to `main`.
- Keep ARB keys in parity across en/es/ar (validate JSON before commit).
- Heavy PDF/image work runs in isolates (`core/image/image_ops.dart` + `compute`).
