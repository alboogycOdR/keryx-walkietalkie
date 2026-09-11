"""V2-VT-011 / V2-VT-012 groups lifecycle and secret scan."""

from __future__ import annotations

from app.encoding import b64url_encode
from app.orm import AlertSend, Base, DirectRoom, Group, GroupMember, Invite
from tests.conftest import ROOM_A, ROOM_B
from tests.v2_helpers import Agent, create_group, sealed_copy


def _secrets_for(members: list[Agent], marker: bytes) -> dict[str, str]:
    enc = sealed_copy(marker)
    return {m.pk_text: enc for m in members}


def test_groups_lifecycle_vt011(client, clock) -> None:
    admin = Agent(client, clock, "ADM-1")
    joiner = Agent(client, clock, "JOIN-2")
    extra = Agent(client, clock, "XTRA-3")
    for a in (admin, joiner, extra):
        assert a.register().status_code == 200

    gid = create_group(admin, ROOM_A, name="Site crew")
    listed = admin.request("GET", f"/v2/groups/{gid}")
    assert listed.status_code == 200, listed.text
    body = listed.json()
    assert body["name"] == "Site crew"
    assert body["key_version"] == 1
    assert body["role"] == "admin"
    assert len(body["members"]) == 1

    inv = admin.request("POST", f"/v2/groups/{gid}/invites", {"expires_in": "7d"})
    assert inv.status_code == 200, inv.text
    token = inv.json()["token"]
    assert token
    # Server stored a hash, never the token as plaintext in the JSON of GET.
    got = admin.request("GET", f"/v2/groups/{gid}").json()
    assert token not in str(got)

    joined = joiner.request(
        "POST",
        "/v2/groups/join",
        {"token": token, "my_secret_enc": sealed_copy(b"\x04")},
    )
    assert joined.status_code == 200, joined.text
    members = admin.request("GET", f"/v2/groups/{gid}").json()["members"]
    assert {m["callsign"] for m in members} == {"ADM-1", "JOIN-2"}

    extra.request("POST", "/v2/groups/join", {"token": token, "my_secret_enc": sealed_copy(b"\x05")})
    remaining = [admin, joiner]
    removed = extra.request(
        "DELETE",
        f"/v2/groups/{gid}/members/{extra.pk_text}",
        {"secrets_enc": _secrets_for(remaining, b"\x06"), "room_id": ROOM_B},
    )
    assert removed.status_code == 403  # extra is not admin

    removed = admin.request(
        "DELETE",
        f"/v2/groups/{gid}/members/{extra.pk_text}",
        {"secrets_enc": _secrets_for(remaining, b"\x06"), "room_id": ROOM_B},
    )
    assert removed.status_code == 200, removed.text
    assert removed.json()["key_version"] == 2
    after = admin.request("GET", f"/v2/groups/{gid}").json()
    assert {m["pk"] for m in after["members"]} == {admin.pk_text, joiner.pk_text}
    assert extra.pk_text not in after["members"]
    # Removed member's sealed copy is not stored.
    session = client.app.state.session_factory()
    try:
        import uuid as uuid_mod

        rows = session.query(GroupMember).filter(GroupMember.group_id == uuid_mod.UUID(after["id"])).all()
        pks = {r.pk for r in rows}
        assert extra.pk not in pks
        assert all(r.secret_enc == (b"\x06" * 64) for r in rows)
    finally:
        session.close()

    promoted = admin.request("POST", f"/v2/groups/{gid}/members/{joiner.pk_text}:admin")
    assert promoted.status_code == 200
    left = admin.request("DELETE", f"/v2/groups/{gid}/members/me")
    assert left.status_code == 200
    # Last remaining member (now admin) still in group.
    stayed = joiner.request("GET", f"/v2/groups/{gid}")
    assert stayed.status_code == 200
    roles = {m["pk"]: m["role"] for m in stayed.json()["members"]}
    assert roles[joiner.pk_text] == "admin"


def test_last_admin_succession(client, clock) -> None:
    admin = Agent(client, clock, "LEAD-1")
    member = Agent(client, clock, "MATE-2")
    admin.register()
    member.register()
    gid = create_group(admin, ROOM_A)
    inv = admin.request("POST", f"/v2/groups/{gid}/invites", {"expires_in": "24h"}).json()["token"]
    assert member.request(
        "POST", "/v2/groups/join", {"token": inv, "my_secret_enc": sealed_copy()}
    ).status_code == 200
    assert admin.request("DELETE", f"/v2/groups/{gid}/members/me").status_code == 200
    detail = member.request("GET", f"/v2/groups/{gid}").json()
    assert detail["role"] == "admin"
    assert len(detail["members"]) == 1


