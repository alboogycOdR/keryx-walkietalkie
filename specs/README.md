# specs/ — Specification Documents

Drop your specification documents here (Markdown preferred). Builders treat this
directory as **read-only**; only ORCH may edit specs, and only to resolve
ambiguities, with a versioned changelog note at the top of the edited spec:

```
> **Changelog:** v1.1 (2026-07-12, ORCH) — clarified §3.4 refresh-token rotation per TASK-000 SPEC_AMBIGUITY block.
```

Each spec should carry a stable filename (referenced by PLAN.md `Spec_References`)
and section numbers (referenced by `Acceptance_Criteria`).

Current specs:

| File | Role |
|---|---|
| `KERYX_Product_Technical_Spec_v1.1.md` | Phase 1 product + architecture (TS) |
| `KERYX_UI_Design_Specification_v1.0.md` | Face tokens, states, copy voice (DS) |
| `keryx-face-prototype.html` | Interactive face prototype (PT) |
| `KERYX_World_Band_Radio_Spec_v1.0.md` | Phase 2 World Band — internet broadcast listen, traced from PocketClaw |

## Proposed Mobile UX Redesign v1.0

The following proposed successor specifications require owner approval and an ADR
before implementation. See `docs/adr/ADR-001-mobile-ux-redesign-reconciliation.md`
(drafted, status: Proposed, pending owner decision) for the conflict analysis
against the existing product and UI specs above.

| File | Role |
|---|---|
| `KERYX_Mobile_UX_Redesign_PRD_v1.0.md` | Mobile UX Redesign — Product Requirements |
| `KERYX_Mobile_UX_Redesign_Design_v1.0.md` | Mobile UX Redesign — Design & Interaction Spec |
| `KERYX_Mobile_UX_Redesign_Technical_v1.0.md` | Mobile UX Redesign — Technical & Migration Spec |
| `KERYX_Mobile_UX_Redesign_Verification_v1.0.md` | Mobile UX Redesign — Verification & Acceptance Plan |
| `KERYX_Mobile_UX_Redesign_Intake_v1.0.md` | Mobile UX Redesign — handover/intake context (historical, not normative) |

**The existing product and UI specifications above remain authoritative outside
the explicitly approved successor scope.** Until ADR-001 is accepted by the
project owner, no builder or ORCH task may cite the Mobile UX Redesign docs as
grounds to deviate from `KERYX_Product_Technical_Spec_v1.1.md` or
`KERYX_UI_Design_Specification_v1.0.md`.
