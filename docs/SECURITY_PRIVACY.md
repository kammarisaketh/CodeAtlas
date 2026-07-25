# Security And Privacy

## Principles
- Repository content is private, sensitive, and untrusted.
- Never log source code, repository tokens, Apple identity tokens, JWTs, or refresh tokens.
- Every repository operation must check user authorization.
- Prompt construction must isolate repository content from system instructions.

## iOS
- Store tokens only in Keychain.
- Clear tokens on logout and session expiration.
- Use TLS for all backend requests.
- Keep local SwiftData content limited to user-selected saved knowledge and non-secret metadata.
- Provide account deletion and repository-data deletion controls.

## Backend
- Hash or encrypt refresh tokens at rest.
- Use least-privilege GitHub scopes.
- Filter secrets and binary/generated/dependency files before indexing.
- Run Git commands with fixed argument arrays, timeouts, and isolated working directories.
- Rate limit auth, chat, search, and indexing endpoints.
- Delete repository data with cascading database deletes and worker cleanup.

## Prompt Injection Defense
- Treat code and documentation as quoted evidence, never instructions.
- Retrieval prompts must say that repository content can be malicious.
- Answers must cite evidence and admit insufficient context.

