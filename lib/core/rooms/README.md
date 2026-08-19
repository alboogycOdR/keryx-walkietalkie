# Room derivation (KRX-053 / TS §8.7)

Pure-Dart channel → `roomId` library. Clients derive the hash; the
token service mints a JWT for that hash and never sees a passphrase.

## Formulas

```
numbered:  roomId = b32( HMAC-SHA256("KERYX.v1", region | ch | code) )[:16]
keyed:     roomId = b32( HMAC-SHA256("KERYX.v1", "PRV" | scrypt(passphrase)) )[:16]
```

`b32` is RFC 4648 §6 **uppercase, unpadded**, first 16 characters
(`^[A-Z2-7]{16}$`). Pinned by ORCH ruling (follow-up d) to match
token-svc's validator. peerId (TASK-009) uses the same alphabet in
lowercase; this package does not import `lib/core/identity`.

## Decisions (spec-silent, pinned here — ORCH ratifies at review)

- **HMAC key** is UTF-8 `"KERYX.v1"`.
- **Numbered message** is UTF-8 `"$region|$ch|$code"` with `ch` and
  `code` zero-padded to two decimal digits (`7` → `"07"`, code `0` →
  `"00"`). Code `00` (open) still participates — FR-002.
- **Region** is used after trim, case-sensitive, non-empty, and must
  not contain `|`. `"za-cpt"` and `"ZA-cpt"` are different rooms.
  This is the FR-008 salt: the same CH/code in two regions hashes
  differently.
- **Keyed message** is the three ASCII bytes `PRV` concatenated with
  the 32-byte scrypt digest. No pipe: the stretch is binary.
- **scrypt**: `N=2^15` (32768), `r=8`, `p=1`, `dkLen=32`, salt =
  UTF-8 `"KERYX.v1"`. Deterministic so every device agrees. The
  passphrase is UTF-8 and is not trimmed; empty is rejected.
  Implemented in-tree against RFC 7914 using `package:crypto`
  HMAC-SHA256 (`pubspec.yaml` is frozen; we do not take a direct
  `pointycastle` dep). RFC Appendix B vectors are in the test suite.
- **Passphrase never leaves the client.** `deriveKeyed` is a pure
  function: no I/O, no logging. The only value that can be sent
  onward is the 16-character room hash.

Changing any pin is a protocol break: the frozen vectors in
`test/core/rooms/vectors_test.dart` will fail, and every already-joined
LiveKit room becomes unreachable.
