"""V2-VT-014 membership-gated /token plus 1:1 on-demand bind."""

from __future__ import annotations

from tests.conftest import CALLSIGN, ROOM_A, ROOM_B
from tests.v2_helpers import Agent, create_group


def test_unsigned_token_refused(client) -> None:
    res = client.post("/token", json={"room_id": ROOM_A, "callsign": CALLSIGN})
    assert res.status_code == 401
    assert res.json()["error"] == "missing_signature"


def test_non_member_token_refused(client, clock) -> None:
    owner = Agent(client, clock, "OWN-1")
    stranger = Agent(client, clock, "STR-2")
    owner.register()
    stranger.register()
    create_group(owner, ROOM_A)
    res = stranger.request("POST", "/token", {"room_id": ROOM_A, "callsign": "STR-2"})
    assert res.status_code == 403
    assert res.json()["error"] == "not_member"


def test_member_token_accepted(client, clock, settings) -> None:
    import jwt

    owner = Agent(client, clock, CALLSIGN)
    owner.register()
    create_group(owner, ROOM_A)
    res = owner.request("POST", "/token", {"room_id": ROOM_A, "callsign": CALLSIGN})
    assert res.status_code == 200, res.text
    claims = jwt.decode(
        res.json()["token"],
        settings.livekit_api_secret,
        algorithms=["HS256"],
        options={"verify_exp": False},
    )
    assert claims["video"]["room"] == ROOM_A


def test_direct_room_on_demand(client, clock) -> None:
    a = Agent(client, clock, "DIR-A")
    b = Agent(client, clock, "DIR-B")
    a.register()
    b.register()
    a.request("POST", "/v2/contacts/requests", {"to_pk": b.pk_text})
    b.request("POST", f"/v2/contacts/requests/{a.pk_text}:accept")
    res = a.request(
        "POST",
        "/token",
        {"room_id": ROOM_B, "callsign": "DIR-A", "peer_pk": b.pk_text},
    )
    assert res.status_code == 200, res.text
    res_b = b.request("POST", "/token", {"room_id": ROOM_B, "callsign": "DIR-B"})
    assert res_b.status_code == 200, res_b.text
