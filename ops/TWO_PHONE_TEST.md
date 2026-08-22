# Two-phone field test — Keryx

Relay-side operator runbook (bring-up, health, triage) plus a reserved
slot for the app-side script.

**Relay-side sections (this file through the failure-triage table): TASK-040
(GB).** Do not rewrite them in later tasks; append.

**App-side operator script (LOCAL / LINKED / Event QR on two phones): TASK-039.**
Append after the HTML comment marker at the bottom. Do not edit headings
above that marker.

This file lives in `ops/` because builders cannot write `docs/**`.

---

## 0. Scope split

| Section | Owner | Needs the Flutter app? |
|---|---|---|
| §1 Env / secret checklist | TASK-040 | no |
| §2 VPS bring-up | TASK-040 | no |
| §3 Local bring-up (dev machine) | TASK-040 | no |
| §4 Health checks before any phone | TASK-040 | no |
| §5 Failure-triage table | TASK-040 | no |
| App-side field script | TASK-039 | yes (`Depends_On: TASK-040`) |

LINKED (TS §8.4) is: derive `roomId` → `POST https://DOMAIN/token` → join
LiveKit with the minted JWT. LOCAL stays serverless (D2) and does not need
this stack.

---

## 1. Env / secret checklist

Copy, do not commit. `relay/.env` and `token-svc/.env` are gitignored.

### `relay/.env` (from `relay/.env.example`)

| Variable | Required | Notes |
|---|---|---|
| `DOMAIN` | yes | Public hostname. ACME will not issue for `localhost`. |
| `TURN_DOMAIN` | yes | A/AAAA on the same VPS as `DOMAIN`. |
| `ACME_EMAIL` | yes | Mailbox someone reads (cert expiry). |
| `EXTERNAL_IP` | yes | Public IPv4. Not `127.0.0.1` on a VPS — coturn advertises this. |
| `LIVEKIT_API_KEY` | yes | `openssl rand -hex 16` |
| `LIVEKIT_API_SECRET` | yes | `openssl rand -hex 32` — must match token-svc |
| `TURN_SHARED_SECRET` | yes | `openssl rand -hex 32` |
| `TURN_REALM` | yes | Usually `TURN_DOMAIN` |
| `TOKEN_SVC_UPSTREAM` | yes | Default `127.0.0.1:8080` |

### `token-svc/.env` (from `token-svc/.env.example`)

| Variable | Required | Notes |
|---|---|---|
| `LIVEKIT_API_KEY` | yes | **Identical** to relay |
| `LIVEKIT_API_SECRET` | yes | **Identical** to relay |
| `EVENT_TOKEN_SECRET` | yes | HMAC for Event-QR tokens; shared with the app, **not** with LiveKit |
| `TOKEN_TTL_SECONDS` | no | default `300` |
| `RATE_LIMIT_MAX` | no | default `30` per IP per window |
| `RATE_LIMIT_WINDOW_SECONDS` | no | default `60` |
| `RATE_LIMIT_TTL_SECONDS` | no | default `3600`, must be ≤ 3600 (TS §8.7) |

