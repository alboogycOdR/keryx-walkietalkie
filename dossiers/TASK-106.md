# TASK-106 — Incoming call (receive-side auto-join)

## Round 2 (this session) — the seam TASK-108 closed is used, not re-invented

The earlier OWNERSHIP_CONFLICT block (`6488454`, prior branch) is now
resolved: TASK-108 added `RadioTargetSwitcher` (additive, on `KeryxRadioHost`,
reached via `radioHostProvider` cast) and wired `mobile_app_shell.dart`'s
`_selectTarget` through it. This task reuses that exact seam for the
*receive* direction instead of the *manual-selection* direction.

### Send side — `lib/services/directory/presence_client.dart` + `talking_presence.dart`

- `PresenceClient.setStatus` gained an optional `talking` param; a new
  `setTalking(bool)` convenience resends the most recently known status
  (defaulting to `available` — nothing in the app calls `setStatus` on its
  own today) together with `talking`. Required because
  `token-svc/app/v2_api.py`'s presence handler only processes `talking`
  *inside* the `if "status" in message` branch — a bare `{"talking": true}`
  would be silently ignored server-side. Verified at source
  (`v2_api.py:484-496`).
- `talking_presence.dart` (new): a `Provider<void>`, same shape as
  `presence_bootstrap.dart`, watching `radioStateProvider` and calling
  `setTalking` exactly on the boundary crossing into/out of
  `RadioPhase.tx` — not on every rebuild while transmitting, not on
  `txRequest`/`rxActive`.

### Receive side — `lib/app_shell/incoming_call.dart`

- New `presenceUpdatesProvider` in `directory_providers.dart`: a raw
  `StreamProvider<PresenceUpdate>` pass-through. Necessary because the
  existing `presenceByPeerIdProvider` collapses each update into a
  `PeerPresence` enum and drops `talking` entirely — it cannot answer "who
  just started talking".
- `incoming_call.dart`'s `incomingCallProvider` listens to that stream; on
  `talking: true` from a pk that resolves to a known contact
  (`contactsControllerProvider.contactsSnapshot`), it builds the same
  `TalkTarget` shape `talkTargetFromContact`/`ContactsTabScreen._selectContact`
  build (`deriveDirectRoom(myKeyPair: mine, theirEdwardsPublicKey: theirs)`,
  `name: contact.callsign` — never the raw pk), sets
  `currentTargetProvider`, and calls `RadioTargetSwitcher.switchTarget` via
  `radioHostProvider` — the identical two-step
  `mobile_app_shell.dart:_selectTarget` already does for manual selection.
