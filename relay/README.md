# Keryx relay (KRX-050)

Self-hosted LINKED-mode stack for a single VPS (clawsrv-class, 4 vCPU / 8 GB is
enough to start). One Docker Compose file brings up:

| Service | Role |
|---|---|
| **LiveKit** | SFU. One room per channel. Audio publish/subscribe mirrors PTT. Floor-control messages ride LiveKit data messages (TS §8.4). |
| **Redis** | Ephemeral room/routing state for LiveKit. **No persistence.** Also the v2 directory nonce/presence bus. |
| **Caddy** | TLS 1.3 on `DOMAIN`, reverse-proxy to LiveKit `:7880`. `/token` reverse-proxies to token-svc on `TOKEN_SVC_UPSTREAM` (loopback `:8080`). |
| **coturn** | TURN for hostile NATs (TS §8.4, NFR-05 ≥ 97% connection success). |
| **Postgres 16** | Directory (identities, contacts, groups). Named volume `keryx_pg`. Loopback-only (`listen_addresses=127.0.0.1`). |

There is **no** LiveKit Egress/Ingress/recording container. Voice is never
written to disk (TS §8.7).

`network_mode: host` is required for WebRTC UDP. `docker compose config`
validates on any OS; `docker compose up` is for a Linux VPS.

## Files

| Path | Purpose |
|---|---|
| `docker-compose.yml` | The stack |
| `.env.example` | Every required variable; copy to `.env` |
| `livekit.yaml.tmpl` | LiveKit config (rendered) |
| `turnserver.conf.tmpl` | coturn config (rendered) |
| `Caddyfile` | Caddy TLS + `/token` → token-svc |
| `Caddyfile.local` | Localhost HTTP edge for proving `/token` without ACME. **Not** mounted by compose. |
| `redis.conf` | Bind localhost, no RDB/AOF |
| `scripts/render_config.py` | `${VAR}` substitution into `generated/` |
| `scripts/validate.ps1` / `validate.sh` | `compose config` + unit checks |
| `HARDENING.md` | Production checklist (KRX-050) |

## Bring-up

1. DNS: `A`/`AAAA` for `DOMAIN` (e.g. `relay.example.com`) and `TURN_DOMAIN`
   (e.g. `turn.example.com`) pointing at the VPS public IP.
2. Install Docker Engine + Compose v2 on Ubuntu 22.04/24.04.
3. Copy this directory to the host (typical: `/opt/keryx/relay`).
4. Secrets:

   ```bash
   cp .env.example .env
   # fill DOMAIN, TURN_DOMAIN, ACME_EMAIL, EXTERNAL_IP
   # LIVEKIT_API_KEY=$(openssl rand -hex 16)
   # LIVEKIT_API_SECRET=$(openssl rand -hex 32)
   # TURN_SHARED_SECRET=$(openssl rand -hex 32)
   ```

5. Render + validate (no live traffic yet):

   ```bash
   python3 scripts/render_config.py --env .env
   docker compose --env-file .env config
   ```

   Windows (validation only):

   ```powershell
   python scripts\render_config.py --env .env.example
   powershell -ExecutionPolicy Bypass -File scripts\validate.ps1
   ```

6. Open the firewall (see table below), then:

   ```bash
   docker compose --env-file .env up -d
   docker compose ps
   curl -fsS "https://$DOMAIN/"     # Caddy should speak TLS; LiveKit may 404 the root
   ```

7. Give the same `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` to the token service
   (TASK-003). Clients join `wss://DOMAIN`.

Stop:

```bash
docker compose --env-file .env down
```

## Ports and firewall

| Port | Proto | Service | Notes |
|---|---|---|---|
| 80/tcp | TCP | Caddy | ACME HTTP-01 + redirect to HTTPS |
| 443/tcp | TCP | Caddy | TLS 1.3 signaling (`wss://DOMAIN`) |
| 7880/tcp | TCP | LiveKit | Bound on host; **do not** publish to the internet — Caddy fronts it |
| 7881/tcp | TCP | LiveKit | WebRTC ICE/TCP fallback (must be public) |
| 3478/udp | UDP | coturn | TURN/UDP |
| 3478/tcp | TCP | coturn | TURN/TCP |
| 5349/tcp | TCP | coturn | TURN/TLS |
| 50000–50200/udp | UDP | LiveKit | RTC media (PTT audio) |
| 52000–52999/udp | UDP | coturn | TURN relay allocations |

