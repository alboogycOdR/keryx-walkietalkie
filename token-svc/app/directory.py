"""Identity + contacts (Technical §4.2; V2-VT-010). Group HTTP is TASK-085."""

from __future__ import annotations

from datetime import timedelta

from sqlalchemy.orm import Session

from app.encoding import b64url_encode, ordered_pair, validate_callsign
from app.errors import (
    DirectoryError,
    ALREADY_CONTACTS,
    ALREADY_PENDING,
    BLOCKED,
    CALLSIGN_TAKEN,
    IDENTITY_EXISTS,
    NOT_CONTACTS,
    NOT_FOUND,
    REQUEST_EXPIRED,
    REQUEST_NOT_FOUND,
    SELF_REQUEST,
    TOO_MANY_OUTSTANDING,
    UNKNOWN_IDENTITY,
)
from app.orm import Block, Contact, ContactRequest, Group, GroupMember, Identity
from app.presence import (
    STATUS_OFFLINE,
    STATUS_TO_NAME,
    contact_pks,
    unix_ts,
    utcfrom,
)

REQUEST_TTL_S = 7 * 24 * 3600
MAX_OUTSTANDING = 20
STATE_PENDING = "pending"
STATE_DECLINED = "declined"
STATE_ACCEPTED = "accepted"
ROLE_TO_NAME = {0: "member", 1: "admin"}


def _ident(session: Session, pk: bytes) -> Identity:
    row = session.get(Identity, pk)
    if row is None:
        raise DirectoryError(401, UNKNOWN_IDENTITY)
    return row


def _blocked(session: Session, blocker: bytes, blocked: bytes) -> bool:
    return session.get(Block, (blocker, blocked)) is not None


def _are_contacts(session: Session, a: bytes, b: bytes) -> Contact | None:
    lo, hi = ordered_pair(a, b)
    return session.get(Contact, (lo, hi))


def register_identity(session: Session, pk: bytes, callsign: str, now: float) -> Identity:
    callsign = validate_callsign(callsign)
    existing = session.get(Identity, pk)
    if existing is not None:
        if existing.callsign != callsign:
            raise DirectoryError(409, IDENTITY_EXISTS)
        return existing
    taken = session.query(Identity).filter(Identity.callsign == callsign).first()
    if taken is not None:
        raise DirectoryError(409, CALLSIGN_TAKEN)
    row = Identity(
        pubkey=pk,
        callsign=callsign,
        created_at=utcfrom(now),
        last_seen_at=utcfrom(now),
        status=STATUS_OFFLINE,
    )
    session.add(row)
    session.flush()
    return row


def patch_callsign(session: Session, pk: bytes, callsign: str) -> Identity:
    callsign = validate_callsign(callsign)
    ident = _ident(session, pk)
    if ident.callsign == callsign:
        return ident
    taken = session.query(Identity).filter(Identity.callsign == callsign).first()
    if taken is not None:
        raise DirectoryError(409, CALLSIGN_TAKEN)
    ident.callsign = callsign
    return ident


def _pending_unexpired(session: Session, from_pk: bytes, now: float) -> list[ContactRequest]:
    now_dt = utcfrom(now)
    return (
        session.query(ContactRequest)
        .filter(
            ContactRequest.from_pk == from_pk,
            ContactRequest.state == STATE_PENDING,
            ContactRequest.expires_at > now_dt,
        )
        .all()
    )


def send_request(session: Session, from_pk: bytes, to_pk: bytes, sig: bytes, now: float) -> ContactRequest:
    _ident(session, from_pk)
    if from_pk == to_pk:
        raise DirectoryError(422, SELF_REQUEST)
    if session.get(Identity, to_pk) is None:
        raise DirectoryError(404, NOT_FOUND)
    if _blocked(session, to_pk, from_pk) or _blocked(session, from_pk, to_pk):
        raise DirectoryError(403, BLOCKED)
    if _are_contacts(session, from_pk, to_pk) is not None:
        raise DirectoryError(409, ALREADY_CONTACTS)

    now_dt = utcfrom(now)
    existing = session.get(ContactRequest, (from_pk, to_pk))
    if existing is not None and existing.state == STATE_PENDING and existing.expires_at > now_dt:
        raise DirectoryError(409, ALREADY_PENDING)

    if len(_pending_unexpired(session, from_pk, now)) >= MAX_OUTSTANDING:
        raise DirectoryError(429, TOO_MANY_OUTSTANDING)

    if existing is not None:
        session.delete(existing)
        session.flush()

    row = ContactRequest(
        from_pk=from_pk,
        to_pk=to_pk,
        sig=sig,
        created_at=now_dt,
        expires_at=now_dt + timedelta(seconds=REQUEST_TTL_S),
        state=STATE_PENDING,
    )
    session.add(row)
    session.flush()
    return row


