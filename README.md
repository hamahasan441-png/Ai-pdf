# Pdoczy — AI-Powered PDF Editor & Document Intelligence

A **privacy-first, offline-capable** Android app that edits, converts, signs, and understands PDFs — with on-device AI that fills forms, answers questions, summarizes, translates, and extracts data. No cloud upload required.

---

## Key capabilities

### PDF Editor (professional, offline)
- Multi-page viewer with pinch-zoom and pan
- Freehand draw, highlighter, straight lines, arrows, rectangles, ovals
- Whiteout / redact (covers original content with a white box)
- Movable, resizable text boxes (font size, bold/italic/underline, color, font family)
- Signatures: draw, type, or reuse saved signatures (persisted across sessions)
- Fill & Sign marks: checkmark, cross, dot, dash, checkbox
- Object selection with move, resize handles, duplicate, copy/paste across pages, bring-to-front / send-to-back
- Edit existing PDF text (OCR-based overlay: whiteout + editable replacement box)
- Multi-select with marquee, alignment (left/center/right/top/middle/bottom), distribute
- Smart snap guides (page quarters, center, margins)
- Page rotate (90/180/270)
- Unlimited undo/redo per page
- High-resolution off-screen export (compositor renders at 1800px max edge)
- Latin-1 text exported as real selectable vector text; rectangles/whiteout as vector boxes

### Smart Form Filling (on-device AI, no upload)
- **Instant field detection** on file open (OCR + glyph/shape/keyword heuristics)
- Type-aware tap: text fields open the right keyboard, checkboxes offer check/cross, radio → dot, dates → picker, signatures → pad
- **Auto-fit**: text shrinks to fit the field width
- **Replicate**: fill matching fields with one tap
- **Auto-fill from saved profile** (encrypted on device): matches 100+ field labels across 12+ languages (German, English, French, Spanish, Arabic, Kurdish, and more)
- **AI Fill** (brain icon): full OCR → FormOntology → multi-signal scoring → date normalization → review sheet → place confirmed values
- **Fill from info document**: upload an ID/certificate/CV, OCR it on-device, match + review + place
- Checkbox/radio option resolution (gender, marital status) — ticks the correct option word

### AI Document Intelligence (on-device + managed backend)
- **Chat with PDF**: ask any question, get page-cited answers grounded in the document
- **BM25 on-device retrieval**: indexes all pages via OCR, retrieves top-K relevant passages per question — fully offline, no model download
- **Summarize**: structured / brief / bullet summaries
- **Translate**: any language
- **Rewrite**: professional / casual / formal / simplified
- **Extract data**: structured JSON extraction (names, dates, amounts, IDs)
- **Analyze**: document type, entities, key points, action items, suggested questions
- **Fix OCR**: AI-powered correction of OCR recognition errors
- **Quick actions**: Summarize, Key facts, Action items, Translate, Explain — one tap

### Offline PDF Tools (no internet, nothing uploaded)
| Tool | Description |
|------|-------------|
| Compress | Shrink images/PDFs on-device |
| Merge / Split | Combine or separate PDFs |
| JPG → PDF | Convert images to PDF |
| PDF → Images | Export pages as JPG/PNG |
| PDF → Text | Full OCR text extraction |
| Rotate PDF | 90/180/270 degree rotation |
| Extract Pages | Pull a page range into a new PDF |
| Delete Pages | Remove a page range |
| Organize Pages | Reorder, rotate, delete, add from multiple sources |
| Watermark | Semi-transparent diagonal text stamp |
| Page Numbers | Clean "n / total" badge on every page |
| Stamp Image | Overlay a logo/photo/signature at any position |
| Read Aloud | Offline TTS (text-to-speech) of any document |
| Import File | Download any file from URL (parallel range download, 5 strategies) |
| Convert (Pro) | PDF → Word / Excel / PowerPoint (server-side) |

### Monetization & Pro
- **Free tier**: all offline tools + metered managed AI (15 calls/day)
- **Pro** (monthly / yearly / lifetime via Google Play Billing): unlimited managed AI, no ads, PDF→Office conversion
- **3-day free trial**: unlocks everything
- **Rewarded ads**: watch to unlock a single Convert operation
- Tasteful banner ads only on browse screens (never in the editor/AI); zero ads for Pro

### Multi-language & Accessibility
- Full i18n: English, Spanish, Arabic (RTL), German
- In-app language switcher (System / English / Español / العربية / Deutsch)
- Dark mode with persistent toggle (System / Light / Dark)
- Calm, professional UI theme (color psychology: serene indigo-blue primary, soft teal accent)

---

## Install

Every push to `main` builds and publishes a signed APK:

