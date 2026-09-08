# TASK-052 — Wire Wave 4 screens into the mobile app shell

## Brief

ORCH-created 2026-09-07 after TASK-049's review surfaced a real planning gap:
TASK-048 built the persistent shell with placeholder screen bodies and froze
`lib/app_shell/**` on merge, so none of the seven Wave 4 screen tasks
(TASK-049/050/051/053/054/055/056) — each correctly scoped to its own
`lib/features/<name>/**` — could ever mount its own real widget. This is the
single-owner convergence task that swaps every placeholder for the real
screen, mirroring the TASK-032/033→035→037 and TASK-041/042→043 pattern
already used twice in this plan. Do not touch `lib/features/**` — findings
there belong to that screen's own task record.

## Spec pointers

- `docs/adr/ADR-001-mobile-ux-redesign-reconciliation.md` §6 — the shell
  mounts real screens, owns no screen content itself.
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §2-§4 — persistent host
  survives navigation; navigation-shaped operations must not retune/dispose.
- `specs/KERYX_Mobile_UX_Redesign_PRD_v1.0.md` UX-D01/UX-D02 — Channels
  default landing, Channels+Settings required destinations.
- TASK-048's own dossier/Review_Findings — the branch-preservation test
  pattern (Talk pushed → Settings → back → Talk still on stack) to extend
  across all seven real screens, not just placeholders.

## Intended approach

1. Read each of TASK-049/050/051/053/054/055/056's final merged widget entry
   points (their dossiers' Artifacts sections name the top-level widget).
2. In `lib/app_shell/**` only, replace each placeholder screen reference with
   the real widget, wiring through whatever constructor parameters the real
   screen needs from `RadioViewState`/`RadioViewIntents`/`RadioHost`.
3. Extend TASK-048's branch-preservation `IndexedStack` test to push/pop
   through the real screens.
4. Re-verify (don't re-litigate) that no screen mounted here reaches past
   `RadioViewIntents`/`RadioHost` into transport/floor/audio/platform APIs —
   each screen's own review already checked this in isolation.
5. Full suite + analyze + debug APK build before `needs_review`.

## Work Log