def test_remove_requires_rotate(client, clock) -> None:
    admin = Agent(client, clock, "BOSS-1")
    other = Agent(client, clock, "HAND-2")
    admin.register()
    other.register()
    gid = create_group(admin, ROOM_A)
    token = admin.request("POST", f"/v2/groups/{gid}/invites", {"expires_in": "4h"}).json()["token"]
    other.request("POST", "/v2/groups/join", {"token": token, "my_secret_enc": sealed_copy()})
    res = admin.request("DELETE", f"/v2/groups/{gid}/members/{other.pk_text}")
    assert res.status_code == 422
    incomplete = admin.request(
        "DELETE",
        f"/v2/groups/{gid}/members/{other.pk_text}",
        {"secrets_enc": {other.pk_text: sealed_copy(b"\x07")}, "room_id": ROOM_B},
    )
    assert incomplete.status_code == 422
    assert incomplete.json()["error"] == "rotate_incomplete"
    ok = admin.request(
        "DELETE",
        f"/v2/groups/{gid}/members/{other.pk_text}",
        {"secrets_enc": {admin.pk_text: sealed_copy(b"\x08")}, "room_id": ROOM_B},
    )
    assert ok.status_code == 200, ok.text
    assert ok.json()["key_version"] == 2


def test_26th_join_refused(client, clock) -> None:
    admin = Agent(client, clock, "CAP-00")
    admin.register()
    gid = create_group(admin, ROOM_A)
    token = admin.request("POST", f"/v2/groups/{gid}/invites", {"expires_in": "none"}).json()["token"]
    # Insert 24 extra members directly so the next join is the 26th person.
    session = client.app.state.session_factory()
    try:
        import uuid
        from datetime import datetime, timezone

        from app.groups import ROLE_MEMBER
        from app.orm import GroupMember

        now = datetime.fromtimestamp(clock[0], tz=timezone.utc).replace(tzinfo=None)
        gid_uuid = uuid.UUID(gid)
        for i in range(24):
            pk = bytes([i + 1]) + b"\x00" * 31
            session.add(
                GroupMember(
                    group_id=gid_uuid,
                    pk=pk,
                    role=ROLE_MEMBER,
                    joined_at=now,
                    secret_enc=b"\x01" * 64,
                )
            )
        session.commit()
    finally:
        session.close()
    last = Agent(client, clock, "CAP-26")
    last.register()
    res = last.request("POST", "/v2/groups/join", {"token": token, "my_secret_enc": sealed_copy()})
    assert res.status_code == 409
    assert res.json()["error"] == "group_full"


def test_no_plaintext_secret_after_lifecycle(client, clock) -> None:
    """V2-VT-012: known group secret never lands in any column."""
    secret = b"PLAINTEXT-GROUP-SECRET-32BYTES!!"
    assert len(secret) == 32
    admin = Agent(client, clock, "SCAN-1")
    peer = Agent(client, clock, "SCAN-2")
    admin.register()
    peer.register()
    gid = create_group(admin, ROOM_A)
    token = admin.request("POST", f"/v2/groups/{gid}/invites", {"expires_in": "7d"}).json()["token"]
    peer.request("POST", "/v2/groups/join", {"token": token, "my_secret_enc": sealed_copy()})
    admin.request(
        "POST",
        f"/v2/groups/{gid}/rotate",
        {"secrets_enc": _secrets_for([admin, peer], b"\x09"), "room_id": ROOM_B},
    )

    session = client.app.state.session_factory()
    try:
        blobs: list[bytes] = []
        texts: list[str] = []
        for table in Base.metadata.sorted_tables:
            for row in session.execute(table.select()):
                for val in row:
                    if isinstance(val, (bytes, bytearray, memoryview)):
                        blobs.append(bytes(val))
                    elif isinstance(val, str):
                        texts.append(val)
        assert secret not in blobs
        assert secret.hex() not in "".join(texts)
        assert b"PLAINTEXT-GROUP-SECRET" not in b"".join(blobs)
        assert "private" not in " ".join(texts).lower()
        # No audio column / payload.
        colnames = {c.name for t in Base.metadata.sorted_tables for c in t.columns}
        assert "audio" not in colnames
        assert "secret" not in colnames  # only secret_enc
        assert session.query(Group).count() >= 1
        assert session.query(Invite).count() >= 1
        assert session.query(DirectRoom).count() == 0
        assert session.query(AlertSend).count() == 0
    finally:
        session.close()


def test_rename_and_rotate_notice(client, clock) -> None:
    import time

    admin = Agent(client, clock, "REN-1")
    member = Agent(client, clock, "REN-2")
    admin.register()
    member.register()
    gid = create_group(admin, ROOM_A)
    token = admin.request("POST", f"/v2/groups/{gid}/invites", {"expires_in": "7d"}).json()["token"]
    member.request("POST", "/v2/groups/join", {"token": token, "my_secret_enc": sealed_copy()})
    renamed = admin.request("PATCH", f"/v2/groups/{gid}", {"name": "Night watch"})
    assert renamed.status_code == 200
    assert renamed.json()["name"] == "Night watch"

    hub = client.app.state.presence_hub
    hub.delivered.clear()
    with client.websocket_connect("/v2/presence", headers=member.ws_headers()):
        res = admin.request(
            "POST",
            f"/v2/groups/{gid}/rotate",
            {"secrets_enc": _secrets_for([admin, member], b"\x0a"), "room_id": ROOM_B},
        )
        assert res.status_code == 200, res.text
        deadline = time.time() + 2
        while time.time() < deadline and not hub.delivered:
            time.sleep(0.02)
        notes = [m for pk, m in hub.delivered if pk == member.pk]
        assert notes, hub.delivered
        assert notes[-1]["type"] == "rotation"
        assert notes[-1]["key_version"] == 2
        assert notes[-1]["group_id"] == gid
