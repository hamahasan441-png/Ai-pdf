# Setup Guide

## Prerequisites

- Python 3.12+
- Flutter 3.16+
- Docker & Docker Compose
- PostgreSQL 16+ (or use Docker)

## Backend Setup

```bash
cd backend

# Create virtual environment
python -m venv .venv
source .venv/bin/activate  # Linux/Mac
# .venv\Scripts\activate   # Windows

# Install dependencies
pip install -r requirements.txt

# Configure environment
cp .env.example .env
# Edit .env with your API keys

# Run database migrations
alembic upgrade head

# Start development server
uvicorn app.main:app --reload --port 8000
```

## Frontend Setup

```bash
cd frontend

# Install dependencies
flutter pub get

# Run the app
flutter run -d chrome  # Web
flutter run            # Mobile
```

## Docker Setup (Recommended)

```bash
# Copy environment file
cp backend/.env.example backend/.env

# Start all services
docker-compose up -d

# Run migrations
docker-compose exec backend alembic upgrade head
```

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| AI_API_BASE_URL | FreeTheAI API base URL | https://api.freetheai.xyz/v1 |
| AI_API_KEY | API key for AI service | - |
| AI_MODEL | AI model to use | gpt-4o-mini |
| DATABASE_URL | PostgreSQL connection string | - |
| JWT_SECRET_KEY | Secret for JWT signing | - |
| ENCRYPTION_KEY | Key for profile encryption | - |
