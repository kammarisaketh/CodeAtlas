"""initial schema

Revision ID: 0001_initial_schema
Revises:
Create Date: 2026-07-23
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from pgvector.sqlalchemy import Vector
from sqlalchemy.dialects import postgresql

revision: str = "0001_initial_schema"
down_revision: str | None = None
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS vector")
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    op.create_table(
        "users",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("apple_subject", sa.String(length=255), nullable=False, unique=True),
        sa.Column("email", sa.String(length=320)),
        sa.Column("display_name", sa.String(length=160)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_table(
        "repositories",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("owner_user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE")),
        sa.Column("provider", sa.String(length=40), nullable=False),
        sa.Column("full_name", sa.String(length=300), nullable=False),
        sa.Column("default_branch", sa.String(length=160), nullable=False),
        sa.Column("last_indexed_commit", sa.String(length=80)),
        sa.Column("languages", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("indexing_status", sa.String(length=40), nullable=False, server_default="not_indexed"),
        sa.Column("last_indexed_at", sa.DateTime(timezone=True)),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("owner_user_id", "provider", "full_name", name="uq_repository_owner_provider_name"),
    )
    op.create_table(
        "repository_files",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("repository_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("repositories.id", ondelete="CASCADE")),
        sa.Column("path", sa.String(length=1000), nullable=False),
        sa.Column("language", sa.String(length=80)),
        sa.Column("commit_sha", sa.String(length=80), nullable=False),
        sa.Column("content_hash", sa.String(length=128), nullable=False),
        sa.Column("line_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("content", sa.Text(), nullable=False),
        sa.UniqueConstraint("repository_id", "path", "commit_sha", name="uq_repository_file_path_commit"),
    )
    op.create_table(
        "code_symbols",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("repository_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("repositories.id", ondelete="CASCADE")),
        sa.Column("file_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("repository_files.id", ondelete="CASCADE")),
        sa.Column("name", sa.String(length=300), nullable=False),
        sa.Column("kind", sa.String(length=80), nullable=False),
        sa.Column("start_line", sa.Integer(), nullable=False),
        sa.Column("end_line", sa.Integer(), nullable=False),
    )
    op.create_table(
        "code_chunks",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("repository_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("repositories.id", ondelete="CASCADE")),
        sa.Column("file_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("repository_files.id", ondelete="CASCADE")),
        sa.Column("symbol_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("code_symbols.id", ondelete="SET NULL")),
        sa.Column("start_line", sa.Integer(), nullable=False),
        sa.Column("end_line", sa.Integer(), nullable=False),
        sa.Column("language", sa.String(length=80)),
        sa.Column("content", sa.Text(), nullable=False),
    )
    op.create_table(
        "embeddings",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("chunk_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("code_chunks.id", ondelete="CASCADE"), unique=True),
        sa.Column("model", sa.String(length=160), nullable=False),
        sa.Column("embedding", Vector(1536), nullable=False),
    )
    op.create_table(
        "indexing_jobs",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("repository_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("repositories.id", ondelete="CASCADE")),
        sa.Column("status", sa.String(length=40), nullable=False, server_default="queued"),
        sa.Column("progress_percent", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("error_message", sa.Text()),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )
    op.create_table(
        "saved_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE")),
        sa.Column("repository_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("repositories.id", ondelete="CASCADE")),
        sa.Column("kind", sa.String(length=40), nullable=False),
        sa.Column("title", sa.String(length=240), nullable=False),
        sa.Column("payload", postgresql.JSONB(), nullable=False, server_default="{}"),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )

    op.create_index("ix_repositories_owner", "repositories", ["owner_user_id"])
    op.create_index("ix_repository_files_path", "repository_files", ["repository_id", "path"])
    op.create_index("ix_code_symbols_name", "code_symbols", ["repository_id", "name"])


def downgrade() -> None:
    op.drop_table("saved_items")
    op.drop_table("indexing_jobs")
    op.drop_table("embeddings")
    op.drop_table("code_chunks")
    op.drop_table("code_symbols")
    op.drop_table("repository_files")
    op.drop_table("repositories")
    op.drop_table("users")

