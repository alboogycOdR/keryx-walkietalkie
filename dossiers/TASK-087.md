# TASK-087 — v2 rooms and transport keys — group and 1:1 room derivation, LAN room prefix, LiveKit E2EE, signed token client

## Brief

Room identity for v2. In `lib/core/rooms/`: delete `deriveNumbered` and its channel/code constants; add `deriveGroupRoom(secret)` = `deriveKeyed(base64(secret))` and `deriveDirectRoom(myPriv, theirPub)` = `deriveKeyed(base64(x25519 shared secret))` (both sides must agree — test it); keep `deriveKeyed` and the scrypt path. In `lib/services/discovery/`: replace `channel_hash_prefix.dart` with `room_prefix.dart` (first 8 chars of the room ID) and let the service advertise up to 3 rooms; keep NSD plumbing. In `lib/services/linked/`: `token_client.dart` signs requests with TASK-083's helper; `livekit_adapter.dart` enables LiveKit E2EE with a `BaseKeyProvider` whose key is HKDF(roomSecret, info `keryx-e2ee-v1`); `LinkedController` takes the room secret alongside the room ID. Migrate the existing derivation/vector tests that still apply; delete only the numbered-channel ones.

## Spec pointers

- specs/KERYX_v2.0_Technical_v1.0.md §1 (rooms/discovery/relay rows), §5.1, §5.4, §5.5, §7 (derivation.dart, token_client.dart); Verification V2-VT-020, V2-VT-023 (prefix half); PRD V2-NFR-004
- Owned_Paths: lib/core/rooms/**, lib/services/discovery/**, lib/services/linked/**, test/core/rooms/**, test/services/discovery/**, test/services/linked/**, dossiers/TASK-087.md
- Depends_On: TASK-083

## Work Log
