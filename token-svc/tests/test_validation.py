"""Input validation — bad room_id / callsign never mint."""

from __future__ import annotations

from tests.conftest import CALLSIGN, ROOM_A


def test_missing_fields(client) -> None:
    res = client.post("/token", json={})
    assert res.status_code == 422
    assert res.json()["detail"] == "invalid_request"


def test_bad_room_id_length(client) -> None:
    res = client.post("/token", json={"room_id": "SHORT", "callsign": CALLSIGN})
    assert res.status_code == 422
    assert res.json()["detail"] == "invalid_request"


def test_bad_room_id_alphabet(client) -> None:
    res = client.post("/token", json={"room_id": "0189ABCDEFGHIJKL", "callsign": CALLSIGN})
    assert res.status_code == 422


def test_bad_callsign(client) -> None:
    res = client.post("/token", json={"room_id": ROOM_A, "callsign": "x"})
    assert res.status_code == 422
    res = client.post("/token", json={"room_id": ROOM_A, "callsign": "this-is-way-too-long"})
    assert res.status_code == 422
    res = client.post("/token", json={"room_id": ROOM_A, "callsign": "bad space"})
    assert res.status_code == 422
