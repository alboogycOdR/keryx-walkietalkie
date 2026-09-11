# TASK-075 — UX R2 Channels as a tab body

## Brief

Make `ChannelsLanding` embeddable under the new shell (no app bar or brand, optional Open Talk, tune-success callback) and polish its rows. Additive API only, so the current shell and its tests keep working until TASK-077 switches over.

## Spec pointers

- docs/adr/ADR-002-zello-aligned-talk-first-ui.md §3 A1
- specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md §2.1, §2.3
- lib/features/channels/channels_landing.dart (AppBar ~L177, Open Talk ~L205)

## Approach

1. Add the optional params with defaults matching today.
2. Restyle rows with the pinned current row and accent bar.
3. Test both modes.
4. Regenerate channels_* goldens.
5. Run test/app_shell and real_composition_test untouched to prove compatibility.

## Work Log
