"""Groups, invites, rotation, alerts, membership (Technical §4.2 / §5)."""

from __future__ import annotations

import hashlib
import secrets
import uuid
from datetime import datetime, timedelta
from typing import Any

from sqlalchemy.orm import Session

from app.directory import ROLE_TO_NAME, _are_contacts, _ident
from app.encoding import b64url_decode, b64url_encode, ordered_pair, parse_pubkey
from app.errors import (
    DirectoryError,
    ALERT_RATE_LIMITED,
    ALREADY_MEMBER,
    GROUP_FULL,
    GROUP_NOT_FOUND,
    INVALID_NAME,
    INVALID_REQUEST,
    INVITE_EXPIRED,
    INVITE_INVALID,
    NOT_ADMIN,
    NOT_CONTACTS,
    NOT_FOUND,
    NOT_MEMBER,
    ROOM_CONFLICT,
    ROTATE_INCOMPLETE,
)
from app.models import ROOM_ID_RE
from app.orm import AlertSend, DirectRoom, Group, GroupMember, Identity, Invite
from app.presence import STATUS_TO_NAME, unix_ts, utcfrom

ROLE_MEMBER = 0
ROLE_ADMIN = 1
MAX_MEMBERS = 25
NAME_MIN = 1
NAME_MAX = 40
ALERT_WINDOW_S = 600
NEVER = datetime(9999, 12, 31, 23, 59, 59)

EXPIRES_PRESETS: dict[str, int | None] = {
    "4h": 4 * 3600,
    "24h": 24 * 3600,
    "7d": 7 * 24 * 3600,
    "none": None,
}


def _group(session: Session, group_id: uuid.UUID) -> Group:
    row = session.get(Group, group_id)
    if row is None:
        raise DirectoryError(404, GROUP_NOT_FOUND)
    return row


def _membership(session: Session, group_id: uuid.UUID, pk: bytes) -> GroupMember:
    row = session.get(GroupMember, (group_id, pk))
    if row is None:
        raise DirectoryError(403, NOT_MEMBER)
    return row


def _require_admin(session: Session, group_id: uuid.UUID, pk: bytes) -> GroupMember:
    mem = _membership(session, group_id, pk)
    if mem.role != ROLE_ADMIN:
        raise DirectoryError(403, NOT_ADMIN)
    return mem


def _validate_name(name: str) -> str:
    text = (name or "").strip()
    if not (NAME_MIN <= len(text) <= NAME_MAX):
        raise DirectoryError(422, INVALID_NAME)
    return text


def _validate_room_id(room_id: str) -> str:
    value = (room_id or "").strip().upper()
    if not ROOM_ID_RE.fullmatch(value):
        raise DirectoryError(422, INVALID_REQUEST)
    return value


def _parse_secret_enc(value: str) -> bytes:
    try:
        raw = b64url_decode(value)
    except DirectoryError:
        raise DirectoryError(422, INVALID_REQUEST) from None
    if not raw or len(raw) > 4096:
        raise DirectoryError(422, INVALID_REQUEST)
    return raw


def _parse_secrets_map(raw: dict[str, str]) -> dict[bytes, bytes]:
    out: dict[bytes, bytes] = {}
    if not isinstance(raw, dict) or not raw:
        raise DirectoryError(422, ROTATE_INCOMPLETE)
    for pk_text, enc_text in raw.items():
        try:
            pk = parse_pubkey(str(pk_text))
            enc = _parse_secret_enc(str(enc_text))
        except DirectoryError:
            raise DirectoryError(422, ROTATE_INCOMPLETE) from None
        out[pk] = enc
    return out


def _room_taken(session: Session, room_id: str, *, except_group: uuid.UUID | None = None) -> bool:
    q = session.query(Group).filter(Group.room_id == room_id)
    if except_group is not None:
        q = q.filter(Group.id != except_group)
    if q.first() is not None:
        return True
    if session.query(DirectRoom).filter(DirectRoom.room_id == room_id).first() is not None:
        return True
    return False


def _apply_sealed(session: Session, group: Group, secrets_enc: dict[bytes, bytes], remaining: set[bytes]) -> None:
    if set(secrets_enc.keys()) != remaining:
        raise DirectoryError(422, ROTATE_INCOMPLETE)
    for pk, enc in secrets_enc.items():
        mem = session.get(GroupMember, (group.id, pk))
        if mem is None:
            raise DirectoryError(422, ROTATE_INCOMPLETE)
        mem.secret_enc = enc


