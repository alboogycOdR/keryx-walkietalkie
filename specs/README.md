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
