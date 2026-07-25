import enum
import uuid
from datetime import datetime

from pgvector.sqlalchemy import Vector
from sqlalchemy import DateTime, Enum, ForeignKey, Integer, String, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base


class RepositoryProvider(str, enum.Enum):
    github = "github"


class IndexingStatus(str, enum.Enum):
    not_indexed = "not_indexed"
    queued = "queued"
    cloning = "cloning"
    parsing = "parsing"
    embedding = "embedding"
    finalizing = "finalizing"
    completed = "completed"
    failed = "failed"


class MessageRole(str, enum.Enum):
    user = "user"
    assistant = "assistant"
    system = "system"


class SavedItemKind(str, enum.Enum):
    answer = "answer"
    file = "file"
    citation = "citation"


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    apple_subject: Mapped[str] = mapped_column(String(255), unique=True, nullable=False)
    email: Mapped[str | None] = mapped_column(String(320))
    display_name: Mapped[str | None] = mapped_column(String(160))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ConnectedAccount(Base):
    __tablename__ = "connected_accounts"
    __table_args__ = (UniqueConstraint("user_id", "provider", name="uq_connected_account_provider"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    provider: Mapped[str] = mapped_column(String(40), nullable=False)
    provider_account_id: Mapped[str] = mapped_column(String(255), nullable=False)
    access_token_ciphertext: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Repository(Base):
    __tablename__ = "repositories"
    __table_args__ = (UniqueConstraint("owner_user_id", "provider", "full_name", name="uq_repository_owner_provider_name"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    owner_user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    provider: Mapped[RepositoryProvider] = mapped_column(Enum(RepositoryProvider), nullable=False)
    full_name: Mapped[str] = mapped_column(String(300), nullable=False)
    default_branch: Mapped[str] = mapped_column(String(160), default="main")
    last_indexed_commit: Mapped[str | None] = mapped_column(String(80))
    languages: Mapped[dict] = mapped_column(JSONB, default=dict)
    indexing_status: Mapped[IndexingStatus] = mapped_column(Enum(IndexingStatus), default=IndexingStatus.not_indexed)
    last_indexed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

    files: Mapped[list["RepositoryFile"]] = relationship(back_populates="repository", cascade="all, delete-orphan")


class RepositoryFile(Base):
    __tablename__ = "repository_files"
    __table_args__ = (UniqueConstraint("repository_id", "path", "commit_sha", name="uq_repository_file_path_commit"),)

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    repository_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("repositories.id", ondelete="CASCADE"))
    path: Mapped[str] = mapped_column(String(1000), nullable=False)
    language: Mapped[str | None] = mapped_column(String(80))
    commit_sha: Mapped[str] = mapped_column(String(80), nullable=False)
    content_hash: Mapped[str] = mapped_column(String(128), nullable=False)
    line_count: Mapped[int] = mapped_column(Integer, default=0)
    content: Mapped[str] = mapped_column(Text, nullable=False)

    repository: Mapped[Repository] = relationship(back_populates="files")


class CodeSymbol(Base):
    __tablename__ = "code_symbols"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    repository_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("repositories.id", ondelete="CASCADE"))
    file_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("repository_files.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(String(300), nullable=False)
    kind: Mapped[str] = mapped_column(String(80), nullable=False)
    start_line: Mapped[int] = mapped_column(Integer, nullable=False)
    end_line: Mapped[int] = mapped_column(Integer, nullable=False)


class CodeChunk(Base):
    __tablename__ = "code_chunks"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    repository_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("repositories.id", ondelete="CASCADE"))
    file_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("repository_files.id", ondelete="CASCADE"))
    symbol_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("code_symbols.id", ondelete="SET NULL"))
    start_line: Mapped[int] = mapped_column(Integer, nullable=False)
    end_line: Mapped[int] = mapped_column(Integer, nullable=False)
    language: Mapped[str | None] = mapped_column(String(80))
    content: Mapped[str] = mapped_column(Text, nullable=False)


class Embedding(Base):
    __tablename__ = "embeddings"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    chunk_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("code_chunks.id", ondelete="CASCADE"), unique=True)
    model: Mapped[str] = mapped_column(String(160), nullable=False)
    embedding: Mapped[list[float]] = mapped_column(Vector(1536), nullable=False)


class IndexingJob(Base):
    __tablename__ = "indexing_jobs"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    repository_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("repositories.id", ondelete="CASCADE"))
    status: Mapped[IndexingStatus] = mapped_column(Enum(IndexingStatus), default=IndexingStatus.queued)
    progress_percent: Mapped[int] = mapped_column(Integer, default=0)
    error_message: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())


class Conversation(Base):
    __tablename__ = "conversations"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    repository_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("repositories.id", ondelete="CASCADE"))
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    title: Mapped[str | None] = mapped_column(String(240))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Message(Base):
    __tablename__ = "messages"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    conversation_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("conversations.id", ondelete="CASCADE"))
    role: Mapped[MessageRole] = mapped_column(Enum(MessageRole), nullable=False)
    content: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class Citation(Base):
    __tablename__ = "citations"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    message_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("messages.id", ondelete="CASCADE"))
    file_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("repository_files.id", ondelete="CASCADE"))
    chunk_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("code_chunks.id", ondelete="SET NULL"))
    path: Mapped[str] = mapped_column(String(1000), nullable=False)
    start_line: Mapped[int] = mapped_column(Integer, nullable=False)
    end_line: Mapped[int] = mapped_column(Integer, nullable=False)
    snippet: Mapped[str | None] = mapped_column(Text)


class SavedItem(Base):
    __tablename__ = "saved_items"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    repository_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("repositories.id", ondelete="CASCADE"))
    kind: Mapped[SavedItemKind] = mapped_column(Enum(SavedItemKind), nullable=False)
    title: Mapped[str] = mapped_column(String(240), nullable=False)
    payload: Mapped[dict] = mapped_column(JSONB, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class UserNote(Base):
    __tablename__ = "user_notes"

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))
    repository_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("repositories.id", ondelete="CASCADE"))
    file_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("repository_files.id", ondelete="SET NULL"))
    message_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("messages.id", ondelete="SET NULL"))
    body: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())

