# AI Document Assistant
AI-powered document understanding platform. See docs/ for details.

## Tech Stack
- Backend: FastAPI + FreeTheAI API (https://api.freetheai.xyz/v1)
- Frontend: Flutter + Material 3 + Riverpod
- Database: PostgreSQL
- Docker deployment

## Quick Start
```bash
cp backend/.env.example backend/.env
docker-compose up -d
cd frontend && flutter run
```
