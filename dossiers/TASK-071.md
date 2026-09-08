# TASK-071 — Clean up the 8 pre-existing TASK-035 analyzer findings

## Brief

ORCH-created 2026-09-09. Eight `flutter analyze` findings, all in
`test/services/session/radio_session_controller_test.dart`, have been
carried as "known, pre-existing, unrelated" through every review since
TASK-035 with no task ever created to fix them. All mechanical, all in one
file. Confirm each is genuinely dead before removing it.

## The 8 findings (as of 2026-09-08)

1. `unused_import` — `package:keryx/services/linked/linked.dart` (line 5)
2. `unused_import` — `package:keryx/services/mesh/mesh.dart` (line 6)
3. `unused_element` — `_characterDspLight` (line 10)
4. `unused_element` — `_dimModeAuto` (line 11)
5. `unused_local_variable` — `settingsAuto` (line 21)
6. `unused_local_variable` — `settingsLinked` (line 22)
7. `no_leading_underscores_for_local_identifiers` — `_testMode` (line 111)
8. `unused_local_variable` — `engine1` (line 344)

(Line numbers as of this writing — re-check against current file before
editing, they may have shifted.)

## Intended approach

1. Read each flagged line in context — is it truly dead, or does removing
   it silently weaken what the surrounding test actually proves?
2. Remove genuinely dead code; rename `_testMode` to drop the leading
   underscore (or inline it if truly single-use).
3. Confirm no test's *meaning* changed, only its unused scaffolding.
4. `flutter analyze` repo-wide should report zero issues afterward.

## Work Log
