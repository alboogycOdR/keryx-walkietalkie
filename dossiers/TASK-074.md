# TASK-074 — UX R2 Talk screen recomposition

## Brief

Replace the Talk header and flat disc with the Zello-style composition: channel card on top, the new ring (TASK-073) in the middle, status text below, and a contextual latch control. All hold/latch/lifecycle safety logic stays exactly as it is; this is presentation only.

## Spec pointers

- docs/adr/ADR-002-zello-aligned-talk-first-ui.md §3 A2, A3, A4
- specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md §2.2, §4, §5
- Verification VT-010–VT-015 — existing tests in test/features/talk/talk_screen_test.dart
- Shared keys used by shell tests: keryx-talk-ptt-disc, keryx-talk-picker, keryx-talk-stations (keep them)

## Approach

1. Map `_DiscTreatment` + phase to the `TalkPttRing` treatment enum.
2. Extract `TalkChannelCard`.
3. Move the status line below the ring.
4. Delete `TalkPttToggleAlternative`/`TalkPttDisc`, and move a11y tests that used the toggle button to the semantics action.
5. Keep the shell tests you own compiling and green without navigation changes.
6. Regenerate talk_* goldens.

## Work Log