`7880` stays loopback-facing in intent (Caddy reverse-proxies `127.0.0.1:7880`).
Host networking still binds `0.0.0.0:7880` inside LiveKit; block it in `ufw`
from WAN (see HARDENING.md). Redis binds `127.0.0.1:6379` only.

Suggested `ufw`:

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 7881/tcp
ufw allow 3478/udp
ufw allow 3478/tcp
ufw allow 5349/tcp
ufw allow 50000:50200/udp
ufw allow 52000:52999/udp
ufw enable
```

## Capacity on one VPS (NFR-09)

**Target:** 1 VPS serves ≥ 500 concurrent channel-joins.

Keryx is PTT, not a video conference:

- A join pre-publishes a **muted** audio track (TS §8.5). Idle cost is a
  keepalive, not 20 kbps of Opus.
- At most one publisher per room at a time. 500 muted subscribers + a handful
  of talkers is well inside a 4 vCPU / 8 GB box.
- Redis holds routing state only (capped at 256 MB).
- LiveKit RTC uses 201 UDP ports (50000–50200); coturn has 1000 relay ports.
  That envelope is sized for hundreds of simultaneous ICE sessions, not 500
  concurrent talkers.

Rule of thumb for this compose (single node, audio-only, no recording):

| Load | Expected fit |
|---|---|
| 500 joined, ~0 talking | comfortably inside 4 vCPU / 8 GB |
| 500 joined, ~25 talking (Opus ~20 kbps × 25 × fan-out via SFU) | still the design point |
| Video, recording, or ≥ 50 simultaneous talkers | scale out (below) |

Measure before you add nodes: `docker stats`, LiveKit `/rtc` logs, and host
`ss -u` on the RTC range. Do not enable Egress to "help" capacity.

## Scale-out (NFR-09)

Documented multi-node path when one VPS is no longer enough. Do not implement this in
Phase 1; keep the single-compose topology until a real load number forces it.

1. **Split Redis** onto its own host (or managed Redis) with TLS + AUTH.
   Point every LiveKit node at it (`redis.address` / sentinel / cluster keys
   in `livekit.yaml`). Redis is the only shared state.
2. **Add LiveKit nodes** behind a signaling load balancer (Caddy / nginx /
   cloud LB) on 443. Each node keeps its own RTC UDP range and a public IP
   (`use_external_ip: true` or `node_ip`). LiveKit's built-in redis mode
   routes participants in the same room to the same node.
3. **TURN cluster:** run coturn on dedicated IPs (or a second NIC) so 3478 /
   5349 / relay ranges do not fight the SFU. Advertise the pool in
   `rtc.turn_servers`. Prefer TURN/TLS on 443 via Caddy L4 (SNI
   `TURN_DOMAIN`) if corporate firewalls block 3478/5349 — that is the
   remaining lever for NFR-05.
4. **Regions:** numbered-channel `region` salt (FR-008 / TASK-007) already
   partitions `roomId` space. Stand up one stack per region rather than one
   global anycast room. Token-svc stays stateless and can sit in front of
   any region.
5. **Do not** add LiveKit Egress, Ingress, or a recording bucket. Scale-out
   is more SFU + Redis + TURN, not a media archive.

## Optional live smoke (not required for review)

If Docker is available on a Linux host with ports free:

```bash
docker compose --env-file .env up -d
docker compose ps
curl -sS -o /dev/null -w "%{http_code}\n" http://127.0.0.1:7880/          # LiveKit speaks here
docker compose logs --tail=50 livekit
docker compose down
```

A full TLS + TURN probe needs real DNS and is an operator step, not CI.

## Token service (TASK-040)

Caddy `https://DOMAIN/token` reverse-proxies to `TOKEN_SVC_UPSTREAM`
(default `127.0.0.1:8080`). That is the TASK-036 client convention
(`wss://HOST` → `https://HOST/token`). The FastAPI app's route is `POST /token`,
so the public URL and the process URL are the same path.

## Postgres (TASK-084 / Technical §9)

