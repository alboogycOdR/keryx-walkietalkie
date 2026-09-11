"""Ed25519 request signatures (Technical §3.3).

Canonical bytes: ``METHOD|path|body|timestamp`` (UTF-8 method/path/ts; body raw).
The Ed25519 signature is over ``sha256(canonical)``. Headers:

- ``X-Keryx-Sig``: standard base64 of the 64-byte signature
- ``X-Keryx-Key``: unpadded base64url of the 32-byte public key
- ``X-Keryx-Ts``: Unix seconds as a decimal string
"""

from __future__ import annotations

import base64
import hashlib

from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives.asymmetric.ed25519 import (
    Ed25519PrivateKey,
    Ed25519PublicKey,
)

from app.encoding import PUBKEY_LEN, b64url_encode, parse_pubkey
from app.errors import (
    DirectoryError,
    INVALID_KEY,
    INVALID_SIGNATURE,
    MISSING_SIGNATURE,
    REPLAYED,
    STALE_TIMESTAMP,
)

HDR_SIG = "x-keryx-sig"
HDR_KEY = "x-keryx-key"
HDR_TS = "x-keryx-ts"


def canonical(method: str, path: str, body: bytes, ts: int) -> bytes:
    return (
        method.upper().encode("ascii")
        + b"|"
        + path.encode("utf-8")
        + b"|"
        + body
        + b"|"
        + str(ts).encode("ascii")
    )


def digest(method: str, path: str, body: bytes, ts: int) -> bytes:
    return hashlib.sha256(canonical(method, path, body, ts)).digest()


def sign_request(
    private_key: Ed25519PrivateKey,
    method: str,
    path: str,
    body: bytes,
    ts: int,
) -> dict[str, str]:
    sig = private_key.sign(digest(method, path, body, ts))
    pub = private_key.public_key().public_bytes_raw()
    return {
        "X-Keryx-Sig": base64.b64encode(sig).decode("ascii"),
        "X-Keryx-Key": b64url_encode(pub),
        "X-Keryx-Ts": str(ts),
    }


def _parse_ts(raw: str | None) -> int:
    if raw is None or raw.strip() == "":
        raise DirectoryError(401, MISSING_SIGNATURE)
    try:
        return int(raw.strip())
    except ValueError as exc:
        raise DirectoryError(401, STALE_TIMESTAMP) from exc


def _parse_sig(raw: str | None) -> bytes:
    if raw is None or raw.strip() == "":
        raise DirectoryError(401, MISSING_SIGNATURE)
    try:
        sig = base64.b64decode(raw.strip(), validate=True)
    except Exception as exc:
        raise DirectoryError(401, INVALID_SIGNATURE) from exc
    if len(sig) != 64:
        raise DirectoryError(401, INVALID_SIGNATURE)
    return sig


class NonceStore:
    def seen(self, nonce: str, now: float, ttl: int) -> bool:
        """Return True if this nonce was already recorded."""
        raise NotImplementedError

    def remember(self, nonce: str, now: float, ttl: int) -> None:
        raise NotImplementedError


class MemoryNonceStore(NonceStore):
    def __init__(self) -> None:
        self._items: dict[str, float] = {}

    def _purge(self, now: float) -> None:
        stale = [k for k, exp in self._items.items() if exp <= now]
        for k in stale:
            del self._items[k]

    def seen(self, nonce: str, now: float, ttl: int) -> bool:
        self._purge(now)
        return nonce in self._items

    def remember(self, nonce: str, now: float, ttl: int) -> None:
        self._purge(now)
        self._items[nonce] = now + ttl


class RedisNonceStore(NonceStore):
    def __init__(self, redis_client: object) -> None:
        self._r = redis_client

    def seen(self, nonce: str, now: float, ttl: int) -> bool:  # noqa: ARG002
        return bool(self._r.exists(f"keryx:nonce:{nonce}"))  # type: ignore[attr-defined]

    def remember(self, nonce: str, now: float, ttl: int) -> None:  # noqa: ARG002
        self._r.set(f"keryx:nonce:{nonce}", "1", ex=max(ttl, 1))  # type: ignore[attr-defined]


def verify_headers(
    headers: dict[str, str],
    method: str,
    path: str,
    body: bytes,
    now: float,
    window_s: int,
    nonce_store: NonceStore,
) -> bytes:
    """Return the 32-byte public key if the request is authentic."""
    lowered = {k.lower(): v for k, v in headers.items()}
    sig_hdr = lowered.get(HDR_SIG)
    key_hdr = lowered.get(HDR_KEY)
    ts_hdr = lowered.get(HDR_TS)
    if not sig_hdr or not key_hdr or not ts_hdr:
        raise DirectoryError(401, MISSING_SIGNATURE)

    ts = _parse_ts(ts_hdr)
    if abs(now - ts) > window_s:
        raise DirectoryError(401, STALE_TIMESTAMP)

    pubkey = parse_pubkey(key_hdr)
    sig = _parse_sig(sig_hdr)
    try:
        Ed25519PublicKey.from_public_bytes(pubkey).verify(sig, digest(method, path, body, ts))
    except (InvalidSignature, ValueError) as exc:
        raise DirectoryError(401, INVALID_SIGNATURE) from exc

    nonce = hashlib.sha256(sig).hexdigest()
    if nonce_store.seen(nonce, now, window_s):
        raise DirectoryError(401, REPLAYED)
    nonce_store.remember(nonce, now, window_s)
    return pubkey


def public_bytes(private_key: Ed25519PrivateKey) -> bytes:
    raw = private_key.public_key().public_bytes_raw()
    if len(raw) != PUBKEY_LEN:
        raise DirectoryError(401, INVALID_KEY)
    return raw
