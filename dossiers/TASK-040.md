# TASK-040 — Relay + token-service deployment validation + runbook foundation

## Brief

`relay/**` and `token-svc/**` were built and unit-tested (TASK-002 / TASK-003)
but never stood up together. This task brings the compose stack up, wires
Caddy `/token` to the real FastAPI service (drop the 503 placeholder), proves
a minted JWT is accepted on a real LiveKit join, demonstrates rate limiting,
and creates `ops/TWO_PHONE_TEST.md` for TASK-039 to append the app-side
script.

No Dart. No new compose services.

## Spec pointers

- TS §8.1 / KRX-050: LiveKit + Redis + Caddy TLS + coturn, one VPS.
- TS §8.4 / KRX-051: token service mints short-lived LiveKit JWTs from
  client-derived `roomId`; TURN for NFR-05.
- TS §8.7: no user DB, logs only ephemeral IP-scoped rate-limit counters.
- TASK-036: `wss://HOST` → `https://HOST/token`.

## Intended approach

1. Wire Caddy `reverse_proxy {$TOKEN_SVC_UPSTREAM}` (default `127.0.0.1:8080`).
   Keep token-svc **out** of `docker-compose.yml`.
2. Local bring-up skips Caddy (ACME will not issue for localhost). Prove the
   `/token` matcher with `Caddyfile.local` (HTTP :8880).
3. `e2e_linked_proof.py`: mint → garbage JWT refused → minted JWT `/rtc` 101
   and identity in RoomService `ListParticipants`; `--rate-limit` for 429.
4. Runbook in `ops/` (builders cannot write `docs/**`), structured for
   TASK-039 to append after `<!-- TASK-039 APP-SIDE START -->`.

## Work Log

- [2026-08-22T04:44:20Z] [GB] Claimed on `task/TASK-040-gb`. Preflight: existing
  `relay/**` (11 files) + `token-svc/**` (20 files); `ops/TWO_PHONE_TEST.md`
  NEW (parent `ops/` missing); this dossier NEW.
- [2026-08-22T04:55:00Z] [GB] Caddy `/token` 503 replaced with reverse_proxy
  to `TOKEN_SVC_UPSTREAM`. `Caddyfile.local` added for HTTP proof without ACME.
  `e2e_linked_proof.py` + `gen_local_env.py` + runbook drafted. Next: validate
  scripts, pytest, local compose up, real join evidence.
- [2026-08-22T05:10:00Z] [GB] Local stack up. Two genuine config bugs fixed:
  (1) `LIVEKIT_KEYS` was `key:secret` — LiveKit requires `key: secret` (space)
  or the process exits `Could not parse keys`; (2) `validate.ps1` rendered
  `.env.example` into `generated/` and would clobber a real `.env` render —
  now uses a temp dir. Compose starts redis+livekit+coturn (caddy skipped:
  ACME cannot issue for localhost). Docker Desktop host-network is the Linux
  VM, not Windows localhost. Join proof from `docker run --network host`:
  garbage JWT `/rtc` 401; minted JWT `/rtc` 101; identity in
  `ListParticipants`. Caddyfile.local `:8880/token` minted a second JWT.
  Rate limiter: 28 successes then 429 `rate_limited`. token-svc pytest 23
  passed; relay tests 18/18. No Dart. Ready for needs_review.
- [2026-08-22T05:18:43Z] [GB] REWORK resume on `task/TASK-040-gb` (no re-claim).
  ORCH blocking finding: `validate.ps1`/`.sh` exit 1 because the clobber-fix
  `--out $TEMP` path hits `dest.relative_to(here)` in `render_config.py:97`.
  Preflight (c8b9872) re-run: relay/** 18 files, token-svc/** 35 files,
  ops/TWO_PHONE_TEST.md FILE, dossiers/TASK-040.md FILE. Scope: one display-
  path fallback in render_config.py + a test that actually executes the
  validate script (separate module so the script's own unit-check step
  cannot recurse). No Dart. No re-litigation of the approved join/rate-limit
  /Caddy/runbook work.
- [2026-08-22T05:20:08Z] [GB] Rework landed. `display_write_path` falls back to
  the absolute dest when `relative_to` raises. `validate.ps1` exit 0 and
  `validate.sh` exit 0 (both previously crashed on step 1). Relay tests 19/19
  (new out-of-tree dest subprocess test). `test_validate_gate.py` executes
  the real gate script, 1/1. Mutation: drop the fallback → that test fails
  with the same `is not in the subpath` ValueError ORCH reported; restored.
  token-svc pytest 23 passed. `git diff --name-only -- '*.dart'` empty.
  → needs_review.
