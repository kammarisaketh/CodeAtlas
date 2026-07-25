# CodeAtlas Product Requirements

## Summary
CodeAtlas is an AI-powered codebase memory and navigation tool for software engineers. It indexes repository source code, documentation, configuration, and project structure, then answers repository-specific questions with file citations and line ranges.

CodeAtlas is not a general chatbot. Every answer must be grounded in indexed repository content. If the repository does not contain enough evidence, the product must say so clearly.

## Target Users
- Engineers onboarding to unfamiliar repositories.
- Senior engineers reviewing impact before code changes.
- Mobile/backend developers tracing flows across services.
- Teams that need searchable memory over private repositories.

## Core Jobs
- Find where a behavior is implemented.
- Explain architecture and module responsibilities.
- Trace dependencies and change impact.
- Search code semantically and exactly.
- Preserve useful answers, notes, and cited files.

## Non-Goals For Phase 1
- Full production GitHub App installation flow.
- Real embedding generation and LLM calls.
- Multi-provider repository support.
- WidgetKit.
- Offline indexing on device.

## Phase 1 Scope
- Native iOS foundation with module boundaries.
- Secure token storage abstraction.
- API client with typed errors.
- Authentication state model.
- Repository dashboard shell.
- FastAPI backend foundation.
- PostgreSQL/pgvector schema and Docker Compose.
- Mock-compatible API contracts and test skeletons.

## Success Criteria
- iOS app builds cleanly.
- Backend imports and exposes health/version endpoints.
- API contracts are documented.
- Database schema covers repository indexing, retrieval, chat, citations, and saved knowledge.
- Phase 2 can add real GitHub ingestion without changing the iOS app shell.