def create_group(
    session: Session,
    creator: bytes,
    name: str,
    secret_enc: bytes,
    room_id: str,
    now: float,
) -> Group:
    _ident(session, creator)
    name = _validate_name(name)
    room_id = _validate_room_id(room_id)
    if _room_taken(session, room_id):
        raise DirectoryError(409, ROOM_CONFLICT)
    group = Group(
        id=uuid.uuid4(),
        name=name,
        created_by=creator,
        created_at=utcfrom(now),
        key_version=1,
        room_id=room_id,
    )
    session.add(group)
    session.flush()
    session.add(
        GroupMember(
            group_id=group.id,
            pk=creator,
            role=ROLE_ADMIN,
            joined_at=utcfrom(now),
            secret_enc=secret_enc,
        )
    )
    session.flush()
    return group


def mint_invite(
    session: Session,
    actor: bytes,
    group_id: uuid.UUID,
    expires_in: str | int | None,
    now: float,
) -> tuple[Invite, str]:
    _membership(session, group_id, actor)
    seconds: int | None
    if expires_in is None or expires_in == "":
        seconds = None
    elif isinstance(expires_in, int):
        seconds = expires_in if expires_in > 0 else None
    else:
        key = str(expires_in).strip().lower()
        if key in EXPIRES_PRESETS:
            seconds = EXPIRES_PRESETS[key]
        else:
            try:
                parsed = int(key)
            except ValueError as exc:
                raise DirectoryError(422, INVALID_REQUEST) from exc
            seconds = parsed if parsed > 0 else None
    token = secrets.token_urlsafe(32)
    token_hash = hashlib.sha256(token.encode("ascii")).digest()
    expires_at = NEVER if seconds is None else utcfrom(now) + timedelta(seconds=seconds)
    row = Invite(
        group_id=group_id,
        token_hash=token_hash,
        expires_at=expires_at,
        created_by=actor,
    )
    session.add(row)
    session.flush()
    return row, token


def join_group(
    session: Session,
    actor: bytes,
    token: str,
    secret_enc: bytes,
    now: float,
) -> GroupMember:
    _ident(session, actor)
    token_hash = hashlib.sha256((token or "").encode("ascii")).digest()
    invite = session.query(Invite).filter(Invite.token_hash == token_hash).first()
    if invite is None:
        raise DirectoryError(404, INVITE_INVALID)
    if invite.expires_at <= utcfrom(now):
        raise DirectoryError(410, INVITE_EXPIRED)
    existing = session.get(GroupMember, (invite.group_id, actor))
    if existing is not None:
        raise DirectoryError(409, ALREADY_MEMBER)
    count = session.query(GroupMember).filter(GroupMember.group_id == invite.group_id).count()
    if count >= MAX_MEMBERS:
        raise DirectoryError(409, GROUP_FULL)
    row = GroupMember(
        group_id=invite.group_id,
        pk=actor,
        role=ROLE_MEMBER,
        joined_at=utcfrom(now),
        secret_enc=secret_enc,
    )
    session.add(row)
    session.flush()
    return row


def get_group(session: Session, actor: bytes, group_id: uuid.UUID) -> dict[str, Any]:
    _membership(session, group_id, actor)
    group = _group(session, group_id)
    members_out = []
    rows = session.query(GroupMember).filter(GroupMember.group_id == group_id).all()
    for mem in rows:
        ident = session.get(Identity, mem.pk)
        members_out.append(
            {
                "pk": b64url_encode(mem.pk),
                "callsign": ident.callsign if ident else "",
                "role": ROLE_TO_NAME.get(mem.role, "member"),
                "status": STATUS_TO_NAME.get(ident.status, "offline") if ident else "offline",
                "last_seen_at": unix_ts(ident.last_seen_at) if ident else 0,
                "joined_at": unix_ts(mem.joined_at),
            }
        )
    members_out.sort(key=lambda r: str(r["callsign"]))
    mine = session.get(GroupMember, (group_id, actor))
    assert mine is not None
    return {
        "id": str(group.id),
        "name": group.name,
        "key_version": group.key_version,
        "room_id": group.room_id,
        "my_secret_enc": b64url_encode(mine.secret_enc),
        "role": ROLE_TO_NAME.get(mine.role, "member"),
        "members": members_out,
    }


def rename_group(session: Session, actor: bytes, group_id: uuid.UUID, name: str) -> Group:
    _require_admin(session, group_id, actor)
    group = _group(session, group_id)
    group.name = _validate_name(name)
    return group


def make_admin(session: Session, actor: bytes, group_id: uuid.UUID, target: bytes) -> GroupMember:
    _require_admin(session, group_id, actor)
    mem = session.get(GroupMember, (group_id, target))
    if mem is None:
        raise DirectoryError(404, NOT_MEMBER)
    mem.role = ROLE_ADMIN
    return mem


