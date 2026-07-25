# CodeAtlas System Architecture

## High-Level Flow
1. User signs in with Apple on iOS.
2. iOS exchanges Apple identity token for backend access and refresh tokens.
3. User connects GitHub and selects a repository.
4. Backend verifies repository permission and starts an indexing job.
5. Worker fetches the repository, filters files, parses code, chunks content, generates embeddings, and stores metadata in PostgreSQL with pgvector.
6. User asks a repository question.
7. Backend performs hybrid retrieval, builds a constrained prompt from repository evidence, streams an answer with citations, and persists conversation history.
8. iOS renders Markdown answer, citations, and source navigation.

## iOS Modules
- `App`: App entry point, navigation shell, dependency assembly.
- `Core`: shared domain models, errors, dependency container.
- `Authentication`: Apple sign-in coordination, session state, logout.
- `Networking`: `URLSession` API client, SSE client, request signing.
- `Repositories`: repository dashboard, add repository, indexing progress.
- `Chat`: repository chat, streamed responses, citations.
- `Search`: hybrid search UI and filters.
- `SourceViewer`: syntax-highlighted source display and citation jumps.
- `SavedItems`: bookmarks, notes, saved answers.
- `Settings`: privacy, account, connected accounts, retention.
- `DesignSystem`: colors, spacing, reusable views.

## Backend Modules
- `api/routes`: FastAPI route definitions.
- `auth`: Apple, GitHub, JWT, token refresh.
- `repository_providers`: GitHub now, GitLab/Bitbucket later.
- `indexing`: clone/fetch, filtering, parsing, chunking, progress.
- `parsers`: language-aware parser abstraction.
- `embeddings`: provider-independent embedding interface.
- `retrieval`: hybrid search and citation assembly.
- `llm`: provider-independent answer generation.
- `models`: SQLAlchemy database models.
- `workers`: background indexing jobs.
- `security`: authorization, rate limits, secret filtering.

## Key Decisions
- iOS depends on protocols, not concrete services, so previews/tests can use mocks.
- Backend treats repository content as untrusted input and never logs source content.
- Citations are first-class database rows linked to messages and code chunks.
- Parser and LLM providers are abstractions from Phase 1 to avoid lock-in.
- SSE is preferred for streaming because it works well with `URLSession`.

## Current Portfolio Implementation

The current implementation is built to demonstrate the end-to-end product shape:

- iOS app with Apple login, mock demo mode, account flow, repository dashboard, ask, explore, and review screens.
- FastAPI backend with GitHub OAuth, repository creation, indexing, file browsing, review, and health endpoints.
- Local development persistence for simple demos.
- PostgreSQL and Docker Compose support for the production path.
- Documentation for product requirements, API contracts, security, database schema, and implementation roadmap.

## Production Expansion Path

For a fully deployed SaaS version, the next architecture upgrades are:

- Hosted PostgreSQL with pgvector enabled.
- Durable background jobs for indexing large repositories.
- Real embedding generation and hybrid retrieval.
- Provider-independent LLM orchestration.
- Observability, audit logs, deployment automation, and incident monitoring.
- Stronger authorization boundaries for multi-user repository access.
