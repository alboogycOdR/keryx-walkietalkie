# TASK-076 — UX R2 Stations as a tab body

## Brief

Make `StationsScreen` embeddable under the new shell and polish its rows: initials avatars, honest presence, and a speaking indicator for the active speaker. Additive API only.

## Spec pointers

- docs/adr/ADR-002-zello-aligned-talk-first-ui.md §3 A1
- specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md §2.4
- lib/features/stations/stations_screen.dart; RadioViewState.activeSpeakerPeerId

## Approach

1. Add `embedded` with the default unchanged.
2. Restyle `_StationRow`.
3. Add the embedded QR action row.
4. Regenerate stations_* goldens.
5. Run the shell tests untouched.

## Work Log

- [2026-09-11T11:00:00Z] [S5] Claimed. Preflight confirmed all Owned_Paths present (see PLAN.md Progress_Note). Branch task/TASK-076-s5 from master post-TASK-072 merge.
- [2026-09-11T11:20:00Z] [S5] Implemented `embedded` (default `false`) on `StationsScreen`/`StationsView`: `appBar: null` when embedded, current-channel context line (`StationsScreenKeys.channelContext`) moves to the top of the body, and a new `_EmbeddedQrActions` compact two-button row (`StationsScreenKeys.embeddedActions`, reusing `StationsScreenKeys.scan`/`.export`) replaces the app-bar QR actions. Default mode's widget tree is byte-identical (title stays in the app bar, actions stay in the app bar; no new keys render).
- [2026-09-11T11:35:00Z] [S5] Restyled `_StationRow` (both modes): new `_StationAvatar` (`CircleAvatar` on `tokens.surfaceRaised` with 1–2 letter initials derived from the display name — never the raw peer ID), row min-height raised 48→64dp (`_rowMinHeight`, within the 64–72dp band), and a new `_SpeakingIndicator` (`tokens.stateRx` dot + "Speaking", key `StationsScreenKeys.speaking`) shown only when `station.peerId == view.activeSpeakerPeerId` — wired `RadioViewState.activeSpeakerPeerId` through `StationsView._rosterBody` → `_StationList` → `_StationRow.speaking`. Presence subtitle text unchanged (`StationsCopy.presenceVisible`); the row's Semantics label appends ", speaking" only for the active-speaker row so no existing semantics test broke.
- [2026-09-11T11:45:00Z] [S5] Tests: added `test/features/stations/stations_screen_test.dart` groups "TASK-076 — embedded mode" (2 tests: embedded renders no app bar / context+actions move to body / QR callbacks fire; default mode unchanged) and "TASK-076 — rows: avatar, presence, speaking indicator" (3 tests: avatar+initials+presence render; only the active-speaker row shows the indicator with the right semantics label; no speaker → no indicator anywhere). `pumpStations`/`makeView` extended with `embedded`/`activeSpeakerPeerId` params (both default-preserving, no existing call site touched). All pre-existing 24 stations tests still pass unmodified.
- [2026-09-11T11:50:00Z] [S5] Regenerated `stations_*` goldens via `flutter test --no-pub --update-goldens test/regression/goldens/stations_golden_test.dart`. Only `stations_populated_{dark,light}.png` changed (rows now have avatars + taller cards); `stations_empty_{dark,light}.png` are byte-identical (no rows to change). Confirmed `test/app_shell/**` and `test/regression/real_composition_test.dart` pass with zero edits (27/27).
- [2026-09-11T11:55:00Z] [S5] `flutter analyze --no-pub` repo-wide clean. Full `flutter test --no-pub` run in progress; will append final count before moving to needs_review.
