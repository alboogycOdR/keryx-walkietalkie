# token-svc

Stateless FastAPI service that mints short-lived LiveKit JWTs for KERYX LINKED
joins (KRX-051 / TS §8.1, §8.4, §8.7, FR-044).

The client derives `roomId` itself (TS §8.7). This service never sees
passphrases, never stores users, and logs nothing beyond ephemeral IP-scoped
rate-limit counters.

Compose does **not** run this process (relay compose stays LiveKit + Redis +
Caddy + coturn). Caddy reverse-proxies `https://DOMAIN/token` to
`TOKEN_SVC_UPSTREAM` (default `127.0.0.1:8080`) — TASK-036's client convention.
Bind loopback-only on a VPS so WAN never sees `:8080`.

## Run

```bash
cp .env.example .env   # fill LIVEKIT_API_KEY / LIVEKIT_API_SECRET / EVENT_TOKEN_SECRET
set -a && source .env && set +a   # or use your process manager
uvicorn app.main:app --host 0.0.0.0 --port 8080 --no-access-log
```

Docker:

```bash
docker build -t keryx-token-svc .
docker run --rm -p 127.0.0.1:8080:8080 --env-file .env keryx-token-svc
```

Share `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` with `relay/.env`. Generate a
paired pair of gitignored files with `python relay/scripts/gen_local_env.py`.

## Environment

| Variable | Required | Default | Notes |
|---|---|---|---|
| `LIVEKIT_API_KEY` | yes | — | Must match the relay LiveKit key |
| `LIVEKIT_API_SECRET` | yes | — | Must match the relay LiveKit secret |
| `EVENT_TOKEN_SECRET` | yes | — | HMAC key for Event-QR tokens (shared with the app) |
| `TOKEN_TTL_SECONDS` | no | `300` | LiveKit JWT lifetime (short-lived) |
| `RATE_LIMIT_MAX` | no | `30` | Requests per IP per window |
| `RATE_LIMIT_WINDOW_SECONDS` | no | `60` | Window length |
| `RATE_LIMIT_TTL_SECONDS` | no | `3600` | Counter idle expiry; **must be ≤ 3600** |

No database. No Redis. Restarting the process wipes rate-limit counters (fail
closed only for the current process lifetime).

## API

### `GET /healthz`

```json
{"ok": true}
```

### `POST /token`

```json
{
  "room_id": "ABCDEFGHIJKLMNOP",
  "callsign": "BRAVO-7",
  "event_token": null
}
```

`room_id` is the 16-character RFC 4648 base32 prefix from TS §8.7 (case
insensitive). `callsign` is 2–12 `[A-Za-z0-9-]`.

Success `200`:

```json
{
  "token": "<LiveKit JWT>",
  "identity": "BRAVO-7#a1b2c3d4",
  "ttl_seconds": 300
}
```

JWT claims (HS256, signed with `LIVEKIT_API_SECRET`):

- `iss` = `LIVEKIT_API_KEY`
- `sub` = `identity` = `{callsign}#{8 hex chars}`
- `name` = callsign
- `nbf` / `exp` = now / now + TTL
- `video.room` = `room_id`
- `video.roomJoin` / `canPublish` / `canSubscribe` / `canPublishData` = true

Errors (stable `detail` codes, no request values echoed):

| Status | `detail` |
|---|---|
| 422 | `invalid_request` |
| 403 | `expired_event_token` |
| 403 | `invalid_event_token` |
| 429 | `rate_limited` |

## Event-QR token contract (normative for TASK-025)

Format:

```
keryx-evt.v1.<base64url(json)>.<base64url(hmac-sha256)>
```

JSON payload (sorted keys, compact separators):

```json
{"exp": 1710000000, "room_id": "ABCDEFGHIJKLMNOP", "v": 1}
```

- `v` must be `1`.
- `room_id` must equal the mint request's room (compared uppercased).
- `exp` is a Unix timestamp in seconds. **Omit `exp` for no-expiry** (the extra
  explicit tap on the client). If `exp` is present and `now >= exp`, mint
  returns 403 `expired_event_token`.
- HMAC key = `EVENT_TOKEN_SECRET`.
- HMAC message = ASCII `keryx-evt.v1.` + the payload base64url string.
- Base64url is unpadded.

A missing `event_token` is a normal numbered/keyed join (no expiry check). A
present but expired/forged/mismatched token is always refused.

Python helper used by tests (same bytes the client must produce):
`app.event_token.sign_event_token(room_id, secret, exp)`.

## Logging policy (TS §8.7)

The process logs:

- `METHOD /path STATUS` (no query, no body)
- `rate_limit limited=<bool> count=<int>` (no IP, no room, no callsign)

It does not log callsigns, room IDs, identities, JWTs, or event tokens.
A logging-policy test (`tests/test_logging_policy.py`) asserts this.

Rate-limit counters live only in process memory and expire after
`RATE_LIMIT_TTL_SECONDS` (≤ 1 h).

## Tests

```bash
python -m pip install -r requirements-dev.txt
python -m pytest
```

## Scale path

Single-process in-memory limits are enough for one VPS next to the relay.
Multiple replicas need a shared limiter (Redis already sits in the relay
compose) — that wiring belongs to a later relay task, not this tree. Per-room
caps (R4) are likewise a follow-up once compose joins this service to the
stack.
