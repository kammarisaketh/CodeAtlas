# CodeAtlas

CodeAtlas is a native iOS and FastAPI portfolio application for codebase memory, repository navigation, and cited AI answers grounded in indexed source code.

## Repository Layout
- `Code Atlas/`: iOS SwiftUI application.
- `backend/`: FastAPI backend, PostgreSQL schema, Docker Compose, and tests.
- `docs/`: product, architecture, API, security, and roadmap documentation.

## Current Phase
Phase 1 foundation is being implemented. The iOS app builds, and the backend contains route contracts, database models, Docker Compose, and test scaffolding.

## Backend Quick Start
```bash
cd backend
cp .env.example .env
docker compose up --build
```

## iOS
Open `Code Atlas.xcodeproj` in Xcode and build the active scheme.

