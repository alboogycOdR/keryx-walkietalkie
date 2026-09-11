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
