from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, Field


class RepositoryCreate(BaseModel):
    provider: str = Field(pattern="^github$")
    full_name: str = Field(min_length=3, max_length=300)
    default_branch: str = "main"


class RepositoryRead(BaseModel):
    id: UUID
    provider: str
    full_name: str
    default_branch: str
    indexing_status: str
    languages: dict[str, int] = {}
    last_indexed_at: datetime | None = None


class IndexingStatusRead(BaseModel):
    repository_id: UUID
    status: str
    progress_percent: int
    error_message: str | None = None


class RepositoryFileRead(BaseModel):
    id: UUID
    path: str
    language: str | None
    line_count: int


class RepositoryFileContentRead(RepositoryFileRead):
    content: str


class ChatRequest(BaseModel):
    question: str = Field(min_length=3, max_length=4000)


class CitationRead(BaseModel):
    file_id: UUID
    path: str
    start_line: int
    end_line: int
    snippet: str | None = None


class RepositorySearchResult(BaseModel):
    file_id: UUID
    path: str
    language: str | None
    start_line: int
    end_line: int
    snippet: str
    match_type: str
    score: float


class RepositorySearchResponse(BaseModel):
    query: str
    results: list[RepositorySearchResult]


class RepositoryMapNode(BaseModel):
    id: str
    name: str
    path: str
    kind: str
    language: str | None = None
    children: list["RepositoryMapNode"] = []


class RepositoryMapEdge(BaseModel):
    source_path: str
    target_path: str
    relationship: str


class RepositoryMapResponse(BaseModel):
    repository_id: UUID
    root: RepositoryMapNode
    important_modules: list[str]
    entry_points: list[str]
    edges: list[RepositoryMapEdge]


class CodeReviewIssueRead(BaseModel):
    severity: str
    title: str
    detail: str
    file_path: str
    line_range: str
    category: str
    snippet: str | None = None


class CodeReviewSummaryRead(BaseModel):
    repository_id: UUID
    repository_name: str
    score: int
    analyzed_files: int
    analyzed_lines: int
    primary_file_path: str
    summary: str
    snippet: str
    issues: list[CodeReviewIssueRead]


class GitHubConnectionRead(BaseModel):
    connected: bool
    account_name: str | None = None
    scopes: list[str] = []


class GitHubConnectRequest(BaseModel):
    mock_account_name: str = Field(default="saketh-codeatlas", min_length=2, max_length=80)


class GitHubOAuthStartRead(BaseModel):
    configured: bool
    authorization_url: str | None = None
    state: str | None = None
    message: str


class GitHubOAuthCallbackRead(BaseModel):
    connected: bool
    account_name: str | None = None
    message: str


class GitHubRepositoryRead(BaseModel):
    full_name: str
    private: bool
    default_branch: str
    html_url: str
    description: str | None = None
