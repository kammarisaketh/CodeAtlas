# Implementation Plan

## Phase 1: Foundation
- Add product and architecture docs.
- Add backend FastAPI skeleton with typed config, database models, routes, Docker Compose, and tests.
- Add iOS module folders, service protocols, API client, Keychain abstraction, session store, and repository dashboard shell.
- Keep the current app compiling.

## Phase 2: Repository Ingestion
- Add GitHub OAuth/App integration.
- Implement repository selection and permission checks.
- Add safe clone/fetch service.
- Implement file filtering, parser abstraction, chunking, metadata persistence.
- Show indexing progress on iOS.

## Phase 3: AI Retrieval
- Add embeddings provider abstraction.
- Implement pgvector search and text search.
- Add RAG prompt assembly with prompt-injection protections.
- Stream answers with citations to iOS.

## Phase 4: Native Experience
- Add source viewer with syntax highlighting and line navigation.
- Add repository map and dependency summary.
- Add saved answers, notes, and search filters.
- Add deep links to repository/file/citation destinations.

## Phase 5: Quality
- Expand XCTest, Pytest, and integration coverage.
- Add accessibility audits.
- Optimize large-file rendering and streaming.
- Add privacy-safe analytics.
- Prepare screenshots, App Store copy, and release checklist.

