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
