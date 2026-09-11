# token-svc

FastAPI service that mints short-lived LiveKit JWTs for KERYX LINKED joins
(KRX-051 / TS §8.1, §8.4, §8.7, FR-044) and, from v2, hosts the directory
under `/v2/` (identities, contacts, presence). Group write endpoints are
TASK-085. `POST /token` is unchanged in this task (membership gate is TASK-085).

The client derives `roomId` itself (TS §8.7). The process never sees
passphrases or private keys. Directory rows are public keys, callsigns,
contact edges and sealed group copies the server cannot open.

Compose does **not** run this process (relay compose is LiveKit + Redis +
Caddy + coturn + Postgres 16). Caddy reverse-proxies `https://DOMAIN/token` to
`TOKEN_SVC_UPSTREAM` (default `127.0.0.1:8080`) — TASK-036's client convention.
Bind loopback-only on a VPS so WAN never sees `:8080`.

Contract for the Flutter client (TASK-086): `openapi-v2.yaml`.

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
| `DATABASE_URL` | prod yes | `sqlite://` | Postgres in production (`postgresql+psycopg://…`). SQLite is tests/dev only |
| `REDIS_URL` | prod yes | empty | `redis://127.0.0.1:6379/0` — nonce replay set + presence pub/sub. Empty → in-memory |
| `KERYX_SIGNING_WINDOW_S` | no | `120` | Reject timestamps outside this many seconds (Technical §3.3) |

Migrate Postgres with `alembic upgrade head` (reads `DATABASE_URL`). Nightly
`pg_dump`: `scripts/pg_dump_nightly.sh` (7 copies).

In-memory rate-limit counters still expire ≤ 1 h. Replay nonces live in Redis
when `REDIS_URL` is set.

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

`/token` keeps `{detail: code}`. Directory `/v2/*` uses `{error: code}` only.

## Directory `/v2` (Technical §4)

Every `/v2/` call carries:

- `X-Keryx-Sig`: standard base64 of Ed25519(`sha256(METHOD|path|body|timestamp)`)
- `X-Keryx-Key`: unpadded base64url of the 32-byte public key
- `X-Keryx-Ts`: Unix seconds

`body` is the raw request bytes (empty string for GET / WS hello). The server
rejects `|now-ts| > 120` (`stale_timestamp`), a replayed signature nonce
(`replayed`), and a signature that does not verify (`invalid_signature`).

| Method | Path | Purpose |
|---|---|---|
| POST | `/v2/identity` | Register `{callsign}` |
| GET | `/v2/identity/me` | Contacts, groups, pending requests |
| PATCH | `/v2/identity/callsign` | `{callsign}` |
| POST | `/v2/contacts/requests` | `{to_pk}` |
| POST | `/v2/contacts/requests/{from_pk}:accept\|decline\|block` | Resolve |
| DELETE | `/v2/contacts/{pk}` | Remove (not announced) |
| WS | `/v2/presence` | Signed hello (same headers, GET `/v2/presence`); `{status}` and `{type:heartbeat}` |

Presence statuses: `available`, `busy`, `dnd`, `offline`. Heartbeat every 60 s.
Offline after 5 minutes without a heartbeat. Fan-out `{pk, status, talking?, since}`
to contacts only (co-members in TASK-085). Nearby is client-side.

### Enumerated `/v2` error codes

| Code | Typical HTTP | When |
|---|---|---|
| `missing_signature` | 401 | One of the three headers is absent |
| `invalid_signature` | 401 | Sig does not verify, or wrong key |
| `stale_timestamp` | 401 | `|now-ts| > 120` |
| `replayed` | 401 | Same signature seen inside the window |
| `invalid_key` | 401 | `X-Keryx-Key` is not 32 raw bytes |
| `unknown_identity` | 401 | Signed but never registered |
| `identity_exists` | 409 | Pubkey already registered with a different callsign |
| `callsign_taken` | 409 | Callsign belongs to another key |
| `invalid_callsign` | 422 | Fails `^[A-Za-z0-9-]{2,12}$` |
| `invalid_request` | 400/422 | Malformed body or path key |
| `self_request` | 422 | `to_pk` is the caller |
| `already_contacts` | 409 | Pair already linked |
| `already_pending` | 409 | Outstanding request exists |
| `blocked` | 403 | Blocker recorded; re-request refused |
| `request_not_found` | 404 | No pending incoming request |
| `request_expired` | 410 | Older than 7 days |
| `too_many_outstanding` | 429 | 21st pending request from this sender |
| `not_found` | 404 | Unknown `to_pk` |
| `not_contacts` | 404 | DELETE of a pair that does not exist |
| `invalid_status` | 422 | Presence status not in the enum |

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
