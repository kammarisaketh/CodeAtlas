# Database Schema

## Extensions
```sql
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
```

## Tables

| Table | Purpose |
| --- | --- |
| `users` | App users authenticated through Apple. |
| `connected_accounts` | External accounts such as GitHub. |
| `repositories` | User-visible repositories and indexing metadata. |
| `repository_files` | Indexed files with path, language, hash, and line count. |
| `code_symbols` | Functions, classes, types, modules, and exported symbols. |
| `code_chunks` | Retrieval units with line ranges and content. |
| `embeddings` | pgvector rows for code chunks. |
| `indexing_jobs` | Background indexing state and progress. |
| `conversations` | Repository-scoped chat sessions. |
| `messages` | User and assistant messages. |
| `citations` | File/line citations attached to assistant messages. |
| `saved_items` | Bookmarks, saved answers, and saved files. |
| `user_notes` | Notes attached to repositories, files, or messages. |

## Core Constraints
- Repository rows are scoped by `owner_user_id`.
- File paths are unique per repository and commit SHA.
- Chunk line ranges must satisfy `start_line <= end_line`.
- Embeddings cascade-delete with chunks.
- Delete repository must delete files, chunks, embeddings, conversations, citations, saved items, and notes for that repository.

## Indexes
- `repositories(owner_user_id, provider, full_name)`
- `repository_files(repository_id, path)`
- `code_symbols(repository_id, name)`
- `code_chunks(repository_id, file_id)`
- `embeddings USING ivfflat (embedding vector_cosine_ops)`
- PostgreSQL full-text index on chunk content for hybrid retrieval.

