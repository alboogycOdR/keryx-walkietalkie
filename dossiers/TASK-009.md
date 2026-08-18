# TASK-009 — Identity: peerId derivation + NATO callsign generator (KRX-075 + §8.6 identity)

## Brief
Device identity in `lib/core/identity/`: install UUID → normative peerId, NATO-phonetic callsign generation/editing, and per-channel collision-suffix rendering as a pure function. peerId is the sole arbiter-election input (TASK-020/022 consume it); callsigns are display-only.

## Spec pointers
- TS §8.6 Peer identity (normative): "`peerId = base32( SHA-256(installUUID) )[:10]` — a stable, device-derived ID generated once at install, independent of the user-editable callsign. It is the sole input to arbiter election (lexicographic minimum)… Callsigns are display-only; on a callsign collision within a channel, later joiners render with a numeric suffix (`BRAVO-7`, `BRAVO-7 (2)`) derived from join order — the underlying peerIds never collide."
- FR-068: "auto-generated NATO-phonetic callsigns on first run (e.g. `BRAVO-7`, `SIERRA-19`), editable, 2–12 chars. No accounts, no uniqueness enforcement beyond per-channel collision suffixing."

## Intended approach
1. `install_identity.dart`: generate UUID v4 once, persist via its own tiny storage adapter (flutter_secure_storage key, injected store interface for tests — do NOT import TASK-008's repository; disjoint territory).
2. `peer_id.dart`: `base32(sha256(installUuidBytes))[:10]` using `crypto` — same base32 convention as TASK-007 (unpadded RFC 4648 lowercase; coordinate via code comment, not shared code, to keep territories disjoint — ORCH will reconcile at review if they drift).
3. `callsign.dart`: generator picks NATO word + 1–2 digit number; validator 2–12 chars; editable value object.
4. `collision.dart`: pure `displayNames(List<(peerId, callsign)> byJoinOrder) → Map<peerId, String>` implementing the "(2)" suffixing.
5. Property tests: peerId stable/deterministic, 10 chars, distribution sanity across random UUIDs; collision suffix ordering; validation edges.

## Work Log
