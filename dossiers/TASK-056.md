# TASK-056 — Event QR re-theme

## Brief

New screens in a new directory over the existing, unmodified
`lib/features/event_qr/**` payload/validation/scan/export logic — the old
directory is a dependency here and is deleted later by TASK-061. Beyond the
re-theme, this closes a real behavioural gap: a scan in LOCAL that needs a LINKED
session currently just errors.

## Spec pointers

- `specs/KERYX_Mobile_UX_Redesign_Design_v1.0.md` §2.7 — modern framing, camera
  permission states, no silent LOCAL failure, no invented keyed-channel UI.
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §8 (host-level join
  coordinator; user-approved cancellable route change; no WAN under force-LOCAL;
  keyed export unverified; no secret logging), §1.1.
- PRD UX-FR-063, §4.4; Verification VT-023.
- ADR-001 §6 — "NEW framing on the existing scan/export LOGIC".

## Approach

Explain the required connectivity change and offer an explicit, cancellable,
user-approved transition — or keep the operation unavailable with a stated
reason. Force-LOCAL is absolute. A failed join leaves a known-good session or an
explicit unavailable state, never a falsely selected channel. Keyed export is
surfaced as unavailable rather than faked.

## Work Log
