# AI PDF

An Android app for working with PDFs and images: **offline file tools** plus **on-device AI** that understands documents and fills forms. AI runs directly from your phone through [OpenRouter](https://openrouter.ai) using your own key — no server required.

## Features

### 🛠 Offline tools (work with no internet, nothing uploaded)
- **JPG → PDF** — turn images into a PDF
- **Compress** — shrink images/PDFs on-device
- **Merge / Split** — combine or separate PDFs
- **PDF Editor** — draw, highlight, text (movable, font size, bold, color), line/arrow/box/oval, whiteout/redact, signatures (savable), rotate pages, object select/move/resize/duplicate, undo/redo, high-res export
- **Organize Pages** — add multiple PDFs/images, reorder (drag), rotate, delete, export one clean PDF

### 🤖 AI tools (your OpenRouter key, on-device)
- **Understand** — chat with any PDF/image: summarize, extract dates/names/amounts, ask anything; save answers as PDF
- **Fill Form** — the AI reads a form, asks what it needs, then **places your answers onto the real form** as editable boxes → export a filled PDF
- **Model picker** — free models (Gemma 4, Gemini Flash, DeepSeek…) and premium (GPT-4o, Claude, Gemini Pro) via one key, plus an **Auto** mode that picks the best model per task
- **Online or offline endpoint** — use OpenRouter, or point to a local/LAN OpenAI-compatible server

### Other
- **Recent Files** — everything you create/edit/save, quick to reopen/share
- **Guest mode** — all tools work without login
- Files can always be **saved to device** or **shared**

## Install (Android)

Every push to `main` builds and publishes a signed APK. Download the latest directly:

**`https://github.com/hamahasan441-png/Ai-pdf/releases/latest/download/AI-PDF.apk`**

1. Open that link on your phone and download `AI-PDF.apk`.
2. Open the file; allow "install from unknown sources" if asked.
3. (Optional) Enable AI: open **AI Settings** (key icon on the home bar) → paste your free OpenRouter key from [openrouter.ai/keys](https://openrouter.ai/keys) → **Test**.

## Tech stack

- **Frontend:** Flutter 3.29, Riverpod, GoRouter, Dio
- **Docs/AI on-device:** pdfx (render), pdf (create), image; OpenRouter (OpenAI-compatible) for AI
- **Storage:** flutter_secure_storage (API key, encrypted), shared_preferences, path_provider
- **CI/CD:** GitHub Actions → APK artifact + GitHub Release
- **Backend (optional/legacy):** FastAPI + PostgreSQL for account-based flows; not required for the on-device experience

See [DEVELOPMENT.md](DEVELOPMENT.md) for architecture and contributor docs, and [BUILD_APK.md](BUILD_APK.md) for build details.