Generate a matching local pair (never a VPS pair — those come from the
operator's secret store):

```powershell
python relay\scripts\gen_local_env.py
```

Work `relay/HARDENING.md` on every VPS. Tick a box only when the control is
actually in place.

---

## 2. VPS bring-up

Target: one Linux VPS (clawsrv-class, 4 vCPU / 8 GB is enough), Ubuntu
22.04/24.04, Docker Engine + Compose v2. This is the D2 / KRX-050 topology.

### DNS / TLS prerequisites localhost cannot prove

1. `A` (and `AAAA` if used) for `DOMAIN` and `TURN_DOMAIN` pointing at the
   VPS **public** IP. Caddy ACME HTTP-01 needs `DOMAIN` to resolve from the
   public internet to this box, with **:80 and :443 reachable from WAN**.
2. Let's Encrypt will **not** issue a certificate for `localhost`,
   `127.0.0.1`, or an `.example.com` placeholder. A laptop `compose up` of
   the `caddy` service with `DOMAIN=localhost` is expected to fail ACME;
   that is not a compose bug.
3. `EXTERNAL_IP` must be the VPS public IPv4. `127.0.0.1` makes coturn
   advertise a blackhole; NFR-05 (LINKED connect ≥ 97% with TURN) is a VPS
   measurement, not a localhost one.
4. Firewall: follow `relay/README.md` port table. **Do not** allow WAN to
   `:7880` (LiveKit), `:6379` (Redis), or `:8080` (token-svc). Caddy on
   `:443` is the only public signaling/mint path (`wss://DOMAIN`,
   `https://DOMAIN/token`).
5. TLS 1.3 only is in `relay/Caddyfile` (`protocols tls1.3`). Confirm on the
   VPS with `nmap --script ssl-enum-ciphers -p 443 $DOMAIN` after ACME
   succeeds — not confirmable on localhost.

### Command sequence (VPS)

```bash
# 1. tree on disk
sudo mkdir -p /opt/keryx && sudo chown "$USER:$USER" /opt/keryx
# copy relay/ and token-svc/ onto the box (git clone or rsync)

# 2. secrets
cd /opt/keryx/relay
cp .env.example .env
# fill DOMAIN, TURN_DOMAIN, ACME_EMAIL, EXTERNAL_IP, keys, TOKEN_SVC_UPSTREAM
cd /opt/keryx/token-svc
cp .env.example .env
# copy LIVEKIT_API_KEY / LIVEKIT_API_SECRET from relay/.env
# EVENT_TOKEN_SECRET=$(openssl rand -hex 32)

# 3. render + validate (no live traffic)
cd /opt/keryx/relay
python3 scripts/render_config.py --env .env
docker compose --env-file .env config
./scripts/validate.sh          # or: python3 tests/test_relay_config.py

# 4. firewall, then stack
# (ufw commands: relay/README.md)
docker compose --env-file .env up -d
docker compose ps

# 5. token-svc on loopback only — not a compose service
cd /opt/keryx/token-svc
docker build -t keryx-token-svc .
docker run -d --name keryx-token-svc --restart unless-stopped \
  -p 127.0.0.1:8080:8080 --env-file .env keryx-token-svc

# 6. health (see §4)
```

Clients: relay URL `wss://DOMAIN`, token URL `https://DOMAIN/token`
(TASK-036 derivation). `--dart-define=KERYX_RELAY_URL=...` is TASK-039.

Note for TASK-039 / session wiring: the public mint URL is `POST
https://DOMAIN/token`. Dart `TokenClient` appends `/token` to its `baseUrl`.
Pass the origin (`https://DOMAIN`) into `TokenClient`, not
`resolvedTokenServiceUrl` (which already includes `/token`), or the app
will POST `/token/token`.

---

## 3. Local bring-up (dev machine)

Docker is enough to prove LiveKit accepts a token-svc JWT. It is **not**
enough to prove ACME, TURN-vs-NAT, or `https://DOMAIN/token`.

Host networking (`network_mode: host` in compose) is required for WebRTC UDP
on a Linux VPS. On Docker Desktop for Windows/Mac, host-network is the
**Linux VM namespace**, not Windows localhost — `curl http://127.0.0.1:7880`
from PowerShell is expected to fail even when the stack is healthy. Prove
from `docker run --rm --network host …` instead. Treat a failed `caddy`
container on localhost as expected (ACME); do not "fix" production compose
to make ACME optional.

```powershell
cd relay
python scripts\gen_local_env.py
python scripts\render_config.py --env .env
powershell -ExecutionPolicy Bypass -File scripts\validate.ps1
# validate.ps1 renders .env.example into a temp dir (does not clobber generated/).
# Re-render from .env before `up` if you ran validate after gen_local_env:
python scripts\render_config.py --env .env

# skip caddy — ACME cannot issue for DOMAIN=localhost
docker compose --env-file .env up -d redis livekit coturn
docker compose ps

cd ..\token-svc
docker build -t keryx-token-svc .
docker run -d --name keryx-token-svc --network host --env-file .env keryx-token-svc
# VPS (Linux): prefer -p 127.0.0.1:8080:8080 so WAN cannot hit :8080.
# Docker Desktop: --network host shares the VM loopback with LiveKit.

cd ..\relay
docker run --rm --network host --env-file ..\token-svc\.env `
  -v ${PWD}\scripts\e2e_linked_proof.py:/e2e.py:ro `
  keryx-token-svc python /e2e.py --rate-limit
```

Optional HTTP stand-in for the Caddy `/token` matcher (same path, no TLS):

```powershell
docker run --rm --name keryx-token-edge --network host `
  -e TOKEN_SVC_UPSTREAM=127.0.0.1:8080 `
  -e LIVEKIT_UPSTREAM=127.0.0.1:7880 `
  -v ${PWD}/Caddyfile.local:/etc/caddy/Caddyfile:ro `
  caddy:2.9.1-alpine

docker run --rm --network host --env-file ..\token-svc\.env `
  -v ${PWD}\scripts\e2e_linked_proof.py:/e2e.py:ro `
  keryx-token-svc python /e2e.py --edge-url http://127.0.0.1:8880/token
```

Stop:

```powershell
docker stop keryx-token-svc keryx-token-edge
docker compose --env-file .env down
```

---

## 4. Health checks before any phone

Run these until they are green. A phone that shows `NO LINK` before this
list is green is not a phone bug.

| Check | Command | Expect |
|---|---|---|
| Compose config | `docker compose --env-file .env config` | exit 0, services `{livekit,redis,caddy,coturn}` |
| Relay unit tests | `python tests/test_relay_config.py` | all pass |
| token-svc unit tests | `python -m pytest` in `token-svc/` | all pass |
| Redis | `docker compose exec redis redis-cli ping` | `PONG` (host-network: `redis-cli -h 127.0.0.1 ping`) |
| LiveKit HTTP | `curl -sS -D- http://127.0.0.1:7880/` | LiveKit speaks (200/404, not connection refused) |
| token-svc health | `curl -fsS http://127.0.0.1:8080/healthz` | `{"ok": true}` |
| Direct mint | `POST http://127.0.0.1:8080/token` JSON `{room_id, callsign}` | 200 `{token, identity, ttl_seconds}` |
| Caddy `/token` (VPS) | `POST https://DOMAIN/token` same JSON | 200, **not** `503 token-svc not wired` |
| Caddy `/token` (local) | `POST http://127.0.0.1:8880/token` via `Caddyfile.local` | 200 |
| JWT join | `python relay/scripts/e2e_linked_proof.py` | minted JWT → LiveKit `/rtc` 101 **and** identity in `ListParticipants` |
| Rate limit | `python relay/scripts/e2e_linked_proof.py --rate-limit` | HTTP 429 `rate_limited` after `RATE_LIMIT_MAX` |
| TLS (VPS only) | `curl -fsSI https://DOMAIN/` | TLS 1.3, Caddy, not a browser MITM warning |
| TURN (VPS only) | coturn logs + a phone on mobile data | ICE `relay` candidate; NFR-05 is a field number, not a curl |

`e2e_linked_proof.py` is the TASK-040 join evidence: it mints through
token-svc, proves a garbage JWT is refused, holds a websocket upgrade with
the minted JWT, and checks LiveKit RoomService `ListParticipants` for that
identity. That is a real join, not "the mint endpoint returned 200".

---

## 5. Failure-triage table

Phone symptoms below are what TASK-039 will see. Match the log column
before changing compose.

| Symptom | Likely cause | What to pull |
|---|---|---|
| `NO LINK` immediately, never a token HTTP status | Relay URL wrong / DNS / :443 closed / Caddy down | `docker compose ps`; `docker compose logs caddy`; `curl -vI https://DOMAIN/` |
| Token HTTP **503** body `token-svc not wired` | Old Caddyfile (pre-TASK-040) still deployed | `relay/Caddyfile` must `reverse_proxy {$TOKEN_SVC_UPSTREAM}`; recreate caddy |
| Token HTTP **connection refused** on `:8080` | token-svc not running, or bound only in another netns | `docker ps -a --filter name=keryx-token-svc`; `curl http://127.0.0.1:8080/healthz` |
| Token HTTP **4xx** `invalid_request` | Client body failed validation (room_id not 16-char base32, bad callsign) | token-svc log line `POST /token 422` (no body — by design, TS §8.7) |
| Token HTTP **403** `invalid_event_token` / `expired_event_token` | Event QR HMAC/exp mismatch (`EVENT_TOKEN_SECRET` ≠ app) | Compare secrets; do **not** log the token |
| Token HTTP **429** `rate_limited` | Per-IP cap (`RATE_LIMIT_MAX` / window). Expected under hammering | token-svc log `rate_limit limited=True count=…` (no IP in the log) |
| Token HTTP **5xx** other than the old 503 | token-svc crash / missing env (`LIVEKIT_API_*`) | `docker logs keryx-token-svc`; process exits if required env is empty |
| Token 200 but LiveKit join fails (401 on `/rtc`) | API key/secret **mismatch** between token-svc and LiveKit | Diff the two `.env` files; `docker compose logs livekit` |
| Token 200, `/rtc` 101, then ICE fail on mobile data | TURN not advertised / `EXTERNAL_IP` wrong / 3478/relay UDP closed | `docker compose logs coturn`; `docker compose logs livekit`; ufw UDP ranges |
| Token 200, join OK on Wi-Fi, fail on LTE | Classic NAT; TURN path is the NFR-05 lever | coturn `external-ip`, 3478/udp + 52000–52999/udp open |
| Caddy ACME fail / TLS warning | DNS not pointing here, :80 closed, or `DOMAIN=localhost` | `docker compose logs caddy`; check A record from a phone (not from the VPS) |
| Redis unhealthy, LiveKit restart loop | Redis not on `127.0.0.1:6379` (host-network assumption) | `docker compose logs redis`; `ss -ltnp \| grep 6379` |
| Two phones, one hears nothing, floor seems granted | Not this stack — floor protocol / TASK-039 script | App logs; do not enable LiveKit media dumps (TS §8.7) |

Privacy (TS §8.7): do not raise LiveKit `pion_level` above `error` in
production, do not tcpdump the RTC range except in a time-boxed incident,
and wipe pcaps. token-svc logs method/path/status and rate-limit counters
only — never callsigns, room IDs, or JWTs.

---

<!-- TASK-039 APP-SIDE START -->

## App-side field script (TASK-039)

_Reserved. TASK-039 appends the `--dart-define` build, two-phone LOCAL
script, LINKED (one phone on mobile data), Event QR script, and per-step
expected SFX / FR citations below this heading. Do not rewrite §0–§5._
