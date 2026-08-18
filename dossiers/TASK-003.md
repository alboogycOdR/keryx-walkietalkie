# TASK-003 — Token service: FastAPI LiveKit JWT mint + rate limiting (KRX-051)

## Brief
Implement the stateless FastAPI token service in `token-svc/`. Clients compute roomId themselves (TS §8.7) and POST roomId + callsign (+ optional event-token) — the service mints a short-lived LiveKit JWT, rate-limits by IP, refuses expired event tokens, and keeps zero user records. Pytest suite includes an explicit logging-policy test.

## Spec pointers
- TS §8.1: "Tiny stateless token service (FastAPI, ~200 LOC): mints LiveKit JWTs from room derivations; no user DB. Keeps 'no accounts' true on LINKED."
- TS §8.4: "token service issues a short-lived LiveKit JWT (identity = callsign + random suffix)".
- FR-044: "Expired tokens are refused by the token service so temporary event channels do not linger on the relay."
- TS §8.7: "token service keeps no user records and **logs nothing beyond ephemeral, IP-scoped rate-limit counters** (no callsigns, no room-join histories; counters expire ≤ 1 h) — asserted by a logging-policy test in KRX-051." Server sees room hashes only, never passphrases.
- R4: "Token-svc rate limits, per-room caps."

## Intended approach
1. `token-svc/app/main.py`: `POST /token {room_id, callsign, event_token?}` → validate shape (room_id = 16-char base32), mint JWT via `livekit-api` (or manual PyJWT with LiveKit claims), TTL ~5 min, identity = `callsign#<random suffix>`.
2. Event tokens: signed payload carrying expiry (format shared with TASK-025 — document it in `token-svc/README.md` as the contract); expired → 403.
3. In-memory IP rate limiter with TTL ≤ 1 h (no Redis dependency; single-process is fine at this scale — note scale path in README).
4. Logging: configure so request logs exclude callsign/room; `tests/test_logging_policy.py` captures log output during a full request cycle and asserts no callsign/roomId appears.
5. `token-svc/Dockerfile`, `requirements.txt`, `README.md` (env: LIVEKIT_API_KEY/SECRET, EVENT_TOKEN_SECRET). Compose wiring belongs to relay/** (not yours).
6. Full pytest suite: mint happy path, bad room_id, expired event token, rate-limit 429, logging policy.

## Work Log
