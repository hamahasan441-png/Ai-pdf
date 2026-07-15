# AI PDF - Development Documentation

## Project Overview

**AI PDF** is a production-grade Android application that uses AI to understand, edit, fill, validate, and export PDF/DOCX documents. It combines a Flutter mobile frontend with a FastAPI Python backend, connected to the FreeTheAI API (free, OpenAI-compatible, 80+ models).

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│              Flutter Android App                      │
│   Material 3 · Riverpod · GoRouter · Dio            │
└───────────────────────┬─────────────────────────────┘
                        │ REST API (JSON)
┌───────────────────────┴─────────────────────────────┐
│              FastAPI Backend (Python)                 │
│   SQLAlchemy · Pydantic · JWT · Fernet Encryption   │
└──────┬────────────────┬─────────────────┬───────────┘
       │                │                 │
┌──────┴──────┐  ┌──────┴──────┐  ┌──────┴──────┐
│ PostgreSQL  │  │    Redis    │  │  FreeTheAI  │
│  Database   │  │    Cache    │  │   API (AI)  │
└─────────────┘  └─────────────┘  └─────────────┘
```

---

## Tech Stack

| Layer | Technology | Version | Purpose |
|-------|-----------|---------|---------|
| Mobile App | Flutter | 3.22+ | Cross-platform UI |
| State Management | flutter_riverpod | ^2.4.9 | Reactive state |
| Navigation | go_router | ^13.2.0 | Declarative routing |
| HTTP Client | dio | ^5.4.0 | API calls + interceptors |
| Secure Storage | flutter_secure_storage | ^9.0.0 | Token storage |
| File Picker | file_picker | ^6.1.1 | Document selection |
| Backend | FastAPI | 0.115.0 | Async REST API |
| ORM | SQLAlchemy (async) | 2.0.35 | Database access |
| AI Provider | FreeTheAI | - | GPT-4o, Claude, Qwen |
| Database | PostgreSQL | 16 | Data persistence |
| Cache | Redis | 7 | Session cache |
| PDF Processing | PyMuPDF | 1.24.10 | Parse/edit PDFs |
| DOCX Processing | python-docx | 1.1.2 | Parse/edit Word |
| OCR | Tesseract | - | Scanned documents |
| Auth | JWT + bcrypt | - | Authentication |
| Encryption | Fernet (AES-128) | - | Profile data at rest |
| Deployment | Docker Compose | - | Container orchestration |
| CI/CD | GitHub Actions | - | Auto-build APK |

---

## Project Structure

```
Ai-Pdf/
├── .github/workflows/
│   └── build-apk.yml              # CI: auto-builds Android APK
├── backend/
│   ├── app/
│   │   ├── main.py                # FastAPI entry point
│   │   ├── core/
│   │   │   ├── config.py          # Settings (env vars, AI config)
│   │   │   ├── security.py        # JWT, bcrypt, Fernet encryption
│   │   │   └── exceptions.py      # Custom error classes
│   │   ├── db/
│   │   │   └── database.py        # Async SQLAlchemy setup
│   │   ├── models/
│   │   │   ├── user.py            # User + UserProfile (encrypted)
│   │   │   └── document.py        # Document + FormField
│   │   ├── schemas/
│   │   │   ├── auth.py            # Login/Register schemas
│   │   │   ├── profile.py         # Profile CRUD schemas
│   │   │   └── document.py        # Document/Field schemas
│   │   ├── api/
│   │   │   ├── deps/auth.py       # get_current_user dependency
│   │   │   └── v1/
│   │   │       ├── router.py      # Aggregates all routes
│   │   │       ├── auth.py        # POST /auth/login, /register, /refresh
│   │   │       ├── profile.py     # GET/PUT/DELETE /profile
│   │   │       └── documents.py   # Upload, process, validate, export
│   │   └── services/
│   │       ├── ai/
│   │       │   ├── provider.py    # FreeTheAI client (fallback chain)
│   │       │   ├── field_mapper.py # Semantic field classification
│   │       │   └── form_filler.py # Auto-fill + validation
│   │       ├── document/
│   │       │   ├── parser.py      # PDF/DOCX text+field extraction
│   │       │   └── exporter.py    # Generate filled output
│   │       ├── ocr/
│   │       │   └── ocr_service.py # Tesseract OCR pipeline
│   │       └── profile/
│   │           └── profile_service.py # Encrypted profile CRUD
│   ├── alembic/                   # Database migrations
│   ├── requirements.txt           # Python dependencies
│   └── .env.example               # Environment template
├── frontend/
│   ├── pubspec.yaml               # Flutter dependencies (8 packages)
│   ├── analysis_options.yaml      # Linter config (relaxed for builds)
│   ├── lib/
│   │   ├── main.dart              # App entry point
│   │   ├── core/
│   │   │   ├── config/
│   │   │   │   ├── app_config.dart    # API URL, file limits
│   │   │   │   └── router.dart        # GoRouter (7 routes)
│   │   │   ├── constants/
│   │   │   │   └── app_constants.dart # Endpoints, storage keys
│   │   │   ├── network/
│   │   │   │   └── api_client.dart    # Dio + auth interceptor
│   │   │   └── theme/
│   │   │       └── app_theme.dart     # Premium Material 3 theme
│   │   └── features/
│   │       ├── auth/presentation/
│   │       │   ├── login_screen.dart      # Gradient login
│   │       │   └── register_screen.dart   # Registration
│   │       ├── home/presentation/
│   │       │   └── home_screen.dart       # Dashboard + doc list
│   │       ├── upload/presentation/
│   │       │   └── upload_screen.dart     # File picker + upload
│   │       ├── document/presentation/
│   │       │   └── document_screen.dart   # Doc detail + AI analyze
│   │       ├── editor/
│   │       │   ├── models/
│   │       │   │   └── annotation.dart    # PdfAnnotation model
│   │       │   ├── presentation/
│   │       │   │   └── editor_screen.dart # Pro PDF editor
│   │       │   └── widgets/
│   │       │       ├── drawing_canvas.dart # Freehand drawing
│   │       │       ├── signature_pad.dart  # Signature capture
│   │       │       └── toolbar.dart        # Editor toolbar
│   │       └── profile/presentation/
│   │           └── profile_screen.dart    # Profile form
│   └── android/
│       ├── app/
│       │   ├── build.gradle           # AGP config (SDK 24-34)
│       │   └── src/main/
│       │       ├── AndroidManifest.xml # Permissions + config
│       │       ├── kotlin/.../MainActivity.kt
│       │       └── res/values/styles.xml
│       ├── build.gradle               # Root Gradle
│       ├── settings.gradle            # Plugin management
│       ├── gradle.properties          # JVM + AndroidX
│       └── gradle/wrapper/
│           └── gradle-wrapper.properties # Gradle 8.3
├── docker/
│   └── Dockerfile.backend             # Python 3.11 + Tesseract
├── docker-compose.yml                 # PostgreSQL + Redis + Backend
├── BUILD_APK.md                       # APK build instructions
├── README.md                          # Project overview
└── docs/
    ├── ARCHITECTURE.md                # System design
    └── SETUP.md                       # Dev environment setup
