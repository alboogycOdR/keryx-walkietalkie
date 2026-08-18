# Floor-control runtime (KRX-041 / 042 / 043)

Engine for TS §8.3 step 4 and §8.6. Protocol codec stays in
`lib/core/protocol/` (frozen). This package never writes `RadioState`;
it emits `DispatchRadio` effects the host feeds to `RadioReducer`.

## Roles

| Piece | Job |
|---|---|
| `Arbiter` | Pure election (`min(peerId)`) and grant/deny |
| `FloorEngine` | Per-channel runtime: PTT, retries, TOT, lease, EMG |
| `FloorClock` / `VirtualClock` | Injected time so tests do not sleep |
| `FloorTransport` / `LoopbackHub` | Injected fan-out (data channel later) |
| `FloorEffect` | Grant tone, deny buzz, TOT, EMG pin, reducer events |

## Decisions (spec-silent, pinned here)

- **Busy lockout is local.** If `busyLockout` is on (default) and a remote
  peer holds the floor, PTT emits `DenyBuzz(LOCKOUT)` and never sends
  `TX_REQ`. The arbiter still denies a held floor with `BUSY` — one
  voice at a time (P5). Emergency (`prio=1`) skips lockout and pre-empts
  the live lease.
- **Idempotent re-grant** keeps the remaining lease. A retry cannot
  extend TOT.
- **Re-election is immediate** on `updateRoster`. The ≤ 500 ms bound is
  the time until the new arbiter answers `TX_REQ` (requesters retry
  every 150 ms).
- **Lease expiry** frees a crashed speaker without a `TX_END`. TOT cut
  at T=0 is the live speaker's own timer and fires 2 s before lease end.
- **`TX_REQ` retry:** send at t=0, 150, 300 ms; give up 150 ms after the
  third unanswered send (3 attempts, 150 ms spacing).

TOT is 30–120 s inclusive (FR-023), default 60 s. Lease = TOT + 2 s.
