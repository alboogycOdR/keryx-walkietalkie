# TASK-025 — Event QR generate/scan + keryx:// deep links (KRX-054)

## Brief
Event join flow in `lib/features/event_qr/`: export any channel as a QR + `keryx://` deep link (region, channel, code or keyed token, expiry with spec presets), and a scanner that tunes the radio instantly. The token payload format is shared with the token service's expiry enforcement — document it as a contract.

## Spec pointers
- FR-044: "any channel can be exported as a QR code + `keryx://` deep link encoding region, channel, code (or keyed-channel token), and expiry. **Default expiry: 24 h**, with presets (4 h 'session', 24 h, 7 d, no expiry — the last requiring an explicit extra tap). Expired tokens are refused by the token service… Scanning tunes the radio instantly."
- FR-043: Event QR is one of the three LINKED join methods.
- TS §4 Event Crew persona: "Coordinator prints a QR; 12 volunteers scan and land on CH 7 · code 21."
- Privacy: keyed-channel QR carries a token, never the raw passphrase in plaintext where avoidable — coordinate format with TASK-003's `EVENT_TOKEN_SECRET`-signed expiry token (read token-svc/README contract; ORCH reconciles if the halves drift).

## Intended approach
1. `event_link.dart`: `keryx://join?v=1&r=<region>&ch=<n>&pc=<code>&exp=<unix>` (numbered) or `keryx://join?v=1&k=<keyed-token>&exp=<unix>`; encode/decode + expiry validation client-side (expired scan → in-world display flag + tone, no dialog).
2. `qr_export_screen.dart`: in-world "print card" style QR (qr_flutter) with expiry preset picker — 4 h / 24 h (default) / 7 d / no-expiry behind an explicit second tap per FR-044.
3. `qr_scan_screen.dart`: mobile_scanner view; successful decode emits a `tuneDirect`/join intent immediately ("tunes the radio instantly") and pops back to the face.
4. Deep-link payload parser exported for the Android intent-filter consumer (manifest registration belongs to the android/** chain — not this task).
5. Tests: encode/decode round-trip, expiry presets incl. default 24 h, expired refusal, malformed links ignored.

## Work Log
