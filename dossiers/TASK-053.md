# TASK-053 — Stations screen

## Brief

A new full-screen roster over the *same* host station stream TASK-043's
`RosterScreen` used — data source unchanged, widget tree new. Live join/depart
while open, driven by its own subscription rather than a parent rebuild. The
honesty requirements are the substance of the task, not decoration.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.4 — live update without a
  parent rebuild, empty state, current-channel context, QR actions, quality
  omitted or marked unavailable, incomplete LINKED roster stated explicitly
  rather than shown as a verified zero.
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §1 (Roster row), §1.1
  (LOCAL-signaling-backed stream; `signalQuality` placeholder maximum).
- PRD UX-FR-008/026/040/045/046; Verification VT-024.
- ADR-001 §6 — "the live-data SOURCE is unchanged, the widget is".

## Approach

Re-prove the live join/depart guarantee here rather than assuming it carried
over. Neutral fallback for unknown identity, never a peer ID as a verified human
name. Local station count and any LINKED member count are distinct. QR entry
points only — the QR screens are TASK-056's.

## Work Log

- [2026-09-08T09:19:16Z] [GB] Session start. Claimed TASK-053, branch `task/TASK-053-gb` off master `09cc11e`. Preflight: new territory `lib/features/stations/**` and `test/features/stations/**`; dossier exists. Plan: `StationsScreen` Consumer widget over `radioHostProvider` + `radioStateProvider` + `settingsProvider`, projecting `RadioViewState`. Own `RadioHost.changes` subscription so join/depart updates without a parent rebuild (same host station stream `RosterScreen` used; no new data source). Honesty: omit `StationInfo.signalQuality` (never bars); LINKED uses `UnavailableRosterCount` copy "Complete member list unavailable" on a dedicated field, distinct from `Local stations: N`. Unknown identity → "Unknown station"; peer ID never shown. QR Scan/Export are launch callbacks (TASK-056). Tokens via `KeryxUxTokens`. Tests use `FakeRadioHost` — no sockets/plugins. Will not edit `lib/app_shell/**` or `lib/features/face/**`.
- [2026-09-08T09:30:00Z] [GB] Implementation complete. `StationsScreen` ships in `lib/features/stations/**` (ADR-001 §7 item 2). Live join/depart via `host.changes` `setState`. Quality unavailable at screen level; rows never read `signalQuality`. LOCAL vs LINKED counts are separate fields. Empty state is Design §5 copy plus `CH XX · YY` context. Revert-mutation-checked 3 guards: (1) drop live `setState` → live join/depart test Expected ALPHA-1 Found 0; (2) inject `signalQuality`/`generate(9)` into source → source quality test Expected false Actual true; (3) replace LINKED unavailable copy with `0 members` → incomplete LINKED test Found 0 widgets with text containing Complete member list unavailable. All three restored; `setState` still present. `lib/app_shell/**` untouched — TASK-052 mounts this screen. → needs_review.
- [2026-09-08T09:50:15Z] [GB] Resume rework round 1 on `task/TASK-053-gb`. Findings (1)–(6): (1) empty copy + localCount(0) only when RosterCount is Known; Unavailable + empty stations is unknown, not verified-empty. (2) Count text from KnownRosterCount.count, never stations.length. (3) Unavailable label from view.connection.effectiveRoute (AUTO ≠ LINKED). (4) Switch on view.signalQuality (Unavailable copy / Measured S-meter text; never bars). (5) Drop source-grep honesty tests; behavioural StationsView + host/projection tests. (6) host.changes onError clears snapshot and shows stream-unavailable. Next: implement StationsView, rewrite tests, mutation-check, full suite.
- [2026-09-08T10:00:55Z] [GB] Rework complete on `task/TASK-053-gb`. `StationsView` switches on sealed `RosterCount`/`SignalQuality`; empty copy only for Known+empty; incomplete-roster label follows `effectiveRoute`; `host.changes.onError` → "Station list unavailable". Source-grep honesty tests removed (colour-literal scan kept). `flutter test test/features/stations/` 21/21. Full suite 1184/0/40 (+3 vs round-1 1181). Analyze owned: No issues found; repo-wide 8 pre-existing TASK-035. Mutations all RED then restored: (1) ungated empty → LINKED empty finds `stations.empty`; (2) KnownRosterCount→stations.length → `Local stations: 5` Found 0; (3) quality hardcoded unavailable → `Quality: S3` Found 0; (4) label hardcoded LINKED → `AUTO members:…` Found 0; (5) drop onError → ALPHA-1 still present. `lib/app_shell/**` untouched. → needs_review.
