"""FR-044: expired / forged / mismatched event tokens are refused."""

from __future__ import annotations

from app.event_token import sign_event_token
from tests.conftest import CALLSIGN, ROOM_A, ROOM_B


def test_valid_event_token_mints(client, settings, clock) -> None:
    token = sign_event_token(ROOM_A, settings.event_token_secret, exp=int(clock[0]) + 3600)
    res = client.post(
        "/token",
        json={"room_id": ROOM_A, "callsign": CALLSIGN, "event_token": token},
    )
    assert res.status_code == 200


def test_expired_event_token_refused(client, settings, clock) -> None:
    token = sign_event_token(ROOM_A, settings.event_token_secret, exp=int(clock[0]) - 1)
    res = client.post(
        "/token",
        json={"room_id": ROOM_A, "callsign": CALLSIGN, "event_token": token},
    )
    assert res.status_code == 403
    assert res.json()["detail"] == "expired_event_token"


def test_event_token_at_exact_expiry_is_refused(client, settings, clock) -> None:
    token = sign_event_token(ROOM_A, settings.event_token_secret, exp=int(clock[0]))
    res = client.post(
        "/token",
        json={"room_id": ROOM_A, "callsign": CALLSIGN, "event_token": token},
    )
    assert res.status_code == 403
    assert res.json()["detail"] == "expired_event_token"


def test_no_expiry_event_token_accepted(client, settings) -> None:
    token = sign_event_token(ROOM_A, settings.event_token_secret, exp=None)
    res = client.post(
        "/token",
        json={"room_id": ROOM_A, "callsign": CALLSIGN, "event_token": token},
    )
    assert res.status_code == 200


def test_event_token_wrong_room_refused(client, settings, clock) -> None:
    token = sign_event_token(ROOM_B, settings.event_token_secret, exp=int(clock[0]) + 60)
    res = client.post(
        "/token",
        json={"room_id": ROOM_A, "callsign": CALLSIGN, "event_token": token},
    )
    assert res.status_code == 403
    assert res.json()["detail"] == "invalid_event_token"


def test_forged_event_token_refused(client, clock) -> None:
    token = sign_event_token(ROOM_A, "wrong-secret-not-the-real-one_____", exp=int(clock[0]) + 60)
    res = client.post(
        "/token",
        json={"room_id": ROOM_A, "callsign": CALLSIGN, "event_token": token},
    )
    assert res.status_code == 403
    assert res.json()["detail"] == "invalid_event_token"


def test_malformed_event_token_refused(client) -> None:
    res = client.post(
        "/token",
        json={"room_id": ROOM_A, "callsign": CALLSIGN, "event_token": "not-a-token"},
    )
    assert res.status_code == 403
    assert res.json()["detail"] == "invalid_event_token"
