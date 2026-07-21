# Pdoczy — Developer Guide

## Architecture overview

Pdoczy is a **Flutter Android app** with an optional **FastAPI backend**. The app is designed offline-first: all PDF tools and the on-device AI work without any server. The backend adds managed AI (no user key needed), server-side billing verification, and PDF→Office conversion.

```
┌────────────────────────────────────────────────────────────────┐
│                    Flutter Android App                          │
│  Material 3 · Riverpod · GoRouter · 4 locales (en/es/ar/de)   │
│                                                                │
│  ┌─────────────┐  ┌────────────────┐  ┌────────────────────┐  │
│  │ Offline PDF  │  │ On-device AI   │  │ Editor (modular)   │  │
│  │ Tools (18)   │  │ OCR + BM25 RAG │  │ 25+ services       │  │
│  │ pdfx + pdf   │  │ ML Kit + Dart  │  │ domain/data/app/ui │  │
│  └─────────────┘  └───────┬────────┘  └────────────────────┘  │
│                            │ AI queries                          │
│  ┌─────────────────────────┼────────────────────────────────┐  │
│  │      OpenRouterService  │  (direct, user's key)          │  │
│  │      OR managed backend │  (server key, metered)         │  │
│  └─────────────────────────┼────────────────────────────────┘  │
└────────────────────────────┼───────────────────────────────────┘
                             │
              ┌──────────────┴──────────────┐
              │     FastAPI Backend          │
              │  (optional / managed AI)     │
              │                             │
              │  Auth · Document AI (8 EP)  │
              │  Forms · Billing · Convert  │
              │  Usage limiter · Entitle.   │
              │  PostgreSQL · Redis         │
              └─────────────────────────────┘
```

---

## Frontend architecture

### State management
- **Riverpod** (`flutter_riverpod`) for DI and reactive state
- `EditorController` (StateNotifier) manages editor lifecycle (loading, page, export, dirty)
- `SubscriptionController` manages entitlements (Pro/free/trial)

### Routing
- **GoRouter** with flat route table in `core/config/router.dart`
- 25+ routes covering tools, AI, editor, settings, profile, subscription

### Editor (the core product)
The editor lives in `features/editor/` with clean-architecture layers:

```
features/editor/
├── domain/
│   ├── entities/       annotation.dart, page_layer.dart, detected_field.dart, editor_tool.dart
│   └── services/       annotation_bounds_service.dart, selection_service.dart
├── data/               25 stateless service classes (render, export, OCR, field input,
│                       hit-test, canvas interaction, smart fill, signatures, ...)
├── application/        EditorController + EditorState (StateNotifier)
└── presentation/
    └── widgets/        EditorCanvas, EditorToolbar, EditorTopBar, overlays, dialogs, sheets
```

**Key design decisions:**
- All coordinates are **normalized 0..1** (position relative to page size)
- Font size is stored in **PDF points (pt)** with fields for RTL, rotation, line-height
- Annotations have **stable IDs** (UUID-style) for safe undo/selection/clipboard
- `PageLayer` holds `items` (annotations) + `redo` stack per page
- `AnnotationDraw` is shared between the on-screen painter AND the export compositor → what you see is what you export
- Render is **JPEG** at capped resolution (proven reliable across Android PDFium builds)
- `EditorDocumentViewport` is a **StatefulWidget** owning a persistent `TransformationController` (prevents transform reset on parent rebuilds)
- The parent `Stack` uses `StackFit.expand` (required because all children are `Positioned`)

### Smart Form Filler
- On-device field detection: `ocr_field_detection_service.dart` (ML Kit OCR + glyph/shape/keyword heuristics)
- Field ontology: `features/tools/services/form_ontology.dart` (100+ labels, 12+ languages, OCR-tolerant diacritic folding)
- Profile matching: `profile_field_matcher.dart` + `smart_form_filler.dart` (multi-signal scoring, checkbox resolution, date normalization)
- Review UX: detected fields shown as color-coded overlays → review sheet before placing

### On-device AI
- `core/network/openrouter_service.dart` — OpenAI-compatible client with auto-model routing, vision detection, fallback chain
- `core/services/bm25_retriever.dart` — pure-Dart BM25 (Okapi) retriever, indexes OCR'd pages, returns page-cited passages
- `core/services/ocr_service.dart` — Google ML Kit wrapper
- `features/ai/presentation/ai_chat_screen.dart` — Understand + Fill Form modes, quick-action pills, grounded retrieval

### Subscriptions & Ads
- `features/subscription/` — Play Billing integration (in_app_purchase), EntitlementStore, SubscriptionController
- `core/ads/` — Google AdMob (banners on browse screens only, interstitial after tool results, zero for Pro)
- 3-day free trial, rewarded ad for single Convert unlock

