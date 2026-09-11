"""Presence WebSocket + fan-out (Technical §4.3 / V2-VT-013).

Statuses stored as smallint: 0 offline, 1 available, 2 busy, 3 dnd.
Fan-out payload: ``{pk, status, talking?, since}``. Nearby is client-side.
Co-member fan-out is TASK-085.
"""

from __future__ import annotations

import asyncio
import json
from collections import defaultdict
from datetime import datetime, timezone
from typing import Any, Callable

from sqlalchemy.orm import Session
from starlette.websockets import WebSocket

from app.encoding import b64url_encode
from app.orm import Contact, Identity

STATUS_OFFLINE = 0
STATUS_AVAILABLE = 1
STATUS_BUSY = 2
STATUS_DND = 3

STATUS_FROM_NAME = {
    "offline": STATUS_OFFLINE,
    "available": STATUS_AVAILABLE,
    "busy": STATUS_BUSY,
    "dnd": STATUS_DND,
    "do_not_disturb": STATUS_DND,
}
STATUS_TO_NAME = {
    STATUS_OFFLINE: "offline",
    STATUS_AVAILABLE: "available",
    STATUS_BUSY: "busy",
    STATUS_DND: "dnd",
}

HEARTBEAT_S = 60
OFFLINE_AFTER_S = 300  # 5 minutes


async def _safe_send(ws: WebSocket, message: dict[str, Any]) -> None:
    try:
        await ws.send_json(message)
    except Exception:
        return


def utcfrom(ts: float) -> datetime:
    # Naive UTC so SQLite (no tz) and Postgres timestamp columns compare.
    return datetime.fromtimestamp(ts, tz=timezone.utc).replace(tzinfo=None)


def unix_ts(dt: datetime) -> int:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp())


class PresenceHub:
    def add(self, pk: bytes, ws: WebSocket) -> None:
        raise NotImplementedError

    def remove(self, pk: bytes, ws: WebSocket) -> None:
        raise NotImplementedError

    def send_to(self, pk: bytes, message: dict[str, Any]) -> None:
        raise NotImplementedError

    def connected(self, pk: bytes) -> bool:
        raise NotImplementedError


class MemoryPresenceHub(PresenceHub):
    def __init__(self) -> None:
        self._sockets: dict[bytes, list[WebSocket]] = defaultdict(list)
        self.delivered: list[tuple[bytes, dict[str, Any]]] = []

    def add(self, pk: bytes, ws: WebSocket) -> None:
        self._sockets[pk].append(ws)

    def remove(self, pk: bytes, ws: WebSocket) -> None:
        conns = self._sockets.get(pk) or []
        self._sockets[pk] = [c for c in conns if c is not ws]
        if not self._sockets[pk]:
            self._sockets.pop(pk, None)

    def send_to(self, pk: bytes, message: dict[str, Any]) -> None:
        self.delivered.append((pk, message))
        for ws in list(self._sockets.get(pk) or []):
            try:
                # TestClient is sync; production uvicorn is async. Both accept send_json.
                maybe = ws.send_json(message)
                if hasattr(maybe, "__await__"):
                    # Stash for the ASGI loop via a no-op; callers in async path await below.
                    pass
            except Exception:
                self.remove(pk, ws)

    def connected(self, pk: bytes) -> bool:
        return bool(self._sockets.get(pk))

    async def send_to_async(self, pk: bytes, message: dict[str, Any]) -> None:
        self.delivered.append((pk, message))
        for ws in list(self._sockets.get(pk) or []):
            # Schedule rather than await: TestClient deadlocks if the sender's
            # request waits for the recipient's receive_json.
            asyncio.create_task(_safe_send(ws, message))


class RedisPresenceHub(MemoryPresenceHub):
    """Local sockets plus Redis pub/sub for other processes (TASK-085 multi-replica)."""

    CHANNEL = "keryx.presence"

    def __init__(self, redis_client: object | None = None) -> None:
        super().__init__()
        self._r = redis_client

    def publish_bus(self, message: dict[str, Any]) -> None:
        if self._r is None:
            return
        self._r.publish(self.CHANNEL, json.dumps(message, separators=(",", ":")))  # type: ignore[attr-defined]


def contact_pks(session: Session, pk: bytes) -> list[bytes]:
    rows = session.query(Contact).filter((Contact.a_pk == pk) | (Contact.b_pk == pk)).all()
    out: list[bytes] = []
    for row in rows:
        out.append(row.b_pk if row.a_pk == pk else row.a_pk)
    return out


def presence_payload(
    pk: bytes,
    status: int,
    since: float,
    talking: bool | None = None,
) -> dict[str, Any]:
    body: dict[str, Any] = {
        "pk": b64url_encode(pk),
        "status": STATUS_TO_NAME.get(status, "offline"),
        "since": int(since),
    }
    if talking is not None:
        body["talking"] = talking
    return body


def apply_status(session: Session, pk: bytes, status: int, now: float) -> Identity:
    ident = session.get(Identity, pk)
    if ident is None:
        raise KeyError("unknown")
    ident.status = status
    ident.last_seen_at = utcfrom(now)
    return ident


def touch_last_seen(session: Session, pk: bytes, now: float) -> Identity | None:
    ident = session.get(Identity, pk)
    if ident is None:
        return None
    ident.last_seen_at = utcfrom(now)
    return ident


def mark_stale_offline(
    session: Session,
    now: float,
    fanout: Callable[[bytes, dict[str, Any], list[bytes]], None],
) -> int:
    cutoff = utcfrom(now - OFFLINE_AFTER_S)
    stale = (
        session.query(Identity)
        .filter(Identity.status != STATUS_OFFLINE, Identity.last_seen_at < cutoff)
        .all()
    )
    for ident in stale:
        ident.status = STATUS_OFFLINE
        payload = presence_payload(ident.pubkey, STATUS_OFFLINE, now)
        fanout(ident.pubkey, payload, contact_pks(session, ident.pubkey))
    return len(stale)
