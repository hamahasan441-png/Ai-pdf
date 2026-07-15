# Architecture Overview

## System Architecture

AI Document Assistant is a full-stack application with:

### Backend (Python/FastAPI)
- **API Layer**: FastAPI with versioned routes (`/api/v1/`)
- **Service Layer**: Business logic separated into services
- **Data Layer**: SQLAlchemy async ORM with PostgreSQL
- **AI Integration**: OpenRouter API (OpenAI-compatible, 400+ models)

### Frontend (Flutter)
- **State Management**: Riverpod
- **Routing**: GoRouter
- **Theming**: Material 3
- **Architecture**: Feature-first folder structure

## Data Flow

1. User uploads document via Flutter app
2. Backend stores file, creates DB record
3. AI analysis extracts text, detects form fields
4. Semantic field mapper links fields to profile data
5. AI form filler suggests values
6. User reviews and confirms
7. Document exported with filled values

## Security

- JWT authentication with refresh tokens
- User profile data encrypted at rest (Fernet)
- File upload size limits
- CORS configuration

## Key Design Decisions

- Async everywhere (asyncio, async SQLAlchemy)
- Profile encryption for PII protection
- AI provider abstraction for easy swapping
- Feature-first frontend organization
