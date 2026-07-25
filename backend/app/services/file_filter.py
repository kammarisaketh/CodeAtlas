from pathlib import PurePosixPath


IGNORED_DIRECTORIES = {
    ".git",
    ".build",
    ".next",
    "build",
    "dist",
    "node_modules",
    "Pods",
    "DerivedData",
    "vendor",
    "__pycache__",
}

IGNORED_FILENAMES = {
    ".env",
    ".env.local",
    "package-lock.json",
    "yarn.lock",
    "pnpm-lock.yaml",
}

SUPPORTED_EXTENSIONS = {
    ".swift",
    ".js",
    ".jsx",
    ".ts",
    ".tsx",
    ".py",
    ".java",
    ".kt",
    ".go",
    ".c",
    ".cpp",
    ".h",
    ".hpp",
    ".md",
    ".json",
    ".yaml",
    ".yml",
}


def should_index_path(path: str) -> bool:
    parsed = PurePosixPath(path)
    if any(part in IGNORED_DIRECTORIES for part in parsed.parts):
        return False
    if parsed.name in IGNORED_FILENAMES:
        return False
    return parsed.suffix in SUPPORTED_EXTENSIONS

