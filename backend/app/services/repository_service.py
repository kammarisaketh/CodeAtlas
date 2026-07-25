from dataclasses import dataclass
from datetime import UTC, datetime
import hashlib
import json
from pathlib import Path
import shutil
import secrets
import subprocess
import tempfile
from urllib.parse import quote, urlencode
from uuid import UUID, uuid4

import httpx

from app.core.config import settings
from app.services.file_filter import should_index_path
from app.schemas.repositories import (
    CodeReviewIssueRead,
    CodeReviewSummaryRead,
    GitHubConnectionRead,
    IndexingStatusRead,
    GitHubOAuthCallbackRead,
    GitHubOAuthStartRead,
    GitHubRepositoryRead,
    RepositoryCreate,
    RepositoryFileContentRead,
    RepositoryFileRead,
    RepositoryMapEdge,
    RepositoryMapNode,
    RepositoryMapResponse,
    RepositoryRead,
    RepositorySearchResponse,
    RepositorySearchResult,
)


MAX_INDEXED_FILES = 180
MAX_FILE_BYTES = 180_000
MAX_TOTAL_BYTES = 5_000_000
GIT_TIMEOUT_SECONDS = 45
DEVELOPMENT_USER_ID = "00000000-0000-0000-0000-000000000001"


@dataclass
class IndexingJobState:
    repository_id: UUID
    started_at: datetime
    error_message: str | None = None


class RepositoryStorageError(RuntimeError):
    pass


class GitHubOAuthError(RuntimeError):
    pass


