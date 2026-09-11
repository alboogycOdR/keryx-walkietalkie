"""FastAPI routes under /v2/ (Technical §4.2)."""

from __future__ import annotations

import base64
from typing import Any

from fastapi import APIRouter, Request, WebSocket, WebSocketDisconnect
from pydantic import BaseModel, Field, ValidationError
from sqlalchemy.orm import Session

from app.directory import (
    accept_request,
    block_request,
    decline_request,
    identity_me,
    patch_callsign,
    register_identity,
    remove_contact,
    send_request,
)
from app.encoding import parse_pubkey, parse_pubkey_param
from app.errors import DirectoryError, INVALID_REQUEST, INVALID_STATUS, UNKNOWN_IDENTITY
from app.presence import (
    STATUS_FROM_NAME,
    unix_ts,
    apply_status,
    contact_pks,
    mark_stale_offline,
    presence_payload,
    touch_last_seen,
)
from app.signing import verify_headers

router = APIRouter(prefix="/v2")


class IdentityBody(BaseModel):
    callsign: str = Field(..., min_length=2, max_length=12)


class RequestBody(BaseModel):
    to_pk: str


class CallsignBody(BaseModel):
    callsign: str = Field(..., min_length=2, max_length=12)


def _session(request: Request) -> Session:
    return request.app.state.session_factory()


def _caller_pk(request: Request, body: bytes) -> bytes:
    return verify_headers(
        {k: v for k, v in request.headers.items()},
        request.method,
        request.url.path,
        body,
        request.app.state.clock(),
        request.app.state.settings.signing_window_s,
        request.app.state.nonce_store,
    )


def _sig_bytes(request: Request) -> bytes:
    raw = request.headers.get("x-keryx-sig") or request.headers.get("X-Keryx-Sig") or ""
    try:
        return base64.b64decode(raw.strip(), validate=True)
    except Exception:
        return b""


async def _read_signed(request: Request) -> tuple[bytes, bytes]:
    body = await request.body()
    return _caller_pk(request, body), body


def _parse(model: type[BaseModel], body: bytes) -> BaseModel:
    try:
        return model.model_validate_json(body or b"{}")
    except ValidationError as exc:
        raise DirectoryError(422, INVALID_REQUEST) from exc


@router.post("/identity")
async def post_identity(request: Request) -> dict[str, Any]:
    pk, body = await _read_signed(request)
    payload = _parse(IdentityBody, body)
    session = _session(request)
    try:
        row = register_identity(session, pk, payload.callsign, request.app.state.clock())  # type: ignore[union-attr]
        session.commit()
        return {"pk": identity_me(session, row.pubkey, request.app.state.clock())["pk"], "callsign": row.callsign}
    finally:
        session.close()


@router.get("/identity/me")
async def get_me(request: Request) -> dict[str, Any]:
    pk, _body = await _read_signed(request)
    session = _session(request)
    try:
        return identity_me(session, pk, request.app.state.clock())
    finally:
        session.close()


@router.patch("/identity/callsign")
async def patch_me_callsign(request: Request) -> dict[str, Any]:
    pk, body = await _read_signed(request)
    payload = _parse(CallsignBody, body)
    session = _session(request)
    try:
        row = patch_callsign(session, pk, payload.callsign)  # type: ignore[union-attr]
        session.commit()
        return {"callsign": row.callsign}
    finally:
        session.close()


@router.post("/contacts/requests")
async def post_contact_request(request: Request) -> dict[str, Any]:
    pk, body = await _read_signed(request)
    payload = _parse(RequestBody, body)
    try:
        to_pk = parse_pubkey(payload.to_pk)  # type: ignore[union-attr]
    except DirectoryError:
        raise DirectoryError(422, INVALID_REQUEST) from None
    session = _session(request)
    try:
        row = send_request(session, pk, to_pk, _sig_bytes(request), request.app.state.clock())
        session.commit()
        return {
            "to_pk": payload.to_pk,
            "expires_at": unix_ts(row.expires_at),
            "state": row.state,
        }
    finally:
        session.close()


@router.post("/contacts/requests/{from_pk}:accept")
async def accept(request: Request, from_pk: str) -> dict[str, str]:
    me, _body = await _read_signed(request)
    other = parse_pubkey_param(from_pk)
    session = _session(request)
    try:
        accept_request(session, me, other, request.app.state.clock())
        session.commit()
        return {"state": "accepted"}
    finally:
        session.close()