def _incoming(session: Session, me: bytes, from_pk: bytes, now: float) -> ContactRequest:
    row = session.get(ContactRequest, (from_pk, me))
    if row is None or row.state != STATE_PENDING:
        raise DirectoryError(404, REQUEST_NOT_FOUND)
    if row.expires_at <= utcfrom(now):
        row.state = "expired"
        raise DirectoryError(410, REQUEST_EXPIRED)
    return row


def accept_request(session: Session, me: bytes, from_pk: bytes, now: float) -> Contact:
    req = _incoming(session, me, from_pk, now)
    if _are_contacts(session, me, from_pk) is None:
        lo, hi = ordered_pair(me, from_pk)
        session.add(Contact(a_pk=lo, b_pk=hi, created_at=utcfrom(now)))
    req.state = STATE_ACCEPTED
    reverse = session.get(ContactRequest, (me, from_pk))
    if reverse is not None and reverse.state == STATE_PENDING:
        reverse.state = STATE_ACCEPTED
    session.flush()
    pair = _are_contacts(session, me, from_pk)
    assert pair is not None
    return pair


def decline_request(session: Session, me: bytes, from_pk: bytes, now: float) -> None:
    req = _incoming(session, me, from_pk, now)
    req.state = STATE_DECLINED
    session.flush()


def block_request(session: Session, me: bytes, from_pk: bytes, now: float) -> None:
    req = session.get(ContactRequest, (from_pk, me))
    if req is not None and req.state == STATE_PENDING:
        if req.expires_at <= utcfrom(now):
            req.state = "expired"
        else:
            req.state = STATE_DECLINED
    if session.get(Block, (me, from_pk)) is None:
        session.add(Block(blocker_pk=me, blocked_pk=from_pk, created_at=utcfrom(now)))
    pair = _are_contacts(session, me, from_pk)
    if pair is not None:
        session.delete(pair)
    session.flush()


def remove_contact(session: Session, me: bytes, other: bytes) -> None:
    pair = _are_contacts(session, me, other)
    if pair is None:
        raise DirectoryError(404, NOT_CONTACTS)
    session.delete(pair)
    session.flush()


def _public_identity(row: Identity) -> dict[str, object]:
    return {
        "pk": b64url_encode(row.pubkey),
        "callsign": row.callsign,
        "status": STATUS_TO_NAME.get(row.status, "offline"),
        "last_seen_at": unix_ts(row.last_seen_at),
    }


def identity_me(session: Session, me: bytes, now: float) -> dict[str, object]:
    ident = _ident(session, me)
    now_dt = utcfrom(now)
    contacts_out = []
    for other in contact_pks(session, me):
        row = session.get(Identity, other)
        if row is not None:
            contacts_out.append(_public_identity(row))
    contacts_out.sort(key=lambda r: str(r["callsign"]))

    pending_in = []
    incoming = (
        session.query(ContactRequest)
        .filter(
            ContactRequest.to_pk == me,
            ContactRequest.state == STATE_PENDING,
            ContactRequest.expires_at > now_dt,
        )
        .all()
    )
    for req in incoming:
        sender = session.get(Identity, req.from_pk)
        pending_in.append(
            {
                "from_pk": b64url_encode(req.from_pk),
                "callsign": sender.callsign if sender else "",
                "created_at": unix_ts(req.created_at),
                "expires_at": unix_ts(req.expires_at),
            }
        )

    pending_out = []
    for req in _pending_unexpired(session, me, now):
        pending_out.append(
            {
                "to_pk": b64url_encode(req.to_pk),
                "created_at": unix_ts(req.created_at),
                "expires_at": unix_ts(req.expires_at),
            }
        )

    groups_out = []
    memberships = session.query(GroupMember).filter(GroupMember.pk == me).all()
    for mem in memberships:
        group = session.get(Group, mem.group_id)
        if group is None:
            continue
        groups_out.append(
            {
                "id": str(group.id),
                "name": group.name,
                "role": ROLE_TO_NAME.get(mem.role, "member"),
                "key_version": group.key_version,
                "room_id": group.room_id,
                "secret_enc": b64url_encode(mem.secret_enc),
            }
        )

    return {
        "pk": b64url_encode(ident.pubkey),
        "callsign": ident.callsign,
        "status": STATUS_TO_NAME.get(ident.status, "offline"),
        "contacts": contacts_out,
        "pending_in": pending_in,
        "pending_out": pending_out,
        "groups": groups_out,
    }
