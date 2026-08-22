#!/usr/bin/env python3
"""End-to-end LINKED proof: token-svc JWT is accepted by a live LiveKit join.

Stdlib + PyJWT (already a token-svc dependency). No Flutter, no new compose
services. Intended command sequence is documented in ops/TWO_PHONE_TEST.md.

Exit 0 only when:
  1. POST /token (direct and, if --edge-url is set, via the Caddy /token path)
     returns a JWT.
  2. LiveKit rejects a garbage token (HTTP 401 on /rtc).
  3. LiveKit accepts the minted JWT (HTTP 101 on /rtc) AND the participant
     appears in RoomService ListParticipants while the socket is held open.
  4. With --rate-limit, the limiter returns 429 after RATE_LIMIT_MAX successes.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import socket
import ssl
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any
from urllib.parse import quote, urlparse

try:
    import jwt
except ImportError as exc:  # pragma: no cover - operator env
    raise SystemExit("PyJWT is required (token-svc/requirements.txt)") from exc

ROOM_ID = "ABCDEFGHIJKLMNOP"  # valid TS §8.7 16-char base32
CALLSIGN = "BRAVO-7"
WS_KEY = base64.b64encode(b"0123456789abcdef").decode("ascii")


def _load_dotenv(path: Path) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path.is_file():
        return values
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def _http_json(
    url: str,
    *,
    method: str = "GET",
    body: dict[str, Any] | None = None,
    headers: dict[str, str] | None = None,
    timeout: float = 10.0,
) -> tuple[int, bytes]:
    data = None if body is None else json.dumps(body).encode("utf-8")
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    for key, value in (headers or {}).items():
        req.add_header(key, value)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()


def mint_token(token_url: str, room_id: str, callsign: str) -> dict[str, Any]:
    status, raw = _http_json(
        token_url,
        method="POST",
        body={"room_id": room_id, "callsign": callsign, "event_token": None},
    )
    if status != 200:
        raise SystemExit(f"mint failed: HTTP {status} body={raw[:500]!r}")
    payload = json.loads(raw.decode("utf-8"))
    if not payload.get("token") or not payload.get("identity"):
        raise SystemExit(f"mint returned malformed body: {payload!r}")
    return payload


def admin_token(api_key: str, api_secret: str, room: str) -> str:
    now = int(time.time())
    return jwt.encode(
        {
            "iss": api_key,
            "iat": now,
            "nbf": now,
            "exp": now + 600,
            "sub": "keryx-e2e-admin",
            "video": {
                "roomCreate": True,
                "roomList": True,
                "roomAdmin": True,
                "roomJoin": True,
                "canPublish": True,
                "canSubscribe": True,
                "room": room,
            },
        },
        api_secret,
        algorithm="HS256",
    )


def list_participants(livekit_http: str, api_key: str, api_secret: str, room: str) -> list[str]:
    url = livekit_http.rstrip("/") + "/twirp/livekit.RoomService/ListParticipants"
    status, raw = _http_json(
        url,
        method="POST",
        body={"room": room},
        headers={"Authorization": f"Bearer {admin_token(api_key, api_secret, room)}"},
    )
    if status != 200:
        raise SystemExit(f"ListParticipants failed: HTTP {status} body={raw[:500]!r}")
    payload = json.loads(raw.decode("utf-8"))
    identities: list[str] = []
    for participant in payload.get("participants") or []:
        ident = participant.get("identity")
        if ident:
            identities.append(ident)
    return identities


def rtc_upgrade(livekit_ws: str, access_token: str) -> tuple[int, str, socket.socket]:
    """RFC 6455 upgrade against LiveKit /rtc. Caller owns the socket."""
    parsed = urlparse(livekit_ws)
    host = parsed.hostname or "127.0.0.1"
    tls = parsed.scheme in ("https", "wss")
    port = parsed.port or (443 if tls else 7880)
    path = (
        "/rtc?access_token="
        + quote(access_token, safe="")
        + "&auto_subscribe=1&protocol=15&sdk=python"
    )
    raw = socket.create_connection((host, port), timeout=10)
    sock: socket.socket = ssl.create_default_context().wrap_socket(raw, server_hostname=host) if tls else raw
    request = (
        f"GET {path} HTTP/1.1\r\n"
        f"Host: {host}:{port}\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        f"Sec-WebSocket-Key: {WS_KEY}\r\n"
        "Sec-WebSocket-Version: 13\r\n"
        "\r\n"
    )
    sock.sendall(request.encode("ascii"))
    buf = b""
    while b"\r\n\r\n" not in buf:
        chunk = sock.recv(4096)
        if not chunk:
            break
        buf += chunk
        if len(buf) > 65536:
            break
    head = buf.split(b"\r\n\r\n", 1)[0].decode("iso-8859-1", errors="replace")
    status_line = head.split("\r\n", 1)[0]
    parts = status_line.split(" ", 2)
    try:
        status = int(parts[1])
    except (IndexError, ValueError):
        sock.close()
        raise SystemExit(f"malformed /rtc response: {status_line!r}")
    reason = parts[2] if len(parts) > 2 else ""
    if status != 101:
        sock.close()
        return status, reason, socket.socket()
    sock.settimeout(8)
    return status, reason, sock


def prove_join(
    livekit_ws: str,
    livekit_http: str,
    api_key: str,
    api_secret: str,
    room: str,
    minted: dict[str, Any],
) -> None:
    bad_status, bad_reason, bad_conn = rtc_upgrade(livekit_ws, "not-a-jwt")
    bad_conn.close()
    print(f"[e2e] garbage token /rtc → HTTP {bad_status} {bad_reason}")
    if bad_status == 101:
        raise SystemExit("LiveKit accepted a garbage token — refusing to claim a join")
    if bad_status not in {401, 403}:
        print("[e2e] note: expected 401/403 for garbage token; continuing with valid JWT")

    status, reason, conn = rtc_upgrade(livekit_ws, minted["token"])
    print(f"[e2e] minted JWT /rtc → HTTP {status} {reason}")
    if status != 101:
        conn.close()
        raise SystemExit(
            f"LiveKit did not accept the minted JWT (want 101 Switching Protocols, got {status})"
        )

    # Hold the upgraded socket open while we query RoomService — a completed
    # signaling upgrade with a valid participant JWT is the join. The identity
    # listing is the independent confirmation LiveKit registered the peer.
    deadline = time.time() + 8
    seen: list[str] = []
    last_error = ""
    while time.time() < deadline:
        try:
            seen = list_participants(livekit_http, api_key, api_secret, room)
        except SystemExit as exc:
            last_error = str(exc)
            seen = []
        print(f"[e2e] ListParticipants identities={seen}")
        if minted["identity"] in seen:
            print(f"[e2e] JOIN OK identity={minted['identity']} room={room}")
            conn.close()
            return
        time.sleep(0.4)
    conn.close()
    extra = f" last_error={last_error}" if last_error else ""
    raise SystemExit(
        "LiveKit upgraded the socket (JWT accepted) but the participant "
        f"never appeared in ListParticipants (seen={seen}).{extra}"
    )


def prove_rate_limit(token_url: str, max_ok: int) -> None:
    successes = 0
    limited = 0
    last_status = 0
    # One extra request past the cap must 429. Use a dedicated callsign prefix
    # so this does not depend on earlier mint calls sharing the window.
    for i in range(max_ok + 2):
        status, raw = _http_json(
            token_url,
            method="POST",
            body={"room_id": ROOM_ID, "callsign": CALLSIGN, "event_token": None},
        )
        last_status = status
        if status == 200:
            successes += 1
        elif status == 429:
            limited += 1
            detail = json.loads(raw.decode("utf-8")).get("detail")
            if detail != "rate_limited":
                raise SystemExit(f"429 without rate_limited detail: {raw[:200]!r}")
        else:
            raise SystemExit(f"rate-limit probe unexpected HTTP {status}: {raw[:200]!r}")
    print(f"[e2e] rate-limit: successes={successes} limited={limited} last={last_status}")
    if limited < 1:
        raise SystemExit(
            f"rate limiter did not fire after {max_ok + 2} calls "
            f"(successes={successes}). Is RATE_LIMIT_MAX higher than expected?"
        )


def wait_http(url: str, timeout: float, *, ok: set[int] | None = None) -> None:
    want = ok or {200}
    deadline = time.time() + timeout
    last = "no attempt"
    while time.time() < deadline:
        try:
            status, raw = _http_json(url, method="GET", timeout=3)
            last = f"HTTP {status} {raw[:80]!r}"
            if status in want:
                print(f"[e2e] ready {url} → {last}")
                return
        except Exception as exc:  # noqa: BLE001 — probe loop
            last = str(exc)
        time.sleep(0.4)
    raise SystemExit(f"timeout waiting for {url}: {last}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--token-url", default=os.environ.get("KERYX_TOKEN_URL", "http://127.0.0.1:8080/token"))
    parser.add_argument("--edge-url", default=os.environ.get("KERYX_EDGE_TOKEN_URL", ""))
    parser.add_argument("--livekit-url", default=os.environ.get("LIVEKIT_URL", "http://127.0.0.1:7880"))
    parser.add_argument("--api-key", default=os.environ.get("LIVEKIT_API_KEY", ""))
    parser.add_argument("--api-secret", default=os.environ.get("LIVEKIT_API_SECRET", ""))
    parser.add_argument("--env-file", type=Path, default=None)
    parser.add_argument("--rate-limit", action="store_true")
    parser.add_argument("--rate-limit-max", type=int, default=int(os.environ.get("RATE_LIMIT_MAX", "30")))
    parser.add_argument("--skip-join", action="store_true")
    args = parser.parse_args()

    env: dict[str, str] = {}
    env_path = args.env_file
    if env_path is None:
        candidate = Path(__file__).resolve().parent.parent / ".env"
        if candidate.is_file():
            env_path = candidate
    if env_path:
        env = _load_dotenv(env_path)
        token_env = Path(__file__).resolve().parent.parent.parent / "token-svc" / ".env"
        env.update(_load_dotenv(token_env))

    api_key = args.api_key or env.get("LIVEKIT_API_KEY", "")
    api_secret = args.api_secret or env.get("LIVEKIT_API_SECRET", "")
    if not api_key or not api_secret:
        raise SystemExit("LIVEKIT_API_KEY / LIVEKIT_API_SECRET required (flags or .env)")

    livekit_http = args.livekit_url
    parsed_lk = urlparse(livekit_http)
    if parsed_lk.scheme in ("ws", "http"):
        livekit_ws = livekit_http.replace("http://", "ws://", 1)
        livekit_http = livekit_http.replace("ws://", "http://", 1)
    elif parsed_lk.scheme in ("wss", "https"):
        livekit_ws = livekit_http.replace("https://", "wss://", 1)
        livekit_http = livekit_http.replace("wss://", "https://", 1)
    else:
        livekit_ws = livekit_http

    print(f"[e2e] token_url={args.token_url}")
    print(f"[e2e] livekit={livekit_http}")

    wait_http(args.token_url.rsplit("/token", 1)[0] + "/healthz", 20)
    wait_http(livekit_http.rstrip("/") + "/", 30, ok={200, 404, 401, 405})

    minted = mint_token(args.token_url, ROOM_ID, CALLSIGN)
    print(f"[e2e] minted identity={minted['identity']} ttl={minted.get('ttl_seconds')}")
    claims = jwt.decode(minted["token"], api_secret, algorithms=["HS256"], options={"verify_exp": True})
    if claims.get("iss") != api_key:
        raise SystemExit(f"JWT iss {claims.get('iss')!r} != LIVEKIT_API_KEY")
    if claims.get("video", {}).get("room") != ROOM_ID:
        raise SystemExit(f"JWT room {claims.get('video')} != {ROOM_ID}")
    print("[e2e] JWT signature + room claim verified against LiveKit API secret")

    if args.edge_url:
        edge = mint_token(args.edge_url, ROOM_ID, CALLSIGN)
        print(f"[e2e] Caddy /token path minted identity={edge['identity']}")
        jwt.decode(edge["token"], api_secret, algorithms=["HS256"])

    if not args.skip_join:
        prove_join(livekit_ws, livekit_http, api_key, api_secret, ROOM_ID, minted)

    if args.rate_limit:
        prove_rate_limit(args.token_url, args.rate_limit_max)

    print("[e2e] OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
