"""Signed-request helpers for directory tests."""

from __future__ import annotations

import json
from typing import Any

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from fastapi.testclient import TestClient

from app.encoding import b64url_encode
from app.signing import public_bytes, sign_request


class Agent:
    def __init__(self, client: TestClient, clock: list[float], callsign: str) -> None:
        self.client = client
        self.clock = clock
        self.callsign = callsign
        self.priv = Ed25519PrivateKey.generate()
        self.pk = public_bytes(self.priv)
        self.pk_text = b64url_encode(self.pk)

    def _headers(self, method: str, path: str, body: bytes) -> dict[str, str]:
        ts = int(self.clock[0])
        hdrs = sign_request(self.priv, method, path, body, ts)
        if body:
            hdrs["Content-Type"] = "application/json"
        return hdrs

    def bump(self) -> None:
        self.clock[0] += 1

    def request(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
    ) -> Any:
        body = b""
        if payload is not None:
            body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        self.bump()
        headers = self._headers(method, path, body)
        return self.client.request(method, path, content=body, headers=headers)

    def register(self) -> Any:
        self.bump()
        return self.request("POST", "/v2/identity", {"callsign": self.callsign})

    def me(self) -> Any:
        self.bump()
        return self.request("GET", "/v2/identity/me")

    def ws_headers(self) -> dict[str, str]:
        self.bump()
        return self._headers("GET", "/v2/presence", b"")
