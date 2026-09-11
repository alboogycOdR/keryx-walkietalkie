# TASK-084 — v2 directory service I — Postgres, signed-request auth, identity + contacts + presence WebSocket

## Brief

Grow `token-svc` into the directory service under `/v2/`. Add Postgres 16 to the compose file (named volume, healthcheck, `DATABASE_URL`), SQLAlchemy + Alembic with the §4.1 schema (identities, contact_requests, contacts, blocks, groups, group_members, invites — create all tables now, implement identity/contacts/presence in this task; groups endpoints are TASK-085). Implement Ed25519 signature verification middleware (`X-Keryx-Sig/Key/Ts`, 120 s window, Redis nonce replay set). Endpoints: `POST /v2/identity`, `GET /v2/identity/me`, `PATCH /v2/identity/callsign`, `POST /v2/contacts/requests`, `POST /v2/contacts/requests/{from_pk}:accept|decline|block`, `DELETE /v2/contacts/{pk}`. Presence: `WS /v2/presence` with signed hello, `{status}` messages, 60 s heartbeat, Offline after 5 min, fan-out via Redis pub/sub to contacts (co-members come in TASK-085). Enumerate error codes in `token-svc/README.md`. Extend `PrivacyFilter` so logs carry no keys, callsigns or room IDs. Publish `token-svc/openapi-v2.yaml` (hand-written or generated) as the contract TASK-086 codes against; keep it in sync with the code. Existing `/token` behaviour is unchanged in this task (the membership gate is TASK-085).

## Spec pointers

- specs/KERYX_v2.0_Technical_v1.0.md §3.3 (signature verification), §4.1 (schema), §4.2 (identity/contacts/presence endpoints), §4.3 (presence protocol), §9 (compose, backups); PRD V2-FR-010..014, V2-FR-030..033, V2-NFR-002/003/004/007; Verification V2-VT-010, 013, 016; existing token-svc/app/** (grow, do not replace)
- Owned_Paths: token-svc/**, relay/docker-compose.yml, relay/README.md, dossiers/TASK-084.md
- Depends_On: —

## Work Log

- [2026-09-11T17:45:00Z] [GB] Claimed. Preflight pasted in PLAN.md. Approach: grow token-svc `/v2/` on the existing FastAPI app; SQLite+memory nonce for tests; Postgres 16 in relay compose with `${VAR:-default}` so `.env.example` (out of territory) is untouched; token-svc stays out of compose (relay tests forbid `token-svc:`). Groups tables via Alembic now; group HTTP left to TASK-085. `/token` remains unsigned. Caddyfile is out of territory — README notes the `/v2/` matcher follow-up.
- [2026-09-11T18:20:00Z] [GB] Implementation complete. `python -m pytest` in token-svc: 48 passed. `python relay/tests/test_relay_config.py`: 19/19 OK. V2-VT-010/013/016 covered. Ready for needs_review.

