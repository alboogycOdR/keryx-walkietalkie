# TASK-063 — Token URL double-append fix

## Brief

Pure debt paydown, independent of the redesign, dispatched in Wave 1 so
TASK-060's LINKED hardware test can use real default settings instead of the
runbook's mandatory workaround. `resolvedTokenServiceUrl`
(`lib/core/settings/settings_model.dart:147-153`) already ends in `/token` and
`TokenClient._resolveTokenUri` (`lib/services/linked/token_client.dart:121-124`)
appends `token` again — `/token/token` → 404 → `NO LINK` on the default LINKED
path.

## Spec pointers

- `docs/adr/ADR-001-mobile-ux-redesign-reconciliation.md` §5 (carried as a
  narrowly scoped successor task, not absorbed into a rewrite).
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §0 ("Any confirmed transport
  defect is a separate, narrowly scoped corrective task"), §8 (token-service
  contracts retained).
- PLAN.md `orchestrator_notes` 2026-08-23T05:55Z — the original defect record
  with exact file/line references.
- `ops/TWO_PHONE_TEST.md` §6 — the bare-origin workaround this retires.

## Approach

Fix on exactly one side of the seam; state which and why. The regression test is
the deliverable's point: assert the **resolved URI string** for default settings
and for a path-prefixed custom URL, so neither side can silently reintroduce the
double-append. TASK-024's prefix-preservation behaviour must not regress.
`radio_session_controller.dart` wires the two but is out of territory — a need to
touch it is `OWNERSHIP_CONFLICT`, not a scope widening.

## Work Log

### [2026-09-07T20:14:20Z] [GB]

Claimed on `task/TASK-063-gb`. Preflight (verbatim in PLAN.md): existing
`settings_model.dart`, `token_client.dart`, `token_client_test.dart`, this
dossier; `test/core/settings/**` currently only
`settings_repository_test.dart`.

**Fix side: TokenClient, not settings.** Reasoning:
- `resolvedTokenServiceUrl` already documents and implements the Caddy
  `/token` route (`path: '/token'`). That string *is* the HTTP endpoint.
- `TokenClient` was written as if `baseUrl` were a service origin that
  still needed the route appended (TASK-024 prefix preservation).
- The session layer (out of territory) passes `resolvedTokenServiceUrl` as
  `TokenClient.baseUrl`, so the client receives an already-complete
  endpoint and appends again → `/token/token`.
- Fixing settings to return a bare origin would leave a user-typed
  `https://DOMAIN/token` (the natural Caddy URL, what the back panel has
  historically stored) still broken, and would make
  `resolvedTokenServiceUrl` no longer be the token route it claims to be.
- TokenClient change: if the last non-empty path segment is already
  `token`, use the URI as-is; otherwise keep TASK-024 `resolve('token')`
  so a prefix such as `/api` still becomes `/api/token`, and a bare
  origin (the TWO_PHONE_TEST §6 workaround / TASK-039 dart-define) still
  becomes `/token`.
- `radio_session_controller.dart` is not touched.
- `ops/TWO_PHONE_TEST.md` §6's bare-origin workaround becomes unnecessary
  once this merges; updating that runbook is TASK-060's, not this
  territory.

Next: public `resolveTokenUri()`, composition tests on the resolved URI
string, revert-mutation, full suite.

### [2026-09-07T20:19:29Z] [GB]

Landed on `task/TASK-063-gb`.

**Fix (TokenClient only):** `resolveTokenUri()` is public. If the last
non-empty path segment is already `token`, return the base URI as-is;
otherwise keep TASK-024 `resolve('token')`. `requestToken` uses that
method. `settings_model.dart` and `radio_session_controller.dart` are
byte-untouched.

**Contracts:** POST body, status mapping, `TokenResponse` /
`TokenRequestException` / `TokenTransportException` unchanged.

**`ops/TWO_PHONE_TEST.md` §6:** the bare-origin workaround is no longer
required after merge (origin-only, derived `/token`, and typed
`https://DOMAIN/token` all resolve to exactly one `/token` segment).
Runbook update is TASK-060's territory.

**Revert-mutation:** temporarily restored always-append. Failed (Expected
`https://relay.example/token`, Actual `https://relay.example/token/token`)
on the default-settings composition test plus 5 sibling double-append
assertions. Prefix-preservation and origin-only tests stayed green.
Restored; `git diff` on the production method matches the fix only.
