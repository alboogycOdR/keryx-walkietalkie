# TASK-083 — v2 identity core — Ed25519 key pair, peer ID from public key, 12-word recovery phrase, sealed-box helpers

## Brief

First v2.0 task; reopens frozen `pubspec.yaml` for this task only (add `cryptography` and a BIP-39 word list; pin versions; no other dependency changes). Replace the install-UUID identity with an Ed25519 key pair generated on first run and stored in `flutter_secure_storage` via the existing `IdentityStore` seam. `derivePeerId` keeps its output shape (base32(sha256(x))[:10]) but takes the public key; add `deriveShortCode` = chars [10:14] of the same digest. Add `RecoveryPhrase` (128-bit entropy → 12 English BIP-39 words; seed → key via HKDF-SHA256 info `keryx-id-v1`; restore = phrase → same key). Add request signing (`X-Keryx-Sig/Key/Ts` over sha256(method|path|body|ts)) and sealed-box helpers (Ed25519→X25519 conversion, seal to a public key / open with the private key) for group secrets. Keep `callsign.dart` and its validation; keep `IdentityRepository`'s public API so existing consumers compile. Migration: an existing install with a UUID but no key gets a key generated and keeps its callsign (Technical §8). Nothing in this task touches UI or the network.

## Spec pointers

- specs/KERYX_v2.0_Technical_v1.0.md §3 (keys, ID, phrase, signing), §7 (peer_id.dart re-point); specs/KERYX_v2.0_PRD_v1.0.md V2-FR-001..004; specs/KERYX_v2.0_Verification_v1.0.md V2-VT-001..004; Product Model D1, D9, D10
- Owned_Paths: pubspec.yaml, pubspec.lock, lib/core/identity/**, test/core/identity/**, dossiers/TASK-083.md
- Depends_On: —

## Work Log
