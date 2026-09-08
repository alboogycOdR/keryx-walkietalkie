# TASK-069 — Keyboard/switch access for Radio Controls' hold targets

## Brief

ORCH-created 2026-09-08, an accepted-not-fixed finding from TASK-057's
review: Monitor's hold-to-open and Emergency's 600ms hold-to-arm are both
pointer-only gestures with no keyboard/switch equivalent. This needs its own
explicit decision — not a copy of Talk's latch-release button — because
Emergency's accidental-activation guard must not be weakened by whatever
keyboard analog is chosen.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §5 — functional floor
  (names TX-latch release explicitly, silent on Monitor/Emergency
  specifically — this task fills that silence with a documented decision).
  Also: "Provide a switch-accessible alternative to mechanical hold where
  the chosen behavior is safe and explicit."
- PRD UX-FR-042 — "Emergency is visually distinct, explicitly labeled and
  protected against accidental initiation."
- TASK-057's Review_Findings — the accepted finding this task closes.
- TASK-054's existing pointer-based Emergency tests (600ms hold, early-release
  safety) — must stay green, unchanged, for pointer input.

## Keyboard/switch decision (written before any production change)

This section is the acceptance-criterion-1 artifact. It is the decision;
implementation follows it, it is not reverse-documented from code.

### Why Talk's latch-release button is rejected for Emergency

Talk's `TalkPttToggleAlternative` is a single-press Material
`OutlinedButton`: one Activate starts (or latches) TX, one Activate
releases it. That is the sanctioned non-drag alternative for ordinary PTT
(Design §2.2). Copying it onto Emergency would let a single accidental
Space / Enter / switch-press pin emergency — strictly weaker than the
600 ms pointer hold UX-FR-042 exists to preserve. TASK-069's Description
forbids that copy.

A keyboard "hold Space for 600 ms" analog is also rejected as the *only*
path: keyboards can hold a key, but switch devices emit discrete Activate
pulses. Design §5 requires the alternative to be switch-accessible.

### Monitor — explicit latch (hold-substitute); pointer hold unchanged

Monitor's hold-to-open is a hardware-squelch analog, **not** an
accidental-activation safety property. TASK-054 preserved pointer
hold-to-open and deliberately offered no pointer toggle; that pointer
contract stays.

Switch users cannot hold. The switch-accessible alternative, therefore:

- Keyboard / switch **Activate** on the Monitor hold target **latches**
  monitor open via the same `MonitorChanged(true)` reducer event the
  pointer-down path uses.
- A second Activate closes it (`MonitorChanged(false)`), same event as
  pointer-up.
- Pointer remains hold-to-open: down opens, up / cancel closes.
- Ineligible (TX / tuning / off) remains a no-op on both paths.

This does not weaken any safety guard because Monitor has none. It is a
hold-substitute, not a silent second Monitor mode for pointer users.

### Emergency — confirm-then-arm two-step, same 600 ms budget as pointer

Keyboard / switch Activate must **not** arm on the first press.

1. **First Activate** enters a confirming state. Emergency is not pinned.
   Copy changes to "Press again to arm emergency". A ready-timer starts
   using the **same** `emergencyHoldDuration` (600 ms) constant the
   pointer path uses (`EmgKey.armThreshold`, preserved by TASK-054). A
   5 s abandon-timeout cancels confirm if there is no valid second
   Activate.
2. **Second Activate before the 600 ms ready-timer fires** is a no-op
   (stays confirming). This is the analog of releasing a pointer hold
   early, and it defeats Space-key-repeat: a held key generating
   Activate + repeats inside 600 ms cannot arm.
3. **Second Activate after 600 ms** calls the same `_activateEmergency()`
   path the pointer timer uses (`floorEngine.requestTransmit(emergency:
   true)`). No second engine entry point.
4. Escape / `DismissIntent` / pointer-hold starting / dispose cancels
   confirm without arming.
5. The pointer path is unchanged: 600 ms `Timer`, early release cancels,
   `_emergencyArming` is independent of `_keyboardConfirming`. Keyboard
   confirm never sets the pointer-arming flag, so TASK-054's existing
   pointer tests keep their original meaning.

**Why this does not undermine UX-FR-042:** emergency still cannot pin
faster than 600 ms from the first intentional activation — the same
accidental-initiation budget as a pointer hold. A single Activate (the
analog of a tap) never pins. Talk's single-press toggle is not used.

Clear is already a Material `FilledButton` (`emergencyClear`); keyboard /
switch Activate already works there. This task adds a regression test for
that path, not a new widget.

### Implementation shape (follows the decision above)

Wrap each hold target in `FocusableActionDetector` (Enter / Space →
`ActivateIntent`, Escape → `DismissIntent`) plus `Semantics.onTap` so
TalkBack / switch tap reaches the same handler. Pointer continues to use
`Listener` `onPointerDown` / `Up` / `Cancel` exclusively — Semantics
`onTap` is an accessibility action, not a competing gesture recognizer.

## Work Log

- [2026-09-08T15:02:00Z] [GB] Decision recorded above *before* any
  production edit. Next: preflight is already run; implement the two
  paths against this decision, leave TASK-054 pointer tests untouched.
