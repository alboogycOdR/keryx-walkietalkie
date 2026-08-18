# Floor-control protocol v1 (KRX-040)

Wire layer for TS §8.6. JSON over data channels; protobuf is reserved for v2.
Transports (LOCAL WebRTC data channels, LiveKit data messages) plug in later.

## Envelope

```json
{"v":1,"t":"TX_REQ","peer":"J7K2M9Q4PX","prio":0,"ts":1710000000000}
```

| Key | Meaning |
|---|---|
| `v` | Protocol version. v1 is `1`. Unknown versions are ignored. |
| `t` | Message type token from the §8.6 table. Unknown types are ignored. |
| remaining | Type-specific fields, names exactly as in the spec table. |

`FloorCodec.decode` never throws: malformed JSON, wrong types, missing fields,
unknown `v`, and unknown `t` all return `null` (ignore). Extra fields on a
known v1 message are ignored (forward compatible within v1).

## Message types

| `t` | Fields | Notes |
|---|---|---|
| `TX_REQ` | `peer`, `prio`, `ts` | `prio` 0 normal / 1 emergency |
| `TX_GRANT` | `peer`, `lease_ms` | lease = TOT + 2 s (default 62000) |
| `TX_DENY` | `peer`, `reason` | `BUSY` or `LOCKOUT` only |
| `TX_START` / `TX_END` | `peer` | speaker announce |
| `PRESENCE` | `peer`, `cs`, `seq` | 5 s heartbeat; 3 misses = departed |
| `RCHK` / `RCHK_ACK` | `peer`, `quality` | `quality` is S-meter 1–9 (FR-066 / §8.9) |
| `EMG` / `EMG_CLR` | `peer` | priority pin (FR-025) |

`ts` is Unix epoch milliseconds. `peer` is the §8.6 `peerId`. `cs` is the
display callsign (not used in election).

## Timing (`FloorTiming`)

Locked table from TS §8.6 — asserted by tests here and by KRX-044 later.

| Constant | Value |
|---|---|
| Presence heartbeat / departure | 5 s / 3 missed (15 s) |
| Grant lease | TOT + 2 s (default 62 s) |
| Arbiter re-election settle | ≤ 500 ms |
| `TX_REQ` retry / give-up | 150 ms / 3 attempts |
| Floor-idle debounce | 750 ms |
