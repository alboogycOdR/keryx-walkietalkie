# TASK-056 — Event QR re-theme

## Brief

New screens in a new directory over the existing, unmodified
`lib/features/event_qr/**` payload/validation/scan/export logic — the old
directory is a dependency here and is deleted later by TASK-061. Beyond the
re-theme, this closes a real behavioural gap: a scan in LOCAL that needs a LINKED
session currently just errors.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.7 — modern framing, camera
  permission states, no silent LOCAL failure, no invented keyed-channel UI.
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §8 (host-level join
  coordinator; user-approved cancellable route change; no WAN under force-LOCAL;
  keyed export unverified; no secret logging), §1.1.
- PRD UX-FR-063, §4.4; Verification VT-023.
- ADR-001 §6 — "NEW framing on the existing scan/export LOGIC".

## Approach

Explain the required connectivity change and offer an explicit, cancellable,
user-approved transition — or keep the operation unavailable with a stated
reason. Force-LOCAL is absolute. A failed join leaves a known-good session or an
explicit unavailable state, never a falsely selected channel. Keyed export is
surfaced as unavailable rather than faked.

## Work Log

- [2026-09-08T18:20:00Z] [S5] Claimed. Researched via subagent: existing
  `lib/features/event_qr/**` (`EventQrScanScreen`/`EventQrScanHandler`,
  `EventQrExportScreen`) never touches join/host state by design — host
  wiring is explicitly out of scope there, which is exactly this task's
  gap to fill. Found the sanctioned join entry point:
  `RadioHost.joinEvent(EventLinkPayload) -> JoinResult` (already exists,
  requires an active LINKED session, returns `unavailableRoute`
  otherwise). Effective route = `radioStateProvider`'s `RadioState.mode`
  (already resolved, never `auto` in practice); force-LOCAL =
  `KeryxSettings.forceLocalOnly`. No dedicated "switch route" API exists
  — the only way to move LOCAL->LINKED is `RadioHost.applySettings`,
  which fully awaits session rebuild before returning (confirmed by
  reading `KeryxRadioHost._startSession`/`_maybeRebuildSession`).

  **Design decisions:**
  - `EventQrJoinCoordinator` (host-level join coordinator, Technical §8)
    is a plain, Riverpod-agnostic class — same testability shape as the
    existing `EventQrScanHandler`. It is the *only* path `event_qr_ui`
    uses to call `RadioHost.joinEvent`/`applySettings`. Force-LOCAL is
    checked before any settings mutation or host call — returns
    `forceLocalBlocked` immediately, no route-transition prompt, no
    settings mutation, no join attempt (no WAN traffic ever attempted).
  - Deliberately does **not** persist the route-transition setting via
    `SettingsRepository`/`settingsProvider.notifier.save` — it calls
    `RadioHost.applySettings` directly with a `mode: RadioMode.linked`
    copy. Scoping call: a one-off "switch to join this event" is a
    runtime host operation, not a standing user preference change; only
    the settings screen (TASK-055) owns persisted preference writes.
  - Keyed export: `EventQrUiExportScreen` renders a full "unavailable"
    state (not a faked/disabled option) whenever
    `RadioState.isPrivate` is true, since `lib/features/event_qr/README.md`
    documents no `EVENT_TOKEN_SECRET` config seam exists yet for the
    signed Event-QR token contract. Only the currently-tuned numbered
    channel can be exported.
  - Camera permission: new `EventQrPermissionGate` interface (mirrors
    `lib/features/face/permission_gate.dart`'s `FacePermissionGate`
    pattern exactly) since `permission_handler`'s real plugin has no
    fake/mock platform-channel backend — same reason
    `test/features/event_qr/qr_scan_screen_test.dart` never mounts the
    real scanner widget. `EventQrUiScanScreen` takes an injectable
    `scannerBuilder` for the same reason; production defaults to the
    real, unmodified `EventQrScanScreen`.
  - Expired scan is terminal (per existing `EventQrScanHandler`, no
    external reset hook) — resumed by remounting the inner scanner with
    a fresh key (`_scanGeneration` counter), not by reaching into the
    handler's private state.

  **Bug caught during widget testing, fixed:** `EventQrUiScanScreen`
  originally only `ref.read(settingsProvider)` inside `_handleTuned` —
  since nothing else in the widget ever watched it, the AsyncNotifier's
  `build()` was still lazily starting (and thus `AsyncLoading`, value
  `null`) the very first time a scan tried to read it, so every join
  saw "settings unavailable" regardless of actual settings. Fixed by
  `ref.watch(settingsProvider)` once in `build()` to warm the provider
  before any scan can occur. Mutation-checked (see Test_Evidence).

  Files: `lib/features/event_qr_ui/{event_qr_ui_copy,
  event_qr_permission_gate, event_qr_join_coordinator,
  event_qr_ui_scan_screen, event_qr_ui_export_screen}.dart`;
  `test/features/event_qr_ui/{fake_radio_host, fake_permission_gate,
  event_qr_join_coordinator_test, event_qr_ui_scan_screen_test,
  event_qr_ui_export_screen_test}.dart`.

  **Environment note (not a code change):** this worktree's local
  `flutter analyze` invocation self-modifies `analysis_options.yaml`
  ("Upgrading analysis_options.yaml to exclude build and platform
  directories") on every run — reverted via `git checkout --
  analysis_options.yaml` after each analyze/test run since that file is
  outside this task's `Owned_Paths`. Also needed a local `python3` shim
  (`/c/Users/User/bin/python3` -> `python`) since this shell's `python3`
  resolves to a non-functional Windows Store stub, which was silently
  breaking `scripts/plan_commit.sh`'s `base_branch` resolution (falling
  back to the wrong default `main` instead of this repo's actual
  `master`). Neither touches any tracked repo file.

  Status -> needs_review. See Test_Evidence in PLAN.md for full
  mutation-check transcript.
