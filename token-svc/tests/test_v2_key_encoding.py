"""TASK-084 interop: X-Keryx-Key accepts Dart standard base64."""

from __future__ import annotations

import base64

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey

from app.signing import public_bytes, sign_request
from tests.v2_helpers import Agent


def test_standard_base64_key_from_dart_client_accepted(client, clock) -> None:
    # Mirror lib/core/identity/signing.dart: base64Encode(publicKey).
    priv = None
    pub = None
    std = ""
    for _ in range(64):
        cand = Ed25519PrivateKey.generate()
        raw = public_bytes(cand)
        encoded = base64.b64encode(raw).decode("ascii")
        if "+" in encoded or "/" in encoded:
            priv, pub, std = cand, raw, encoded
            break
    assert priv is not None and ("+" in std or "/" in std)
    assert std.endswith("=")

    body = b'{"callsign":"DART-1"}'
    ts = int(clock[0]) + 1
    clock[0] = float(ts)
    headers = sign_request(priv, "POST", "/v2/identity", body, ts)
    headers["X-Keryx-Key"] = std
    headers["Content-Type"] = "application/json"
    res = client.post("/v2/identity", content=body, headers=headers)
    assert res.status_code == 200, res.text
    # Canonical response pk stays unpadded base64url.
    from app.encoding import b64url_encode

    assert res.json()["pk"] == b64url_encode(pub)


def test_unpadded_base64url_still_accepted(client, clock) -> None:
    agent = Agent(client, clock, "URL-1")
    res = agent.register()
    assert res.status_code == 200
    assert "=" not in res.json()["pk"]
    assert "+" not in res.json()["pk"]
    assert "/" not in res.json()["pk"]
