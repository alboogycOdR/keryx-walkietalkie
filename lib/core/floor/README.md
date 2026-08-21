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
- **Late-joiner join guard (TASK-031 / §8.6 option A).** A peer must not
  self-grant until `FloorTiming.presenceHeartbeat` (5 s) has elapsed
  since engine construction, unless it is alone or was the first
  occupant (others appeared only after that same 5 s of being the sole
  roster member), or when every other rostered peer has advertised an
  idle floor via `PRESENCE` (direct idle proof — a simultaneous join).
  The elapsed-time gate cannot be satisfied by a burst of `PRESENCE`
  from a *subset* of peers: the missing witness is the live holder,
  who advertises `holder` rather than idle. During the window a local
  `TX_REQ` resolves to `TX_DENY(BUSY)`. Granting a remote requester is
  unchanged so a freshly formed channel can still take its first PTT
  synchronously; late joiners learn a live lease via inbound
  `PRESENCE.holder` and then the existing decide() path BUSY-denies
  (or emergency-pre-empts after the guard). Outgoing `PRESENCE`
  carries live `holder` / `lease_remaining_ms` (omitted when idle),
  populated at send time from `_liveHolder`, not a snapshot cache.
  Inbound `PRESENCE` with a holder is adopted so a late joiner learns
  the lease; idle `PRESENCE` is honoured only from the current holder.
  Constructor `callsign` is optional and defaults to `localPeerId` so
  existing hosts do not need a territory-crossing change.

TOT is 30–120 s inclusive (FR-023), default 60 s. Lease = TOT + 2 s.
