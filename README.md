# AI PDF - Smart Document Assistant

AI-powered document understanding, editing, and form filling platform.

## Tech Stack
- **Backend**: FastAPI + OpenRouter API (https://openrouter.ai/api/v1)
- **Frontend**: Flutter + Material 3 + Riverpod
- **AI Models**: Gemini 2.0 Flash (free), Llama 3.2 Vision (free), Gemma 4 (free)
- **Database**: PostgreSQL
- **Deployment**: Docker

## Features
- Upload ANY document (PDF, DOCX, images, scans, photos)
- AI understands content in any language (vision + text)
- Auto-detect and fill form fields (200+ field types, 10+ languages)
- Pro PDF Editor (draw, sign, stamp, highlight, text, shapes)
- Export filled documents as PDF/DOCX
- Encrypted user profiles for instant form filling

## Quick Start
```bash
# 1. Clone
git clone https://github.com/hamahasan441-png/Ai-pdf.git
cd Ai-pdf

# 2. Configure API key (get free key at https://openrouter.ai/keys)
cp backend/.env.example backend/.env
# Edit backend/.env → add your AI_API_KEY

# 3. Run
docker-compose up -d
cd frontend && flutter run
```

## API Key Setup
Get your free key from [OpenRouter](https://openrouter.ai/keys), then:
```bash
echo "AI_API_KEY=your-key-here" >> backend/.env
```

## Free AI Models Used
| Model | Purpose | Cost |
|-------|---------|------|
| google/gemini-2.0-flash-exp:free | Fast text + vision | FREE |
| meta-llama/llama-3.2-11b-vision-instruct:free | Image understanding | FREE |
| google/gemma-4-26b-a4b-it:free | Multimodal | FREE |
| qwen/qwen-2.5-72b-instruct:free | Text analysis | FREE |
| mistralai/mistral-7b-instruct:free | Fallback | FREE |

## Docs
- [DEVELOPMENT.md](DEVELOPMENT.md) - Full technical documentation
- [BUILD_APK.md](BUILD_APK.md) - How to build the Android APK
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) - System architecture
- [docs/SETUP.md](docs/SETUP.md) - Development setup guide
