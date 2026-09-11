"""v2 directory schema (Technical §4.1).

Revision ID: 0001_v2_schema
Revises:
Create Date: 2026-09-11
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0001_v2_schema"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "identities",
        sa.Column("pubkey", sa.LargeBinary(32), primary_key=True),
        sa.Column("callsign", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=False), nullable=False),
        sa.Column("last_seen_at", sa.DateTime(timezone=False), nullable=False),
        sa.Column("status", sa.SmallInteger(), nullable=False),
        sa.UniqueConstraint("callsign", name="identities_callsign_key"),
    )
    op.create_table(
        "contact_requests",
        sa.Column("from_pk", sa.LargeBinary(32), primary_key=True),
        sa.Column("to_pk", sa.LargeBinary(32), primary_key=True),
        sa.Column("sig", sa.LargeBinary(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=False), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=False), nullable=False),
        sa.Column("state", sa.Text(), nullable=False),
    )
    op.create_table(
        "contacts",
        sa.Column("a_pk", sa.LargeBinary(32), primary_key=True),
        sa.Column("b_pk", sa.LargeBinary(32), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=False), nullable=False),
        sa.CheckConstraint("a_pk < b_pk", name="contacts_ordered"),
    )
    op.create_table(
        "blocks",
        sa.Column("blocker_pk", sa.LargeBinary(32), primary_key=True),
        sa.Column("blocked_pk", sa.LargeBinary(32), primary_key=True),
        sa.Column("created_at", sa.DateTime(timezone=False), nullable=False),
    )
    op.create_table(
        "groups",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("created_by", sa.LargeBinary(32), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=False), nullable=False),
        sa.Column("key_version", sa.Integer(), nullable=False),
    )
    op.create_table(
        "group_members",
        sa.Column("group_id", sa.Uuid(), primary_key=True),
        sa.Column("pk", sa.LargeBinary(32), primary_key=True),
        sa.Column("role", sa.SmallInteger(), nullable=False),
        sa.Column("joined_at", sa.DateTime(timezone=False), nullable=False),
        sa.Column("secret_enc", sa.LargeBinary(), nullable=False),
    )
    op.create_table(
        "invites",
        sa.Column("group_id", sa.Uuid(), primary_key=True),
        sa.Column("token_hash", sa.LargeBinary(), primary_key=True),
        sa.Column("expires_at", sa.DateTime(timezone=False), nullable=False),
        sa.Column("created_by", sa.LargeBinary(32), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("invites")
    op.drop_table("group_members")
    op.drop_table("groups")
    op.drop_table("blocks")
    op.drop_table("contacts")
    op.drop_table("contact_requests")
    op.drop_table("identities")
