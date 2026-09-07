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

### [2026-09-07T19:45:16Z] [GB]

Claimed on `task/TASK-065-gb`. Preflight (verbatim in PLAN.md): existing
`rtc_adapter.dart` + `rtc_adapter_flutter_webrtc.dart` + this dossier; NEW
`test/services/mesh/rtc_adapter_test.dart`.

Territory constraint: `FakePeerConnection` / `FakeRtcAdapter` `implement`
the abstract types and live in `test/services/mesh/fakes/` — **out of
Owned_Paths**. Adding members to `RtcPeerConnection` would break the full
suite at compile time. Remote-track observation is therefore an
**extension + Expando** (`RtcPeerConnectionRemoteTracks` /
`rtcRemoteTracks`) so fakes keep compiling and consumers still write
`pc.onRemoteAudioTrack = …`.

Honesty policy, pinned:
- Measured RX level = inbound-rtp `audioLevel` only (WebRTC stats spec,
  linear 0–1).
- `totalAudioEnergy`, jitter, `packetsLost`, media-source (local TX),
  outbound-rtp, another track's level, and out-of-range values (e.g. 0–10
  not rescaled) all return **unavailable**.
- Signal quality is always unavailable — those same RTP stats are not an
  S-meter (UX-FR-045).
- TASK-044 `setAndroidAudioConfiguration` / `setSpeakerphoneOn` block is
  not touched. TX path, floor gating, SDP munging not touched. No
  consumer wiring into TASK-046/051.

Next: implement + tests + revert-mutation + full suite + debug APK.

### [2026-09-07T20:01:18Z] [GB]

Landed on `task/TASK-065-gb`.

**API (in-territory, Fake-safe):** `RtcPeerConnectionRemoteTracks` extension +
Expando (`rtcRemoteTracks` / `deliverRemoteAudioTrack` / `onRemoteAudioTrack`
/ `remoteAudioTracks`). Existing `FakePeerConnection implements
RtcPeerConnection` compiles unchanged. Production
`_FlutterWebrtcPeerConnection` assigns unified-plan `_pc.onTrack` to
`handleFlutterWebrtcTrackEvent` → `deliverRemoteAudioTrack`. Video tracks
ignored. RX mute = `RtcRemoteAudioTrack.enabled`; volume =
`Helper.setVolume` pass-through (not rescaled).

**Honesty:** `audioLevelFromInboundRtpStats` returns `RtcMeasuredAudioLevel`
only for inbound-rtp `audioLevel` in 0–1. Unavailable for: missing field,
`totalAudioEnergy`, jitter/`packetsLost`, media-source (local TX),
outbound-rtp, other-track `trackIdentifier`, out-of-range (e.g. 4.0 not
rescaled from 0–10). `signalQuality` is always unavailable — those RTP
stats are not an S-meter. Does not import TASK-046 `telemetry.dart`. No
consumer wiring into mesh_connection / RadioViewState.

**TASK-044:** `getLocalAudioTrack` audio-session/routing block is
byte-identical. TX path, floor gating, SDP munging untouched (diff is
handler + `_pc.onTrack =` only).

**Tests:** 21 new in `test/services/mesh/rtc_adapter_test.dart`. Mesh suite
53/53. Full suite 1117 passed / 40 skipped / 0 failed.

**Revert-mutation (restored after each):**
1. `if (false && kind != 'audio')` → "video onTrack is ignored" red
   (Expected empty, Actual `[RtcRemoteAudioTrack]`).
2. missing `audioLevel` → `RtcMeasuredAudioLevel(1.0)` → "missing
   audioLevel" and "totalAudioEnergy" red.
3. accept `media-source` as inbound → "media-source … is local TX" red
   (Expected unavailable, Actual measured 0.9).

**Analyze:** owned paths no issues. Repo-wide 8 pre-existing TASK-035
warnings in `radio_session_controller_test.dart`. Flutter CLI auto-upgrades
`analysis_options.yaml` and `android/gradle.properties`; reverted, not
committed.

**Debug APK:** `flutter build apk --debug` exit 0,
`build/app/outputs/flutter-apk/app-debug.apk` 232,148,027 bytes.

→ needs_review.
