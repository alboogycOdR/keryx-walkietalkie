# TASK-028 — Theme material tokens + faceplate seam (theme successor, follow-up (q))

## Brief
Successor to TASK-005 (010→011 pattern): reopen the now-frozen
`lib/core/theme/**` to add the material tokens TASK-005 could not ship (they
were never in the prototype's `:root` block, so the token-only pass had nothing
to abstract) and to introduce the faceplate seam DS §8 requires. TASK-012 was
forced to hardcode the glass chrome because the frozen theme exposes no token
for it; this task adds those tokens and the runtime-swappable seam so faceplates
(FR-101) become possible without a cross-cutting refactor of six frozen
territories. **ADD-only: every existing TASK-005 value is preserved byte-for-byte.**

## Spec pointers
- PT `.glass` L51-58 (inline, never in `:root`): `box-shadow: inset 0 3px 10px
  rgba(0,0,0,.85), 0 1px 0 rgba(255,255,255,.05); border: 1px solid #0a0f0c;`
  plus the `::after` backlight-bloom transparent stop — the exact values
  TASK-012 hardcoded (`Color(0xFF0A0F0C)`, `Color.fromRGBO(0,0,0,0.85)`,
  `Color.fromRGBO(255,255,255,0.05)`, `Colors.transparent`).
- DS §4 (L92): "Housing = `--shell-700` with a 2–3% monochrome noise overlay
  (moulded texture) … No gradients longer than 20% of an element's height."
- DS §4 (L98): "Pressed keys move 1 dp down, lose their top highlight, and gain
  an inner shadow — the same three changes on every control." (also TS §6.4)
- DS §3 (L82): "Interface (panels) `Inter`, 400/600" — the 600 axis/style that
  is currently synthesised (carried from TASK-001 follow-up 4, TASK-005
  follow-up 5).
- DS §8 (L134): "Faceplates may change materials and hue but **never** layout,
  contrast ratios, or control positions." + FR-101 (packs are "Pure cosmetics,
  zero layout changes"), KRX-018 amended (golden tests on every shipped
  faceplate), KRX-096 (per-faceplate contrast validation in CI) — the seam.
- DS §9 KRX-010 amendment: "the tests are the design reviewer."
- Prior art (NOT spec): TASK-005 Review_Findings follow-ups 1–4 (key travel,
  noise, gradient, faceplate seam) and TASK-012 Review_Findings (the hardcoded
  `.glass` chrome, and why it was unavoidable in a frozen theme).

## Intended approach
1. Add glass-recess chrome tokens (border, inner shadow, highlight, bloom stop)
   from PT `.glass` L51-58 — the values TASK-012 hardcoded.
2. Add `keyTravel = 1` (dp), the 2–3% noise-overlay opacity token, and the
   20%-max-gradient constant.
3. Add a real Inter 600 text style / `FontVariation` axis entry.
4. Introduce the faceplate seam: make hue/material tokens swappable at runtime
   (e.g. an injectable `FacePlate`/token-set behind the existing facade)
   WITHOUT moving layout — `FaceAllocation` stays a grouped instance class. The
   default "Field Black" plate must reproduce every current TASK-005 value.
5. Tests: assert every NEW token against its spec/PT number, and add a guard
   test that pins every EXISTING TASK-005 value unchanged (byte-for-byte) so a
   regression that would break TASK-012 fails loudly.
6. NOTE only (do not own): TASK-012's widget refactor onto these tokens is a
   separate re-open task (or folded into TASK-017); `lib/features/display/**`
   is frozen and outside this territory.

## Work Log
