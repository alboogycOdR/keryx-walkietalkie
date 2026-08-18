# TASK-002 — Relay stack: LiveKit + Redis + Caddy + coturn Docker compose (KRX-050)

## Brief
Build the self-hosted relay deployment under `relay/`: one Docker compose stack (LiveKit SFU, Redis, Caddy TLS, coturn) sized for a single VPS, with config files, env templating, a runbook, and a hardening checklist. Nothing app-side; no live VPS needed — validation is `docker compose config` plus optional local bring-up.

## Spec pointers
- TS §8.1 Relay row: "**Self-hosted LiveKit** (single Docker compose: LiveKit + Redis + Caddy TLS + coturn) on one VPS (clawsrv-class, 4 vCPU/8 GB starts fine)".
- TS §8.4: "TURN (coturn) bundled for hostile NATs; target ≥ 97% connection success."
- TS §9 NFR-09: "1 VPS serves ≥ 500 concurrent channel-joins; scale-out documented."
- TS §11 KRX-050: "Relay deployment: LiveKit + Redis + coturn + Caddy compose; hardening checklist."
- TS §8.7: transport is TLS 1.3 to the relay; no voice ever recorded server-side — reflect in config (no egress/recording services enabled).

## Intended approach
1. `relay/docker-compose.yml` with pinned image versions; services: livekit, redis, caddy, coturn. Host-network or explicit UDP port ranges for RTC (document the range).
2. `relay/livekit.yaml` (keys from env, Redis wired, TURN pointed at coturn), `relay/Caddyfile` (TLS + reverse proxy to LiveKit ws/http; reserve a route for token-svc at `/token` — wiring lands later, do not create token-svc files), `relay/turnserver.conf`.
3. `relay/.env.example` documenting every variable (DOMAIN, LIVEKIT_API_KEY/SECRET, TURN creds...). No real secrets committed.
4. `relay/README.md`: bring-up runbook, firewall/port table, scale-out section (multi-node LiveKit + Redis per NFR-09).
5. `relay/HARDENING.md` checklist: TLS 1.3, non-root containers, ufw rules, fail2ban/rate limits, key rotation, no logs of media, auto-updates.
6. Evidence: `docker compose config` output; if Docker available, `docker compose up` smoke + `curl` LiveKit health.

## Work Log
