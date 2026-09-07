# TASK-065 — RX remote-track handling and real telemetry source

## Brief

Pure debt paydown of the gap TASK-044 disclosed rather than hid: `RtcAdapter` has
no `onTrack`/remote-stream handling anywhere, so the app has no visibility into
or control over the incoming peer's audio track — no RX volume/mute control and
no source from which a genuine RX level could ever be measured. Remote audio is
believed to auto-play natively regardless, so this is a completeness gap rather
than the suspected cause of the silent-audio field report — but both the
Verification and Technical specs name it as the next thing to review if voice is
still absent, which makes landing it before TASK-059 genuinely useful.

## Spec pointers

- `docs/adr/ADR-001-mobile-ux-redesign-reconciliation.md` §5 (folded in as its
  own task, not conflated with shell work).
- `specs/KERYX_Mobile_UX_Redesign_Technical_v1.0.md` §5.3 ("use a verified real
  audio tap in a separately scoped telemetry task"), §0, §12.
- `specs/KERYX_Mobile_UX_Redesign_Verification_v1.0.md` VT-015, §7.
- PRD UX-FR-027, UX-FR-045; PTS §8.1/§8.5; TASK-044's own Description.

## Approach

Surface remote audio tracks through the adapter interface and its
`flutter_webrtc` implementation, and expose whatever level/quality signal the
platform genuinely provides. The honesty rule is the acceptance bar, not the
feature: if the platform gives nothing usable, return *unavailable* and say so
plainly — no proxy under a measurement name. This provides the `measured` source
TASK-046 models but must not reach into it; consumers are wired later. TASK-044's
audio-session/routing config, the TX path, floor gating and SDP negotiation are
all untouched.

## Work Log
