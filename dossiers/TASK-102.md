# TASK-102 — Settings → Restore/rename never re-enrols or re-keys the running app

## Shape decision

Chose **Shape (B), live re-key**, not Shape (A) restart-required.

Reasoning: production's identity factory (`_defaultIdentityFactory` in
`radio_host_provider.dart`) already reads storage *directly*
(`IdentityRepository(SecureIdentityStore()).loadOrCreate()`) on every call —
it is not routed through the memoised `identityProvider` at all. So
`KeryxRadioHost` was always capable of observing a freshly-written identity;
the only things missing were (1) something telling it to re-read and rebuild
its session, and (2) `identityProvider` (a *separate* memoised read of the
same disk store, used by `identityEnrolmentProvider`/directory/presence/
contacts/groups) being invalidated after Restore. Callsign rename already had
half of this (TASK-104 added `ref.invalidate(identityProvider)`), so the gap
was narrower and more mechanical than a restart-required fallback would have
been — Shape B was the smaller diff here, not the riskier one.

## Design

- **`RadioIdentityReloader`** (`lib/core/radio_host/radio_host_contract.dart`)
  — a new, deliberately **optional** interface (`Future<void>
  reloadIdentity()`), *not* a member of `RadioHost` itself. `RadioHost` is
  implemented by several test doubles outside this task's `Owned_Paths`
  (`test/app_shell/fake_radio_host.dart`,
  `test/features/radio_controls/fake_radio_host.dart`,
  `test/features/talk/fake_radio_host.dart`,
  `test/core/presentation/radio_view_intents_test.dart`); adding a required
  member there would have broken all four to implement a capability only
  Settings' restore/rename flow needs. Same additive-interface, `is`-checked-
  by-the-caller shape TASK-107 used for `SessionHostEngineEvents`.
  - **Dart flow-analysis gotcha, same one TASK-107 hit**: `RadioHost` and
    `RadioIdentityReloader` are unrelated interfaces, so a bare `if (host is
    RadioIdentityReloader) { host.reloadIdentity(); }` does **not** promote —
    Dart only promotes to a subtype of the static type. Confirmed with a
    minimal repro (`abstract interface class A`/`B`, `if (a is B) a.bar()` →
    `undefined_method`). Fixed with an explicit `as` cast into a local
    nullable variable, exactly like `keryx_radio_host.dart:503-506` already
    does for `SessionHostEngineEvents`.
- **`KeryxRadioHost.reloadIdentity()`** — no-op if boot hasn't produced a
  first `_identity` yet (nothing running to re-key); otherwise re-reads
  `identityFactory()`, updates `_identity`, and reconstructs the session via
  the existing `_startSession(identity:, settings:)` — the exact teardown/
  rebuild path a session-affecting settings change already takes, keyed off
  a changed identity instead. That also re-runs `_ensureDirectoryEnrolment()`
  before the new session starts, same as every other `_startSession` call —
  so directory/presence/the LINKED `/token` signer all move together.
- **`settings_screen.dart`**: `_reEnrolAfterIdentityChange()` is the one seam
  both Restore and callsign-rename call after writing to disk:
  `ref.invalidate(identityProvider)` FIRST (so
  `identityEnrolmentProvider`'s re-enrolment resolves the new identity, not a
  stale cached one), then `host.reloadIdentity()` if the host is a
  `RadioIdentityReloader`.
- **Restore now actually reloads the displayed identity**: the pre-existing
  code called `setState(() {})` with nothing reassigned, so the Identity
  section kept showing the pre-restore callsign until the screen was fully
  rebuilt some other way. Fixed by calling `_loadIdentity()` (same one
  `initState` uses) after the restore write.
- **Double-commit de-dupe (`_callsignSubmitInFlight`)**: `SettingsTextRow`
  (`settings_rows.dart`, **outside** this task's `Owned_Paths`) commits on
  both `TextField.onSubmitted` and its own focus-loss listener — under
  `TextInputAction.done` both fire in the same frame for the same value,
  before the first `await` in `_setCallsign` has had a chance to update
  `_identity`/rebuild the row with the new `value` (so the row's own
  `next != widget.value` guard can't see the first call in flight and lets
  the second one through too). This was harmless before this task (a second
  `ref.invalidate(identityProvider)` is a no-op) but `reloadIdentity()` now
  does a real session teardown/rebuild + directory POST, so double-firing
  became a real, testable defect — caught by the settings_screen test
  itself (`Expected: <1>, Actual: <2>` on `host.reloadIdentityCalls`).
  De-duped from `settings_screen.dart`'s own territory rather than touching
  `settings_rows.dart`.

## No mixed-identity window

`RadioSessionController`'s default `/token` signer already reads storage
fresh per LINKED start (`IdentityRepository(SecureIdentityStore())
.loadOrCreate()`, `radio_session_controller.dart:144`) — it was never the
stale one. The actual gaps were the *ordering/wiring* ones above. Proven at
`test/app_shell/directory_enrolment_test.dart`'s new TASK-102 group: after
`reloadIdentity()`, the very next `POST /v2/identity` carries the NEW
`x-keryx-key` header (asserted `isNot(oldKeyHeader)`), and the enrolment
record settles to `registered` with exactly 2 total requests (no further
call under the old key).

## Territory

All files touched are inside `Owned_Paths`:
`lib/core/radio_host/radio_host_contract.dart`,
`lib/core/radio_host/keryx_radio_host.dart`,
`lib/features/settings/settings_screen.dart`,
`test/app_shell/directory_enrolment_test.dart`,
`test/features/settings/settings_screen_test.dart`,
`test/features/settings/fake_radio_host.dart`, this dossier.
`directory_providers.dart`, `radio_host_provider.dart` and
`radio_host_contract.dart`'s existing members are untouched apart from the
one additive interface.

## Mutation checks (both bit)

1. Disabling `unawaited(reloader.reloadIdentity())` in
   `_reEnrolAfterIdentityChange` → 2 red: both the restore test and the
   callsign-rename test (`host.reloadIdentityCalls` stayed 0). Reverted.
2. `buildHost`'s `_SessionHostFake` had to become a fresh instance per
   `sessionFactory` call (not one fixed instance reused across boot +
   reload) — with the old fixed-instance fixture, `host.dispose()` at test
   teardown threw `Bad state: FloorEngine.dispose() has already been
   called`, because `reloadIdentity()` disposed-then-reconstructed the SAME
   engine object a real `RadioSessionController` never would. Fixed the
   fixture, not the production code — confirmed against
   `RadioSessionController._teardownActive`/`_startLocal`/`_startLinked`,
   which always builds a brand-new controller.

## Test_Evidence

`flutter analyze --no-pub` → No issues found.
`flutter test --no-pub test/app_shell/directory_enrolment_test.dart
test/features/settings/settings_screen_test.dart` → 33 passed / 0 failed.
`flutter test --no-pub --concurrency=2` (full suite) → **1528 passed / 41
skipped / 0 failed**, exit 0. Reconciles exactly against the baseline this
branch was cut from (master's post-TASK-105-round-2 merged-tree count,
1524/41/0 — this task's own Progress_Note): +4 new tests (2 in
`directory_enrolment_test.dart`'s TASK-102 group, 2 in
`settings_screen_test.dart`), 0 regressions, 0 failures.
