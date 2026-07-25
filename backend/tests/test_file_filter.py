from app.services.file_filter import should_index_path


def test_indexes_supported_source_files() -> None:
    assert should_index_path("Sources/Auth/AuthService.swift")
    assert should_index_path("backend/app/main.py")
    assert should_index_path("README.md")


def test_ignores_dependency_and_secret_files() -> None:
    assert not should_index_path("node_modules/react/index.js")
    assert not should_index_path(".env")
    assert not should_index_path("dist/app.js")

