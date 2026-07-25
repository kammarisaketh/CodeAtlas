# API Contract

Base path: `/api/v1`

## Authentication
| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/auth/apple` | Exchange Apple identity token for backend JWTs. |
| `POST` | `/auth/refresh` | Rotate refresh token and return a new access token. |
| `POST` | `/auth/logout` | Revoke the current refresh token. |

## Repositories
| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/repositories` | List repositories visible to the user. |
| `POST` | `/repositories` | Add a GitHub repository. |
| `GET` | `/repositories/{id}` | Get metadata and indexing state. |
| `DELETE` | `/repositories/{id}` | Delete repository and indexed data. |
| `POST` | `/repositories/{id}/index` | Start or restart indexing. |
| `GET` | `/repositories/{id}/index-status` | Get background job progress. |
| `GET` | `/repositories/{id}/files` | List indexed files. |
| `GET` | `/repositories/{id}/files/{file_id}` | Fetch source text and metadata. |
| `GET` | `/repositories/{id}/map` | Return a hierarchical repository map and dependency edges. |

## GitHub
| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/repositories/github/connection` | Read GitHub connection state. |
| `POST` | `/repositories/github/connect` | Connect a mock GitHub account in V2 local mode. |
| `DELETE` | `/repositories/github/connection` | Disconnect GitHub and clear provider state. |

## Chat And Search
| Method | Path | Purpose |
| --- | --- | --- |
| `POST` | `/repositories/{id}/chat` | Stream grounded answer with citations using SSE. |
| `GET` | `/repositories/{id}/search?q={query}` | Hybrid semantic/text/file/symbol search. |

## Saved Knowledge
| Method | Path | Purpose |
| --- | --- | --- |
| `GET` | `/saved-items` | List saved answers/files/bookmarks. |
| `POST` | `/saved-items` | Save an answer, file, or citation. |
| `DELETE` | `/saved-items/{id}` | Delete a saved item. |

## Error Shape
```json
{
  "error": {
    "code": "repository_not_found",
    "message": "Repository not found.",
    "request_id": "req_123"
  }
}
```

## Citation Shape
```json
{
  "file_id": "uuid",
  "path": "Sources/Auth/AuthService.swift",
  "start_line": 42,
  "end_line": 76,
  "snippet": "func refreshSession() async throws { ... }"
}
```
