# AI PDF — Development Documentation

## Overview

**AI PDF** is an Android-first Flutter app. Its two pillars:

1. **Offline file tools** — JPG→PDF, compress, merge, split, a pro PDF editor, and page organizer. All run **on-device**; no network, nothing uploaded.
2. **On-device AI** — "Understand" (chat with a document) and "Fill Form" (place answers onto the real form). The app calls **OpenRouter** (OpenAI-compatible) **directly from the phone** using the user's own API key, stored encrypted on device.

A FastAPI backend exists in `backend/` for account-based flows (auth, encrypted profiles, server-side pipeline) but is **optional** — the shipped on-device experience does not require it.

---

## Architecture (on-device path)

```
┌──────────────────────────────────────────────┐
│              Flutter Android App               │
│   Material 3 · Riverpod · GoRouter · Dio       │
│                                                │
│  Offline tools:  pdfx (render) + pdf (create)  │
│                  + image (compress)            │
│  AI tools:       Dio → OpenRouter API          │
│  Secrets:        flutter_secure_storage        │
└───────────────┬───────────────────┬───────────┘
                │ (AI only)          │ (optional account flows)
        ┌───────┴────────┐   ┌───────┴───────────┐
        │  OpenRouter    │   │  FastAPI backend  │
        │  (user's key)  │   │  (optional/legacy)│
        └────────────────┘   └───────────────────┘
```

The AI endpoint is configurable: OpenRouter (online) or any OpenAI-compatible server, including a local/LAN one for offline AI.

---

## Frontend tech stack

| Concern | Package | Notes |
|--------|---------|-------|
| State | flutter_riverpod ^2.4.9 | |
| Routing | go_router ^13.2.0 | |
| HTTP | dio ^5.4.0 | AI + optional backend |
| Secure storage | flutter_secure_storage ^9.0.0 | OpenRouter key (encrypted) |
| Prefs | shared_preferences ^2.2.2 | model, endpoint, recents |
| Paths | path_provider ^2.1.2 | output files |
| PDF render | pdfx ^2.6.0 | PDFium; capped-resolution rendering |
| PDF create | pdf ^3.11.1 | export/flatten |
| Images | image ^4.3.0 | compress/downscale (pure Dart) |
| File pick | file_picker ^8.1.6 | SAF (no runtime permission) |
| Image pick | image_picker ^1.1.2 | camera/photos |
| Share | share_plus ^10.1.2 | |
| Permissions | permission_handler ^11.3.1 | startup prompt (plugins also self-request) |
| i18n | intl ^0.19.0 | date formatting |

**Android toolchain (committed in `frontend/android/`):** AGP 8.7.0, Gradle 8.10.2, Kotlin 1.9.24, compileSdk 35, minSdk 24, targetSdk 34, `desugar_jdk_libs:2.0.4`, multidex on, minify/shrink **off**. Namespace `com.aidocassistant.app`. CI uses **Flutter 3.29.0** (required by pdfx 2.9.x, which uses the `SurfaceProducer.Callback.onSurfaceCleanup` API introduced in Flutter 3.29).

---

## Project structure (frontend)

```
frontend/lib/
├── main.dart                         # entry; global error boundary; loads AppSettings
├── core/
│   ├── config/
│   │   ├── app_config.dart           # endpoints, model catalog, auto-router constants
│   │   ├── app_settings.dart         # runtime settings: AI key (secure), model, endpoint, base URL
│   │   └── router.dart               # GoRouter routes
│   ├── constants/app_constants.dart
│   ├── network/
│   │   ├── api_client.dart           # Dio + auth interceptor (optional backend)
│   │   └── openrouter_service.dart   # on-device AI: chat(), ask(), auto model routing, errors
│   ├── services/
│   │   ├── permission_service.dart   # storage/photos/camera prompt
│   │   └── recent_files_service.dart # persisted recent files (ValueNotifier)
│   └── theme/app_theme.dart
└── features/
    ├── home/presentation/home_screen.dart        # dashboard, quick actions, recents, app-bar: key/history/profile
    ├── tools/
    │   ├── models/filled_field.dart              # AI form-fill value + position (tolerant JSON parse)
    │   ├── services/offline_pdf_service.dart     # merge/split/compress/jpg→pdf (capped rendering)
    │   ├── services/output_actions.dart          # Save (SAF) / Share / mirror to "AI PDF" folder
    │   ├── widgets/result_sheet.dart             # Preview/Save/Share sheet + FilePreviewScreen
    │   └── presentation/
    │       ├── tools_screen.dart                 # tools hub (Offline / AI sections)
    │       ├── jpg_to_pdf_screen.dart
    │       ├── compress_screen.dart
    │       ├── pdf_tools_screen.dart             # merge / split
    │       ├── pick_edit_screen.dart             # pro editor (see below)
    │       └── organize_pages_screen.dart        # reorder/rotate/delete/merge pages
    ├── ai/presentation/ai_chat_screen.dart       # Understand + Fill Form chat (mode enum)
    ├── settings/presentation/ai_settings_screen.dart  # key/model/endpoint + Test
    ├── recent/presentation/recent_files_screen.dart
    ├── auth/…  home/…  upload/…  document/…  editor/…  profile/…   # account-based / legacy
```

---

## On-device AI (`openrouter_service.dart`)

- `chat(messages, {model})` — OpenAI-style multi-turn; images attached as data URLs on the first user turn so vision models can "see" pages.
- **Auto routing:** model `'auto'` (default) resolves to a free **vision** model when the request has images, else a strong free **text** model.
- **Fallback:** on a model-unavailable error, retries once with a known-good free model matching the request (vision/text).
- `lastModelUsed` records the resolved slug (shown by Settings → Test).
- Errors are mapped to friendly messages (no key / 401 / 402 credits / 429 rate limit / 400-404 model / 5xx / timeouts / offline).

