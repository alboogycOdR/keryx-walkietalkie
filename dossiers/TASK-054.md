# TASK-054 — Radio controls and guarded emergency

## Brief

Secondary radio functions move off the main surface into a labelled controls
screen, replacing the legacy four-key rail's role without reusing its widgets.
Monitor keeps hold-to-open; scan shows authoritative state and eligibility;
locked or unimplemented capabilities explain themselves rather than appearing
enabled. Emergency gets a separate orange/priority treatment with a guarded
activation and an explicit clear, preserving the existing hold duration and
floor semantics exactly.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.5, §4 (Emergency row).
- PRD UX-FR-041/042/043/044, UX-D06; Verification VT-013, §8 (no location or
  emergency-service claims).
- `specs/KERYX_Product_Technical_Spec_v1.1.md` §8.2/§8.6 — arbitration and
  emergency semantics preserved.
- ADR-001 §5 — **FR-025 emergency-preemption double-grant stays PARKED.**

## Approach

Indicators are driven only by authoritative state — test both directions (state
lights it; local interaction alone does not). The intake risk register names this
task as the one most likely to drift into FR-025; if emergency behaviour looks
wrong at the engine level, record a finding and stop. Emergency renders as an
overlay that never conceals the actual floor phase.

## Work Log
