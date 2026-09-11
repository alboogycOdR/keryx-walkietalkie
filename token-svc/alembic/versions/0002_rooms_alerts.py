"""Room IDs, 1:1 rooms, alert rate-limit table (TASK-085).

Revision ID: 0002_rooms_alerts
Revises: 0001_v2_schema
Create Date: 2026-09-11
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "0002_rooms_alerts"
down_revision: Union[str, None] = "0001_v2_schema"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("groups", sa.Column("room_id", sa.Text(), nullable=True))
    op.create_index("ix_groups_room_id", "groups", ["room_id"], unique=True)
    op.create_table(
        "direct_rooms",
        sa.Column("a_pk", sa.LargeBinary(32), primary_key=True),
        sa.Column("b_pk", sa.LargeBinary(32), primary_key=True),
        sa.Column("room_id", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=False), nullable=False),
        sa.CheckConstraint("a_pk < b_pk", name="direct_rooms_ordered"),
        sa.UniqueConstraint("room_id", name="direct_rooms_room_id_key"),
    )
    op.create_table(
        "alert_sends",
        sa.Column("from_pk", sa.LargeBinary(32), primary_key=True),
        sa.Column("to_pk", sa.LargeBinary(32), primary_key=True),
        sa.Column("sent_at", sa.DateTime(timezone=False), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("alert_sends")
    op.drop_table("direct_rooms")
    op.drop_index("ix_groups_room_id", table_name="groups")
    op.drop_column("groups", "room_id")
