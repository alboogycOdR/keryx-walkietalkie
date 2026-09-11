"""Pubkey and path encoding.

Canonical on the wire is unpadded base64url of 32 raw bytes (Technical §3.3).
The server also accepts standard base64 (padded, ``+``/``/``) for
``X-Keryx-Key`` — the Dart client in TASK-083 emits that form.
"""

from __future__ import annotations

import base64
import re

from app.errors import DirectoryError, INVALID_KEY, INVALID_REQUEST
from app.models import CALLSIGN_RE

PUBKEY_LEN = 32
# Canonical unpadded base64url, plus standard base64 (+ / =) from the Dart client.
_KEY_RE = re.compile(r"^[A-Za-z0-9_+/=\-]+$")
_B64URL_RE = re.compile(r"^[A-Za-z0-9_-]+$")


def b64url_encode(raw: bytes) -> str:
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def b64url_decode(value: str) -> bytes:
    text = (value or "").strip()
    if not text or not _KEY_RE.fullmatch(text):
        raise DirectoryError(401, INVALID_KEY)
    stripped = text.rstrip("=")
    pad = "=" * ((4 - len(stripped) % 4) % 4)
    try:
        # urlsafe decoder also accepts standard +/ after the -/_ translation.
        raw = base64.urlsafe_b64decode(stripped + pad)
    except Exception as exc:
        raise DirectoryError(401, INVALID_KEY) from exc
    return raw


def parse_pubkey(value: str) -> bytes:
    raw = b64url_decode(value)
    if len(raw) != PUBKEY_LEN:
        raise DirectoryError(401, INVALID_KEY)
    return raw


def parse_pubkey_param(value: str) -> bytes:
    """Path param — 404-shaped invalid is still an invalid key/request."""
    try:
        return parse_pubkey(value)
    except DirectoryError:
        raise DirectoryError(400, INVALID_REQUEST) from None


def validate_callsign(value: str) -> str:
    callsign = (value or "").strip()
    if not CALLSIGN_RE.fullmatch(callsign):
        from app.errors import INVALID_CALLSIGN

        raise DirectoryError(422, INVALID_CALLSIGN)
    return callsign


def ordered_pair(a: bytes, b: bytes) -> tuple[bytes, bytes]:
    return (a, b) if a < b else (b, a)