---

## Backend architecture

### Tech
- FastAPI + async SQLAlchemy 2.0 + PostgreSQL + Redis
- JWT auth (access + refresh tokens, bcrypt hashing)
- Fernet symmetric encryption for profile fields
- OpenRouter AI provider with automatic model fallback

### Key services
| Service | Purpose |
|---------|---------|
| `ai/provider.py` | OpenRouter client with fallback chain |
| `ai/model_router.py` | Free vs advanced model selection |
| `ai/usage_limiter.py` | Shared free-tier daily cap + Pro bypass |
| `ai/field_mapper.py` | 100+ field mappings across 12+ languages |
| `ai/form_filler.py` | Multi-stage form filling pipeline |
| `ai/understanding.py` | Document analysis (vision + text) |
| `billing/play_verifier.py` | Google Play purchase verification |
| `convert/converter.py` | PDF → Word/Excel/PPT (PyMuPDF + pdf2docx + python-pptx) |
| `profile/profile_service.py` | Encrypted profile CRUD |

### Security
- Passwords: bcrypt (direct, with 72-byte truncation)
- Profile fields: Fernet symmetric encryption at rest
- JWT: access (30min) + refresh (7 days) with rotation
- Production secrets guard: refuses to boot with default placeholder keys
- Network security config: cleartext disabled by default
- No data backed up (allowBackup=false)

### CI (`backend-ci.yml`)
- **Static checks**: `ruff --select F` (pyflakes) + `python -m compileall`
- **Tests**: pytest against in-memory SQLite (no Postgres/network needed)
- Covers: auth flow, AI metering, security (JWT/bcrypt/encryption), profile, config guard, forms

---

## Android configuration

| Setting | Value |
|---------|-------|
| Package | `com.aidocassistant.app` |
| compileSdk | 36 |
| targetSdk | 35 |
| minSdk | 24 |
| Kotlin | 2.1.0 |
| AGP | 8.7.0 |
| Gradle | 8.10.2 |
| Flutter | 3.29.0 (required by pdfx 2.9.x) |
| Java target | 17 |

---

## Local development

### Frontend
```bash
cd frontend
flutter pub get
flutter run          # debug on connected device
flutter build apk    # release APK
```

### Backend
```bash
cd backend
cp .env.example .env   # edit with real values
pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000
```

Or with Docker:
```bash
docker-compose up -d   # PostgreSQL + Redis + FastAPI
```

### Tests
```bash
# Backend
cd backend && pytest -q

# Frontend
cd frontend && flutter test
```

---

## Adding new features

### New offline tool
1. Create `frontend/lib/features/tools/presentation/<name>_screen.dart`
2. Add the render/transform logic to `OfflinePdfService` (or a new service)
3. Register a route in `core/config/router.dart`
4. Add a card to `tools_screen.dart`
5. Localize strings in all 4 ARB files (en/es/ar/de)

### New AI endpoint (backend)
1. Add request/response models + handler to `backend/app/api/v1/document_ai.py`
2. Use `_meter(request, user, db)` for consistent free-tier enforcement
3. Add tests to `backend/tests/test_document_ai.py`
4. Verify: `ruff check app tests --select F && python -m compileall -q app tests`

### New editor annotation type
1. Add subclass to `domain/entities/annotation.dart` (with stable `id`)
2. Add drawing logic to `data/annotation_draw.dart`
3. Add to `PageLayer` typed accessor
4. Update `editor_canvas.dart` and `editor_export_service.dart`
5. Extend `editor_hit_test_service.dart` for selection

---

## Design principles

1. **Privacy first**: on-device by default; managed AI is opt-in and metered
2. **Offline capable**: all PDF tools + OCR + BM25 RAG work without internet
3. **Memory safe**: capped rendering, LRU eviction, isolate-based image ops
4. **One render path**: `AnnotationDraw` shared between screen and export
5. **Small PRs**: each change compiles + analyzes + tests before merge
6. **No blind changes**: Flutter toolchain required for frontend changes (lesson learned from PR #84)

---

## Known issues & roadmap

See `docs/MASTER_ENGINEERING_PLAN.md` for the full 5-part roadmap and `docs/EDITOR_AND_INTELLIGENCE_MASTERPLAN.md` for the deep editor/AI plan.

**Next priorities:**
- Inline text editing (caret + selection, not dialog)
- RTL font embedding (Arabic/Kurdish searchable export)
- AcroForm fill (native PDF form fields)
- Multi-document RAG
- Annotation persistence + crash recovery
