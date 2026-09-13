# TASK-103 — Two-phone journey test

## Problem

Every existing test is fakes-all-the-way-down. Four client fixes each
turned one gate green while the next stayed invisible. This file is the
executable definition of "it works": two real phones against one
stateful directory fake.

## Gate map (what ORCH un-skips)

| Gate | Test name | Real types exercised | Faked seams | Status |
|---|---|---|---|---|
| 1 | A boots and registers | `KeryxRadioHost`, `identityEnrolmentProvider`, `DirectoryClient.registerIdentity` | 5 host natives + LiveKit/RTC/NSD/signaling | pass today |
| 2 | B boots and registers | same, second `ProviderContainer` | same | pass today |
| 3 | A pastes B's ID → pending_out | `ContactsListController.sendRequestFromId`, `ContactsController.sendRequest`, `DirectoryClient.sendContactRequest` | same | pass today |
| 4 | A GET /me still shows pending_out | `DirectoryClient.getMe` | same | pass today |
| 5 | B GET /me lists A in pending_in | `DirectoryClient.getMe` (server truth, not the missing refresh) | same | pass today |
| 6 | B refreshes and sees the request | `ContactsListController.load` → should call `ContactsController.refreshFromServer` | same | **skip TASK-105** — `load()` is disk-only; `refreshFromServer` has zero production callers |
| 7 | B accepts → both list each other | `ContactsListController.accept` after a refresh | same | **skip TASK-105** |
| 8 | A selects B → `/token` + `peer_pk` + DirectRoom + `SetTransport(relay)` | `RadioSessionController.switchTarget`, `TokenClient.requestToken`, `FakeLiveKitAdapter.connect` | same + LiveKit | pass today (contacts seeded on the fake; production accept is gate 7) |
| 8b | B selects A → same room id | `deriveDirectRoom` both directions + two `switchTarget`s | same | pass today |
| receive | B hears A without selecting | — | — | **skip TASK-106** |

## Native seams (the only fakes)

Host constructor: `RecordingAudioSink`, `_PermissionGateFake`,
`FakeRadioServicePlatform`, `identityFactory` returning the in-memory
`DeviceIdentity`. Session constructor: `FakeLiveKitAdapter`,
`FakeRtcAdapter`, `_NoopDiscoveryService`, `InProcessSignalingHub`.
`directoryBaseUriResolverProvider` points both phones at the loopback
fake (TLS upgrade is the same seam TASK-099 introduced).
`settingsStoreProvider` / `identityProvider` are per-phone in-memory
stores, not wholesale controller overrides.

## Work Log

- [2026-09-13T06:12:00Z] [GB] Claimed. Preflight: 4 NEW files + existing
  `fake_directory_server.dart`. Implementing.
- [2026-09-13T06:25:00Z] [GB] Journey file 17 pass / 3 skip. Mutation:
  omitting `/token` `unknown_identity` turned that test 403 `not_member`.
  Full suite +1482 ~43 -0. Analyze clean. → needs_review.