class RepositoryService:
    def __init__(self) -> None:
        self._repositories: dict[UUID, RepositoryRead] = {}
        self._jobs: dict[UUID, IndexingJobState] = {}
        self._files: dict[UUID, list[RepositoryFileContentRead]] = {}
        self._github_connection = GitHubConnectionRead(connected=False)
        self._github_access_token: str | None = None
        self._oauth_states: dict[str, datetime] = {}
        self._storage_path = Path(settings.local_data_path)
        self._load_state()

    def list_repositories(self) -> list[RepositoryRead]:
        return list(self._repositories.values())

    def create_repository(self, request: RepositoryCreate) -> RepositoryRead:
        repository = RepositoryRead(
            id=uuid4(),
            provider=request.provider,
            full_name=request.full_name,
            default_branch=request.default_branch,
            indexing_status="not_indexed",
            languages={},
            last_indexed_at=None,
        )
        self._repositories[repository.id] = repository
        self._files[repository.id] = self._sample_files(repository.id, request.full_name)
        self._save_state()
        return repository

    def get_repository(self, repository_id: UUID) -> RepositoryRead | None:
        return self._repositories.get(repository_id)

    def delete_repository(self, repository_id: UUID) -> bool:
        self._jobs.pop(repository_id, None)
        self._files.pop(repository_id, None)
        deleted = self._repositories.pop(repository_id, None) is not None
        if deleted:
            self._save_state()
        return deleted

    def start_indexing(self, repository_id: UUID) -> IndexingStatusRead | None:
        repository = self._repositories.get(repository_id)
        if repository is None:
            return None
        self._jobs[repository_id] = IndexingJobState(repository_id=repository_id, started_at=datetime.now(UTC))
        self._repositories[repository_id] = repository.model_copy(update={"indexing_status": "cloning"})

        try:
            files = self._clone_public_github_repository(repository)
        except RepositoryCloneError as error:
            self._jobs.pop(repository_id, None)
            failed = repository.model_copy(update={"indexing_status": "failed"})
            self._repositories[repository_id] = failed
            self._save_state()
            return IndexingStatusRead(
                repository_id=repository_id,
                status="failed",
                progress_percent=0,
                error_message=str(error),
            )

        self._files[repository_id] = files
        completed = repository.model_copy(
            update={
                "indexing_status": "completed",
                "languages": self._language_counts(repository_id),
                "last_indexed_at": datetime.now(UTC),
            }
        )
        self._repositories[repository_id] = completed
        self._jobs.pop(repository_id, None)
        self._save_state()
        return IndexingStatusRead(repository_id=repository_id, status="completed", progress_percent=100)

    def get_indexing_status(self, repository_id: UUID) -> IndexingStatusRead | None:
        repository = self._repositories.get(repository_id)
        if repository is None:
            return None
        job = self._jobs.get(repository_id)
        if job is None:
            return IndexingStatusRead(
                repository_id=repository.id,
                status=repository.indexing_status,
                progress_percent=100 if repository.indexing_status == "completed" else 0,
            )

        elapsed_seconds = (datetime.now(UTC) - job.started_at).total_seconds()
        if elapsed_seconds < 2:
            status, progress = "cloning", 18
        elif elapsed_seconds < 4:
            status, progress = "parsing", 42
        elif elapsed_seconds < 6:
            status, progress = "embedding", 68
        elif elapsed_seconds < 8:
            status, progress = "finalizing", 88
        else:
            status, progress = "completed", 100
            repository = repository.model_copy(
                update={
                    "indexing_status": status,
                    "languages": self._language_counts(repository_id),
                    "last_indexed_at": datetime.now(UTC),
                }
            )
            self._repositories[repository_id] = repository
            self._jobs.pop(repository_id, None)
            self._save_state()
            return IndexingStatusRead(repository_id=repository.id, status=status, progress_percent=progress)

        updated = repository.model_copy(update={"indexing_status": status})
        self._repositories[repository_id] = updated
        return IndexingStatusRead(
            repository_id=repository.id,
            status=status,
            progress_percent=progress,
            error_message=job.error_message,
        )

    def list_files(self, repository_id: UUID) -> list[RepositoryFileRead] | None:
        files = self._files.get(repository_id)
        if files is None:
            return None
        return [
            RepositoryFileRead(id=file.id, path=file.path, language=file.language, line_count=file.line_count)
            for file in files
        ]

    def get_file(self, repository_id: UUID, file_id: UUID) -> RepositoryFileContentRead | None:
        files = self._files.get(repository_id)
        if files is None:
            return None
        return next((file for file in files if file.id == file_id), None)

    def search(self, repository_id: UUID, query: str) -> RepositorySearchResponse | None:
        files = self._files.get(repository_id)
        if files is None:
            return None

        normalized_query = query.strip().lower()
        query_terms = [term for term in normalized_query.split() if len(term) > 1]
        results: list[RepositorySearchResult] = []
        for file in files:
            lines = file.content.splitlines()
            for index, line in enumerate(lines, start=1):
                haystack = f"{file.path} {line}".lower()
                exact_match = normalized_query in haystack
                term_hits = sum(1 for term in query_terms if term in haystack)
                if exact_match or term_hits:
                    score = min(1.0, 0.45 + 0.2 * term_hits + (0.25 if exact_match else 0))
                    results.append(
                        RepositorySearchResult(
                            file_id=file.id,
                            path=file.path,
                            language=file.language,
                            start_line=index,
                            end_line=index,
                            snippet=line.strip() or file.path,
                            match_type="exact" if exact_match else "keyword",
                            score=round(score, 2),
                        )
                    )

        if not results and files:
            file = files[0]
            results.append(
                RepositorySearchResult(
                    file_id=file.id,
                    path=file.path,
                    language=file.language,
                    start_line=1,
                    end_line=min(file.line_count, 8),
                    snippet="\n".join(file.content.splitlines()[:8]),
                    match_type="fallback",
                    score=0.2,
                )
            )

        return RepositorySearchResponse(query=query, results=results[:12])

    def repository_map(self, repository_id: UUID) -> RepositoryMapResponse | None:
        files = self._files.get(repository_id)
        if files is None:
            return None

        root = RepositoryMapNode(id="root", name="Repository", path="", kind="folder", children=[])
        folder_index: dict[str, RepositoryMapNode] = {"": root}
        for file in sorted(files, key=lambda item: item.path):
            parts = file.path.split("/")
            current_path = ""
            parent = root
            for part in parts[:-1]:
                current_path = f"{current_path}/{part}".strip("/")
                node = folder_index.get(current_path)
                if node is None:
                    node = RepositoryMapNode(
                        id=current_path,
                        name=part,
                        path=current_path,
                        kind="folder",
                        children=[],
                    )
                    parent.children.append(node)
                    folder_index[current_path] = node
                parent = node
            parent.children.append(
                RepositoryMapNode(
                    id=str(file.id),
                    name=parts[-1],
                    path=file.path,
                    kind="file",
                    language=file.language,
                    children=[],
                )
            )

        file_paths = [file.path for file in files]
        edges = [
            RepositoryMapEdge(
                source_path=file_paths[index],
                target_path=file_paths[index + 1],
                relationship="imports-or-documents",
            )
            for index in range(max(0, len(file_paths) - 1))
        ]
        return RepositoryMapResponse(
            repository_id=repository_id,
            root=root,
            important_modules=sorted({path.split("/")[0] for path in file_paths if "/" in path}),
            entry_points=[path for path in file_paths if path.endswith(("App.swift", "main.py", "README.md"))],
            edges=edges,
        )

    def review_code(self, repository_id: UUID) -> CodeReviewSummaryRead | None:
        repository = self._repositories.get(repository_id)
        files = self._files.get(repository_id)
        if repository is None or files is None:
            return None

        issues: list[CodeReviewIssueRead] = []
        source_files = [file for file in files if file.language not in {None, "Markdown", "JSON", "YAML"}]
        test_files = [file for file in files if self._looks_like_test_file(file.path)]

        for file in source_files:
            issues.extend(self._review_file(file))

        if source_files and not test_files:
            first_file = source_files[0]
            issues.append(
                CodeReviewIssueRead(
                    severity="warning",
                    title="No test files found in indexed source",
                    detail=(
                        "The indexed repository does not include obvious unit or UI test files. "
                        "A senior reviewer would treat changes here as higher risk until automated coverage exists."
                    ),
                    file_path=first_file.path,
                    line_range="1-1",
                    category="Testing",
                    snippet=None,
                )
            )

        if not issues and source_files:
            first_file = source_files[0]
            issues.append(
                CodeReviewIssueRead(
                    severity="info",
                    title="No high-risk patterns found by deterministic scan",
                    detail=(
                        "The indexed files did not match the current security, reliability, or maintainability rules. "
                        "This is not a full proof of correctness; it means the first-pass static review found no obvious issue."
                    ),
                    file_path=first_file.path,
                    line_range="1-1",
                    category="Review",
                    snippet="\n".join(first_file.content.splitlines()[:6]),
                )
            )

        critical_count = sum(1 for issue in issues if issue.severity == "critical")
        warning_count = sum(1 for issue in issues if issue.severity == "warning")
        info_count = sum(1 for issue in issues if issue.severity == "info")
        score = max(35, 100 - critical_count * 18 - warning_count * 8 - info_count * 2)
        primary_file = self._primary_review_file(source_files, issues)
        analyzed_lines = sum(file.line_count for file in source_files)

        return CodeReviewSummaryRead(
            repository_id=repository_id,
            repository_name=repository.full_name,
            score=score,
            analyzed_files=len(source_files),
            analyzed_lines=analyzed_lines,
            primary_file_path=primary_file.path if primary_file else "No source files",
            summary=self._review_summary_text(repository.full_name, len(source_files), critical_count, warning_count),
            snippet="\n".join((primary_file.content if primary_file else "").splitlines()[:12]),
            issues=issues[:18],
        )

    def github_connection(self) -> GitHubConnectionRead:
        return self._github_connection

    def begin_github_oauth(self) -> GitHubOAuthStartRead:
        if not settings.github_client_id or not settings.github_client_secret:
            return GitHubOAuthStartRead(
                configured=False,
                authorization_url=None,
                state=None,
                message="GitHub OAuth is not configured. Add CODEATLAS_GITHUB_CLIENT_ID and CODEATLAS_GITHUB_CLIENT_SECRET.",
            )

        state = secrets.token_urlsafe(32)
        self._oauth_states[state] = datetime.now(UTC)
        query = urlencode(
            {
                "client_id": settings.github_client_id,
                "redirect_uri": settings.github_oauth_redirect_url,
                "scope": "repo read:user",
                "state": state,
                "allow_signup": "true",
            }
        )
        return GitHubOAuthStartRead(
            configured=True,
            authorization_url=f"https://github.com/login/oauth/authorize?{query}",
            state=state,
            message="Open this URL in a browser to connect GitHub.",
        )

    def complete_github_oauth(self, code: str, state: str) -> GitHubOAuthCallbackRead:
        if not settings.github_client_id or not settings.github_client_secret:
            raise GitHubOAuthError("GitHub OAuth is not configured on the backend.")
        if state not in self._oauth_states:
            raise GitHubOAuthError("Invalid or expired GitHub OAuth state.")
        self._oauth_states.pop(state, None)

        token_response = httpx.post(
            "https://github.com/login/oauth/access_token",
            json={
                "client_id": settings.github_client_id,
                "client_secret": settings.github_client_secret,
                "code": code,
                "redirect_uri": settings.github_oauth_redirect_url,
            },
            headers={"Accept": "application/json"},
            timeout=20,
        )
        token_response.raise_for_status()
        token_payload = token_response.json()
        access_token = token_payload.get("access_token")
        if not isinstance(access_token, str) or not access_token:
            error = token_payload.get("error_description") or token_payload.get("error") or "GitHub did not return an access token."
            raise GitHubOAuthError(str(error))

        user_payload = self._github_get("/user", access_token=access_token)
        account_name = str(user_payload.get("login") or "github-user")
        scope_header = token_response.headers.get("x-oauth-scopes", "")
        scopes = [scope.strip() for scope in scope_header.split(",") if scope.strip()] or ["repo", "read:user"]
        self._github_access_token = access_token
        self._github_connection = GitHubConnectionRead(connected=True, account_name=account_name, scopes=scopes)
        self._save_state()
        return GitHubOAuthCallbackRead(
            connected=True,
            account_name=account_name,
            message="GitHub connected. You can return to CodeAtlas.",
        )

    def list_github_repositories(self) -> list[GitHubRepositoryRead]:
        if not self._github_access_token:
            raise GitHubOAuthError("Connect GitHub with OAuth before listing account repositories.")
        payload = self._github_get("/user/repos?per_page=50&sort=updated&type=all")
        if not isinstance(payload, list):
            raise GitHubOAuthError("GitHub returned an invalid repository list.")
        return [
            GitHubRepositoryRead(
                full_name=str(item.get("full_name")),
                private=bool(item.get("private")),
                default_branch=str(item.get("default_branch") or "main"),
                html_url=str(item.get("html_url") or ""),
                description=item.get("description") if isinstance(item.get("description"), str) else None,
            )
            for item in payload
            if item.get("full_name")
        ]

    def connect_github(self, account_name: str) -> GitHubConnectionRead:
        self._github_connection = GitHubConnectionRead(
            connected=True,
            account_name=account_name,
            scopes=["repo:read", "metadata:read", "pull_requests:read"],
        )
        self._save_state()
        return self._github_connection

    def disconnect_github(self) -> GitHubConnectionRead:
        self._github_connection = GitHubConnectionRead(connected=False)
        self._github_access_token = None
        self._save_state()
        return self._github_connection

    def reset_for_tests(self) -> None:
        self._repositories = {}
        self._jobs = {}
        self._files = {}
        self._github_connection = GitHubConnectionRead(connected=False)
        self._github_access_token = None
        self._oauth_states = {}
        if self._storage_path.exists():
            self._storage_path.unlink()

    def _language_counts(self, repository_id: UUID) -> dict[str, int]:
        counts: dict[str, int] = {}
        for file in self._files.get(repository_id, []):
            language = file.language or "Text"
            counts[language] = counts.get(language, 0) + 1
        return counts

    def _clone_public_github_repository(self, repository: RepositoryRead) -> list[RepositoryFileContentRead]:
        if repository.provider != "github" or not self._is_safe_full_name(repository.full_name):
            raise RepositoryCloneError("Only GitHub repositories in owner/repository format are supported.")

        clone_url = self._clone_url_for_repository(repository.full_name)
        temp_root = Path(tempfile.mkdtemp(prefix="codeatlas-repo-"))
        clone_path = temp_root / "source"
        try:
            command = [
                "git",
                "clone",
                "--depth",
                "1",
                "--single-branch",
                "--branch",
                repository.default_branch,
                clone_url,
                str(clone_path),
            ]
            result = subprocess.run(
                command,
                check=False,
                capture_output=True,
                text=True,
                timeout=GIT_TIMEOUT_SECONDS,
            )
            if result.returncode != 0:
                fallback_command = [
                    "git",
                    "clone",
                    "--depth",
                    "1",
                    clone_url,
                    str(clone_path),
                ]
                result = subprocess.run(
                    fallback_command,
                    check=False,
                    capture_output=True,
                    text=True,
                    timeout=GIT_TIMEOUT_SECONDS,
                )
            if result.returncode != 0:
                message = result.stderr.strip() or "Git clone failed."
                raise RepositoryCloneError(self._safe_git_error(message))

            return self._read_indexable_files(clone_path)
        except subprocess.TimeoutExpired as error:
            raise RepositoryCloneError("GitHub clone timed out. Try a smaller public repository.") from error
        finally:
            shutil.rmtree(temp_root, ignore_errors=True)

    def _clone_url_for_repository(self, full_name: str) -> str:
        if self._github_access_token:
            token = quote(self._github_access_token, safe="")
            return f"https://x-access-token:{token}@github.com/{full_name}.git"
        return f"https://github.com/{full_name}.git"

    def _read_indexable_files(self, clone_path: Path) -> list[RepositoryFileContentRead]:
        indexed_files: list[RepositoryFileContentRead] = []
        total_bytes = 0
        for path in sorted(clone_path.rglob("*")):
            if len(indexed_files) >= MAX_INDEXED_FILES or total_bytes >= MAX_TOTAL_BYTES:
                break
            if not path.is_file():
                continue
            relative_path = path.relative_to(clone_path).as_posix()
            if not should_index_path(relative_path):
                continue
            file_size = path.stat().st_size
            if file_size > MAX_FILE_BYTES:
                continue
            try:
                content = path.read_text(encoding="utf-8")
            except UnicodeDecodeError:
                continue

            total_bytes += file_size
            indexed_files.append(
                RepositoryFileContentRead(
                    id=uuid4(),
                    path=relative_path,
                    language=self._language_for_path(relative_path),
                    line_count=max(1, content.count("\n") + 1),
                    content=content,
                )
            )
        return indexed_files

    def _language_for_path(self, path: str) -> str | None:
        suffix = Path(path).suffix.lower()
        return {
            ".swift": "Swift",
            ".js": "JavaScript",
            ".jsx": "JavaScript",
            ".ts": "TypeScript",
            ".tsx": "TypeScript",
            ".py": "Python",
            ".java": "Java",
            ".kt": "Kotlin",
            ".go": "Go",
            ".c": "C",
            ".cpp": "C++",
            ".h": "C/C++ Header",
            ".hpp": "C++ Header",
            ".md": "Markdown",
            ".json": "JSON",
            ".yaml": "YAML",
            ".yml": "YAML",
        }.get(suffix)

    def _is_safe_full_name(self, full_name: str) -> bool:
        parts = full_name.split("/")
        allowed = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return len(parts) == 2 and all(part and set(part) <= allowed for part in parts)

    def _safe_git_error(self, message: str) -> str:
        first_line = message.splitlines()[0] if message else "Git clone failed."
        if self._github_access_token:
            first_line = first_line.replace(self._github_access_token, "[redacted]")
        if "not found" in first_line.lower() or "repository" in first_line.lower():
            return "Could not clone this GitHub repository. Check that it exists and that the connected GitHub account has access."
        return first_line[:180]

    def _github_get(self, path: str, access_token: str | None = None) -> object:
        token = access_token or self._github_access_token
        if not token:
            raise GitHubOAuthError("GitHub is not connected.")
        response = httpx.get(
            f"https://api.github.com{path}",
            headers={
                "Accept": "application/vnd.github+json",
                "Authorization": f"Bearer {token}",
                "X-GitHub-Api-Version": "2022-11-28",
            },
            timeout=20,
        )
        response.raise_for_status()
        return response.json()

    def _load_state(self) -> None:
        if settings.storage_backend == "postgres":
            self._load_postgres_state()
            return
        if not self._storage_path.exists():
            return
        try:
            payload = json.loads(self._storage_path.read_text(encoding="utf-8"))
            repositories = [
                RepositoryRead.model_validate(item)
                for item in payload.get("repositories", [])
            ]
            files_by_repository: dict[UUID, list[RepositoryFileContentRead]] = {}
            for repository_id, files in payload.get("files", {}).items():
                files_by_repository[UUID(repository_id)] = [
                    RepositoryFileContentRead.model_validate(item)
                    for item in files
                ]

            self._repositories = {repository.id: repository for repository in repositories}
            self._files = {
                repository_id: files_by_repository.get(repository_id, [])
                for repository_id in self._repositories
            }
            self._github_connection = GitHubConnectionRead.model_validate(
                payload.get("github_connection", {"connected": False})
            )
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            self._repositories = {}
            self._files = {}
            self._github_connection = GitHubConnectionRead(connected=False)

    def _save_state(self) -> None:
        if settings.storage_backend == "postgres":
            self._save_postgres_state()
            return
        self._storage_path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "repositories": [
                repository.model_dump(mode="json")
                for repository in self._repositories.values()
            ],
            "files": {
                str(repository_id): [
                    file.model_dump(mode="json")
                    for file in files
                ]
                for repository_id, files in self._files.items()
            },
            "github_connection": self._github_connection.model_dump(mode="json"),
        }
        temporary_path = self._storage_path.with_suffix(".tmp")
        temporary_path.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
        temporary_path.replace(self._storage_path)

    def _postgres_dsn(self) -> str:
        return settings.database_url.replace("postgresql+asyncpg://", "postgresql://", 1)

    def _load_postgres_state(self) -> None:
        try:
            import psycopg
            from psycopg.rows import dict_row

            with psycopg.connect(self._postgres_dsn(), row_factory=dict_row) as connection:
                self._ensure_development_user(connection)
                repository_rows = connection.execute(
                    """
                    SELECT id, provider, full_name, default_branch, languages, indexing_status, last_indexed_at
                    FROM repositories
                    WHERE owner_user_id = %s
                    ORDER BY created_at DESC
                    """,
                    (DEVELOPMENT_USER_ID,),
                ).fetchall()
                file_rows = connection.execute(
                    """
                    SELECT id, repository_id, path, language, line_count, content
                    FROM repository_files
                    WHERE repository_id = ANY(%s::uuid[])
                    ORDER BY path
                    """,
                    ([str(row["id"]) for row in repository_rows],),
                ).fetchall() if repository_rows else []
        except Exception as error:
            raise RepositoryStorageError("Could not load repository state from PostgreSQL.") from error

        self._repositories = {
            row["id"]: RepositoryRead(
                id=row["id"],
                provider=row["provider"],
                full_name=row["full_name"],
                default_branch=row["default_branch"],
                indexing_status=row["indexing_status"],
                languages=row["languages"] or {},
                last_indexed_at=row["last_indexed_at"],
            )
            for row in repository_rows
        }
        self._files = {repository_id: [] for repository_id in self._repositories}
        for row in file_rows:
            self._files.setdefault(row["repository_id"], []).append(
                RepositoryFileContentRead(
                    id=row["id"],
                    path=row["path"],
                    language=row["language"],
                    line_count=row["line_count"],
                    content=row["content"],
                )
            )

    def _save_postgres_state(self) -> None:
        try:
            import psycopg
            from psycopg.types.json import Jsonb

            with psycopg.connect(self._postgres_dsn()) as connection:
                self._ensure_development_user(connection)
                stored_repository_ids = set(
                    connection.execute(
                        "SELECT id FROM repositories WHERE owner_user_id = %s",
                        (DEVELOPMENT_USER_ID,),
                    ).fetchall()
                )
                current_repository_ids = {(repository_id,) for repository_id in self._repositories}
                deleted_repository_ids = stored_repository_ids - current_repository_ids
                if deleted_repository_ids:
                    connection.execute(
                        "DELETE FROM repositories WHERE id = ANY(%s::uuid[])",
                        ([str(row[0]) for row in deleted_repository_ids],),
                    )

                for repository in self._repositories.values():
                    connection.execute(
                        """
                        INSERT INTO repositories (
                            id, owner_user_id, provider, full_name, default_branch,
                            languages, indexing_status, last_indexed_at
                        )
                        VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                        ON CONFLICT (owner_user_id, provider, full_name)
                        DO UPDATE SET
                            default_branch = EXCLUDED.default_branch,
                            languages = EXCLUDED.languages,
                            indexing_status = EXCLUDED.indexing_status,
                            last_indexed_at = EXCLUDED.last_indexed_at
                        """,
                        (
                            repository.id,
                            DEVELOPMENT_USER_ID,
                            repository.provider,
                            repository.full_name,
                            repository.default_branch,
                            Jsonb(repository.languages),
                            repository.indexing_status,
                            repository.last_indexed_at,
                        ),
                    )
                    connection.execute("DELETE FROM repository_files WHERE repository_id = %s", (repository.id,))
                    for file in self._files.get(repository.id, []):
                        connection.execute(
                            """
                            INSERT INTO repository_files (
                                id, repository_id, path, language, commit_sha,
                                content_hash, line_count, content
                            )
                            VALUES (%s, %s, %s, %s, %s, %s, %s, %s)
                            """,
                            (
                                file.id,
                                repository.id,
                                file.path,
                                file.language,
                                "development",
                                hashlib.sha256(file.content.encode("utf-8")).hexdigest(),
                                file.line_count,
                                file.content,
                            ),
                        )
                connection.commit()
        except Exception as error:
            raise RepositoryStorageError("Could not save repository state to PostgreSQL.") from error

    def _ensure_development_user(self, connection) -> None:  # type: ignore[no-untyped-def]
        connection.execute(
            """
            INSERT INTO users (id, apple_subject, email, display_name)
            VALUES (%s, %s, %s, %s)
            ON CONFLICT (apple_subject) DO NOTHING
            """,
            (
                DEVELOPMENT_USER_ID,
                "development:codeatlas",
                "demo@codeatlas.local",
                "CodeAtlas Demo User",
            ),
        )

    def _review_file(self, file: RepositoryFileContentRead) -> list[CodeReviewIssueRead]:
        issues: list[CodeReviewIssueRead] = []
        lines = file.content.splitlines()

        if file.line_count > 450:
            issues.append(
                self._issue(
                    "warning",
                    "Large source file should be split",
                    "This file is large enough to slow review and increase coupling. Split it around cohesive responsibilities.",
                    file,
                    1,
                    min(file.line_count, 20),
                    "Architecture",
                    "\n".join(lines[:8]),
                )
            )

        for index, line in enumerate(lines, start=1):
            normalized = line.lower()
            stripped = line.strip()
            if self._looks_like_hardcoded_secret(stripped):
                issues.append(
                    self._issue(
                        "critical",
                        "Possible hardcoded secret",
                        "A credential-like value appears in source. Move secrets to secure configuration or Keychain/server-side storage and rotate the exposed value.",
                        file,
                        index,
                        index,
                        "Security",
                        stripped,
                    )
                )
            if "forceunwrap" in normalized or "try!" in stripped or "fatalerror(" in normalized:
                issues.append(
                    self._issue(
                        "warning",
                        "Crash-prone control flow",
                        "This line can terminate the app or process instead of returning a recoverable error. Prefer explicit error handling.",
                        file,
                        index,
                        index,
                        "Reliability",
                        stripped,
                    )
                )
            if "todo" in normalized or "fixme" in normalized:
                issues.append(
                    self._issue(
                        "info",
                        "Unresolved implementation note",
                        "Track this TODO as a concrete task or remove it before shipping so unfinished behavior is not hidden in source.",
                        file,
                        index,
                        index,
                        "Maintainability",
                        stripped,
                    )
                )
            if "print(" in normalized or "console.log(" in normalized:
                issues.append(
                    self._issue(
                        "info",
                        "Debug logging in source",
                        "Debug output can leak user or repository data and adds noise in production. Use structured logging with privacy controls.",
                        file,
                        index,
                        index,
                        "Observability",
                        stripped,
                    )
                )
            if "except:" in normalized or "catch {" in normalized:
                issues.append(
                    self._issue(
                        "warning",
                        "Broad error handling",
                        "This catches too much without proving recovery behavior. Catch specific errors and preserve enough context for diagnostics.",
                        file,
                        index,
                        index,
                        "Reliability",
                        stripped,
                    )
                )
        return issues

    def _issue(
        self,
        severity: str,
        title: str,
        detail: str,
        file: RepositoryFileContentRead,
        start_line: int,
        end_line: int,
        category: str,
        snippet: str | None,
    ) -> CodeReviewIssueRead:
        return CodeReviewIssueRead(
            severity=severity,
            title=title,
            detail=detail,
            file_path=file.path,
            line_range=f"{start_line}-{end_line}",
            category=category,
            snippet=snippet,
        )

    def _looks_like_hardcoded_secret(self, line: str) -> bool:
        lowered = line.lower()
        secret_words = ("api_key", "apikey", "secret", "password", "token", "private_key")
        assignment_markers = ("=", ":", "let ", "var ", "const ")
        return any(word in lowered for word in secret_words) and any(marker in lowered for marker in assignment_markers) and len(line) > 18

    def _looks_like_test_file(self, path: str) -> bool:
        lowered = path.lower()
        return any(marker in lowered for marker in ("test", "tests", "spec", "__tests__"))

    def _primary_review_file(
        self,
        files: list[RepositoryFileContentRead],
        issues: list[CodeReviewIssueRead],
    ) -> RepositoryFileContentRead | None:
        if not files:
            return None
        if issues:
            issue_path = issues[0].file_path
            match = next((file for file in files if file.path == issue_path), None)
            if match is not None:
                return match
        return max(files, key=lambda file: file.line_count)

    def _review_summary_text(self, full_name: str, analyzed_files: int, critical_count: int, warning_count: int) -> str:
        if analyzed_files == 0:
            return f"{full_name} was indexed, but no supported source files were available for review."
        if critical_count:
            return f"CodeAtlas found critical risks in {full_name}. Fix security findings before treating this repository as production-ready."
        if warning_count:
            return f"CodeAtlas reviewed {analyzed_files} source files in {full_name} and found reliability or maintainability issues worth fixing."
        return f"CodeAtlas reviewed {analyzed_files} source files in {full_name} and found no obvious high-risk patterns in this first-pass scan."

    def _sample_files(self, repository_id: UUID, full_name: str) -> list[RepositoryFileContentRead]:
        return [
            RepositoryFileContentRead(
                id=uuid4(),
                path="Sources/App/AuthService.swift",
                language="Swift",
                line_count=34,
                content=(
                    "import Foundation\n\n"
                    "actor AuthService {\n"
                    "    func refreshSession() async throws -> Session {\n"
                    "        // Exchanges refresh token for an access token.\n"
                    "        fatalError(\"Implemented in repository\")\n"
                    "    }\n"
                    "}\n"
                ),
            ),
            RepositoryFileContentRead(
                id=uuid4(),
                path="backend/app/api/routes/auth.py",
                language="Python",
                line_count=28,
                content=(
                    "from fastapi import APIRouter\n\n"
                    "router = APIRouter()\n\n"
                    "@router.post('/auth/apple')\n"
                    "async def apple_auth():\n"
                    "    return {'repository': '" + full_name + "'}\n"
                ),
            ),
            RepositoryFileContentRead(
                id=uuid4(),
                path="README.md",
                language="Markdown",
                line_count=12,
                content="# " + full_name + "\n\nRepository overview and setup notes.\n",
            ),
        ]


repository_service = RepositoryService()


class RepositoryCloneError(Exception):
    pass
