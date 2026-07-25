# CodeAtlas Backend

## Setup
```bash
cd backend
cp .env.example .env
docker compose up --build
```

API docs are available at `http://localhost:8000/docs`.

For local Xcode development without Docker:
```bash
cd "/Users/saketh/Desktop/Code Atlas"
backend/.venv/bin/uvicorn app.main:create_app --factory --reload --app-dir backend
```

## PostgreSQL Mode
The default `CODEATLAS_STORAGE_BACKEND=local` stores development data in JSON so the iOS Simulator is easy to test.

To use PostgreSQL instead:
```bash
cd "/Users/saketh/Desktop/Code Atlas/backend"
cp .env.example .env
```

In `backend/.env`, set:
```bash
CODEATLAS_STORAGE_BACKEND=postgres
CODEATLAS_DATABASE_URL=postgresql+asyncpg://codeatlas:codeatlas@postgres:5432/codeatlas
```

Then start Docker:
```bash
docker compose up --build
```

Docker starts PostgreSQL, runs `alembic upgrade head`, then starts the FastAPI server.

For local non-Docker PostgreSQL, use:
```bash
CODEATLAS_STORAGE_BACKEND=postgres \
CODEATLAS_DATABASE_URL=postgresql+asyncpg://codeatlas:codeatlas@localhost:5432/codeatlas \
backend/.venv/bin/alembic -c backend/alembic.ini upgrade head
```

## GitHub OAuth
Create a GitHub OAuth App in GitHub Developer Settings.

Use this callback URL for local development:
```text
http://127.0.0.1:8000/api/v1/repositories/github/oauth/callback
```

Set these values in `backend/.env`:
```bash
CODEATLAS_GITHUB_CLIENT_ID=your-client-id
CODEATLAS_GITHUB_CLIENT_SECRET=your-client-secret
CODEATLAS_GITHUB_OAUTH_REDIRECT_URL=http://127.0.0.1:8000/api/v1/repositories/github/oauth/callback
```

OAuth endpoints:
- `GET /api/v1/repositories/github/oauth/start`
- `GET /api/v1/repositories/github/oauth/callback`
- `GET /api/v1/repositories/github/repositories`

The backend follows GitHub's OAuth web application flow: generate an authorization URL, validate `state`, exchange the returned `code` at GitHub's token endpoint, then use the token to call the GitHub REST API.

When an OAuth token is connected, repository indexing uses an authenticated clone URL so private repositories that the user can access may be indexed. Git error messages are sanitized so access tokens are not returned to clients.

## Local Tests
```bash
cd backend
python -m venv .venv
source .venv/bin/activate
pip install -e ".[test]"
pytest
```

## Current Production Hardening
- JWT access and refresh tokens are issued separately.
- Refresh tokens are validated before new tokens are issued.
- Every response includes security headers and an `x-request-id`.
- Oversized requests are rejected.
- Basic per-IP rate limiting is enabled.
- Public GitHub repositories can be cloned and indexed with file filtering.
- Indexed source can be searched, explored, viewed, chatted against, and reviewed.
- Local repository state is persisted to `.codeatlas_data/repositories.json` so data survives backend restarts during development.
- PostgreSQL repository/file persistence is available with `CODEATLAS_STORAGE_BACKEND=postgres`.
- GitHub OAuth start/callback and repository listing are implemented when credentials are configured.
- Private GitHub clone is supported during the active backend session after OAuth connection.

To reset local development data:
```bash
rm -rf backend/.codeatlas_data .codeatlas_data
```

## Remaining Production Work
- Expand PostgreSQL persistence to conversations, saved items, notes, indexing jobs, chunks, symbols, and embeddings.
- Move indexing into a Redis-backed background worker.
- Add real Sign in with Apple token verification.
- Store GitHub OAuth tokens with production-grade encryption or a secrets manager instead of active-session memory.
- Add embeddings with pgvector and provider-independent LLM integration.
- Add repository authorization checks to every repository-scoped endpoint.
- Add persistent audit logs that never store secrets or raw private source unnecessarily.