@router.post("/contacts/requests/{from_pk}:decline")
async def decline(request: Request, from_pk: str) -> dict[str, str]:
    me, _body = await _read_signed(request)
    other = parse_pubkey_param(from_pk)
    session = _session(request)
    try:
        decline_request(session, me, other, request.app.state.clock())
        session.commit()
        return {"state": "declined"}
    finally:
        session.close()


@router.post("/contacts/requests/{from_pk}:block")
async def block(request: Request, from_pk: str) -> dict[str, str]:
    me, _body = await _read_signed(request)
    other = parse_pubkey_param(from_pk)
    session = _session(request)
    try:
        block_request(session, me, other, request.app.state.clock())
        session.commit()
        return {"state": "blocked"}
    finally:
        session.close()


@router.delete("/contacts/{pk}")
async def delete_contact(request: Request, pk: str) -> dict[str, str]:
    me, _body = await _read_signed(request)
    other = parse_pubkey_param(pk)
    session = _session(request)
    try:
        remove_contact(session, me, other)
        session.commit()
        return {"state": "removed"}
    finally:
        session.close()


@router.websocket("/presence")
async def presence_ws(websocket: WebSocket) -> None:
    app = websocket.app
    now = app.state.clock()
    try:
        pk = verify_headers(
            {k: v for k, v in websocket.headers.items()},
            "GET",
            "/v2/presence",
            b"",
            now,
            app.state.settings.signing_window_s,
            app.state.nonce_store,
        )
    except DirectoryError as exc:
        await websocket.close(code=4401, reason=exc.code)
        return

    session = app.state.session_factory()
    try:
        from app.orm import Identity

        if session.get(Identity, pk) is None:
            await websocket.close(code=4401, reason=UNKNOWN_IDENTITY)
            return
    finally:
        session.close()

    await websocket.accept()
    hub = app.state.presence_hub
    hub.add(pk, websocket)
    try:
        while True:
            message = await websocket.receive_json()
            now = app.state.clock()
            session = app.state.session_factory()
            try:
                pending: list[tuple[bytes, dict[str, Any]]] = []

                def _collect(_src: bytes, payload: dict[str, Any], recips: list[bytes]) -> None:
                    for dest in recips:
                        pending.append((dest, payload))

                mark_stale_offline(session, now, _collect)
                if message.get("type") == "heartbeat" or message.get("heartbeat") is True:
                    touch_last_seen(session, pk, now)
                    session.commit()
                    await _ws_fanout_async(hub, [d for d, _ in pending], None, extra=pending)
                    continue
                if "status" in message:
                    name = str(message["status"]).strip().lower()
                    if name not in STATUS_FROM_NAME:
                        raise DirectoryError(422, INVALID_STATUS)
                    status = STATUS_FROM_NAME[name]
                    apply_status(session, pk, status, now)
                    talking = message.get("talking")
                    if talking is not None:
                        talking = bool(talking)
                    payload = presence_payload(pk, status, now, talking=talking)
                    recips = contact_pks(session, pk)
                    session.commit()
                    await _ws_fanout_async(hub, recips, payload, extra=pending)
                    continue
                session.commit()
                await _ws_fanout_async(hub, [], None, extra=pending)
            except DirectoryError as exc:
                await websocket.send_json({"error": exc.code})
            finally:
                session.close()
    except WebSocketDisconnect:
        hub.remove(pk, websocket)
    except Exception:
        hub.remove(pk, websocket)
        raise


async def _ws_fanout_async(
    hub: Any,
    recipients: list[bytes],
    payload: dict[str, Any] | None,
    extra: list[tuple[bytes, dict[str, Any]]] | None = None,
) -> None:
    sender = getattr(hub, "send_to_async", None)
    queue: list[tuple[bytes, dict[str, Any]]] = list(extra or [])
    if payload is not None:
        for dest in recipients:
            queue.append((dest, payload))
    for dest, msg in queue:
        if callable(sender):
            await sender(dest, msg)
        else:
            hub.send_to(dest, msg)
    publish = getattr(hub, "publish_bus", None)
    if callable(publish) and payload is not None:
        publish({"payload": payload})


