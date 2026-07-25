from fastapi.testclient import TestClient

from app.main import create_app
from app.services.repository_service import RepositoryService, repository_service


client = TestClient(create_app())


def setup_function() -> None:
    repository_service.reset_for_tests()


def test_health() -> None:
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
    assert response.headers["x-content-type-options"] == "nosniff"
    assert response.headers["x-request-id"]


def test_readiness() -> None:
    response = client.get("/health/ready")
    assert response.status_code == 200
    assert response.json()["status"] == "ready"


def test_auth_refresh_validates_token_type() -> None:
    auth_response = client.post("/api/v1/auth/apple", json={"identity_token": "mock-apple-token-12345"})
    assert auth_response.status_code == 200
    tokens = auth_response.json()

    refresh_response = client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["refresh_token"]})
    assert refresh_response.status_code == 200
    assert refresh_response.json()["access_token"]

    invalid_refresh_response = client.post("/api/v1/auth/refresh", json={"refresh_token": tokens["access_token"]})
    assert invalid_refresh_response.status_code == 401


def test_auth_rejects_invalid_apple_identity_token() -> None:
    response = client.post("/api/v1/auth/apple", json={"identity_token": "not-a-real-apple-token"})
    assert response.status_code == 401


def test_repository_lifecycle(monkeypatch) -> None:
    monkeypatch.setattr(
        repository_service,
        "_clone_public_github_repository",
        lambda repository: repository_service._sample_files(repository.id, repository.full_name),
    )
    create_response = client.post(
        "/api/v1/repositories",
        json={"provider": "github", "full_name": "openai/example", "default_branch": "main"},
    )
    assert create_response.status_code == 201
    repository = create_response.json()

    list_response = client.get("/api/v1/repositories")
    assert list_response.status_code == 200
    assert any(item["id"] == repository["id"] for item in list_response.json())

    index_response = client.post(f"/api/v1/repositories/{repository['id']}/index")
    assert index_response.status_code == 200
    assert index_response.json()["status"] == "completed"

    search_response = client.get(f"/api/v1/repositories/{repository['id']}/search", params={"q": "auth"})
    assert search_response.status_code == 200
    assert search_response.json()["results"]

    map_response = client.get(f"/api/v1/repositories/{repository['id']}/map")
    assert map_response.status_code == 200
    assert map_response.json()["root"]["kind"] == "folder"

    review_response = client.post(f"/api/v1/repositories/{repository['id']}/review")
    assert review_response.status_code == 200
    review = review_response.json()
    assert review["repository_name"] == "openai/example"
    assert review["analyzed_files"] > 0
    assert review["issues"]
    assert any(issue["file_path"] == "Sources/App/AuthService.swift" for issue in review["issues"])


def test_repository_state_persists_across_service_instances(monkeypatch) -> None:
    monkeypatch.setattr(
        repository_service,
        "_clone_public_github_repository",
        lambda repository: repository_service._sample_files(repository.id, repository.full_name),
    )
    create_response = client.post(
        "/api/v1/repositories",
        json={"provider": "github", "full_name": "openai/persistent-example", "default_branch": "main"},
    )
    repository = create_response.json()
    index_response = client.post(f"/api/v1/repositories/{repository['id']}/index")
    assert index_response.status_code == 200

    restarted_service = RepositoryService()
    repositories = restarted_service.list_repositories()
    persisted_repository = next(
        item for item in repositories
        if item.full_name == "openai/persistent-example"
    )
    files = restarted_service.list_files(persisted_repository.id)
    assert files is not None


def test_chat_requires_existing_repository() -> None:
    response = client.post(
        "/api/v1/repositories/00000000-0000-0000-0000-000000000000/chat",
        json={"question": "Where is auth implemented?"},
    )
    assert response.status_code == 404


def test_github_connection_lifecycle() -> None:
    initial_response = client.get("/api/v1/repositories/github/connection")
    assert initial_response.status_code == 200
    assert initial_response.json()["connected"] is False

    connect_response = client.post(
        "/api/v1/repositories/github/connect",
        json={"mock_account_name": "codeatlas-test"},
    )
    assert connect_response.status_code == 200
    assert connect_response.json()["connected"] is True
    assert connect_response.json()["account_name"] == "codeatlas-test"

    disconnect_response = client.delete("/api/v1/repositories/github/connection")
    assert disconnect_response.status_code == 200
    assert disconnect_response.json()["connected"] is False


def test_github_oauth_reports_missing_configuration() -> None:
    response = client.get("/api/v1/repositories/github/oauth/start")
    assert response.status_code == 200
    payload = response.json()
    assert payload["configured"] is False
    assert payload["authorization_url"] is None


def test_github_repositories_require_oauth_connection() -> None:
    response = client.get("/api/v1/repositories/github/repositories")
    assert response.status_code == 400
    assert "Connect GitHub" in response.json()["detail"]


def test_authenticated_clone_url_uses_connected_token() -> None:
    repository_service._github_access_token = "gho_test_token"  # noqa: SLF001
    clone_url = repository_service._clone_url_for_repository("openai/private-example")  # noqa: SLF001
    assert clone_url == "https://x-access-token:gho_test_token@github.com/openai/private-example.git"


def test_git_errors_redact_connected_token() -> None:
    repository_service._github_access_token = "gho_sensitive_token"  # noqa: SLF001
    message = repository_service._safe_git_error("fatal: https://x-access-token:gho_sensitive_token@github.com failed")  # noqa: SLF001
    assert "gho_sensitive_token" not in message
    assert "[redacted]" in message
