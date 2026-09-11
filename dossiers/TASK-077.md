# TASK-077 — UX R2 shell — Talk-first launch, top tabs, overflow menu

## Brief

Swap the bottom navigation for a top app bar and an icon-only tab strip (Talk · Channels · Stations), with Talk as the default on every launch. Settings and Radio controls move to the overflow menu. The single app-scoped RadioHost lifecycle is untouched.

## Spec pointers

- docs/adr/ADR-002-zello-aligned-talk-first-ui.md §2 O1/O2, §3 A1
- specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md §1
- Verification VT-001–VT-005
- lib/app_shell/mobile_app_shell.dart (branch navigators + IndexedStack pattern to keep)

## Approach

1. Keep the branch-navigator IndexedStack.
2. Build the app bar and tab strip.
3. Wire the callbacks from TASK-074/075/076.
4. Handle back with PopScope.
5. Rewrite the shell tests, and add a drag-over-PTT test to prove tabs never swipe.

## Work Log
