# TASK-092 — v2 Talk — target card, audience-aware ready ring, honest lone-press refusal, status control, Alert banner

## Brief

Rework the Talk screen for v2 targets. `TalkChannelCard` → `TalkTargetCard`: avatar/glyph, name, presence line (`Ben · Available · Nearby` / `Site crew · 4 of 12 online`), own-status control (Available/Busy/DND/appear offline) on the right, chevron → `onOpenTarget`. No-target state replaces the ring with the 'Add your first contact / Create a group' card. Ring ready rule from `RadioViewState.audience` (V2-FR-041); a press with `canHear == 0` is refused locally, never calls `press()`, and reuses the TASK-082 flash with the audience reason as copy (V2-FR-044). Alert-received banner (10 s, Reply). Remove every channel/route string. All VT-010..015 safety logic stays untouched.

## Spec pointers

- specs/KERYX_v2.0_Design_v1.0.md §2.1, §4; PRD V2-FR-040..045, V2-FR-033; Verification V2-VT-022 (UI half), V2-VT-024, V2-VT-030 (talk goldens); ADR-002 A3/A7 (ring and flash carried)
- Owned_Paths: lib/features/talk/**, test/features/talk/**, test/regression/goldens/goldens/talk_*.png, test/regression/goldens/talk_states_golden_test.dart, dossiers/TASK-092.md
- Depends_On: TASK-088

## Work Log