```

---

## AI Integration

### Provider: FreeTheAI

- **Base URL**: `https://api.freetheai.xyz/v1`
- **Compatibility**: OpenAI API format (`/chat/completions`)
- **Free**: Join Discord, run `/signup`, get API key
- **Models available**: 80+ (GPT-4o, Claude, Qwen, Gemma, etc.)

### Model Strategy

| Task | Model | Why |
|------|-------|-----|
| Quick operations | `gpt-4o-mini` | Fast, cheap, good enough |
| Document analysis | `gpt-4o` | Complex understanding |
| Fallback chain | mini → 4o → claude → gemini | Auto-retry on failure |

### AI Pipeline (14 steps)

```
1. Upload document
2. Detect type (PDF/DOCX/Image)
3. Detect language
4. Determine if OCR needed
5. Extract text, tables, fields
6. Generate structured schema
7. Detect all form fields
8. AI classifies field meanings (semantic)
9. Map fields to user profile
10. Auto-fill known values
11. Ask user only missing required info
12. AI validates completed form
13. Generate filled document
14. Export PDF or DOCX
```

### Semantic Understanding

The AI understands that these all mean the same thing:
- Last Name, Surname, Family Name, Nachname (DE), Apellido (ES), Nom (FR)

This is done via AI classification, NOT keyword matching.