def rotate_group(
    session: Session,
    actor: bytes,
    group_id: uuid.UUID,
    secrets_enc: dict[bytes, bytes],
    room_id: str,
    now: float,
    remove_pk: bytes | None = None,
) -> Group:
    _require_admin(session, group_id, actor)
    group = _group(session, group_id)
    room_id = _validate_room_id(room_id)
    members = session.query(GroupMember).filter(GroupMember.group_id == group_id).all()
    remaining = {m.pk for m in members}
    if remove_pk is not None:
        if remove_pk not in remaining:
            raise DirectoryError(404, NOT_MEMBER)
        if remove_pk == actor:
            raise DirectoryError(422, INVALID_REQUEST)
        remaining.discard(remove_pk)
    _apply_sealed(session, group, secrets_enc, remaining)
    if _room_taken(session, room_id, except_group=group.id):
        raise DirectoryError(409, ROOM_CONFLICT)
    group.room_id = room_id
    group.key_version += 1
    if remove_pk is not None:
        doomed = session.get(GroupMember, (group_id, remove_pk))
        if doomed is not None:
            session.delete(doomed)
    session.flush()
    return group


def leave_group(session: Session, actor: bytes, group_id: uuid.UUID) -> None:
    mem = _membership(session, group_id, actor)
    members = session.query(GroupMember).filter(GroupMember.group_id == group_id).all()
    others = [m for m in members if m.pk != actor]
    session.delete(mem)
    if not others:
        session.query(Invite).filter(Invite.group_id == group_id).delete()
        group = session.get(Group, group_id)
        if group is not None:
            session.delete(group)
        session.flush()
        return
    admins_left = [m for m in others if m.role == ROLE_ADMIN]
    if mem.role == ROLE_ADMIN and not admins_left:
        oldest = sorted(others, key=lambda m: (m.joined_at, m.pk))[0]
        oldest.role = ROLE_ADMIN
    session.flush()


def send_alert(session: Session, actor: bytes, target: bytes, now: float) -> AlertSend:
    _ident(session, actor)
    if session.get(Identity, target) is None:
        raise DirectoryError(404, NOT_FOUND)
    if _are_contacts(session, actor, target) is None:
        raise DirectoryError(403, NOT_CONTACTS)
    last = session.get(AlertSend, (actor, target))
    if last is not None and (utcfrom(now) - last.sent_at).total_seconds() < ALERT_WINDOW_S:
        raise DirectoryError(429, ALERT_RATE_LIMITED)
    if last is None:
        last = AlertSend(from_pk=actor, to_pk=target, sent_at=utcfrom(now))
        session.add(last)
    else:
        last.sent_at = utcfrom(now)
    session.flush()
    return last


def ensure_direct_room(
    session: Session,
    actor: bytes,
    peer: bytes,
    room_id: str,
    now: float,
) -> DirectRoom:
    room_id = _validate_room_id(room_id)
    if actor == peer:
        raise DirectoryError(422, INVALID_REQUEST)
    if _are_contacts(session, actor, peer) is None:
        raise DirectoryError(403, NOT_CONTACTS)
    lo, hi = ordered_pair(actor, peer)
    existing = session.get(DirectRoom, (lo, hi))
    if existing is not None:
        if existing.room_id != room_id:
            raise DirectoryError(409, ROOM_CONFLICT)
        return existing
    if _room_taken(session, room_id):
        taken = session.query(DirectRoom).filter(DirectRoom.room_id == room_id).first()
        if taken is not None and {taken.a_pk, taken.b_pk} == {lo, hi}:
            return taken
        raise DirectoryError(409, ROOM_CONFLICT)
    row = DirectRoom(a_pk=lo, b_pk=hi, room_id=room_id, created_at=utcfrom(now))
    session.add(row)
    session.flush()
    return row


def assert_room_member(session: Session, actor: bytes, room_id: str) -> None:
    room_id = _validate_room_id(room_id)
    group = session.query(Group).filter(Group.room_id == room_id).first()
    if group is not None:
        if session.get(GroupMember, (group.id, actor)) is None:
            raise DirectoryError(403, NOT_MEMBER)
        return
    direct = session.query(DirectRoom).filter(DirectRoom.room_id == room_id).first()
    if direct is not None:
        if actor not in (direct.a_pk, direct.b_pk):
            raise DirectoryError(403, NOT_MEMBER)
        return
    raise DirectoryError(403, NOT_MEMBER)


def member_pks(session: Session, group_id: uuid.UUID) -> list[bytes]:
    rows = session.query(GroupMember).filter(GroupMember.group_id == group_id).all()
    return [r.pk for r in rows]


def parse_group_id(value: str) -> uuid.UUID:
    try:
        return uuid.UUID(str(value))
    except (ValueError, AttributeError) as exc:
        raise DirectoryError(404, GROUP_NOT_FOUND) from exc
