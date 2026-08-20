# Rotary tuning knob (KRX-011)

The hero interaction (TS D1): a 96 dp knurled knob with arc-drag detent
tuning, flywheel fling, and per-detent haptic/tick/LCD hooks firing in the
same frame (TS §6.2).

## Contract

`KeryxTuningKnob` is presentation + intent only. It never touches
`RadioReducer` or dispatches `TuneTo` itself:

- `channel` — the host's current absolute channel, read only to clamp
  deltas at the 1/99 boundary.
- `onDetent(int delta)` — fired once per resolved detent crossing. The
  caller (a future TASK-017-class assembly) is responsible for turning
  `delta` into `TuneTo(channel: current + delta, ...)` against the
  reducer, plus the tick-sound and LCD-update halves of TS §6.2's
  same-frame contract. This widget fires the haptic half itself
  (`knob_feedback.dart`) — see below.

No `tuneDelta` reducer event exists (TASK-004/027's reducer only exposes
absolute `TuneTo`), so this widget resolves and clamps deltas locally
rather than depending on one. See `knob_physics.dart`'s library dartdoc for
the full ORCH ruling this implements (clamp, not wrap, at 99/1 and 38/00).

## Physics

- **Detents:** 30° per channel, matching PT's arc-drag script
  (`specs/keryx-face-prototype.html` L286-323).
- **Fling:** exponential friction decay (`velocity *= 0.94` per frame,
  clamped to `±22`°/frame, "not a spring preset" per DS §4), governed to
  never exceed TS §6.2's normative 12 ch/s tick rate — see
  `KnobFlywheel`'s dartdoc for why this is an explicit governor rather than
  relying on PT's velocity clamp alone.
- **Settle:** rest angle always snaps to the nearest detent multiple.

## Haptics

`KnobHapticFeedback.click()` approximates TS §6.4's `PRIMITIVE_CLICK (scale
0.6)` via `package:vibration` (8 ms pulse, amplitude 153/255 where
amplitude control exists; bare duration pulse otherwise). Fired
synchronously from the same callback that invokes `onDetent`, so haptic +
caller hooks are initiated in the same frame. Tests should inject
`onHapticClick` to avoid depending on a real platform vibrator channel;
production leaves it unset (defaults to `KnobHapticFeedback.click`).

## Visuals

96 dp knurled body (`KeryxTheme.shell500`, 36 knurl marks) with an olive
(`KeryxTheme.olive`) indicator line rotating with the knob angle, per DS
§5.1.