`postgres:16.10-alpine` is in this compose. It binds `127.0.0.1:5432` only
(host network). Defaults (override in the VPS `.env`; these use compose
`${VAR:-default}` so `.env.example` does not have to change):

| Variable | Default |
|---|---|
| `POSTGRES_USER` | `keryx` |
| `POSTGRES_PASSWORD` | `REPLACE_ME_POSTGRES_PASSWORD` |
| `POSTGRES_DB` | `keryx` |

token-svc (still **not** a compose service) must receive:

```
DATABASE_URL=postgresql+psycopg://keryx:REPLACE_ME_POSTGRES_PASSWORD@127.0.0.1:5432/keryx
REDIS_URL=redis://127.0.0.1:6379/0
KERYX_SIGNING_WINDOW_S=120
```

Migrate before serving `/v2/`:

```bash
cd ../token-svc
DATABASE_URL=postgresql+psycopg://keryx:REPLACE_ME_POSTGRES_PASSWORD@127.0.0.1:5432/keryx \
  alembic upgrade head
```

Nightly backups: `token-svc/scripts/pg_dump_nightly.sh` — `pg_dump` to
`/var/backups/keryx`, keep 7 copies. Install as a cron job on the VPS
(`15 3 * * *`). The database is small by design (V2-NFR-007).

Caddy's `/token` matcher does not yet include `/v2/` (Caddyfile is outside
this task). Until a successor widens the matcher, bind token-svc on
loopback and front `/v2/` the same way as `/token` (`path /token /token/* /v2 /v2/*`).

token-svc is **not** a compose service. Run it next to this stack, sharing
`LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET` with `.env`:

```bash
# on the VPS, loopback-only so WAN cannot hit :8080
docker build -t keryx-token-svc ../token-svc
docker run -d --name keryx-token-svc --restart unless-stopped \
  -p 127.0.0.1:8080:8080 --env-file ../token-svc/.env keryx-token-svc
```

Do not add it to `docker-compose.yml` — host-network LiveKit/Caddy already
reach loopback, and WAN exposure of `:8080` is a HARDENING miss.

`LIVEKIT_KEYS` in compose is `"${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}"`
(space after the colon). LiveKit 1.9.11 exits with `Could not parse keys`
if the space is missing — that was a real bring-up bug, not a docs miss.

## What localhost cannot prove

This compose uses `network_mode: host` (WebRTC UDP) and Caddy ACME for a real
`DOMAIN`. A developer laptop therefore **cannot** stand in for a VPS:

| Thing | Localhost | Real VPS |
|---|---|---|
| `docker compose config` + unit tests | yes | yes |
| LiveKit signaling on `:7880` | yes inside the host-network namespace. Docker Desktop: that namespace is the Linux VM, **not** Windows localhost | yes |
| Caddy TLS 1.3 + Let's Encrypt | **no** — ACME will not issue for `localhost` / `127.0.0.1` | yes, after `DOMAIN` A/AAAA points at the VPS and :80/:443 are open |
| TURN against a hostile NAT (NFR-05) | **no** — coturn `external-ip=127.0.0.1` and `denied-peer-ip` covers RFC1918 | yes, with `EXTERNAL_IP` = public IPv4 |
| `https://DOMAIN/token` | **no** (no cert). Use `Caddyfile.local` on `:8880` as an HTTP stand-in | yes |

Local bring-up (Windows/Docker Desktop included) therefore starts **redis +
livekit + coturn only**, runs token-svc on loopback `:8080`, and proves the
Caddy `/token` matcher with `Caddyfile.local`. That is a documentation gap
being closed, not a production compose change.

```powershell
python scripts\gen_local_env.py
python scripts\render_config.py --env .env
docker compose --env-file .env up -d redis livekit coturn
# token-svc shares the VM loopback with LiveKit (Docker Desktop host-network).
docker build -t keryx-token-svc ..\token-svc
docker run -d --name keryx-token-svc --network host --env-file ..\token-svc\.env keryx-token-svc
# e2e must also use --network host — Windows curl to :7880 will fail
docker run --rm --network host --env-file ..\token-svc\.env `
  -v ${PWD}\scripts\e2e_linked_proof.py:/e2e.py:ro `
  keryx-token-svc python /e2e.py --rate-limit
```

Optional HTTP edge (proves Caddy `/token` reaches token-svc without ACME):

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
