"""Request/response shapes. room_id is a client-derived hash — never a passphrase."""

from __future__ import annotations

import re

from pydantic import BaseModel, Field, field_validator

# TS §8.7 roomId = b32(...)[:16] — RFC 4648 alphabet, no padding.
ROOM_ID_RE = re.compile(r"^[A-Z2-7]{16}$")
# FR-068 display callsign: 2–12 chars; NATO form like BRAVO-7.
CALLSIGN_RE = re.compile(r"^[A-Za-z0-9-]{2,12}$")


class TokenRequest(BaseModel):
    room_id: str = Field(..., description="16-char base32 room derivation (TS §8.7)")
    callsign: str = Field(..., description="Display callsign; identity suffix is added")
    event_token: str | None = Field(
        default=None,
        description="Optional Event-QR token; expired tokens are refused (FR-044)",
    )
    peer_pk: str | None = Field(
        default=None,
        description="Optional contact public key; binds a 1:1 room_id on demand",
    )

    @field_validator("room_id")
    @classmethod
    def normalize_room_id(cls, value: str) -> str:
        room_id = value.strip().upper()
        if not ROOM_ID_RE.fullmatch(room_id):
            raise ValueError("room_id must be 16 characters of RFC 4648 base32")
        return room_id

    @field_validator("callsign")
    @classmethod
    def validate_callsign(cls, value: str) -> str:
        callsign = value.strip()
        if not CALLSIGN_RE.fullmatch(callsign):
            raise ValueError("callsign must be 2-12 letters, digits, or hyphens")
        return callsign

    @field_validator("event_token")
    @classmethod
    def empty_event_token_is_absent(cls, value: str | None) -> str | None:
        if value is None:
            return None
        stripped = value.strip()
        return stripped or None


class TokenResponse(BaseModel):
    token: str
    identity: str
    ttl_seconds: int