---

## Frontend Screens

| Route | Screen | Features |
|-------|--------|----------|
| `/login` | Login | Gradient background, floating card, validation |
| `/register` | Register | Name/email/password, auto-login after |
| `/home` | Dashboard | Hero banner, quick actions, document list |
| `/upload` | Upload | File picker, progress bar, size validation |
| `/document/:id` | Document Detail | Status, AI analysis, field list, export |
| `/editor/:id` | Pro PDF Editor | Full annotation toolkit (see below) |
| `/profile` | Profile | 12 encrypted fields, auto-fill source |

### Pro Editor Tools

| Tool | Icon | Function |
|------|------|----------|
| Select | pan_tool_alt | Select/move annotations |
| Text | text_fields | Add text at tap position |
| Highlight | highlight | Yellow highlight overlay |
| Draw | draw | Freehand drawing (7 colors) |
| Eraser | auto_fix_high | Erase drawings |
| Sign | gesture | Full-screen signature pad |
| Stamp | approval | 10 stamps (APPROVED, REJECTED, etc.) |
| Shapes | crop_square | Rectangle shapes |
| Undo | undo | Undo last action |
| Redo | redo | Redo undone action |

---

## Backend API Endpoints

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| POST | `/api/v1/auth/register` | No | Create account |
| POST | `/api/v1/auth/login` | No | Get JWT tokens |
| POST | `/api/v1/auth/refresh` | No | Refresh access token |
| GET | `/api/v1/auth/me` | Yes | Current user info |
| GET | `/api/v1/profile` | Yes | Get profile (decrypted) |
| PUT | `/api/v1/profile` | Yes | Update profile (encrypts) |
| DELETE | `/api/v1/profile` | Yes | Delete profile (GDPR) |
| POST | `/api/v1/documents/upload` | Yes | Upload PDF/DOCX/image |
| GET | `/api/v1/documents` | Yes | List user's documents |
| GET | `/api/v1/documents/:id` | Yes | Get document + fields |
| POST | `/api/v1/documents/:id/analyze` | Yes | Run AI pipeline |
| PUT | `/api/v1/documents/:id/fields` | Yes | Update field values |
| POST | `/api/v1/documents/:id/validate` | Yes | AI validation |
| POST | `/api/v1/documents/:id/export` | Yes | Export filled document |
| POST | `/api/v1/documents/:id/annotations` | Yes | Save editor annotations |
| DELETE | `/api/v1/documents/:id` | Yes | Delete document |

---

## Security Model

```
┌─────────────────────────────────────────────┐
│ Client (Flutter App)                         │
│ - Stores JWT in flutter_secure_storage       │
│ - Auto-refreshes expired tokens              │
│ - Never stores passwords                     │
└──────────────────────┬──────────────────────┘
                       │ HTTPS + Bearer Token
┌──────────────────────┴──────────────────────┐
│ Backend (FastAPI)                             │
│ - JWT verification on every request          │
│ - Passwords: bcrypt hash (never stored raw)  │
│ - Profile data: Fernet AES-128 encryption    │
│ - Input validation: Pydantic schemas         │
│ - SQL injection: prevented by ORM            │
│ - CORS: configurable origins                 │
└─────────────────────────────────────────────┘
```

---

## Build & Deployment

### Android APK (GitHub Actions)

Triggers automatically on push to `main`:

