# Deployment Guide — AI PDF managed backend

This makes the cloud features live: **managed AI** (`/ai/chat`), **purchase
verification** (`/billing/verify`), and **PDF→Office conversion** (`/convert/*`).
Everything on-device (editor, offline tools, OCR, i18n) already works without it.

---

## 1. What you need

| Item | Why | Where |
|---|---|---|
| A host (VM/container) | Run the FastAPI backend | Fly.io / Render / Railway / any VM |
| Postgres database | Store entitlements | Managed Postgres or the compose DB |
| `AI_API_KEY` (OpenRouter) | Power managed AI | openrouter.ai/keys |
| Play service-account JSON | Verify purchases | Google Cloud + Play Console |
| Google Play Console | Create products, upload the app | play.google.com/console |

---

## 2. Backend environment (`backend/.env`)

Copy `backend/.env.example` → `backend/.env` and fill in:

```
APP_ENV=production
DEBUG=false
DATABASE_URL=postgresql+asyncpg://user:pass@host:5432/aipdf
SECRET_KEY=<long-random-string>

# Managed AI
AI_API_KEY=<your OpenRouter key>
AI_FREE_DAILY_LIMIT=15

# Play Billing verification
GOOGLE_PLAY_PACKAGE_NAME=com.aidocassistant.app
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON=<paste the full service-account JSON on one line>
PRODUCT_MONTHLY=pro_monthly
PRODUCT_YEARLY=pro_yearly
PRODUCT_LIFETIME=pro_lifetime

CORS_ORIGINS=["https://yourdomain.com"]
```

> The `entitlements` table is created automatically on startup (`init_db()` runs
> `create_all`, which is idempotent). For schema changes over time, use Alembic.

---

## 3. Google Play service account (for `/billing/verify`)

1. Google Cloud Console → create a **service account** → create a **JSON key**.
2. Enable the **Google Play Android Developer API** for that project.
3. Play Console → **Users & permissions** → invite the service-account email →
   grant **View financial data / manage orders**.
4. Paste the JSON into `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`.

If left blank, `/billing/verify` returns `503` and the app falls back to the
optimistic local grant (still works, just not spoof-proof).

---

## 4. Run it

### Docker (recommended)
```
docker compose up -d --build     # uses docker-compose.yml (+ docker/Dockerfile.backend)
```

### Or bare
```
cd backend
pip install -r requirements.txt
uvicorn app.main:app --host 0.0.0.0 --port 8000
```

Verify: `curl https://<host>/health` → `{"status":"healthy"}`.
API docs (when `DEBUG=true`): `https://<host>/api/docs`.

> Conversions need the optional libs in `requirements.txt` (`pdf2docx`,
> `python-pptx`, `openpyxl`); `google-auth` is needed for purchase verification.
> If any converter lib is missing, `/convert/*` returns a clean `503`.

---

## 5. Point the app at the backend

The client base URL includes `/api/v1`. Set it one of two ways:

- **Per-user**: in the app → **AI Settings** → provider **“AI PDF (managed)”** →
  enter `https://<your-host>/api/v1`.
- **Baked default** (recommended for release): build with
  `--dart-define=API_BASE_URL=https://<your-host>/api/v1`
  (add it next to `OPENROUTER_API_KEY` in `.github/workflows/build-apk.yml`).

Once set:
- **Convert** tool (PDF→Word/Excel/PPT) works.
- **Managed AI** works with no user key; free daily cap, unlimited for Pro.
- **Purchases** are verified server-side before Pro is granted.

---

## 6. Google Play Console (billing + release)

1. **Monetize → Products**: create subscriptions `pro_monthly`, `pro_yearly` and
   an in-app product `pro_lifetime` (IDs must match `ProductIds` in the app).
2. **App signing**: enroll in Play App Signing; add your upload keystore to CI
   secrets and reference it via `android/key.properties` (see `build.gradle`).
3. **App content**: add a **Privacy Policy** and complete the **Data safety**
   form — disclose that documents/PII may be sent to AI providers for processing.
4. Set `targetSdk 35` (already done), upload an **.aab**, and roll out.

---

## 7. Post-deploy checklist

- [ ] `/health` returns healthy over HTTPS.
- [ ] AI Settings → managed provider → **Test** returns “OK”.
- [ ] A sandbox purchase → `/billing/verify` returns `valid:true` and Pro unlocks.
- [ ] Pro device gets **unlimited** managed AI; free device hits the daily cap.
- [ ] PDF→Word/Excel/PPT downloads a valid file.
- [ ] Smoke-test the **minified release APK** on a device (R8).

## Follow-ups (already scaffolded / noted in code)
- Move the AI free-tier limiter from in-memory to **Redis** for multi-instance.
- Wire the **`/billing/rtdn`** webhook to re-verify on renewal/cancel/refund.
- Add **Crashlytics/Sentry** behind the existing `Crash`/`Analytics` facades.
