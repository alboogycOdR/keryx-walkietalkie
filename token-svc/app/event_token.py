"""Event-QR token verify/sign. Contract documented in README.md for TASK-025."""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
from typing import Any

PREFIX = "keryx-evt.v1."


class EventTokenError(Exception):
    def __init__(self, code: str) -> None:
        super().__init__(code)
        self.code = code


def _b64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def _b64url_decode(text: str) -> bytes:
    pad = "=" * (-len(text) % 4)
    return base64.urlsafe_b64decode(text + pad)


def sign_event_token(room_id: str, secret: str, exp: int | None) -> str:
    """Mint a v1 event token. Used by tests; clients (TASK-025) must match this."""
    payload: dict[str, Any] = {"v": 1, "room_id": room_id.upper()}
    if exp is not None:
        payload["exp"] = int(exp)
    body = _b64url_encode(json.dumps(payload, separators=(",", ":"), sort_keys=True).encode())
    sig = hmac.new(secret.encode("utf-8"), (PREFIX + body).encode("ascii"), hashlib.sha256).digest()
    return f"{PREFIX}{body}.{_b64url_encode(sig)}"


def verify_event_token(token: str, room_id: str, secret: str, now: float) -> None:
    if not token.startswith(PREFIX):
        raise EventTokenError("invalid_event_token")
    rest = token[len(PREFIX) :]
    try:
        body, sig_text = rest.rsplit(".", 1)
    except ValueError as exc:
        raise EventTokenError("invalid_event_token") from exc
    expected = hmac.new(secret.encode("utf-8"), (PREFIX + body).encode("ascii"), hashlib.sha256).digest()
    try:
        given = _b64url_decode(sig_text)
    except Exception as exc:
        raise EventTokenError("invalid_event_token") from exc
    if not hmac.compare_digest(expected, given):
        raise EventTokenError("invalid_event_token")
    try:
        payload = json.loads(_b64url_decode(body))
    except Exception as exc:
        raise EventTokenError("invalid_event_token") from exc
    if not isinstance(payload, dict) or payload.get("v") != 1:
        raise EventTokenError("invalid_event_token")
    token_room = str(payload.get("room_id", "")).upper()
    if token_room != room_id.upper():
        raise EventTokenError("invalid_event_token")
    exp = payload.get("exp")
    if exp is not None:
        try:
            exp_ts = float(exp)
        except (TypeError, ValueError) as exc:
            raise EventTokenError("invalid_event_token") from exc
        if now >= exp_ts:
            raise EventTokenError("expired_event_token")
