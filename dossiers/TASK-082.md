# TASK-082 — Owner review fixes: denied flash, deny copy, PTT centring

## Brief

The owner installed the R2 review APK on one phone, with no second phone.
Pressing PTT is refused, and the ring then stays grey with "Channel busy"
forever, because `isTransmitDenied` only clears on the next radio event, which
never comes when you are alone. Make the flash transient (~1.5 s back to Ready),
say "No other stations on this channel" when the roster is known to be empty,
and centre the PTT vertically. Talk presentation layer only; `lib/core/**` stays frozen.

## Spec pointers

- docs/adr/ADR-002-zello-aligned-talk-first-ui.md §3 A7 (this task's owner decisions), A2, A3
- specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md §4 (Denied/busy = transient; flash never overrides TX), §5 copy
- lib/core/state/radio_state.dart `_clearTransientDenied` (why it sticks)
- lib/core/floor/floor_engine.dart deny paths; lib/core/floor/arbiter.dart `maySelfGrant` (for the dossier diagnosis)
- Owner screenshots 2026-09-11 17:35 (yellow Ready) / 17:36 (grey + "Channel busy" after release)

## Approach

1. Track the deniedFlash rising edge in `_TalkScreenState`, and hold a `Timer(1500 ms)` that sets an `_flashExpired` flag.
2. Treatment and cue use `deniedFlash && !_flashExpired`. Reset the flag on each new rising edge; cancel the timer in dispose.
3. Override the cue label and status with `TalkCopy.noOtherStationsOnChannel` when `rosterCount` is `KnownRosterCount(0)`.
4. Layout: keep the top group; the bottom group goes in an `Expanded` → `Center` within the existing scroll fallback.
5. Tests: expiry with fake time, re-flash, TX precedence, both copies, a centring geometry test, small-phone/landscape reachability.
6. Diagnose the solo-refusal path and record it here.

## Work Log

- [2026-09-11T16:20:00Z] [GB] Implemented on `task/TASK-082-gb`. Presentation-only: 1500 ms `_deniedFlashTimer` on `isTransmitDenied` rising edge; expired flash treats ring as Ready and hides the cue with no further radio event. `TalkCopy.channelBusy` / `noOtherStationsOnChannel`; overlay + status use the empty-LOCAL copy when `KnownRosterCount(0)`, else "Channel busy". PTT centred via `_TalkBody` (two-child render object) inside the existing LayoutBuilder/scroll fallback — SliverFillRemaining rejected because `TalkPttRing`'s LayoutBuilder cannot report intrinsics. Goldens regenerated: all `talk_*.png` + `shell_frame_{dark,light}.png`. layout_matrix 360×640 @ 1.0 now asserts remaining-space centring.

### Solo-press diagnosis (no floor change)

Production `RadioSessionController._publishRoster` runs only on peer join/leave, **not** at session start with `{self}`. Until a second station is discovered, `FloorEngine.updateRoster` is never called.

A solo PTT therefore hits **join-guard `_denyBusy(FloorDenyReason.busy)`**, not lockout and not TX_REQ give-up:

1. `requestTransmit` (`floor_engine.dart`): no remote holder, so not the lockout shortcut. Local peer is the only roster member → `isLocalArbiter` → `_arbitrate`.
2. `_inJoinGuardWindow` is true because `_linkPaused` is true (`_lastInboundAt == null` — nobody else emits PRESENCE).
3. `_hasDirectIdleProof` is false: `_rosterConverged` requires `updateRoster` (or the construction instant). Constructor `{self}` is not aloneness proof (TASK-031).
4. `_arbitrate` first branch: `_inJoinGuardWindow && _liveHolder == null && !_hasDirectIdleProof` → `_denyBusy` → `TransmitDenied` + `DenyBuzz(busy)`.

`Arbiter.maySelfGrant` would allow a solo grant when `rosterSize <= 1 && rosterConverged`, or after `FloorTiming.presenceHeartbeat` (5 s) of **reachable** observation, or `firstOccupant`. In production-alone none of those fire: the host never declares a solo roster, `_linkPaused` stays true forever with no inbound, and `firstOccupant` is only set when someone else appears after a full heartbeat of being alone. So a station that is genuinely alone cannot self-grant until another peer is seen (or a successor task has the host call `updateRoster({localPeerId})` at boot). ORCH's call whether that floor policy needs a successor.

layout_matrix: added the 360×640 @ 1.0 remaining-mid assertion only; other matrix rows unchanged.
