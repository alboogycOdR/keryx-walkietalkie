# TASK-087 — v2 rooms and transport keys — group and 1:1 room derivation, LAN room prefix, LiveKit E2EE, signed token client

## Brief

Room identity for v2. In `lib/core/rooms/`: delete `deriveNumbered` and its channel/code constants; add `deriveGroupRoom(secret)` = `deriveKeyed(base64(secret))` and `deriveDirectRoom(myPriv, theirPub)` = `deriveKeyed(base64(x25519 shared secret))` (both sides must agree — test it); keep `deriveKeyed` and the scrypt path. In `lib/services/discovery/`: replace `channel_hash_prefix.dart` with `room_prefix.dart` (first 8 chars of the room ID) and let the service advertise up to 3 rooms; keep NSD plumbing. In `lib/services/linked/`: `token_client.dart` signs requests with TASK-083's helper; `livekit_adapter.dart` enables LiveKit E2EE with a `BaseKeyProvider` whose key is HKDF(roomSecret, info `keryx-e2ee-v1`); `LinkedController` takes the room secret alongside the room ID. Migrate the existing derivation/vector tests that still apply; delete only the numbered-channel ones.

## Spec pointers

- specs/KERYX_v2.0_Technical_v1.0.md §1 (rooms/discovery/relay rows), §5.1, §5.4, §5.5, §7 (derivation.dart, token_client.dart); Verification V2-VT-020, V2-VT-023 (prefix half); PRD V2-NFR-004
- Owned_Paths: lib/core/rooms/**, lib/services/discovery/**, lib/services/linked/**, test/core/rooms/**, test/services/discovery/**, test/services/linked/**, dossiers/TASK-087.md
- Depends_On: TASK-083

## Work Log

- [2026-09-11T20:35:00Z] [S5] Implemented on branch `task/TASK-087-s5`:
  - **`lib/core/rooms/derivation.dart`**: added `deriveGroupRoom(secret)` = `deriveKeyed(base64(secret))` and `Future<String> deriveDirectRoom({myKeyPair, theirEdwardsPublicKey})` (X25519 ECDH via `IdentityKeyPair.toX25519KeyPair()` + `edwardsPublicKeyToX25519`, then `deriveKeyed(base64(sharedSecretBytes))`). ECDH is symmetric by construction, proven by a dedicated test computing both directions. `deriveNumbered` **retained** (see scoping note below) with an added dartdoc marking it for deletion once its callers move.
  - **`lib/services/discovery/room_prefix.dart`** (new): `RoomPrefix.compute(roomId)` = first 8 chars. `DiscoveryConfig` gained an additive `roomPrefixes` list (validated: no dup, ≤ `maxAdvertisedRooms` (3) total with the primary `channelHashPrefix`, no empty entries) and `allRoomPrefixes`; `toPlatformArgs()` now carries `roomPrefixes`. `NsdDiscoveryService._maybeAddPeer` matches against `config.allRoomPrefixes` instead of only the primary prefix, so a peer on any of the up-to-3 advertised rooms is found. `channel_hash_prefix.dart` kept, with a dartdoc pointer to `RoomPrefix` and a note on why it's still wired.
  - **`lib/services/linked/token_client.dart`**: optional `IdentityKeyPair? signer` constructor param; when set, every request carries `X-Keryx-Sig/Key/Ts` via TASK-083's `signRequest` over `POST|<path>|<body>|<ts>`. `signer == null` keeps the v1 unsigned shape exactly as before.
  - **`lib/services/linked/livekit_adapter.dart`**: `LiveKitAdapter.connect` gained an optional `Uint8List? e2eeKey`; new top-level `deriveE2eeKey(roomSecret)` = HKDF-SHA256(roomSecret, info `keryx-e2ee-v1`) → 32 bytes (`package:cryptography`'s `Hkdf`). `LiveKitRoom` gained `bool get isEncrypted` so a caller checks the *actual* outcome, not just "did I pass a key".
  - **`lib/services/linked/livekit_client_adapter.dart`**: when `e2eeKey != null`, builds a `BaseKeyProvider` via `.create()` + `setRawKey(e2eeKey)` (raw-byte round trip through `String.fromCharCodes`/`.codeUnits`, safe for 0-255 values), wraps it in `RoomOptions(encryption: E2EEOptions(...))` (the non-deprecated field; `e2eeOptions` is `@Deprecated`), passed to the `lk.Room` constructor *before* `connect()` — LiveKit requires the key provider at room-construction time, not after. `isEncrypted` reflects whether encryption was actually configured.
  - **`lib/services/linked/linked_controller.dart`**: `joinRoomId` gained an optional `List<int>? roomSecret`, threaded through `_join`/`_reconnectRoom`/`_connectAndPublish`. When supplied, `_connectAndPublish` derives the E2EE key, passes it to `adapter.connect`, and — before ever calling `publishMutedAudioTrack()` — checks `room.isEncrypted`; if false, disconnects and throws the new `LinkedE2eeUnavailableException` (V2-NFR-004: never publish plaintext for a room that asked to be encrypted). `joinNumbered`/`joinKeyed` unchanged (no `roomSecret` — legacy numbered path, see scoping note).
  - Fakes updated additively: `FakeNsdPlatform`/`FakeLiveKitAdapter`/`FakeLiveKitRoom`/`FakeTokenServer` (the last gained `lastRequestHeaders` + `requireSignature` to let a test literally reject an unsigned call, per AC 3's wording).

  **Cross-task scoping decision (recorded in PLAN.md Progress_Notes too):** `deriveNumbered`, `ChannelHashPrefix`, and `DiscoveryConfig.channelHashPrefix` are **not deleted** in this task. Both remaining callers — `lib/services/session/radio_session_controller.dart` (TASK-088's `Owned_Paths`) and `lib/features/event_qr/event_link.dart` (TASK-094's `Owned_Paths`) — are outside TASK-087's territory, and Technical §10 itself orders "Room derivation" (item 4, this task) strictly before "Session/host changes" (item 5, depends on 4) and "Deletions" (item 11, "after 10"). Deleting the legacy symbols here would break `flutter analyze`/the full suite in files this task cannot touch. The two AC boxes that say "no longer exists"/"is gone" are left **unchecked** with this note as the reason; TASK-088 and TASK-094 are where those callers actually migrate and the dead code becomes deletable.

  **Test evidence:**
  - `flutter analyze --no-pub` (full repo): **No issues found.**
  - `flutter test --no-pub test/core/rooms/` : 36/36 pass.
  - `flutter test --no-pub test/services/discovery/`: 24/24 pass.
  - `flutter test --no-pub test/services/linked/`: 60/60 pass (token_client 18 + linked_controller 17 + others).
  - Full `flutter test --no-pub`: **1584 passed, 0 failed, 40 skipped** (same PARKED FR-025 soak-seed skips, untouched), exit code 0.
  - `git diff master...HEAD --stat`: touches only files under `lib/core/rooms/**`, `lib/services/discovery/**`, `lib/services/linked/**`, `test/core/rooms/**`, `test/services/discovery/**`, `test/services/linked/**`, and this dossier — all inside `Owned_Paths`.
  → Status: needs_review.