```yaml
Steps:
1. Checkout code
2. Setup Java 17 (Temurin)
3. Setup Flutter 3.22.3 (stable)
4. flutter create (generates local.properties + gradle wrapper)
5. Restore custom files from git
6. flutter pub get
7. flutter analyze (non-blocking)
8. flutter build apk --release
9. Upload artifact: AI-PDF-Release
```

### Backend (Docker)

```bash
docker-compose up -d
# Starts: PostgreSQL 16 + Redis 7 + Backend (port 8000)
```

### Local Development

```bash
# Backend
cd backend && pip install -r requirements.txt
uvicorn app.main:app --reload --port 8000

# Frontend
cd frontend && flutter pub get && flutter run
```

---

## Design System

### Color Palette

| Name | Hex | Usage |
|------|-----|-------|
| Primary Dark | #1E3A5F | Deep backgrounds |
| Primary | #2E5BBA | Buttons, links |
| Primary Light | #5B8DEF | Dark mode primary |
| Accent | #FF6B4A | FAB, highlights |
| Success | #10B981 | Completed states |
| Warning | #F59E0B | Attention states |
| Error | #EF4444 | Error states |
| BG Light | #F8FAFC | Light mode background |
| BG Dark | #0F172A | Dark mode background |

### Gradients

- **Hero**: #1E3A5F → #2E5BBA → #7C3AED (login background)
- **Primary**: #2E5BBA → #7C3AED (buttons, banners)
- **Accent**: #FF6B4A → #FF9472 (highlights)

### Design Tokens

- Border radius: 14px (inputs), 16px (cards), 24px (modals)
- Elevation: 0 (cards use borders instead)
- Font weights: 700 (titles), 600 (buttons), 400 (body)
- Spacing: 8px grid system

---

## Key Decisions

| Decision | Rationale |
|----------|-----------|
| Riverpod over BLoC | Less boilerplate, better testability |
| GoRouter over Navigator 2.0 | Declarative, deep linking support |
| Dio over http package | Interceptors, form data, progress |
| Fernet over AES-GCM | Simpler API, sufficient for profile data |
| PyMuPDF over pdfplumber | Faster, better form field support |
| FreeTheAI over OpenAI direct | Free, same API, 80+ models |
| No code generation (freezed) | Simpler builds, fewer CI failures |
| No ProGuard/R8 shrink | Prevents production crashes from minification |
| Flutter 3.22.3 pinned | Known stable, avoids breaking changes |
| AGP 8.1.0 + Gradle 8.3 | Verified compatible combination |

---

## File Count & Lines

- **Frontend Dart files**: 17
- **Backend Python files**: 20+
- **Total project files**: 63+
- **Total lines of code**: ~4000+

---

## How to Continue Development

### Adding a new screen:
1. Create `lib/features/<name>/presentation/<name>_screen.dart`
2. Add route in `lib/core/config/router.dart`
3. Import and use `apiClientProvider` for API calls

### Adding a new API endpoint:
1. Create schema in `backend/app/schemas/`
2. Create route in `backend/app/api/v1/`
3. Register in `backend/app/api/v1/router.py`

### Adding a new AI capability:
1. Add prompt in `backend/app/services/ai/`
2. Call `ai_provider.chat_completion_json()` for structured output
3. Use `use_advanced=True` for complex tasks

---

## Status

- [x] Authentication (JWT + refresh)
- [x] User profiles (50+ encrypted fields)
- [x] Document upload (PDF, DOCX, images)
- [x] AI document analysis
- [x] Form field detection
- [x] Semantic field mapping
- [x] Auto-fill from profile
- [x] Pro PDF editor (8 tools)
- [x] Signature capture
- [x] Stamps (10 types)
- [x] Freehand drawing
- [x] Undo/Redo
- [x] Export PDF/DOCX
- [x] OCR pipeline
- [x] Docker deployment
- [x] GitHub Actions CI/CD
- [x] Premium UI (Material 3, gradients)
- [x] Dark mode
- [ ] Offline mode (local SQLite cache)
- [ ] Batch processing
- [ ] Push notifications
- [ ] Play Store release
