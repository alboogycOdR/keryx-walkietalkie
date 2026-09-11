"""SQLAlchemy models for Technical §4.1 plus TASK-085 room_id / 1:1 / alerts."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    Integer,
    LargeBinary,
    SmallInteger,
    Text,
    Uuid,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class Identity(Base):
    __tablename__ = "identities"

    pubkey: Mapped[bytes] = mapped_column(LargeBinary(32), primary_key=True)
    callsign: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), nullable=False)
    last_seen_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), nullable=False)
    status: Mapped[int] = mapped_column(SmallInteger, nullable=False, default=0)


class ContactRequest(Base):
    __tablename__ = "contact_requests"

    from_pk: Mapped[bytes] = mapped_column(LargeBinary(32), primary_key=True)
    to_pk: Mapped[bytes] = mapped_column(LargeBinary(32), primary_key=True)
    sig: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), nullable=False)
    state: Mapped[str] = mapped_column(Text, nullable=False)


class Contact(Base):
    __tablename__ = "contacts"
    __table_args__ = (CheckConstraint("a_pk < b_pk", name="contacts_ordered"),)

    a_pk: Mapped[bytes] = mapped_column(LargeBinary(32), primary_key=True)
    b_pk: Mapped[bytes] = mapped_column(LargeBinary(32), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), nullable=False)


class Block(Base):
    __tablename__ = "blocks"

    blocker_pk: Mapped[bytes] = mapped_column(LargeBinary(32), primary_key=True)
    blocked_pk: Mapped[bytes] = mapped_column(LargeBinary(32), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), nullable=False)


class Group(Base):
    __tablename__ = "groups"

    id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True, default=uuid.uuid4)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    created_by: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), nullable=False)
    key_version: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    room_id: Mapped[str | None] = mapped_column(Text, nullable=True, unique=True)


class GroupMember(Base):
    __tablename__ = "group_members"

    group_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    pk: Mapped[bytes] = mapped_column(LargeBinary(32), primary_key=True)
    role: Mapped[int] = mapped_column(SmallInteger, nullable=False)
    joined_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), nullable=False)
    secret_enc: Mapped[bytes] = mapped_column(LargeBinary, nullable=False)


class Invite(Base):
    __tablename__ = "invites"

    group_id: Mapped[uuid.UUID] = mapped_column(Uuid, primary_key=True)
    token_hash: Mapped[bytes] = mapped_column(LargeBinary, primary_key=True)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), nullable=False)
    created_by: Mapped[bytes] = mapped_column(LargeBinary(32), nullable=False)


class DirectRoom(Base):
    """1:1 room_id stored on demand at first signed /token (TASK-085)."""

    __tablename__ = "direct_rooms"
    __table_args__ = (CheckConstraint("a_pk < b_pk", name="direct_rooms_ordered"),)

    a_pk: Mapped[bytes] = mapped_column(LargeBinary(32), primary_key=True)
    b_pk: Mapped[bytes] = mapped_column(LargeBinary(32), primary_key=True)
    room_id: Mapped[str] = mapped_column(Text, nullable=False, unique=True)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), nullable=False)


class AlertSend(Base):
    __tablename__ = "alert_sends"

    from_pk: Mapped[bytes] = mapped_column(LargeBinary(32), primary_key=True)
    to_pk: Mapped[bytes] = mapped_column(LargeBinary(32), primary_key=True)
    sent_at: Mapped[datetime] = mapped_column(DateTime(timezone=False), nullable=False)