**[Download latest APK](https://github.com/hamahasan441-png/Ai-pdf/releases/latest/download/AI-PDF.apk)**

1. Download `AI-PDF.apk` on your Android phone
2. Open the file; allow "install from unknown sources" if prompted
3. (Optional) Set up AI: **AI Settings** (key icon) → paste your free [OpenRouter key](https://openrouter.ai/keys) → Test

---

## Tech stack

| Layer | Technology |
|-------|-----------|
| **Frontend** | Flutter 3.29, Riverpod, GoRouter, Material 3 |
| **PDF render** | pdfx (PDFium) with capped-resolution memory-safe rendering |
| **PDF create/export** | pdf package (vector text + raster composite) |
| **Image processing** | image package (pure Dart, isolate-safe via `compute()`) |
| **On-device OCR** | Google ML Kit Text Recognition |
| **On-device RAG** | Custom BM25 retriever (pure Dart, no model download) |
| **AI provider** | OpenRouter (400+ models, OpenAI-compatible) — direct from phone |
| **Managed AI backend** | FastAPI + async SQLAlchemy + PostgreSQL |
| **Billing** | Google Play Billing (in_app_purchase) + server-side verification |
| **Security** | JWT auth, bcrypt, Fernet field encryption, network_security_config |
| **CI/CD** | GitHub Actions → APK + GitHub Release + backend static checks + pytest |
| **Languages** | Dart (frontend), Python (backend), Kotlin (native Android plugins) |

---

## Project structure

```
.
├── frontend/               Flutter Android app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/           DI, config, theme, network, services, widgets
│   │   ├── features/
│   │   │   ├── ai/         AI chat screen (Understand + Fill Form)
│   │   │   ├── editor/     Modular PDF editor (domain/data/application/presentation)
│   │   │   ├── home/       Dashboard
│   │   │   ├── profile/    User profile (encrypted)
│   │   │   ├── recent/     Recent files
│   │   │   ├── settings/   AI settings
│   │   │   ├── subscription/ Pro billing (Play Billing)
│   │   │   └── tools/      18 offline + AI tool screens
│   │   └── l10n/           ARB localization (en/es/ar/de)
│   ├── android/            Native Android (Kotlin plugins, Gradle config)
│   └── test/               Unit tests (image ops, entitlements, theme, observability)
├── backend/                FastAPI server (optional for managed AI)
│   ├── app/
│   │   ├── api/v1/         REST endpoints (auth, ai, document-ai, forms, billing, convert, profile, documents)
│   │   ├── core/           Config, security, exceptions
│   │   ├── models/         SQLAlchemy models (User, Document, Entitlement, FormField)
│   │   ├── services/       AI provider, field mapper, form filler, OCR, pipeline, billing, convert
│   │   └── middleware/     Rate limiting, audit log
│   ├── tests/              pytest suite (auth, AI metering, security, profile, config, forms)
│   └── requirements.txt
├── docs/                   Architecture, review, masterplan, deployment, status
├── docker/                 Dockerfile for backend
└── .github/workflows/      CI (build-apk.yml, backend-ci.yml)
```

---

## Backend API (managed AI — optional)

The backend provides managed AI (no user key needed), server-side billing verification, and PDF→Office conversion. All AI endpoints are metered (free daily cap; Pro = unlimited).

| Endpoint | Description |
|----------|-------------|
| `POST /api/v1/auth/{register,login,refresh,change-password}` | JWT auth |
| `GET /api/v1/auth/me` | Current user profile |
| `POST /api/v1/ai/chat` | Managed AI chat (metered) |
| `POST /api/v1/document-ai/chat` | Chat with document (grounded Q&A) |
| `POST /api/v1/document-ai/summarize` | Structured / brief / bullet summary |
| `POST /api/v1/document-ai/translate` | Translate to any language |
| `POST /api/v1/document-ai/rewrite` | Professional / casual / formal / simplified |
| `POST /api/v1/document-ai/extract` | Structured JSON data extraction |
| `POST /api/v1/document-ai/analyze` | Full document intelligence (type, entities, actions, questions) |
| `POST /api/v1/document-ai/fix-ocr` | OCR error correction |
| `POST /api/v1/document-ai/understand-form` | Semantic field classification |
| `POST /api/v1/forms/acroform/read` | Native AcroForm field reading (PyMuPDF) |
| `POST /api/v1/billing/verify` | Google Play purchase verification |
| `POST /api/v1/convert/pdf-to-{word,excel,ppt}` | PDF → Office conversion |
| `GET/PUT /api/v1/profile/` | Encrypted user profile (auto-fill source) |

---

## Development

See **[DEVELOPMENT.md](DEVELOPMENT.md)** for full architecture, editor internals, contribution guide, and local setup.

---

## License

Private repository. All rights reserved.
