"""Presence WebSocket + fan-out (Technical §4.3 / V2-VT-013).

Statuses stored as smallint: 0 offline, 1 available, 2 busy, 3 dnd.
Fan-out payload: ``{pk, status, talking?, since}``. Nearby is client-side.
Fan-out goes to contacts and co-members. A periodic sweep (≤60 s) marks
silent identities Offline. Redis pub/sub carries fan-out across processes.
"""

from __future__ import annotations

import asyncio
import json
import threading
from collections import defaultdict
from datetime import datetime, timezone
from typing import Any, Callable

from sqlalchemy.orm import Session
from starlette.websockets import WebSocket

from app.encoding import b64url_encode, parse_pubkey
from app.orm import Contact, GroupMember, Identity

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
    """Local sockets plus Redis pub/sub so a second process receives fan-out."""

    CHANNEL = "keryx.presence"

    def __init__(self, redis_client: object | None = None) -> None:
        super().__init__()
        self._r = redis_client
        self._stop = threading.Event()
        self._thread: threading.Thread | None = None

    def publish_bus(self, dest: bytes, message: dict[str, Any]) -> None:
        if self._r is None:
            return
        payload = {
            "dest": b64url_encode(dest),
            "payload": message,
        }
        self._r.publish(self.CHANNEL, json.dumps(payload, separators=(",", ":")))  # type: ignore[attr-defined]

    def handle_bus_message(self, raw: str | bytes | dict[str, Any]) -> None:
        """Deliver a bus payload to a local socket without re-publishing."""
        try:
            if isinstance(raw, dict):
                data = raw
            else:
                text = raw.decode("utf-8") if isinstance(raw, (bytes, bytearray)) else str(raw)
                data = json.loads(text)
            dest = parse_pubkey(str(data["dest"]))
            payload = data["payload"]
        except Exception:
            return
        try:
            loop = asyncio.get_running_loop()
        except RuntimeError:
            MemoryPresenceHub.send_to(self, dest, payload)
            return
        loop.create_task(MemoryPresenceHub.send_to_async(self, dest, payload))

    def start_subscriber(self) -> None:
        if self._r is None or self._thread is not None:
            return
        pubsub = getattr(self._r, "pubsub", None)
        if not callable(pubsub):
            return
        self._stop.clear()

        def _run() -> None:
            ps = pubsub()
            subscribe = getattr(ps, "subscribe", None)
            listen = getattr(ps, "listen", None)
            if not callable(subscribe) or not callable(listen):
                return
            subscribe(self.CHANNEL)
            for item in listen():
                if self._stop.is_set():
                    break
                if not isinstance(item, dict):
                    continue
                if item.get("type") != "message":
                    continue
                data = item.get("data")
                if data is None:
                    continue
                self.handle_bus_message(data)

        self._thread = threading.Thread(target=_run, name="keryx-presence-bus", daemon=True)
        self._thread.start()

    def stop_subscriber(self) -> None:
        self._stop.set()
        self._thread = None


def contact_pks(session: Session, pk: bytes) -> list[bytes]:
    rows = session.query(Contact).filter((Contact.a_pk == pk) | (Contact.b_pk == pk)).all()
    out: list[bytes] = []
    for row in rows:
        out.append(row.b_pk if row.a_pk == pk else row.a_pk)
    return out


def co_member_pks(session: Session, pk: bytes) -> list[bytes]:
    mine = session.query(GroupMember).filter(GroupMember.pk == pk).all()
    seen: set[bytes] = set()
    for mem in mine:
        others = (
            session.query(GroupMember)
            .filter(GroupMember.group_id == mem.group_id, GroupMember.pk != pk)
            .all()
        )
        for other in others:
            seen.add(other.pk)
    return list(seen)


def audience_pks(session: Session, pk: bytes) -> list[bytes]:
    """Contacts ∪ co-members (Technical §4.3 / V2-FR-032)."""
    seen = set(contact_pks(session, pk))
    seen.update(co_member_pks(session, pk))
    return list(seen)


def rotation_payload(group_id: object, key_version: int) -> dict[str, Any]:
    return {"type": "rotation", "group_id": str(group_id), "key_version": int(key_version)}


def alert_payload(from_pk: bytes, now: float) -> dict[str, Any]:
    return {"type": "alert", "from_pk": b64url_encode(from_pk), "since": int(now)}


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
        fanout(ident.pubkey, payload, audience_pks(session, ident.pubkey))
    return len(stale)
