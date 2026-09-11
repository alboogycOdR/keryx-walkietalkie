"""Happy-path mint: LiveKit JWT shape, identity suffix, no user DB."""

from __future__ import annotations

from pathlib import Path

import jwt

from tests.conftest import CALLSIGN, ROOM_A
from tests.v2_helpers import Agent, create_group


def _member(client, clock, callsign: str = CALLSIGN, room: str = ROOM_A) -> Agent:
    agent = Agent(client, clock, callsign)
    assert agent.register().status_code == 200
    create_group(agent, room)
    return agent


def test_healthz(client) -> None:
    res = client.get("/healthz")
    assert res.status_code == 200
    assert res.json() == {"ok": True}


def test_mint_returns_short_lived_livekit_jwt(client, settings, clock) -> None:
    agent = _member(client, clock)
    res = agent.request("POST", "/token", {"room_id": ROOM_A, "callsign": CALLSIGN})
    assert res.status_code == 200
    body = res.json()
    token = body["token"]
    identity = body["identity"]
    assert body["ttl_seconds"] == 300
    assert identity.startswith(f"{CALLSIGN}#")
    suffix = identity.split("#", 1)[1]
    assert len(suffix) == 8
    int(suffix, 16)

    claims = jwt.decode(
        token,
        settings.livekit_api_secret,
        algorithms=["HS256"],
        options={"verify_exp": False},
    )
    assert claims["iss"] == settings.livekit_api_key
    assert claims["sub"] == identity
    assert claims["name"] == CALLSIGN
    assert claims["exp"] - claims["nbf"] == 300
    assert claims["nbf"] == int(clock[0])
    assert claims["video"]["room"] == ROOM_A
    assert claims["video"]["roomJoin"] is True
    assert claims["video"]["canPublish"] is True
    assert claims["video"]["canSubscribe"] is True
    assert claims["video"]["canPublishData"] is True


def test_identity_suffix_is_unique_per_mint(client, clock) -> None:
    agent = _member(client, clock)
    a = agent.request("POST", "/token", {"room_id": ROOM_A, "callsign": CALLSIGN}).json()
    b = agent.request("POST", "/token", {"room_id": ROOM_A, "callsign": CALLSIGN}).json()
    assert a["identity"] != b["identity"]
    assert a["token"] != b["token"]


def test_room_id_is_normalized_uppercase(client, settings, clock) -> None:
    agent = _member(client, clock)
    res = agent.request("POST", "/token", {"room_id": ROOM_A.lower(), "callsign": CALLSIGN})
    assert res.status_code == 200
    claims = jwt.decode(
        res.json()["token"],
        settings.livekit_api_secret,
        algorithms=["HS256"],
        options={"verify_exp": False},
    )
    assert claims["video"]["room"] == ROOM_A


def test_no_committed_sqlite_state_files() -> None:
    root = Path(__file__).resolve().parents[1]
    forbidden = []
    for path in root.rglob("*"):
        if any(part in {".venv", "__pycache__", ".pytest_cache", "alembic"} for part in path.parts):
            continue
        if path.suffix.lower() in {".db", ".sqlite", ".sqlite3"}:
            forbidden.append(path)
    assert forbidden == []


def test_unsigned_token_is_refused(client) -> None:
    res = client.post("/token", json={"room_id": ROOM_A, "callsign": CALLSIGN})
    assert res.status_code == 401
    assert res.json()["error"] == "missing_signature"
