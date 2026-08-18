# TASK-006 — Floor control protocol v1: codec, versioning, timing constants (KRX-040)

## Brief
The wire layer of the floor-control protocol in `lib/core/protocol/`: typed Dart models + JSON codec for the ten §8.6 messages, protocol-version tagging with forward compatibility, and the locked timing constants as a single exported module. Transport-agnostic — LOCAL data channels (TASK-021) and LiveKit data messages (TASK-024) both consume it; the runtime engine is TASK-022.

## Spec pointers
- TS §8.6 message table: `TX_REQ {peer, prio, ts}` (prio 0 normal / 1 emergency), `TX_GRANT {peer, lease_ms}`, `TX_DENY {peer, reason BUSY|LOCKOUT}`, `TX_START`/`TX_END {peer}`, `PRESENCE {peer, cs, seq}` (5 s heartbeat, 3 misses = departed), `RCHK`/`RCHK_ACK {peer, quality}`, `EMG`/`EMG_CLR {peer}`.
- "JSON over data channels; protobuf reserved for v2." · "All messages carry protocol version; unknown versions are ignored (forward compatibility)."
- Locked timing constants: heartbeat 5 s / 3 missed (15 s); grant lease TOT + 2 s (default 62 s); arbiter re-election settle ≤ 500 ms; TX_REQ retry 150 ms / 3 attempts; floor-idle debounce 750 ms. "asserted by the KRX-044 simulation harness".

## Intended approach
1. `messages.dart`: sealed class `FloorMessage` with one subtype per §8.6 row, exact field names from the table (`peer`, `prio`, `ts`, `lease_ms`, `reason`, `cs`, `seq`, `quality`).
2. `codec.dart`: `encode(FloorMessage) → String` / `decode(String) → FloorMessage?` — envelope `{v: 1, t: "TX_REQ", ...fields}`; unknown `v` or `t` → null (ignored), malformed JSON → null, never throws across the wire boundary.
3. `timing.dart`: `FloorTiming` const class with the five locked constants, documented with the spec table.
4. Tests: round-trip every message type, golden JSON strings (freeze the wire format), unknown-version/unknown-type ignored, malformed input, timing constant assertions.

## Work Log
