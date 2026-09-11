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
from app.groups import (
    create_group,
    get_group,
    join_group,
    leave_group,
    make_admin,
    member_pks,
    mint_invite,
    parse_group_id,
    rename_group,
    rotate_group,
    send_alert,
    _parse_secret_enc,
    _parse_secrets_map,
)
from app.presence import (
    STATUS_FROM_NAME,
    alert_payload,
    unix_ts,
    apply_status,
    audience_pks,
    mark_stale_offline,
    presence_payload,
    rotation_payload,
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


class GroupCreateBody(BaseModel):
    name: str
    my_secret_enc: str
    room_id: str


class InviteBody(BaseModel):
    expires_in: str | int | None = "7d"


class JoinBody(BaseModel):
    token: str
    my_secret_enc: str


class GroupRenameBody(BaseModel):
    name: str


class RotateBody(BaseModel):
    secrets_enc: dict[str, str]
    room_id: str


class AlertBody(BaseModel):
    to_pk: str


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


@router.post("/groups")
async def post_group(request: Request) -> dict[str, Any]:
    pk, body = await _read_signed(request)
    payload = _parse(GroupCreateBody, body)
    session = _session(request)
    try:
        group = create_group(
            session,
            pk,
            payload.name,  # type: ignore[union-attr]
            _parse_secret_enc(payload.my_secret_enc),  # type: ignore[union-attr]
            payload.room_id,  # type: ignore[union-attr]
            request.app.state.clock(),
        )
        session.commit()
        return {
            "id": str(group.id),
            "name": group.name,
            "key_version": group.key_version,
            "room_id": group.room_id,
            "role": "admin",
        }
    finally:
        session.close()


@router.post("/groups/{group_id}/invites")
async def post_invite(request: Request, group_id: str) -> dict[str, Any]:
    pk, body = await _read_signed(request)
    payload = _parse(InviteBody, body or b"{}")
    gid = parse_group_id(group_id)
    session = _session(request)
    try:
        row, token = mint_invite(
            session, pk, gid, payload.expires_in, request.app.state.clock()  # type: ignore[union-attr]
        )
        session.commit()
        return {"token": token, "expires_at": unix_ts(row.expires_at), "group_id": str(gid)}
    finally:
        session.close()


@router.post("/groups/join")
async def post_join(request: Request) -> dict[str, Any]:
    pk, body = await _read_signed(request)
    payload = _parse(JoinBody, body)
    session = _session(request)
    try:
        mem = join_group(
            session,
            pk,
            payload.token,  # type: ignore[union-attr]
            _parse_secret_enc(payload.my_secret_enc),  # type: ignore[union-attr]
            request.app.state.clock(),
        )
        session.commit()
        return {"id": str(mem.group_id), "role": "member", "key_version": get_group(session, pk, mem.group_id)["key_version"]}
    finally:
        session.close()


@router.get("/groups/{group_id}")
async def get_group_route(request: Request, group_id: str) -> dict[str, Any]:
    pk, _body = await _read_signed(request)
    gid = parse_group_id(group_id)
    session = _session(request)
    try:
        return get_group(session, pk, gid)
    finally:
        session.close()


@router.patch("/groups/{group_id}")
async def patch_group(request: Request, group_id: str) -> dict[str, Any]:
    pk, body = await _read_signed(request)
    payload = _parse(GroupRenameBody, body)
    gid = parse_group_id(group_id)
    session = _session(request)
    try:
        group = rename_group(session, pk, gid, payload.name)  # type: ignore[union-attr]
        session.commit()
        return {"id": str(group.id), "name": group.name}
    finally:
        session.close()


@router.post("/groups/{group_id}/rotate")
async def post_rotate(request: Request, group_id: str) -> dict[str, Any]:
    pk, body = await _read_signed(request)
    payload = _parse(RotateBody, body)
    gid = parse_group_id(group_id)
    session = _session(request)
    try:
        group = rotate_group(
            session,
            pk,
            gid,
            _parse_secrets_map(payload.secrets_enc),  # type: ignore[union-attr]
            payload.room_id,  # type: ignore[union-attr]
            request.app.state.clock(),
        )
        recips = [m for m in member_pks(session, gid) if m != pk]
        notice = rotation_payload(group.id, group.key_version)
        session.commit()
        await _ws_fanout_async(request.app.state.presence_hub, recips, notice)
        return {"id": str(group.id), "key_version": group.key_version, "room_id": group.room_id}
    finally:
        session.close()


@router.delete("/groups/{group_id}/members/me")
async def delete_me(request: Request, group_id: str) -> dict[str, str]:
    pk, _body = await _read_signed(request)
    gid = parse_group_id(group_id)
    session = _session(request)
    try:
        leave_group(session, pk, gid)
        session.commit()
        return {"state": "left"}
    finally:
        session.close()


@router.delete("/groups/{group_id}/members/{member_pk}")
async def delete_member(request: Request, group_id: str, member_pk: str) -> dict[str, Any]:
    pk, body = await _read_signed(request)
    payload = _parse(RotateBody, body)
    gid = parse_group_id(group_id)
    target = parse_pubkey_param(member_pk)
    session = _session(request)
    try:
        group = rotate_group(
            session,
            pk,
            gid,
            _parse_secrets_map(payload.secrets_enc),  # type: ignore[union-attr]
            payload.room_id,  # type: ignore[union-attr]
            request.app.state.clock(),
            remove_pk=target,
        )
        recips = [m for m in member_pks(session, gid) if m != pk]
        notice = rotation_payload(group.id, group.key_version)
        session.commit()
        await _ws_fanout_async(request.app.state.presence_hub, recips, notice)
        return {"id": str(group.id), "key_version": group.key_version, "removed": True}
    finally:
        session.close()


@router.post("/groups/{group_id}/members/{member_pk}:admin")
async def post_make_admin(request: Request, group_id: str, member_pk: str) -> dict[str, str]:
    pk, _body = await _read_signed(request)
    gid = parse_group_id(group_id)
    target = parse_pubkey_param(member_pk)
    session = _session(request)
    try:
        make_admin(session, pk, gid, target)
        session.commit()
        return {"role": "admin"}
    finally:
        session.close()


@router.post("/alerts")
async def post_alert(request: Request) -> dict[str, Any]:
    pk, body = await _read_signed(request)
    payload = _parse(AlertBody, body)
    target = parse_pubkey(payload.to_pk)  # type: ignore[union-attr]
    now = request.app.state.clock()
    session = _session(request)
    try:
        send_alert(session, pk, target, now)
        notice = alert_payload(pk, now)
        session.commit()
        await _ws_fanout_async(request.app.state.presence_hub, [target], notice)
        return {"state": "sent"}
    finally:
        session.close()


async def run_presence_sweep(app: Any) -> int:
    session = app.state.session_factory()
    try:
        pending: list[tuple[bytes, dict[str, Any]]] = []

        def _collect(_src: bytes, payload: dict[str, Any], recips: list[bytes]) -> None:
            for dest in recips:
                pending.append((dest, payload))

        n = mark_stale_offline(session, app.state.clock(), _collect)
        session.commit()
        await _ws_fanout_async(app.state.presence_hub, [], None, extra=pending)
        return n
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
                    recips = audience_pks(session, pk)
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
    if callable(publish):
        seen: set[bytes] = set()
        for dest, msg in queue:
            if dest in seen:
                continue
            seen.add(dest)
            try:
                publish(dest, msg)
            except TypeError:
                publish({"dest": dest, "payload": msg})


