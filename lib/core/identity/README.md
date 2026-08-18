# Identity (KRX-075 / TS §8.6)

Install-scoped device identity. Callsigns are display-only; `peerId` is
the sole input to arbiter election (lexicographic minimum).

## Formula

```
peerId = base32( SHA-256(installUUID) )[:10]
```

`installUUID` is generated once (RFC 4122 v4) and persisted under
`keryx.identity.install_uuid`. The hash input is the **16 raw UUID
bytes**, not the hyphenated string.

## Decisions (spec-silent, pinned here)

- **base32** is RFC 4648 §6, **lowercase, unpadded**, first 10
  characters. Alphabet `a–z2–7`. Same family as the TASK-007 dossier
  (rooms/ is a different territory — no shared import). token-svc
  roomIds use this alphabet in uppercase; peerId stays lowercase.
- **UUID persistence** is the canonical lowercase `8-4-4-4-12` form.
- **NATO number** is 1–99 inclusive (`BRAVO-7`, `SIERRA-19`). Word list
  is the 26 ICAO spellings (`JULIETT`, `XRAY`).
- **Callsign charset** is `[A-Za-z0-9-]{2,12}` after trim — the same
  2–12 class FR-068 names and the token-svc identity regex already
  accepts. No uniqueness check on save.
- **Collision** is an exact string match, walk-in-join-order. First
  keeper of a name is unsuffixed; later joiners get ` (2)`, ` (3)`, …
  Suffixes are display-only and are not written back to storage.
- **Corrupt storage** (bad UUID or unparseable callsign) is
  regenerated. A missing callsign next to a good UUID mints a new
  NATO name and keeps the peerId.

This package does not import `lib/core/settings` (TASK-008). The
store interface is local. Test doubles live in `test/` — they are
not exported from `identity.dart`.
