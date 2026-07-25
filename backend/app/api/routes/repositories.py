from uuid import UUID

from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse, StreamingResponse

from app.schemas.repositories import (
    ChatRequest,
    CodeReviewSummaryRead,
    GitHubConnectRequest,
    GitHubConnectionRead,
    GitHubOAuthStartRead,
    GitHubRepositoryRead,
    IndexingStatusRead,
    RepositoryCreate,
    RepositoryFileContentRead,
    RepositoryFileRead,
    RepositoryMapResponse,
    RepositoryRead,
    RepositorySearchResponse,
)
from app.services.chat_service import chat_service
from app.services.repository_service import GitHubOAuthError, repository_service

router = APIRouter()


@router.get("", response_model=list[RepositoryRead])
async def list_repositories() -> list[RepositoryRead]:
    return repository_service.list_repositories()


@router.post("", response_model=RepositoryRead, status_code=201)
async def create_repository(request: RepositoryCreate) -> RepositoryRead:
    return repository_service.create_repository(request)


@router.get("/github/connection", response_model=GitHubConnectionRead)
async def get_github_connection() -> GitHubConnectionRead:
    return repository_service.github_connection()


@router.get("/github/oauth/start", response_model=GitHubOAuthStartRead)
async def start_github_oauth() -> GitHubOAuthStartRead:
    return repository_service.begin_github_oauth()


@router.get("/github/oauth/callback", response_class=HTMLResponse)
async def github_oauth_callback(code: str, state: str) -> str:
    try:
        result = repository_service.complete_github_oauth(code=code, state=state)
    except GitHubOAuthError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    return f"""
    <!doctype html>
    <html>
      <head><title>CodeAtlas GitHub Connected</title></head>
      <body style="font-family: -apple-system, BlinkMacSystemFont, sans-serif; padding: 32px;">
        <h1>GitHub connected</h1>
        <p>{result.account_name or "GitHub"} is now connected to CodeAtlas.</p>
        <p>You can close this window and return to the iOS app.</p>
      </body>
    </html>
    """


@router.get("/github/repositories", response_model=list[GitHubRepositoryRead])
async def list_github_repositories() -> list[GitHubRepositoryRead]:
    try:
        return repository_service.list_github_repositories()
    except GitHubOAuthError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error


@router.post("/github/connect", response_model=GitHubConnectionRead)
async def connect_github(request: GitHubConnectRequest) -> GitHubConnectionRead:
    return repository_service.connect_github(request.mock_account_name)


@router.delete("/github/connection", response_model=GitHubConnectionRead)
async def disconnect_github() -> GitHubConnectionRead:
    return repository_service.disconnect_github()


@router.get("/{repository_id}", response_model=RepositoryRead)
async def get_repository(repository_id: UUID) -> RepositoryRead:
    repository = repository_service.get_repository(repository_id)
    if repository is None:
        raise HTTPException(status_code=404, detail="Repository not found")
    return repository


@router.delete("/{repository_id}", status_code=204)
async def delete_repository(repository_id: UUID) -> None:
    if not repository_service.delete_repository(repository_id):
        raise HTTPException(status_code=404, detail="Repository not found")


@router.post("/{repository_id}/index", response_model=IndexingStatusRead)
async def start_indexing(repository_id: UUID) -> IndexingStatusRead:
    status = repository_service.start_indexing(repository_id)
    if status is None:
        raise HTTPException(status_code=404, detail="Repository not found")
    return status


@router.get("/{repository_id}/index-status", response_model=IndexingStatusRead)
async def get_indexing_status(repository_id: UUID) -> IndexingStatusRead:
    status = repository_service.get_indexing_status(repository_id)
    if status is None:
        raise HTTPException(status_code=404, detail="Repository not found")
    return status


@router.get("/{repository_id}/files", response_model=list[RepositoryFileRead])
async def list_files(repository_id: UUID) -> list[RepositoryFileRead]:
    files = repository_service.list_files(repository_id)
    if files is None:
        raise HTTPException(status_code=404, detail="Repository not found")
    return files


@router.get("/{repository_id}/files/{file_id}", response_model=RepositoryFileContentRead)
async def get_file(repository_id: UUID, file_id: UUID) -> RepositoryFileContentRead:
    file = repository_service.get_file(repository_id, file_id)
    if file is None:
        raise HTTPException(status_code=404, detail="File not found")
    return file


@router.get("/{repository_id}/search", response_model=RepositorySearchResponse)
async def search_repository(repository_id: UUID, q: str) -> RepositorySearchResponse:
    response = repository_service.search(repository_id, q)
    if response is None:
        raise HTTPException(status_code=404, detail="Repository not found")
    return response


@router.get("/{repository_id}/map", response_model=RepositoryMapResponse)
async def repository_map(repository_id: UUID) -> RepositoryMapResponse:
    response = repository_service.repository_map(repository_id)
    if response is None:
        raise HTTPException(status_code=404, detail="Repository not found")
    return response


@router.post("/{repository_id}/review", response_model=CodeReviewSummaryRead)
async def review_repository(repository_id: UUID) -> CodeReviewSummaryRead:
    response = repository_service.review_code(repository_id)
    if response is None:
        raise HTTPException(status_code=404, detail="Repository not found")
    return response


@router.post("/{repository_id}/chat")
async def chat(repository_id: UUID, request: ChatRequest) -> StreamingResponse:
    if repository_service.get_repository(repository_id) is None:
        raise HTTPException(status_code=404, detail="Repository not found")
    files = repository_service.list_files(repository_id) or []
    search = repository_service.search(repository_id, request.question)
    return StreamingResponse(
        chat_service.stream_answer(request.question, files=files, search_results=search.results if search else []),
        media_type="text/event-stream",
    )