- State precedence (Design §4, "never steal an active TX or a deliberately
  selected different target"): proceeds only when `currentTargetProvider`
  is `null`, or the radio is otherwise idle (`RadioPhase.idle`) — re-checked
  a second time after the identity/room-derivation awaits, since a TX could
  start while those resolve.

### Wiring without touching `mobile_app_shell.dart`

`mobile_app_shell.dart` is deliberately not in this task's `Owned_Paths`
(TASK-108 already showed the same OWNERSHIP_CONFLICT shape on that file).
`talk_screen.dart` (owned) is mounted by default at launch (Talk is index 0,
ADR-002 §2 O1) and already unconditionally reads `presenceClientProvider`
transitively via `presenceByPeerIdProvider` — so `ref.read(talkingPresenceProvider)`
/`ref.read(incomingCallProvider)` added there is the same category of
"single owner, read once" arm as `presence_bootstrap.dart`'s own, without
widening the risk profile: the chain those two new providers touch
(`presenceClientProvider`) was already being forced by the pre-existing
`presenceByPeerIdProvider` watch on every `TalkScreen` build, in every test
that mounts it — this doesn't introduce a new category of eager network
read, it reuses the one already there.

### AC3 — "Talk renders the incoming-call state with the contact's
callsign, never the raw pk"

Not a new code path: `RadioViewState.receivingLabel` (pre-existing,
`radio_view_state.dart:248`) already resolves `activeSpeakerCallsign` from
`hostSnapshot.stations` and falls back to the neutral "Someone is speaking"
— never the pk — when unresolved. `incoming_call.dart`'s `TalkTarget.name`
is always `contact.callsign` (`talkTargetFromContact`'s own established
contract — `TalkTarget.id` is the pk, `TalkTarget.name` never is), so the
header card the moment selection happens is already callsign-only by
construction. Verified via `incoming_call_test.dart`'s
`selection?.target.name == 'ZULU-1'` assertion (never `theirPk`).

### AC4 — journey receive-side gate

`journey_harness.dart` (TASK-107's `Owned_Paths`, not this task's) never
wires `presenceClientProvider`/`contactsControllerProvider` for either
phone — nothing needed to, until now — and `FakeDirectoryServer` has no
presence-WebSocket support to connect a real client to. Rather than touch
that file, the gate builds a second, narrow `ProviderContainer` for B's
app_shell layer that overrides `radioHostProvider` with **the exact same
`KeryxRadioHost` instance** `harness.phoneB.radioHost` already is — so a
`switchTarget` call issued from this second container dispatches into B's
*real* `RadioSessionController`/`radioStateProvider`, exactly as
`mobile_app_shell.dart`'s own composition root would. A `FakePresenceTransport`
delivers A's `talking: true` frame; the gate asserts
`currentTargetProvider` becomes A, the derived room id matches gate 8b's
own symmetry proof, and `phoneB.radioState.transport == Transport.relay`
(the real session actually joined).

**Mutation run:** commented out
`unawaited((host as RadioTargetSwitcher).switchTarget(target))` in
`incoming_call.dart` (leaving the `currentTargetProvider` write intact —
the exact "we look selected but never actually join" defect this task
exists to close). Reran `flutter test test/regression/journey_two_phones_test.dart
--plain-name "receive-side"` → **1 failed** (room-id expectation reads
`<null>`, since nothing ever dispatched `SetRoom`). Restored; `git diff` on
`lib/` empty afterward.

## Full evidence (this session)

- `flutter analyze --no-pub` → **No issues found** (5.4s).
- `flutter test --no-pub --concurrency=2` → **1541 passed / 40 skipped / 0
  failed**, exit 0. Baseline (post-TASK-108 merge) was 1528/41/0. This task
  adds 4 tests to `presence_client_test.dart`, 2 to `talking_presence_test.dart`
  (new file), 6 to `incoming_call_test.dart` (new file) = +12 new tests,
  plus un-skips the journey's already-existing receive-side gate (moves
  from the skip count to the pass count, not a new test): 1528 + 12 new +
  1 un-skipped = 1541 passed; 41 − 1 = 40 skipped. ✓
- Isolated: `test/services/directory/presence_client_test.dart` (12/12),
  `test/app_shell/talking_presence_test.dart` (2/2),
  `test/app_shell/incoming_call_test.dart` (6/6),
  `test/regression/journey_two_phones_test.dart` (21/21, all previously-passing
  gates still pass, receive-side gate now real and green).
- `git diff master...HEAD --stat` (once committed): every changed/added
  file sits inside `Owned_Paths`; `lib/app_shell/mobile_app_shell.dart` is
  untouched.

## Work Log

- 2026-09-13T21:50Z [S5] Re-claimed after TASK-108 unblocked the seam;
  fresh branch (old one only held the obsolete blocker dossier). Read
  `presence_client.dart`, `directory_providers.dart`, `mobile_app_shell.dart`
  (for the `_selectTarget` pattern to mirror), `contacts_tab_screen.dart`
  (for `talkTargetFromContact`/`decodeUnpaddedBase64Url`), `radio_state.dart`
  (phase enum), `token-svc/app/v2_api.py`/`presence.py` (confirmed `talking`
  requires `status` in the same message, is not persisted server-side).
- Implemented `presence_client.dart`'s `setTalking`/`setStatus(talking:)`,
  `directory_providers.dart`'s `presenceUpdatesProvider`,
  `talking_presence.dart`, `incoming_call.dart`, wired both into
  `talk_screen.dart`. Added/extended tests in all four locations plus the
  journey gate. Ran the mutation check, full suite, analyzer — all green.
  → Status: needs_review.
