"""V2-VT-016 storage budget against disposable Postgres + Alembic."""

from __future__ import annotations

import os
import uuid
from pathlib import Path

import os

os.environ.setdefault("TESTCONTAINERS_RYUK_DISABLED", "true")

import pytest
from sqlalchemy import create_engine, insert, text
from sqlalchemy.orm import Session, sessionmaker

from app.orm import Contact, Group, GroupMember, Identity
from app.presence import STATUS_AVAILABLE, utcfrom

N_USERS = 1000
N_CONTACTS = 20
N_GROUPS = 3


@pytest.fixture(scope="module")
def postgres_url() -> str:
    pytest.importorskip("testcontainers")
    from testcontainers.postgres import PostgresContainer

    image = "postgres:16.10-alpine"
    with PostgresContainer(image) as pg:
        url = pg.get_connection_url()
        # psycopg3
        if url.startswith("postgresql+psycopg2"):
            url = url.replace("postgresql+psycopg2", "postgresql+psycopg", 1)
        elif url.startswith("postgresql://"):
            url = url.replace("postgresql://", "postgresql+psycopg://", 1)
        yield url


def test_alembic_and_storage_budget(postgres_url: str, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", postgres_url)
    from alembic import command
    from alembic.config import Config

    root = Path(__file__).resolve().parents[1]
    cfg = Config(str(root / "alembic.ini"))
    cfg.set_main_option("script_location", str(root / "alembic").replace("\\", "/"))
    command.upgrade(cfg, "head")

    engine = create_engine(postgres_url, future=True)
    factory = sessionmaker(bind=engine, future=True)
    now = utcfrom(1_700_000_000.0)
    session: Session = factory()
    try:
        pks = [bytes((i >> 8, i & 0xFF)) + os.urandom(30) for i in range(N_USERS)]
        session.execute(
            insert(Identity),
            [
                {
                    "pubkey": pk,
                    "callsign": f"U{i:04d}",
                    "created_at": now,
                    "last_seen_at": now,
                    "status": STATUS_AVAILABLE,
                }
                for i, pk in enumerate(pks)
            ],
        )
        seen: set[tuple[bytes, bytes]] = set()
        contact_rows = []
        for i, pk in enumerate(pks):
            for k in range(1, N_CONTACTS + 1):
                other = pks[(i + k) % N_USERS]
                a, b = (pk, other) if pk < other else (other, pk)
                if (a, b) in seen:
                    continue
                seen.add((a, b))
                contact_rows.append({"a_pk": a, "b_pk": b, "created_at": now})
        session.execute(insert(Contact), contact_rows)
        groups = []
        for n in range(N_GROUPS):
            g = Group(
                id=uuid.uuid4(),
                name=f"G{n}",
                created_by=pks[0],
                created_at=now,
                key_version=1,
            )
            session.add(g)
            groups.append(g)
        session.flush()
        sealed = b"\x01" * 48
        member_rows = []
        for g in groups:
            for pk in pks:
                member_rows.append(
                    {
                        "group_id": g.id,
                        "pk": pk,
                        "role": 0,
                        "joined_at": now,
                        "secret_enc": sealed,
                    }
                )
        session.execute(insert(GroupMember), member_rows)
        session.commit()
    finally:
        session.close()

    with engine.connect() as conn:
        def rel(name: str) -> int:
            return int(conn.execute(text("SELECT pg_total_relation_size(:n)")).params(n=name).scalar_one())

        # pg_total_relation_size wants a regclass; pass quoted ident.
        def rel_name(name: str) -> int:
            # Heap + toast, not indexes — V2-NFR-007 is data stored per user.
            return int(
                conn.execute(text(f"SELECT pg_table_size('{name}'::regclass)")).scalar_one()
            )

        ident = rel_name("identities")
        contacts = rel_name("contacts")
        blocks = rel_name("blocks")
        reqs = rel_name("contact_requests")
        members = rel_name("group_members")
        per_user = (ident + contacts + blocks + reqs) / N_USERS
        per_member = members / (N_USERS * N_GROUPS)
        assert per_user < 4096, f"per-user {per_user:.1f} bytes"
        assert per_member < 2048, f"per-membership {per_member:.1f} bytes"
        # No plaintext group secret column exists; secret_enc is opaque.
        cols = conn.execute(
            text(
                "SELECT column_name FROM information_schema.columns "
                "WHERE table_schema='public'"
            )
        ).fetchall()
        names = {r[0] for r in cols}
        assert "secret" not in names
        assert "private_key" not in names
        assert "audio" not in names
