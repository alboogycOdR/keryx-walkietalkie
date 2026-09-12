# TASK-099 — Wire DirectoryClient.registerIdentity into the app

## Brief

`DirectoryClient.registerIdentity(callsign)` was fully built and unit-tested
in isolation but had zero call sites in `lib/**` — no device has ever
registered with the v2 directory. `token-svc` rejects a well-signed request
from an unregistered public key with `unknown_identity` (401). This is very
likely the true underlying cause behind the earlier field-reported
"Couldn't send that request." contact-add failure (TASK-098 fixed the UI
symptom of that; this task is the actual root cause).

## Spec pointers

- `lib/services/directory/directory_client.dart:46` — `registerIdentity`
- `token-svc/app/directory.py:58-77` — idempotent upsert semantics (safe to
  call unconditionally, not just once-ever)
- `token-svc/README.md:108,166` — `unknown_identity` / 401
- `lib/app_shell/directory_providers.dart:50-59` — `directoryClientProvider`,
  the single composition-root call site

## Approach

1. `directoryClientProvider`: after constructing `client`, call
   `client.registerIdentity(identity.callsign.value)` inside a try/catch —
   log and continue on failure, never rethrow (matches this file's
   documented "directory bootstrap must not block reaching Talk"
   philosophy, and the existing null-propagation convention every dependent
   provider already handles).
2. Do not touch `patchCallsign`'s call sites — grepped, there currently are
   none in `lib/**` (contacts/groups controllers don't call it yet); the
   acceptance criterion holds trivially since those files are untouched.
3. New test `test/app_shell/directory_providers_test.dart` must drive the
   REAL `directoryClientProvider` (not a hand-built controller-level fake)
   against a fake HTTP layer underneath the real `DirectoryClient`.

## Preflight (c8b9872 filesystem check)

```
[preflight] TASK-099 Owned_Paths inspected in C:/CLAUDECODE_TOOLSETS/wt-s5-walkietalkie-keryx
[preflight] 3 entr(y/ies). FILE/DIR/GLOB = exists, NEW = you are creating it.
  FILE   lib/app_shell/directory_providers.dart  -> exists, 158 line(s), 7161 bytes
  NEW    test/app_shell/directory_providers_test.dart  -> does not exist; parent test/app_shell/ exists
  NEW    dossiers/TASK-099.md  -> does not exist; parent dossiers/ exists
```
Territory matched expectation.

## A design fork worth recording: how to test the real provider

Every existing test that needs a working directory
(`DirectoryShellHarness`, `test/regression/real_composition_test.dart`)
overrides `directoryClientProvider` wholesale with an already-constructed
`DirectoryClient` pointed at `FakeDirectoryServer` (plain HTTP), sidestepping
`directoryBaseUri`'s unconditional `https` upgrade entirely. That is exactly
the "hand-built controller-level fake" this task's acceptance criterion
says NOT to do — it would never exercise the new `registerIdentity` call,
since the provider body that makes that call is what gets replaced.

Getting the REAL `directoryClientProvider` body to run against a fake
backend meant either standing up a TLS-terminating fake server (rejected —
would need a static private-key/cert fixture, which `secret-scan.js`
correctly refuses to let any unit write into the repo regardless of path,
and generating one at test-runtime via a shelled-out `openssl` call would
make the suite depend on an external binary being on PATH in every review/
CI environment) or adding a narrow injection seam. Went with the latter:
`directoryBaseUriResolverProvider` (`lib/app_shell/directory_providers.dart`)
is a `Provider<Uri? Function(String relayUrl)>` defaulting to the real
`directoryBaseUri`; only the test overrides it, to point straight at
`FakeDirectoryServer`'s plain-HTTP `baseUrl`. Same shape as
`radio_host_provider.dart`'s constructor-injected platform factories
(TASK-048) — production is unaffected (default resolver is `directoryBaseUri`
itself, still forcing `https` for every real device), and
`directoryClientProvider`'s own body — settings/identity reads, real
`DirectoryClient` construction, the new `registerIdentity` call, the
try/catch, the return — is never overridden.

## Test_Evidence

- `flutter test test/app_shell/directory_providers_test.dart` — 3/3 pass:
  - registerIdentity happens before any dependent (contacts/groups/presence)
    provider can observe the client, and resolving those providers adds no
    further server request.
  - a repeat provider rebuild (same callsign) does not throw; server
    receives 2 idempotent POSTs.
  - a registration failure (500) is caught — `directoryClientProvider` still
    resolves non-null, and every dependent provider still resolves without
    throwing.
- `flutter analyze` — no issues found.
- Full suite: see Work Log for the run covering the whole worktree (started
  as a background command past the 120s foreground timeout; result appended
  below once it completes).

## Outstanding (cannot close from this headless session)

Acceptance criterion "Dossier records a live two-device field retest: a
contact-add request that previously failed now succeeds end-to-end" needs
the owner's two physical phones (same as TASK-059/060's remaining rows per
`CLAUDE.md`'s current-focus notes) — not obtainable in a headless builder
session. Flagging for ORCH/owner rather than fabricating evidence.

## Work Log

- [2026-09-12T19:17:49Z] [S5] Claimed via `scripts/plan_commit.sh`, branch
  `task/TASK-099-s5`. Preflight run (above), territory matches expectation.
- [2026-09-12T19:37:34Z] [S5] Implementation + tests committed
  (`bd1cd1d`). `flutter test test/app_shell/directory_providers_test.dart`
  3/3 pass; `flutter analyze` clean; full suite `flutter test` — 1431
  passed / 0 failed / 40 skipped (pre-existing PARKED FR-025 rows,
  unrelated). PLAN.md TASK-099 -> `needs_review` (`7b0291d` on master).
  Only unticked criterion is the live two-device field retest — needs the
  owner's phones, out of reach from this headless session; noted in
  PLAN.md's Acceptance_Criteria and above under "Outstanding".
