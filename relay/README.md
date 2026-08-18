# Keryx relay (KRX-050)

Self-hosted LINKED-mode stack for a single VPS (clawsrv-class, 4 vCPU / 8 GB is
enough to start). One Docker Compose file brings up:

| Service | Role |
|---|---|
| **LiveKit** | SFU. One room per channel. Audio publish/subscribe mirrors PTT. Floor-control messages ride LiveKit data messages (TS §8.4). |
| **Redis** | Ephemeral room/routing state for LiveKit. **No persistence.** |
| **Caddy** | TLS 1.3 on `DOMAIN`, reverse-proxy to LiveKit `:7880`. `/token` reserved for the token service (wired later). |
| **coturn** | TURN for hostile NATs (TS §8.4, NFR-05 ≥ 97% connection success). |

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
| `Caddyfile` | Caddy TLS + `/token` reservation |
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

## Token service

`Caddyfile` reserves `https://DOMAIN/token` and returns **503** until TASK-003
is wired. Do not add a `token-svc` service in this compose — that file tree
belongs to `token-svc/**`.