Model catalog and constants live in `app_config.dart` (`aiModels`, `autoModel`, `autoVisionModel`, `autoTextModel`, `defaultAiModel`). The key is read via `AppSettings.openRouterKey()` (secure storage first, then optional `--dart-define` build value).

### Form filling (auto-place)
`ai_chat_screen.dart` (Fill Form mode) collects info by chat, then **"Place answers on the form"** asks the AI for strict JSON `[{page,x,y,text}]`, parsed by `FilledField.tryParse` (tolerant of percent-vs-fraction, missing fields), and opens `PickEditScreen(initialPath, initialFields)` with the values dropped as editable text boxes on the correct pages.

---

## PDF Editor (`pick_edit_screen.dart`)

- Memory-safe: pages rendered by pdfx at a capped long edge; only a few pages cached; far pages evicted.
- Tools: pan/select, draw, highlight, text (movable, font size, bold, color), line, arrow, rectangle, oval, whiteout/redact, signature (savable + reuse), eraser, page rotate.
- Selection: tap in pan mode to select any text/shape/stroke; move by drag; **resize handles** on shapes; **duplicate**, **bring-to-front**, **send-to-back**, delete.
- Undo/redo per page. Unsaved-changes guard (`PopScope`) on back.
- Export uses an **off-screen compositor**: each page re-rendered at up to 1800px and annotations painted onto a `Canvas` via `PictureRecorder` → crisp PDF that matches the screen. Shared `_AnnDraw` keeps on-screen and export drawing identical (resolution-independent scaling).

---

## Routing (`core/config/router.dart`)

| Route | Screen |
|-------|--------|
| `/home` | Dashboard (guest-friendly) |
| `/tools` | Tools hub |
| `/tools/jpg-to-pdf`, `/tools/compress`, `/tools/merge`, `/tools/split` | Offline tools |
| `/tools/pick-edit` | PDF editor |
| `/tools/organize` | Organize Pages |
| `/ai` | Understand (AI chat) |
| `/ai-form` | Fill Form (AI chat) |
| `/settings` | AI Settings (key / model / endpoint / Test) |
| `/recent` | Recent Files |
| `/login`, `/register`, `/upload`, `/document/:id`, `/editor/:id`, `/profile` | Account-based / legacy |

---

## Build & release

### CI (`.github/workflows/build-apk.yml`)
On push to `main` (and PRs):
1. Checkout, Java 17, Flutter **3.29.0**.
2. `flutter create … android .` to fill gitignored files (gradle wrapper, mipmaps, local.properties), then `git checkout -- android/ lib/ pubspec.yaml` to restore committed files, and delete any generated `*.gradle.kts` (project uses Groovy).
3. `flutter pub get` (tee'd to `build.log`).
4. `flutter build apk --release --dart-define=OPENROUTER_API_KEY=<secret>` (secret optional).
5. **On failure:** a "Show error summary on failure" step prints the key error lines last, and `build.log` is uploaded as an artifact.
6. Rename to `AI-PDF.apk`, upload artifact, and (on `main`) **publish a GitHub Release** via `gh release create` → permanent link `releases/latest/download/AI-PDF.apk`.

The release build is signed with the debug key (installable for personal use). `OPENROUTER_API_KEY` is optional; without it the app still works and the user pastes a key in-app.

### Local
```bash
cd frontend
flutter pub get
flutter run                       # or: flutter build apk --release
```

Optional backend:
```bash
docker-compose up -d              # PostgreSQL + Redis + FastAPI (port 8000)
```

---

## Conventions & decisions

- **On-device first:** offline tools never touch the network; AI goes phone → OpenRouter directly. Keeps the app usable, private, and cheap.
- **No secrets in the repo:** the OpenRouter key lives in encrypted device storage (or an optional CI secret via `--dart-define`). Never commit `sk-or-...` (GitHub push protection blocks it and it would leak).
- **Build safety:** minify/shrink off; no code-gen; pinned toolchain; avoid risky native deps. Each change should keep CI green and be independently shippable.
- **pdfx over printing/syncfusion:** explicit capped-resolution rendering → bounded memory (printing caused OOM; syncfusion removed an API we relied on).
- **Raster export** for editor/organize: lossy but reliable and memory-safe.

### Adding a screen
1. `lib/features/<name>/presentation/<name>_screen.dart`
2. Register a route in `core/config/router.dart`.
3. For AI, use `OpenRouterService`; for offline PDFs, use `OfflinePdfService` / pdfx / pdf.

---

## Status

- [x] Offline: JPG→PDF, Compress, Merge, Split
- [x] Pro PDF Editor (draw/text/shapes/whiteout/signature/rotate/select-move-resize/undo-redo/hi-res export)
- [x] Organize Pages (reorder/rotate/delete/merge/export)
- [x] On-device AI: Understand (chat + save answer as PDF) & Fill Form (auto-place answers)
- [x] Model picker + Auto routing + configurable endpoint (online/offline)
- [x] In-app AI Settings with Test; key encrypted on device
- [x] Recent Files; Save/Share everywhere; guest mode
- [x] Global error boundary (no crash screens)
- [x] CI → signed APK + GitHub Release direct link
- [ ] On-device OCR (planned; adds a native dependency)
- [ ] Profile-powered auto-fill, templates, batch (roadmap)
- [ ] Play Store release
