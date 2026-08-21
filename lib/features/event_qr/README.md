# event_qr — Event QR generate/scan + `keryx://` deep links

TASK-025 (KRX-054). FR-043 (Event QR as a first-class LINKED join method),
FR-044 (export/scan/expiry contract).

## What's here

- `event_link.dart` — the `keryx://join?...` wire format: encode/decode,
  expiry presets, and `buildKeyedEventLink` (the off-UI-isolate `deriveKeyed`
  wrapper for a keyed-channel export).
- `qr_export_screen.dart` — `EventQrExportScreen`: renders the QR + link text
  for a payload the host supplies, with the FR-044 expiry-preset picker
  (4 h / 24 h default / 7 d / no-expiry behind an explicit second tap).
- `qr_scan_screen.dart` — `EventQrScanScreen` (camera) + `EventQrScanHandler`
  (the pure "handle exactly one successful scan" policy, kept separate so it
  is unit-testable without a platform camera channel) + `handleBarcodeCapture`
  (pure decode-first-valid-code-in-frame step).

## Deep-link format

```
keryx://join?v=1&r=<region>&ch=<2-digit>&pc=<2-digit>&exp=<unix>   # numbered
keryx://join?v=1&k=<roomId>&exp=<unix>                             # keyed
```

`exp` is a Unix timestamp in seconds; omitted entirely for no-expiry. The
link carries a `roomId` (or the region/channel/code that re-derives one),
**never a raw keyed-channel passphrase** — see `event_link.dart`'s library
dartdoc and TASK-007's `deriveKeyed` contract ("the passphrase never leaves
this function").

Decoding never throws: malformed/out-of-domain input (wrong scheme, wrong
version, out-of-range channel/code, malformed keyed token) always returns
`EventLinkDecodeFailure`, since a scanned code is untrusted external input.
Expiry is a client-side check only (`EventLinkDecoded.isExpired`) — it lets
a scan of an expired code surface an immediate in-world flag/tone instead of
round-tripping to the server first; the token service remains the
authoritative enforcer.

## Known gap, disclosed rather than invented around

FR-044 says the link encodes "region, channel, code (or keyed-channel
token), and expiry" — that's exactly what's implemented here. Separately,
`token-svc/README.md`'s "Event-QR token contract" describes a **different**
artifact, `keryx-evt.v1.<payload>.<hmac>`, signed with a server-side
`EVENT_TOKEN_SECRET` that per that doc's own `.env` comment is "shared with
the app" so a client can mint one offline and hand it to
`LinkedController.joinRoomId`'s `eventToken` parameter (already wired and
waiting — see that method's dartdoc, which names TASK-025 as its expected
producer).

This module deliberately does **not** implement that signing step: there is
no existing Dart-side config surface anywhere in `lib/**` for
`EVENT_TOKEN_SECRET` (grep-confirmed absent), and creating one is a
`lib/core/settings/**`-shaped concern outside this task's `Owned_Paths` —
inventing a hardcoded secret or a new config seam here would be exactly the
kind of out-of-territory reach the coordination protocol forbids. The
dossier itself flags this exact seam as an open coordination point ("ORCH
reconciles if the halves drift"). `decodeEventLink`'s output (`roomId` +
`expiresAt`) is the input a future task needs to build that token once the
secret has a real home; nothing here blocks that follow-up.

## Deliberately out of scope

- Android manifest `keryx://` intent-filter registration lands with the
  android-chain tasks (TASK-001/019/026) per this task's own Description —
  this module only owns the payload parser and the UI, not the platform
  registration.
- Wiring `onTuned`/`buildKeyedEventLink` into the live radio/link state
  (`radioStateProvider`, `LinkedController`) is host integration, not this
  feature's concern — same boundary TASK-024 drew around its own SFX
  wiring, ratified spec-correct.
