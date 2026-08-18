# TASK-007 — Room derivation library: numbered/keyed/scrypt + test vectors (KRX-053)

## Brief
Pure-Dart channel→roomId derivation in `lib/core/rooms/`, matching TS §8.7 exactly, with a frozen test-vector suite so the derivation can never silently drift (the token service and Event QR both hang off these IDs). Used by TASK-024 (LINKED) and TASK-025 (Event QR).

## Spec pointers
- TS §8.7 (verbatim):
  ```
  numbered:  roomId = b32( HMAC-SHA256("KERYX.v1", region | ch | code) )[:16]
  keyed:     roomId = b32( HMAC-SHA256("KERYX.v1", "PRV" | scrypt(passphrase)) )[:16]
  ```
- "Keyed channels get real entropy from the passphrase (scrypt-stretched)… Server sees keyed-channel room hashes only, never passphrases."
- FR-002: "on LINKED, code participates in room derivation (§8.7)". FR-008: region salt partitions the numbered namespace.
- FR-007: keyed channels are "identified by a passphrase instead of a number; roomId derived from the passphrase".

## Intended approach
1. `derivation.dart`: `deriveNumbered({region, channel, code})` and `deriveKeyed({passphrase})`. Canonical byte encoding for `region | ch | code` must be pinned and documented (spec leaves it open — propose `utf8("$region|$ch|$code")` with zero-padded two-digit ch/code; record the choice in code comments and the work log for ORCH ratification). Unpadded RFC 4648 base32, lowercase, first 16 chars.
2. scrypt via pointycastle (already transitively available; if a direct dep is needed, STOP — pubspec is frozen territory → `blocked: OWNERSHIP_CONFLICT`). Pin parameters (propose N=2^15, r=8, p=1, dkLen=32) and document; deterministic fixed salt derived from "KERYX.v1" context (documented rationale: roomId must be identical on every device given the same passphrase).
3. `vectors_test.dart`: hand-computed frozen vectors (several numbered combos incl. code 00, region variants; keyed with known passphrases). Any future change that breaks a vector is a protocol break by definition.

## Work Log
