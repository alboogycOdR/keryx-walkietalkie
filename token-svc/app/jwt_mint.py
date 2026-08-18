"""Mint short-lived LiveKit access tokens. Identity = callsign + random suffix."""

from __future__ import annotations

import secrets
import time
from typing import Callable

import jwt

IDENTITY_SEP = "#"
SUFFIX_BYTES = 4  # 8 hex chars


def new_identity(callsign: str) -> str:
    return f"{callsign}{IDENTITY_SEP}{secrets.token_hex(SUFFIX_BYTES)}"


def mint_livekit_jwt(
    *,
    api_key: str,
    api_secret: str,
    identity: str,
    room_id: str,
    ttl_seconds: int,
    now: float | None = None,
    clock: Callable[[], float] | None = None,
) -> str:
    issued = int(now if now is not None else (clock or time.time)())
    payload = {
        "iss": api_key,
        "sub": identity,
        "name": identity.split(IDENTITY_SEP, 1)[0],
        "nbf": issued,
        "exp": issued + ttl_seconds,
        "jti": secrets.token_hex(8),
        "video": {
            "room": room_id,
            "roomJoin": True,
            "canPublish": True,
            "canSubscribe": True,
            "canPublishData": True,
        },
    }
    return jwt.encode(payload, api_secret, algorithm="HS256")
