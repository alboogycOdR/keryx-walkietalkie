"""V2-VT-004 server side: valid / stale / replayed / wrong key."""

from __future__ import annotations

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from app.signing import sign_request
from tests.v2_helpers import Agent


def test_valid_signature_registers(client, clock) -> None:
    agent = Agent(client, clock, "ALPHA-1")
    res = agent.register()
    assert res.status_code == 200, res.text
    assert res.json()["callsign"] == "ALPHA-1"
    assert res.json()["pk"] == agent.pk_text


def test_stale_timestamp_rejected(client, clock) -> None:
    agent = Agent(client, clock, "BRAVO-2")
    body = b'{"callsign":"BRAVO-2"}'
    ts = int(clock[0]) - 121
    headers = sign_request(agent.priv, "POST", "/v2/identity", body, ts)
    headers["Content-Type"] = "application/json"
    res = client.post("/v2/identity", content=body, headers=headers)
    assert res.status_code == 401
    assert res.json() == {"error": "stale_timestamp"}


def test_replayed_nonce_rejected(client, clock) -> None:
    agent = Agent(client, clock, "CHARLIE-3")
    body = b'{"callsign":"CHARLIE-3"}'
    headers = agent._headers("POST", "/v2/identity", body)
    res1 = client.post("/v2/identity", content=body, headers=headers)
    assert res1.status_code == 200, res1.text
    res2 = client.post("/v2/identity", content=body, headers=headers)
    assert res2.status_code == 401
    assert res2.json() == {"error": "replayed"}


def test_wrong_key_rejected(client, clock) -> None:
    agent = Agent(client, clock, "DELTA-4")
    body = b'{"callsign":"DELTA-4"}'
    headers = agent._headers("POST", "/v2/identity", body)
    other = Ed25519PrivateKey.generate()
    headers["X-Keryx-Key"] = __import__("app.encoding", fromlist=["b64url_encode"]).b64url_encode(
        other.public_key().public_bytes_raw()
    )
    res = client.post("/v2/identity", content=body, headers=headers)
    assert res.status_code == 401
    assert res.json() == {"error": "invalid_signature"}


def test_missing_headers_rejected(client) -> None:
    res = client.post("/v2/identity", json={"callsign": "ECHO-5"})
    assert res.status_code == 401
    assert res.json() == {"error": "missing_signature"}


def test_tampered_body_rejected(client, clock) -> None:
    agent = Agent(client, clock, "FOXTROT-6")
    body = b'{"callsign":"FOXTROT-6"}'
    headers = agent._headers("POST", "/v2/identity", body)
    res = client.post("/v2/identity", content=b'{"callsign":"TAMPERED-1"}', headers=headers)
    assert res.status_code == 401
    assert res.json() == {"error": "invalid_signature"}


def test_unknown_identity_on_me(client, clock) -> None:
    agent = Agent(client, clock, "GOLF-7")
    res = agent.me()
    assert res.status_code == 401
    assert res.json() == {"error": "unknown_identity"}
